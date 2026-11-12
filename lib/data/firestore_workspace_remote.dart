import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

import '../domain/models.dart';
import '../lab3/services/contracts.dart';
import 'shared_workspace_sync.dart';

String firestoreWorkspaceId(String uid, String semester) =>
    sha256.convert(utf8.encode('$uid/$semester')).toString();

String firestoreClassId(String uid, String semester, String localId) =>
    sha256.convert(utf8.encode('$uid/$semester/$localId')).toString();

/// Firestore is authoritative. The existing disk outbox retries this transport
/// with the same mutation ID after network failures or application restarts.
class FirestoreWorkspaceRemote implements WorkspaceRemote {
  FirestoreWorkspaceRemote(this.db, this.auth);
  final FirebaseFirestore db;
  String? _cachedOwner;
  String? _cachedWorkspaceId;
  Map<String, dynamic>? _cachedWorkspace;
  @override
  final AuthService auth;
  String get owner =>
      auth.current?.uid ?? (throw const AppProblem('Vui lòng đăng nhập.'));

  Future<void> requireTeacher() async {
    final profile = await db
        .doc('users/$owner')
        .get(const GetOptions(source: Source.server));
    if (profile.data()?['role'] != 'teacher') {
      throw const WorkspaceAccessDenied();
    }
  }

  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) async {
    await requireTeacher();
    final uid = owner;
    DocumentReference<Map<String, dynamic>> ref;
    if (semester == null) {
      final rows = await db
          .collection('workspaces')
          .where('ownerUid', isEqualTo: uid)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (rows.docs.isEmpty) return {'data': null};
      ref = rows.docs.single.reference;
    } else {
      ref = db.doc('workspaces/${firestoreWorkspaceId(uid, semester)}');
    }
    final result = await db.runTransaction<Map<String, dynamic>>((tx) async {
      final snapshot = await tx.get(ref);
      final manifest = snapshot.data();
      if (manifest == null) return {'data': null};
      // Every class/meeting mutation advances this manifest in the same commit.
      // Keep validating the role and server revision, but reuse an unchanged graph.
      if (_cachedOwner == uid &&
          _cachedWorkspaceId == ref.id &&
          _cachedWorkspace?['revision'] == manifest['revision']) {
        return {'data': _cachedWorkspace};
      }
      final layout = Map<String, dynamic>.from(manifest['layout'] as Map);
      final classes = <Map<String, dynamic>>[];
      for (final entry in layout.entries) {
        final course = (await tx.get(db.doc('classes/${entry.key}'))).data()!;
        final meetings = <Map<String, dynamic>>[];
        final attendance = <String, dynamic>{};
        final audits = <dynamic>[];
        for (final id in (entry.value as List).cast<String>()) {
          final meeting = (await tx.get(
            db.doc('classes/${entry.key}/meetings/$id'),
          )).data()!;
          meetings.add({
            for (final key in ['id', 'number', 'startAt', 'endAt', 'state'])
              key: meeting[key],
          });
          attendance[id] = meeting['records'];
          audits.addAll(meeting['auditEvents'] as List);
        }
        classes.add({
          ...Map<String, dynamic>.from(course['data'] as Map),
          'meetings': meetings,
          'attendance': attendance,
          'auditEvents': audits,
        });
      }
      if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
      return {
        'data': {
          'revision': manifest['revision'],
          'workspace': {
            ...Map<String, dynamic>.from(manifest['data'] as Map),
            'classes': classes,
          },
        },
      };
    });
    if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
    _remember(uid, ref.id, result['data'] as Map<String, dynamic>?);
    return result;
  }

  void _remember(String uid, String id, Map<String, dynamic>? value) {
    _cachedOwner = uid;
    _cachedWorkspaceId = id;
    _cachedWorkspace = value;
  }

  @override
  Future<Map<String, dynamic>> writeWorkspace(
    Map<String, dynamic> pending,
  ) async {
    await requireTeacher();
    final uid = owner;
    final workspace = TeacherWorkspace.fromJson(
      Map<String, Object?>.from(pending['workspace'] as Map),
    );
    final workspaceId = firestoreWorkspaceId(uid, workspace.semester);
    final ref = db.doc('workspaces/$workspaceId');
    final documents = <String, Map<String, dynamic>>{};
    final layout = <String, List<String>>{};
    for (final course in workspace.classes) {
      final classId = firestoreClassId(uid, workspace.semester, course.id);
      layout[classId] = course.meetings.map((m) => m.id).toList();
      final data = course.toJson()
        ..remove('meetings')
        ..remove('attendance')
        ..remove('auditEvents');
      final roster = <String, String>{};
      for (final student in course.students) {
        if (student.normalizedEmail.isEmpty) continue;
        if (roster.containsKey(student.normalizedEmail)) {
          throw const AppProblem(
            'Roster có email trùng. Hãy sửa tệp trước khi đồng bộ.',
          );
        }
        roster[student.normalizedEmail] = student.rollNumber;
      }
      documents['classes/$classId'] = {
        'ownerUid': uid,
        'workspaceId': workspaceId,
        'archived': false,
        'data': data,
        'roster': roster,
      };
      for (final meeting in course.meetings) {
        final start = meeting.startAt.toLocal();
        documents['classes/$classId/meetings/${meeting.id}'] = {
          ...meeting.toJson(),
          'dayStart': Timestamp.fromDate(
            DateTime(start.year, start.month, start.day),
          ),
          'dayEnd': Timestamp.fromDate(
            DateTime(start.year, start.month, start.day + 1),
          ),
          'records':
              course.attendance[meeting.id]?.map(
                (roll, mark) => MapEntry(roll, mark.toJson()),
              ) ??
              {},
          'auditEvents': course.auditEvents
              .where((a) => a.meetingId == meeting.id)
              .map((a) => a.toJson())
              .toList(),
        };
      }
    }
    final result = await db.runTransaction<Map<String, dynamic>>((tx) async {
      final previous = (await tx.get(ref)).data();
      if (previous?['mutationId'] == pending['mutationId']) {
        return {
          'data': {
            'revision': previous!['revision'],
            'workspace': workspace.toJson(),
          },
        };
      }
      if ((previous?['revision'] ?? 0) != pending['revision']) {
        throw const SyncConflict();
      }
      final oldLayout = Map<String, dynamic>.from(
        previous?['layout'] as Map? ?? {},
      );
      final paths = {...documents.keys};
      for (final classId in oldLayout.keys) {
        paths.add('classes/$classId');
      }
      final existing = <String, Map<String, dynamic>?>{};
      for (final path in paths) {
        existing[path] = (await tx.get(db.doc(path))).data();
      }
      if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
      for (final entry in documents.entries) {
        if (!const DeepCollectionEquality().equals(
          entry.value,
          existing[entry.key],
        )) {
          tx.set(db.doc(entry.key), entry.value);
        }
      }
      for (final classId in oldLayout.keys.where(
        (id) => !layout.containsKey(id),
      )) {
        tx.update(db.doc('classes/$classId'), {'archived': true});
      }
      final revision = (previous?['revision'] as int? ?? 0) + 1;
      final data = workspace.toJson()..remove('classes');
      tx.set(ref, {
        'ownerUid': uid,
        'revision': revision,
        'mutationId': pending['mutationId'],
        'data': data,
        'layout': layout,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {
        'data': {'revision': revision, 'workspace': workspace.toJson()},
      };
    });
    if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
    _remember(uid, ref.id, result['data'] as Map<String, dynamic>?);
    return result;
  }
}
