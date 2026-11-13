import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAuth implements AuthService {
  TeacherIdentity? identity = const TeacherIdentity(
    'uid-1',
    'gv@fpt.edu.vn',
    'GV',
  );

  @override
  TeacherIdentity? get current => identity;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {
    identity = null;
  }

  @override
  Future<String> token() async => 'fake-jwt';
}

class _MemoryRemote implements WorkspaceRemote {
  _MemoryRemote(this.auth);

  @override
  final _FakeAuth auth;

  Map<String, dynamic>? serverRow;
  int nextRevision = 1;
  bool throwConflictOnNextWrite = false;
  bool throwOfflineOnNextWrite = false;
  bool throwAccessDenied = false;

  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) async {
    if (throwAccessDenied) throw const WorkspaceAccessDenied();
    return {'data': serverRow};
  }

  @override
  Future<Map<String, dynamic>> writeWorkspace(Map<String, dynamic> pending) async {
    if (throwAccessDenied) throw const WorkspaceAccessDenied();
    if (throwOfflineOnNextWrite) throw const SocketException('offline');
    if (throwConflictOnNextWrite) {
      throwConflictOnNextWrite = false;
      throw const SyncConflict();
    }
    serverRow = {
      'workspace': pending['workspace'],
      'revision': nextRevision++,
    };
    return {'data': serverRow};
  }
}

TeacherWorkspace _sampleWorkspace({
  MeetingState meetingState = MeetingState.upcoming,
  Map<String, Map<String, AttendanceRecord>> attendance = const {},
}) {
  return TeacherWorkspace(
    id: 'ws-sync',
    semester: 'FA26',
    semesterStart: DateTime(2026, 9, 7),
    teacherEmail: 'gv@fpt.edu.vn',
    classes: [
      CourseClass(
        id: 'cls-1',
        courseCode: 'PRM392',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: const [
          Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'An'),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 9, 7, 7, 30),
            endAt: DateTime(2026, 9, 7, 9, 15),
            state: meetingState,
          ),
        ],
        attendance: attendance,
      ),
    ],
  );
}

void main() {
  group('SharedApi', () {
    test('configured checks HTTPS and non-empty host', () {
      final auth = _FakeAuth();
      expect(SharedApi(auth, baseUrl: 'https://example.com').configured, isTrue);
      expect(SharedApi(auth, baseUrl: 'http://example.com').configured, isFalse);
      expect(SharedApi(auth, baseUrl: '').configured, isFalse);
    });

    test('request maps 200, 409, 401/403, and 500 responses appropriately', () async {
      final auth = _FakeAuth();
      final client = MockClient((req) async {
        if (req.url.path == '/api/workspaces' && req.method == 'GET') {
          return http.Response(jsonEncode({'data': null}), 200);
        }
        if (req.url.path == '/conflict') {
          return http.Response('conflict', 409);
        }
        if (req.url.path == '/unauth') {
          return http.Response('unauth', 401);
        }
        return http.Response('err', 500);
      });

      final api = SharedApi(auth, baseUrl: 'https://api.example.com/', client: client);
      final ok = await api.readWorkspace(semester: 'FA26');
      expect(ok['data'], isNull);

      expect(() => api.request('PUT', '/conflict', {}), throwsA(isA<SyncConflict>()));
      expect(() => api.request('GET', '/unauth'), throwsA(isA<AppProblem>()));
      expect(() => api.request('GET', '/boom'), throwsA(isA<AppProblem>()));
    });
  });

  group('SharedWorkspaceSync', () {
    late Directory tempDir;
    late _FakeAuth auth;
    late _MemoryRemote remote;
    late SharedWorkspaceSync sync;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('shared_sync_test_');
      auth = _FakeAuth();
      remote = _MemoryRemote(auth);
      sync = SharedWorkspaceSync(remote, tempDir);
    });

    tearDown(() async {
      sync.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('save pushes to remote, updates status, and persists locally', () async {
      final ws = _sampleWorkspace();
      final saved = await sync.save(ws);
      expect(saved.semester, 'FA26');
      expect(sync.status, 'Đã đồng bộ');
      expect(sync.conflict, isFalse);

      final loaded = await sync.load(semester: 'FA26');
      expect(loaded?.id, 'ws-sync');
    });

    test('save sets offline status when remote fails and recovers on next load', () async {
      final ws = _sampleWorkspace();
      remote.throwOfflineOnNextWrite = true;
      await sync.save(ws);
      expect(sync.status, contains('Chờ đồng bộ'));

      remote.throwOfflineOnNextWrite = false;
      final loaded = await sync.load();
      expect(loaded?.id, 'ws-sync');
      expect(sync.status, 'Đã đồng bộ');
    });

    test('save sets conflict flag on 409 without closing metadata and useServer restores server copy', () async {
      final ws = _sampleWorkspace();
      await sync.save(ws);

      remote.throwConflictOnNextWrite = true;
      await sync.save(ws.copyWith(teacherEmail: 'edited@fpt.edu.vn'));
      expect(sync.conflict, isTrue);

      final restored = await sync.useServer('FA26');
      expect(restored?.teacherEmail, 'gv@fpt.edu.vn');
      expect(sync.status, contains('Đã nhận bản máy chủ'));
    });

    test('save with closing merges remote scan marks on conflict automatically', () async {
      final serverActive = _sampleWorkspace(
        meetingState: MeetingState.active,
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: DateTime.utc(2026, 9, 7, 7, 40),
            ),
          },
        },
      );
      remote.serverRow = {'workspace': serverActive.toJson(), 'revision': 5};

      final localClosed = _sampleWorkspace(
        meetingState: MeetingState.closed,
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: DateTime.utc(2026, 9, 7, 9, 15),
            ),
          },
        },
      );
      remote.throwConflictOnNextWrite = true;

      final merged = await sync.save(
        localClosed,
        closing: (classId: 'cls-1', meetingId: 'm1'),
      );
      expect(sync.status, 'Đã đồng bộ');
      expect(
        merged.classes.first.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
    });

    test('validates uid and semester formats to prevent path traversal', () {
      expect(() => sync.local('../escape'), throwsA(isA<AppProblem>()));
      expect(() => sync.load(semester: '../FA26'), throwsA(isA<AppProblem>()));
    });
  });
}
