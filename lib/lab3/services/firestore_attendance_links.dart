import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import '../../data/firestore_workspace_remote.dart';
import '../../domain/models.dart';
import 'contracts.dart';

abstract class LiveAttendanceLinks implements AttendanceLinkService {
  Stream<void> changes(LinkSession session);
  Future<LinkSession?> current();
  Future<LinkSession?> forMeeting(CourseClass course, Meeting meeting);
}

class FirestoreAttendanceLinks implements LiveAttendanceLinks {
  FirestoreAttendanceLinks(
    this.db,
    this.auth,
    this.semester, {
    required this.hostingUrl,
  });
  final FirebaseFirestore db;
  final AuthService auth;
  final String? Function() semester;
  final String hostingUrl;
  String get _uid =>
      auth.current?.uid ?? (throw const AppProblem('Vui lòng đăng nhập.'));
  @override
  bool get configured => Uri.tryParse(hostingUrl)?.scheme == 'https';

  String _idFor(CourseClass course, Meeting meeting) {
    final classId = firestoreClassId(_uid, semester()!, course.id);
    return sha256.convert(utf8.encode('$classId/${meeting.id}')).toString();
  }

  @override
  Future<LinkSession?> forMeeting(CourseClass course, Meeting meeting) async {
    final id = _idFor(course, meeting);
    final snapshot = await db
        .doc('attendanceSessions/$id')
        .get(const GetOptions(source: Source.server));
    return snapshot.exists ? _session(id, snapshot.data()!) : null;
  }

  LinkSession _session(String id, Map<String, dynamic> data) => LinkSession(
    id: id,
    classId: data['localClassId'] as String,
    meetingId: data['meetingId'] as String,
    url: '${hostingUrl.replaceFirst(RegExp(r'/+$'), '')}/join/$id',
    expiresAt: (data['expiresAt'] as Timestamp).toDate(),
    receiving: data['receiving'] as bool,
  );

  @override
  Future<LinkSession> create(CourseClass course, Meeting meeting) async {
    if (!configured || semester() == null) {
      throw const AppProblem('Chưa có cấu hình Hosting hoặc học kỳ.');
    }
    final uid = _uid;
    final classId = firestoreClassId(uid, semester()!, course.id);
    // One session per meeting makes retries and reopening idempotent. Existing
    // check-ins remain immutable across every displayed QR for this meeting.
    final id = _idFor(course, meeting);
    final ref = db.doc('attendanceSessions/$id');
    final result = await db.runTransaction((tx) async {
      final storedMeeting = (await tx.get(
        db.doc('classes/$classId/meetings/${meeting.id}'),
      )).data();
      final old = (await tx.get(ref)).data();
      if (storedMeeting?['state'] != 'active') {
        throw const AppProblem(
          'Buổi học chưa mở trên Firestore. Hãy đồng bộ trước.',
        );
      }
      final now = DateTime.now();
      if (old != null &&
          old['receiving'] == true &&
          (old['expiresAt'] as Timestamp).toDate().isAfter(now)) {
        return _session(id, old);
      }
      final dayEnd = (storedMeeting!['dayEnd'] as Timestamp).toDate();
      var expiry = now.add(const Duration(minutes: 2));
      if (expiry.isAfter(dayEnd)) expiry = dayEnd;
      final data = <String, dynamic>{
        'ownerUid': uid,
        'classId': classId,
        'localClassId': course.id,
        'meetingId': meeting.id,
        'label': '${course.courseCode} · ${course.classCode}',
        'receiving': true,
        'expiresAt': Timestamp.fromDate(expiry),
        'createdAt': old?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.set(ref, data);
      return _session(id, data);
    });
    if (uid != _uid) throw const AppProblem('Tài khoản đã thay đổi.');
    return result;
  }

  @override
  Future<LinkUpdate> poll(LinkSession session) async {
    // Freeze acknowledgement must precede this server-only query when closing.
    final ref = db.doc('attendanceSessions/${session.id}');
    final data = (await ref.get(const GetOptions(source: Source.server)))
        .data();
    if (data == null) throw const AppProblem('Không tìm thấy phiên điểm danh.');
    final rows = await ref
        .collection('checkIns')
        .get(const GetOptions(source: Source.server));
    return LinkUpdate(
      _session(session.id, data),
      rows.docs
          .map(
            (row) => LinkSubmission(
              row.data()['email'] as String,
              (row.data()['at'] as Timestamp).toDate().toLocal(),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> stop(LinkSession session) async {
    await db.doc('attendanceSessions/${session.id}').update({
      'receiving': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<LinkSession?> current() async {
    final rows = await db
        .collection('attendanceSessions')
        .where('ownerUid', isEqualTo: _uid)
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .get(const GetOptions(source: Source.server));
    if (rows.docs.isEmpty) return null;
    return _session(rows.docs.single.id, rows.docs.single.data());
  }

  @override
  Stream<void> changes(LinkSession session) => Stream<void>.multi((controller) {
    final ref = db.doc('attendanceSessions/${session.id}');
    final metadata = ref.snapshots().listen(
      (_) => controller.add(null),
      onError: controller.addError,
    );
    final submissions = ref
        .collection('checkIns')
        .snapshots()
        .listen((_) => controller.add(null), onError: controller.addError);
    controller.onCancel = () async {
      await metadata.cancel();
      await submissions.cancel();
    };
  });
}
