import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'dart:convert';

import '../../data/firestore_workspace_remote.dart';
import '../../domain/models.dart';
import 'contracts.dart';

abstract class LiveAttendanceLinks implements AttendanceLinkService {
  Stream<void> changes(LinkSession session);
  Future<LinkSession?> current();
  Future<LinkSession?> forMeeting(CourseClass course, Meeting meeting);
}

abstract interface class ServerTimedAttendanceLinks {
  DateTime get serverNow;
}

/// Accepted check-ins delivered with their payload, without a follow-up poll.
abstract interface class RealtimeAttendanceUpdates {
  Stream<LinkUpdate> watchUpdates(LinkSession session);
}

class FirestoreAttendanceLinks
    implements
        LiveAttendanceLinks,
        ServerTimedAttendanceLinks,
        RealtimeAttendanceUpdates {
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
  Duration _clockOffset = Duration.zero;
  @override
  DateTime get serverNow => DateTime.now().add(_clockOffset);
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
    final openingId = const Uuid().v4();
    final startedAt = DateTime.now().toUtc();
    // Stage a stopped session with a server timestamp. Opening it afterwards
    // derives the two-minute deadline entirely from Firebase, not the phone clock.
    await db.runTransaction((tx) async {
      final storedMeeting = (await tx.get(
        db.doc('classes/$classId/meetings/${meeting.id}'),
      )).data();
      final old = (await tx.get(ref)).data();
      if (storedMeeting?['state'] != 'active') {
        throw const AppProblem(
          'Buổi học chưa mở trên Firestore. Hãy đồng bộ trước.',
        );
      }
      final data = <String, dynamic>{
        'ownerUid': uid,
        'classId': classId,
        'localClassId': course.id,
        'meetingId': meeting.id,
        'label': '${course.courseCode} · ${course.classCode}',
        'receiving': false,
        'expiresAt': FieldValue.serverTimestamp(),
        'openingId': openingId,
        'createdAt': old?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.set(ref, data);
    });
    final staged = (await ref.get(const GetOptions(source: Source.server)))
        .data();
    if (uid != _uid) throw const AppProblem('Tài khoản đã thay đổi.');
    if (staged?['openingId'] != openingId) {
      throw const AppProblem(
        'Phiên đang được thay đổi trên thiết bị khác. Hãy tạo lại link.',
      );
    }
    final serverAnchor = (staged!['expiresAt'] as Timestamp).toDate();
    final elapsed = DateTime.now().toUtc().difference(startedAt);
    _clockOffset = serverAnchor.difference(
      startedAt.add(Duration(microseconds: elapsed.inMicroseconds ~/ 2)),
    );
    final result = await db.runTransaction((tx) async {
      final current = (await tx.get(ref)).data();
      final m = (await tx.get(
        db.doc('classes/$classId/meetings/${meeting.id}'),
      )).data();
      if (current?['openingId'] != openingId || m?['state'] != 'active') {
        throw const AppProblem(
          'Buổi học hoặc phiên đã thay đổi. Hãy đồng bộ và tạo lại link.',
        );
      }
      if (current!['receiving'] == true) return _session(id, current);
      if (current['updatedAt'] != staged['updatedAt']) {
        throw const AppProblem(
          'Phiên đã bị dừng trên thiết bị khác. Hãy kiểm tra trước khi mở lại.',
        );
      }
      final dayEnd = (m!['dayEnd'] as Timestamp).toDate();
      var expiry = serverAnchor.add(const Duration(minutes: 2));
      if (expiry.isAfter(dayEnd)) expiry = dayEnd;
      final changes = {
        'receiving': true,
        'expiresAt': Timestamp.fromDate(expiry),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      tx.update(ref, changes);
      return _session(id, {...current, ...changes});
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
  Stream<LinkUpdate> watchUpdates(
    LinkSession session,
  ) => Stream<LinkUpdate>.multi((controller) {
    final ref = db.doc('attendanceSessions/${session.id}');
    LinkSession? latestSession;
    List<LinkSubmission>? latestRows;
    void emit() {
      if (latestSession != null && latestRows != null) {
        controller.add(LinkUpdate(latestSession!, latestRows!));
      }
    }

    final metadata = ref.snapshots(includeMetadataChanges: true).listen((
      snapshot,
    ) {
      // Server timestamps can be unresolved during a local write.
      if (snapshot.metadata.hasPendingWrites || snapshot.metadata.isFromCache) {
        return;
      }
      final data = snapshot.data();
      if (data == null) {
        controller.addError(
          const AppProblem('Không tìm thấy phiên điểm danh.'),
        );
        return;
      }
      latestSession = _session(session.id, data);
      emit();
    }, onError: controller.addError);
    final submissions = ref
        .collection('checkIns')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          // A reset/reimport can reuse meeting IDs. Never resurrect accepted
          // rows from an old offline cache before server confirmation.
          if (snapshot.metadata.isFromCache) return;
          latestRows = [
            for (final row in snapshot.docs)
              if (!row.metadata.hasPendingWrites &&
                  row.data()['email'] is String &&
                  row.data()['at'] is Timestamp)
                LinkSubmission(
                  row.data()['email'] as String,
                  (row.data()['at'] as Timestamp).toDate().toLocal(),
                ),
          ];
          emit();
        }, onError: controller.addError);
    controller.onCancel = () async {
      await metadata.cancel();
      await submissions.cancel();
    };
  });

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
