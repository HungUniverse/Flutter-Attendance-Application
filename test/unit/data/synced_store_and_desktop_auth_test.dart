// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fap_attendance/data/desktop_teacher_auth.dart';
import 'package:fap_attendance/data/firestore_report_metadata.dart';
import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/data/synced_desktop_store.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/mobile_workspace_repository.dart';
import 'package:fap_attendance/lab3/services/synced_workspace_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeAuth implements AuthService {
  _FakeAuth(this.current);

  @override
  TeacherIdentity? current;

  final _controller = StreamController<TeacherIdentity?>.broadcast();

  @override
  Stream<TeacherIdentity?> get changes => _controller.stream;

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<String> token() async => 'fake-token';
}

class _InMemoryRemote implements WorkspaceRemote {
  _InMemoryRemote(this.auth);

  @override
  final AuthService auth;

  final Map<String, Map<String, dynamic>> stored = {};
  int revision = 0;
  int reads = 0;
  int writes = 0;

  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) async {
    reads++;
    if (semester != null) {
      return {'data': stored[semester]};
    }
    if (stored.isEmpty) return {'data': null};
    return {'data': stored.values.last};
  }

  @override
  Future<Map<String, dynamic>> writeWorkspace(Map<String, dynamic> pending) async {
    writes++;
    revision++;
    final wsJson = Map<String, dynamic>.from(pending['workspace'] as Map);
    final semester = wsJson['semester'] as String;
    final storedEnvelope = {'revision': revision, 'workspace': wsJson};
    stored[semester] = storedEnvelope;
    return {'data': storedEnvelope};
  }
}

class _FakeDocSnap extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocSnap(this._exists);
  final bool _exists;

  @override
  bool get exists => _exists;
}

class _FakeDocRef extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _FakeDocRef(this.path);

  @override
  final String path;
}

class _FakeTransaction extends Fake implements Transaction {
  final List<String> writtenPaths = [];
  final Map<String, Map<String, Object?>> writtenPayloads = {};
  bool existingDoc = false;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    return _FakeDocSnap(existingDoc) as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T extends Object?>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    writtenPaths.add(documentReference.path);
    if (data is Map) {
      writtenPayloads[documentReference.path] = Map<String, Object?>.from(data);
    }
    return this;
  }
}

class _FakeFirestore extends Fake implements FirebaseFirestore {
  final _FakeTransaction tx = _FakeTransaction();
  bool failNextTransaction = false;

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) =>
      _FakeDocRef(documentPath);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (failNextTransaction) throw StateError('offline');
    return await transactionHandler(tx);
  }
}

TeacherWorkspace _sampleWorkspace({
  String semester = 'Fall2026',
  AttendanceStatus m1Status = AttendanceStatus.present,
}) {
  final now = DateTime.utc(2026, 9, 7, 8, 0);
  return TeacherWorkspace(
    id: 'ws-$semester',
    semester: semester,
    semesterStart: DateTime(2026, 9, 7),
    teacherEmail: 'gv@fpt.edu.vn',
    updatedAt: now,
    classes: [
      CourseClass(
        id: 'cls-1',
        courseCode: 'PRM393',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE180001',
            fullName: 'Nguyen Van An',
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
            state: MeetingState.closed,
          ),
        ],
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: m1Status,
              source: AttendanceSource.manual,
              recordedAt: now,
            ),
          },
        },
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fap_sync_auth_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SyncedDesktopStore', () {
    test('delegates save, loadWorkspace, and loadMostRecentWorkspace through SharedWorkspaceSync', () async {
      final auth = _FakeAuth(
        const TeacherIdentity('uid-teacher-1', 't1@fpt.edu.vn', 'Teacher 1'),
      );
      final remote = _InMemoryRemote(auth);
      final sync = SharedWorkspaceSync(remote, tempDir);
      addTearDown(sync.dispose);
      final store = SyncedDesktopStore(sync, 'uid-teacher-1');

      final ws = _sampleWorkspace(semester: 'Fall2026');
      final savedFile = await store.saveWorkspace(ws);
      expect(savedFile.path.endsWith('Fall2026/workspace.json'), isTrue);
      expect(remote.writes, 1);

      final loadedSpecific = await store.loadWorkspace('Fall2026');
      expect(loadedSpecific?.semester, 'Fall2026');
      expect(loadedSpecific?.classes.single.courseCode, 'PRM393');

      final loadedRecent = await store.loadMostRecentWorkspace();
      expect(loadedRecent?.semester, 'Fall2026');
    });

    test('local directory isolates storage per uid', () async {
      final auth = _FakeAuth(
        const TeacherIdentity('uid-alpha', 'a@fpt.edu.vn', 'Alpha'),
      );
      final sync = SharedWorkspaceSync(_InMemoryRemote(auth), tempDir);
      addTearDown(sync.dispose);
      final storeA = SyncedDesktopStore(sync, 'uid-alpha');
      final storeB = SyncedDesktopStore(sync, 'uid-beta');

      expect(storeA.rootDirectory.path, isNot(storeB.rootDirectory.path));
      expect(storeA.rootDirectory.path, contains('uid-alpha'));
      expect(storeB.rootDirectory.path, contains('uid-beta'));
    });
  });

  group('FileMobileWorkspaceRepository & SyncedMobileWorkspaceRepository', () {
    test('rejects invalid uid, semester, courseCode, or path traversal segments', () async {
      final repo = FileMobileWorkspaceRepository(tempDir);

      final badSegments = [
        '',
        '../etc',
        'bad space',
        'a/b',
        'x' * 129,
        'sem@2026',
      ];
      for (final bad in badSegments) {
        await expectLater(
          () => repo.listSemesters(bad),
          throwsA(isA<AppProblem>()),
        );
        await expectLater(
          () => repo.load('uid-ok', semester: bad),
          throwsA(isA<AppProblem>()),
        );
      }
    });

    test('exports csv, pdf, json, rejects invalid format and incomplete unmarked attendance', () async {
      final repo = FileMobileWorkspaceRepository(tempDir);
      final completeWs = _sampleWorkspace(m1Status: AttendanceStatus.present);
      final course = completeWs.classes.single;
      final meeting = course.meetings.single;

      await repo.save('teacher-1', completeWs);
      final semesters = await repo.listSemesters('teacher-1');
      expect(semesters, ['Fall2026']);

      final csvFile = await repo.export(
        'teacher-1',
        completeWs,
        course,
        meeting,
        'csv',
      );
      expect(await csvFile.exists(), isTrue);

      final pdfFile = await repo.export(
        'teacher-1',
        completeWs,
        course,
        meeting,
        'pdf',
      );
      expect(await pdfFile.exists(), isTrue);
      expect(await pdfFile.length(), greaterThan(100));

      final jsonFile = await repo.export(
        'teacher-1',
        completeWs,
        course,
        meeting,
        'json',
      );
      expect(await jsonFile.exists(), isTrue);
      expect(jsonFile.path, endsWith('.json'));

      await expectLater(
        () => repo.export('teacher-1', completeWs, course, meeting, 'xlsx'),
        throwsA(isA<AppProblem>()),
      );

      final incompleteWs = _sampleWorkspace(m1Status: AttendanceStatus.unmarked);
      await expectLater(
        () => repo.export(
          'teacher-1',
          incompleteWs,
          incompleteWs.classes.single,
          incompleteWs.classes.single.meetings.single,
          'json',
        ),
        throwsStateError,
      );
    });

    test('saves source archive, active link session, and archives course folders cleanly', () async {
      final repo = FileMobileWorkspaceRepository(tempDir);
      final ws = _sampleWorkspace();
      await repo.save('t-arch', ws);

      await repo.saveSource(
        't-arch',
        'Fall2026',
        'roster.csv',
        Uint8List.fromList(utf8.encode('Roll,Name\nSE1,An')),
      );
      expect(
        await File(
          p.join(
            tempDir.path,
            'teachers',
            't-arch',
            'Fall2026',
            'source',
            'roster.csv',
          ),
        ).exists(),
        isTrue,
      );

      expect(await repo.loadLink('t-arch'), isNull);
      final link = LinkSession(
        id: 'sess-1',
        classId: 'cls-1',
        meetingId: 'm1',
        url: 'https://example.web.app/join/sess-1',
        expiresAt: DateTime.utc(2026, 9, 7, 12, 0),
        receiving: true,
      );
      await repo.saveLink('t-arch', link);
      final loadedLink = await repo.loadLink('t-arch');
      expect(loadedLink?.id, 'sess-1');
      expect(loadedLink?.url, link.url);

      await repo.saveLink('t-arch', null);
      expect(await repo.loadLink('t-arch'), isNull);

      await repo.archive('t-arch', ws, ws.classes.single);
      final trashed = Directory(
        p.join(tempDir.path, 'teachers', 't-arch', 'Fall2026', 'trash', 'classes'),
      );
      expect(await trashed.exists(), isTrue);
    });

    test('SyncedMobileWorkspaceRepository blocks uid mismatch and flushes FirestoreReportMetadata', () async {
      final auth = _FakeAuth(
        const TeacherIdentity('uid-owner', 'owner@fpt.edu.vn', 'Owner'),
      );
      final remote = _InMemoryRemote(auth);
      final sync = SharedWorkspaceSync(remote, tempDir);
      addTearDown(sync.dispose);

      final db = _FakeFirestore();

      final reports = FirestoreReportMetadata(db, tempDir);
      final syncedRepo = SyncedMobileWorkspaceRepository(
        tempDir,
        sync,
        reports: reports,
      );

      await expectLater(
        () => syncedRepo.load('other-uid'),
        throwsStateError,
      );
      final ws = _sampleWorkspace();
      await syncedRepo.save('uid-owner', ws);
      final csv = await syncedRepo.export(
        'uid-owner',
        ws,
        ws.classes.single,
        ws.classes.single.meetings.single,
        'csv',
      );
      expect(await csv.exists(), isTrue);
      expect(reports.warning, isNull);
      expect(db.tx.writtenPaths.single, startsWith('reportMetadata/'));

      final loaded = await syncedRepo.load('uid-owner', semester: 'Fall2026');
      expect(loaded?.semester, 'Fall2026');
    });
  });

  group('FirestoreReportMetadata offline queueing & recovery', () {
    test('queues outbox item on Firestore error and drains on retry', () async {
      final db = _FakeFirestore()..failNextTransaction = true;

      final metadata = FirestoreReportMetadata(db, tempDir);
      final reportFile = File(p.join(tempDir.path, 'report.csv'))
        ..writeAsStringSync('RollNumber,Status\nSE1,P\n');
      final ws = _sampleWorkspace();

      await metadata.record(
        'teacher-offline',
        ws,
        ws.classes.single,
        ws.classes.single.meetings.single,
        reportFile,
        'csv',
      );
      expect(metadata.warning, contains('đang chờ đồng bộ'));

      final outboxDir = Directory(
        p.join(
          tempDir.path,
          'teachers',
          'teacher-offline',
          'report-metadata-outbox',
        ),
      );
      expect(await outboxDir.list().length, 1);

      db.failNextTransaction = false;
      await metadata.flush('teacher-offline');
      expect(metadata.warning, isNull);
      expect(await outboxDir.list().length, 0);
      expect(db.tx.writtenPaths.length, 1);
    });

    test('rejects invalid UID and flags ownerUid mismatch in outbox', () async {
      final db = _FakeFirestore();
      final metadata = FirestoreReportMetadata(db, tempDir);

      expect(() => metadata.flush('../bad'), throwsArgumentError);

      final outboxDir = Directory(
        p.join(tempDir.path, 'teachers', 'u1', 'report-metadata-outbox'),
      )..createSync(recursive: true);
      File(p.join(outboxDir.path, 'tampered.json')).writeAsStringSync(
        jsonEncode({'ownerUid': 'someone-else'}),
      );

      await metadata.flush('u1');
      expect(metadata.warning, contains('chờ đồng bộ'));
    });
  });

  group('DesktopTeacherAuth validation guards', () {
    test('rejects missing, non-HTTPS, and userinfo URLs before opening browser', () async {
      for (final badUrl in [
        '',
        'http://attendance.example.com',
        'ftp://attendance.example.com',
        'https://user:pass@attendance.example.com',
      ]) {
        final auth = DesktopTeacherAuth(baseUrl: badUrl);
        await expectLater(() => auth.signIn(), throwsA(isA<AppProblem>()));
        await expectLater(() => auth.token(), throwsA(isA<AppProblem>()));
        expect(auth.current, isNull);
      }
    });

    test('signOut clears token and emits null even if server call fails', () async {
      final auth = DesktopTeacherAuth(baseUrl: 'http://insecure.local');
      final events = <TeacherIdentity?>[];
      final sub = auth.changes.listen(events.add);

      await expectLater(() => auth.signOut(), throwsA(isA<AppProblem>()));
      await Future<void>.delayed(Duration.zero);
      expect(auth.current, isNull);
      expect(events, [null]);
      await sub.cancel();
    });
  });
}
