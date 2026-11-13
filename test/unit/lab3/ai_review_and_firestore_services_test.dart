// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/ai_attendance_review.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/firestore_attendance_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _FakeConfig implements ConfigService {
  _FakeConfig(this.current);

  @override
  FeatureSettings current;

  @override
  Future<void> refresh() async {}
}

class _FakeTelemetry implements TelemetryService {
  final List<String> events = [];
  bool throwOnEvent = false;

  @override
  Future<void> crashForDemo() async {}

  @override
  Future<void> error(Object error, StackTrace stack, String operation) async {}

  @override
  Future<void> event(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {
    if (throwOnEvent) throw StateError('telemetry down');
    events.add(name);
  }

  @override
  Future<void> identify(String? uid) async {}
}

class _StaticAuth implements AuthService {
  _StaticAuth(this.current);

  @override
  TeacherIdentity? current;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<String> token() async => 'tok';
}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockCollectionRef extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockDocSnap extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockQuerySnap extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockQueryDocSnap extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _MockMeta extends Mock implements SnapshotMetadata {}

class _FakeGetOptions extends Fake implements GetOptions {}

CourseClass _course() => CourseClass(
  id: 'cls-link',
  courseCode: 'PRM393',
  classCode: 'SE1801',
  scheduleCode: '11',
  students: const [
    Student(
      rollNumber: 'SE1',
      fullName: 'An',
      email: 'an@fpt.edu.vn',
    ),
  ],
  scheduleRule: ScheduleRule(
    scheduleCode: '11',
    semesterStart: DateTime(2026, 9, 7),
    weeks: 1,
  ),
  meetings: [
    Meeting(
      id: 'm1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7, 30),
      endAt: DateTime(2026, 9, 7, 9, 50),
      state: MeetingState.active,
    ),
  ],
);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeGetOptions());
  });

  group('AiAttendanceReview.parse & formatting', () {
    test('parses valid JSON and formats checks with bullet prefix', () {
      final raw = jsonEncode({
        'summary': '18 có mặt, 2 vắng, 0 chưa chốt.',
        'checks': [
          'Kiểm tra 2 sinh viên vắng.',
          'Xác nhận trước khi xuất CSV.',
        ],
      });
      final parsed = AiAttendanceReview.parse(raw);
      expect(parsed.summary, '18 có mặt, 2 vắng, 0 chưa chốt.');
      expect(parsed.checks.length, 2);
      expect(
        parsed.text,
        '18 có mặt, 2 vắng, 0 chưa chốt.\n'
        '• Kiểm tra 2 sinh viên vắng.\n'
        '• Xác nhận trước khi xuất CSV.',
      );
    });

    test('allows empty checks list when summary is valid non-empty string', () {
      final parsed = AiAttendanceReview.parse(
        jsonEncode({'summary': 'Đầy đủ 20/20 sinh viên.', 'checks': <String>[]}),
      );
      expect(parsed.checks, isEmpty);
      expect(parsed.text, 'Đầy đủ 20/20 sinh viên.');
    });

    test('rejects malformed payloads, extra fields, blank summary, or blank check items', () {
      final invalidPayloads = [
        'not json at all',
        '[]',
        jsonEncode({'summary': 'ok'}),
        jsonEncode({'summary': 'ok', 'checks': <String>[], 'extra': 1}),
        jsonEncode({'summary': '   ', 'checks': ['a']}),
        jsonEncode({'summary': 123, 'checks': ['a']}),
        jsonEncode({'summary': 'ok', 'checks': 'not-a-list'}),
        jsonEncode({'summary': 'ok', 'checks': ['valid', '   ']}),
        jsonEncode({'summary': 'ok', 'checks': [42]}),
      ];
      for (final bad in invalidPayloads) {
        expect(() => AiAttendanceReview.parse(bad), throwsFormatException);
      }
    });
  });

  group('FirebaseAttendanceReview offline/guard behaviors', () {
    late Directory evidenceDir;

    setUp(() async {
      evidenceDir = await Directory.systemTemp.createTemp('ai_evidence_');
    });

    tearDown(() async {
      if (await evidenceDir.exists()) {
        await evidenceDir.delete(recursive: true);
      }
    });

    test('review throws AppProblem immediately when enableAi is disabled', () async {
      final cfg = _FakeConfig(const FeatureSettings(enableAi: false));
      final telemetry = _FakeTelemetry();
      final service = FirebaseAttendanceReview(cfg, telemetry, evidenceDir);

      await expectLater(
        () => service.review(present: 10, absent: 2, unmarked: 0),
        throwsA(isA<AppProblem>()),
      );
      expect(telemetry.events, isEmpty);
    });

    test('accept rejects whitespace-only text and persists evidence + telemetry when valid', () async {
      final cfg = _FakeConfig(const FeatureSettings());
      final telemetry = _FakeTelemetry();
      final service = FirebaseAttendanceReview(cfg, telemetry, evidenceDir);

      await expectLater(
        () => service.accept('   \n\t '),
        throwsA(isA<AppProblem>()),
      );

      await service.accept('  Đã đối chiếu đủ 20 sinh viên. ');
      expect(telemetry.events, ['ai_result_accepted']);
      final files = await evidenceDir.list().toList();
      expect(files.length, 1);
      final data =
          jsonDecode(await (files.single as File).readAsString())
              as Map<String, dynamic>;
      expect(data['status'], 'accepted');
      expect(data['text'], 'Đã đối chiếu đủ 20 sinh viên.');
    });

    test('accept continues cleanly even when telemetry throws', () async {
      final cfg = _FakeConfig(const FeatureSettings());
      final telemetry = _FakeTelemetry()..throwOnEvent = true;
      final service = FirebaseAttendanceReview(cfg, telemetry, evidenceDir);

      await service.accept('Tiếp tục chốt buổi học.');
      expect(await evidenceDir.list().length, 1);
    });
  });

  group('FirestoreAttendanceLinks service contracts & stream handling', () {
    test('configured checks HTTPS scheme strictly', () {
      final db = _MockFirestore();
      final auth = _StaticAuth(const TeacherIdentity('u1', 't@fpt.edu.vn', 'T'));
      expect(
        FirestoreAttendanceLinks(
          db,
          auth,
          () => 'Fall2026',
          hostingUrl: 'https://fap-app.web.app',
        ).configured,
        isTrue,
      );
      expect(
        FirestoreAttendanceLinks(
          db,
          auth,
          () => 'Fall2026',
          hostingUrl: 'http://fap-app.web.app',
        ).configured,
        isFalse,
      );
      expect(
        FirestoreAttendanceLinks(
          db,
          auth,
          () => 'Fall2026',
          hostingUrl: 'not a url',
        ).configured,
        isFalse,
      );
    });

    test('create validates hostingUrl, semester, and signed-in teacher before Firestore', () async {
      final db = _MockFirestore();
      final c = _course();
      final m = c.meetings.single;

      final noHost = FirestoreAttendanceLinks(
        db,
        _StaticAuth(const TeacherIdentity('u1', 't@fpt.edu.vn', 'T')),
        () => 'Fall2026',
        hostingUrl: 'http://invalid',
      );
      await expectLater(() => noHost.create(c, m), throwsA(isA<AppProblem>()));

      final noSem = FirestoreAttendanceLinks(
        db,
        _StaticAuth(const TeacherIdentity('u1', 't@fpt.edu.vn', 'T')),
        () => null,
        hostingUrl: 'https://fap.web.app',
      );
      await expectLater(() => noSem.create(c, m), throwsA(isA<AppProblem>()));

      final signedOut = FirestoreAttendanceLinks(
        db,
        _StaticAuth(null),
        () => 'Fall2026',
        hostingUrl: 'https://fap.web.app',
      );
      await expectLater(
        () => signedOut.create(c, m),
        throwsA(isA<AppProblem>()),
      );
    });

    test('forMeeting, current, poll, and stop parse server documents cleanly', () async {
      final db = _MockFirestore();
      final auth = _StaticAuth(
        const TeacherIdentity('uid-1', 't@fpt.edu.vn', 'Teacher'),
      );
      final links = FirestoreAttendanceLinks(
        db,
        auth,
        () => 'Fall2026',
        hostingUrl: 'https://fap-host.web.app///',
      );

      final sessionDoc = _MockDocRef();
      final snap = _MockDocSnap();
      final checkInsCol = _MockCollectionRef();
      final checkInsQuery = _MockQuerySnap();
      final subDoc = _MockQueryDocSnap();
      final colSessions = _MockCollectionRef();
      final q1 = _MockQuery();
      final q2 = _MockQuery();
      final q3 = _MockQuery();
      final currentQuerySnap = _MockQuerySnap();

      final expires = Timestamp.fromDate(DateTime.utc(2026, 9, 7, 10, 0));
      final subAt = Timestamp.fromDate(DateTime.utc(2026, 9, 7, 8, 15));

      when(() => snap.exists).thenReturn(true);
      when(() => snap.id).thenReturn('sess-hash');
      when(() => snap.data()).thenReturn({
        'localClassId': 'cls-link',
        'meetingId': 'm1',
        'expiresAt': expires,
        'receiving': true,
      });

      when(() => subDoc.data()).thenReturn({
        'email': 'an@fpt.edu.vn',
        'at': subAt,
      });
      when(() => checkInsQuery.docs).thenReturn([subDoc]);
      when(() => checkInsCol.get(any())).thenAnswer((_) async => checkInsQuery);
      when(() => sessionDoc.collection('checkIns')).thenReturn(checkInsCol);
      when(() => sessionDoc.get(any())).thenAnswer((_) async => snap);
      when(() => sessionDoc.update(any())).thenAnswer((_) async {});
      when(() => db.doc(any())).thenReturn(sessionDoc);

      when(() => db.collection('attendanceSessions')).thenReturn(colSessions);
      when(() => colSessions.where('ownerUid', isEqualTo: 'uid-1'))
          .thenReturn(q1);
      when(() => q1.orderBy('updatedAt', descending: true)).thenReturn(q2);
      when(() => q2.limit(1)).thenReturn(q3);
      when(() => subDoc.id).thenReturn('sess-hash');
      when(() => currentQuerySnap.docs).thenReturn([]);
      when(() => q3.get(any())).thenAnswer((_) async => currentQuerySnap);

      final c = _course();
      final m = c.meetings.single;
      final found = await links.forMeeting(c, m);
      expect(found, isNotNull);
      expect(found!.url, startsWith('https://fap-host.web.app/join/'));
      expect(found.receiving, isTrue);

      expect(await links.current(), isNull);

      final update = await links.poll(found);
      expect(update.session.id, found.id);
      expect(update.submissions.single.email, 'an@fpt.edu.vn');

      await links.stop(found);
      verify(() => sessionDoc.update(any())).called(1);
    });

    test('watchUpdates skips cached/pending writes and emits once server snapshots arrive', () async {
      final db = _MockFirestore();
      final auth = _StaticAuth(
        const TeacherIdentity('uid-1', 't@fpt.edu.vn', 'Teacher'),
      );
      final links = FirestoreAttendanceLinks(
        db,
        auth,
        () => 'Fall2026',
        hostingUrl: 'https://fap-host.web.app',
      );

      final sessionDoc = _MockDocRef();
      final checkInsCol = _MockCollectionRef();
      final docStream = StreamController<DocumentSnapshot<Map<String, dynamic>>>();
      final checkInsStream = StreamController<QuerySnapshot<Map<String, dynamic>>>();

      when(() => db.doc('attendanceSessions/s1')).thenReturn(sessionDoc);
      when(() => sessionDoc.collection('checkIns')).thenReturn(checkInsCol);
      when(() => sessionDoc.snapshots(includeMetadataChanges: true))
          .thenAnswer((_) => docStream.stream);
      when(() => checkInsCol.snapshots(includeMetadataChanges: true))
          .thenAnswer((_) => checkInsStream.stream);

      final emitted = <LinkUpdate>[];
      final sub = links
          .watchUpdates(
            LinkSession(
              id: 's1',
              classId: 'c1',
              meetingId: 'm1',
              url: 'https://fap-host.web.app/join/s1',
              expiresAt: DateTime.utc(2026, 9, 7, 10, 0),
            ),
          )
          .listen(emitted.add);

      // Pending/cached snapshots must be ignored
      final pendingMeta = _MockMeta();
      when(() => pendingMeta.hasPendingWrites).thenReturn(true);
      when(() => pendingMeta.isFromCache).thenReturn(true);
      final cachedDocSnap = _MockDocSnap();
      when(() => cachedDocSnap.metadata).thenReturn(pendingMeta);
      docStream.add(cachedDocSnap);

      final cachedQuerySnap = _MockQuerySnap();
      when(() => cachedQuerySnap.metadata).thenReturn(pendingMeta);
      checkInsStream.add(cachedQuerySnap);
      await Future<void>.delayed(Duration.zero);
      expect(emitted, isEmpty);

      // Server snapshots emit combined LinkUpdate
      final serverMeta = _MockMeta();
      when(() => serverMeta.hasPendingWrites).thenReturn(false);
      when(() => serverMeta.isFromCache).thenReturn(false);

      final serverDocSnap = _MockDocSnap();
      when(() => serverDocSnap.metadata).thenReturn(serverMeta);
      when(() => serverDocSnap.data()).thenReturn({
        'localClassId': 'c1',
        'meetingId': 'm1',
        'expiresAt': Timestamp.fromDate(DateTime.utc(2026, 9, 7, 10, 5)),
        'receiving': true,
      });

      final serverRowMeta = _MockMeta();
      when(() => serverRowMeta.hasPendingWrites).thenReturn(false);
      when(() => serverRowMeta.isFromCache).thenReturn(false);
      final serverRow = _MockQueryDocSnap();
      when(() => serverRow.metadata).thenReturn(serverRowMeta);
      when(() => serverRow.data()).thenReturn({
        'email': 'binh@fpt.edu.vn',
        'at': Timestamp.fromDate(DateTime.utc(2026, 9, 7, 9, 5)),
      });
      final serverQuerySnap = _MockQuerySnap();
      when(() => serverQuerySnap.metadata).thenReturn(serverMeta);
      when(() => serverQuerySnap.docs).thenReturn([serverRow]);

      docStream.add(serverDocSnap);
      checkInsStream.add(serverQuerySnap);
      await Future<void>.delayed(Duration.zero);

      expect(emitted.length, 1);
      expect(emitted.single.submissions.single.email, 'binh@fpt.edu.vn');
      await sub.cancel();
      await docStream.close();
      await checkInsStream.close();
    });
  });
}
