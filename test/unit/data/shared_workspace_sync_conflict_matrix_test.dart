import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _FakeAuth implements AuthService {
  _FakeAuth([this.current = const TeacherIdentity('uid-1', 'gv@fpt.edu.vn', 'GV')]);

  @override
  TeacherIdentity? current;

  String authToken = 'token-123';
  void Function()? onTokenRead;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<String> token() async {
    onTokenRead?.call();
    return authToken;
  }
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request, String body) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final response = await handler(request, utf8.decode(bodyBytes));
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

class _ScriptedRemote implements WorkspaceRemote {
  _ScriptedRemote(this.auth);

  @override
  final AuthService auth;

  Future<Map<String, dynamic>> Function(String? semester)? onRead;
  Future<Map<String, dynamic>> Function(Map<String, dynamic> pending)? onWrite;

  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) =>
      (onRead ?? (_) async => {'data': null})(semester);

  @override
  Future<Map<String, dynamic>> writeWorkspace(Map<String, dynamic> pending) =>
      (onWrite ??
          (p) async => {
            'data': {
              'revision': ((p['revision'] as int?) ?? 0) + 1,
              'workspace': p['workspace'],
            },
          })(pending);
}

void main() {
  final t0 = DateTime.utc(2026, 9, 15, 8, 0);

  TeacherWorkspace makeWorkspace({
    String semester = 'FA26',
    MeetingState m1State = MeetingState.upcoming,
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
    String classExtraNote = '',
  }) => TeacherWorkspace(
    id: 'ws-$semester',
    semester: semester,
    semesterStart: DateTime(2026, 9, 7),
    teacherEmail: 'gv@fpt.edu.vn',
    updatedAt: t0,
    classes: [
      CourseClass(
        id: 'cls-1',
        courseCode: 'PRM393',
        classCode: classExtraNote.isEmpty ? 'SE1801' : classExtraNote,
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE180001',
            email: 'an@fpt.edu.vn',
            fullName: 'Nguyen Van An',
          ),
          Student(
            rollNumber: 'SE180002',
            email: 'binh@fpt.edu.vn',
            fullName: 'Tran Thi Binh',
          ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 9, 14, 7, 30),
            endAt: DateTime(2026, 9, 14, 9, 30),
            state: m1State,
          ),
        ],
        attendance: attendance,
      ),
    ],
  );

  group('SharedApi HTTP transport & status code mapping', () {
    test('rejects non-HTTPS or empty baseUrl before hitting HTTP client', () async {
      final auth = _FakeAuth();
      final badUrls = ['', 'http://sync.fpt.edu.vn', 'https://', 'not-a-url'];
      for (final url in badUrls) {
        final api = SharedApi(
          auth,
          baseUrl: url,
          client: _FakeHttpClient((_, _) async => http.Response('{}', 200)),
        );
        expect(api.configured, isFalse);
        await expectLater(
          () => api.readWorkspace(),
          throwsA(isA<AppProblem>()),
        );
      }
    });

    test('maps 200, 409 conflict, 401/403 auth, 500 server error, and UID swap mid-request', () async {
      final auth = _FakeAuth();
      var nextStatus = 200;
      String? capturedAuthHeader;
      String? capturedUri;

      final api = SharedApi(
        auth,
        baseUrl: 'https://relay.example.com///',
        client: _FakeHttpClient((req, body) async {
          capturedAuthHeader = req.headers['authorization'];
          capturedUri = req.url.toString();
          return http.Response(jsonEncode({'data': {'revision': 4}}), nextStatus);
        }),
      );

      expect(api.configured, isTrue);

      final ok = await api.readWorkspace(semester: 'FA26');
      expect(ok['data']['revision'], 4);
      expect(capturedAuthHeader, 'Bearer token-123');
      expect(capturedUri, 'https://relay.example.com/api/workspaces?semester=FA26');

      nextStatus = 409;
      await expectLater(
        () => api.writeWorkspace({'revision': 1}),
        throwsA(isA<SyncConflict>()),
      );

      nextStatus = 401;
      await expectLater(() => api.readWorkspace(), throwsA(isA<AppProblem>()));

      nextStatus = 403;
      await expectLater(() => api.readWorkspace(), throwsA(isA<AppProblem>()));

      nextStatus = 502;
      await expectLater(() => api.readWorkspace(), throwsA(isA<AppProblem>()));

      // Switching user while fetching token throws account-changed guard.
      auth.onTokenRead = () => auth.current = const TeacherIdentity(
        'uid-2',
        'other@fpt.edu.vn',
        'Other',
      );
      await expectLater(() => api.readWorkspace(), throwsA(isA<AppProblem>()));
    });
  });

  group('SharedWorkspaceSync outbox, conflict reconciliation, and offline recovery', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('shared_sync_test_');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('enforces valid UID and semester patterns against path traversal', () async {
      final auth = _FakeAuth(const TeacherIdentity('../bad', 'x@fpt.edu.vn', 'X'));
      final sync = SharedWorkspaceSync(_ScriptedRemote(auth), root);
      addTearDown(sync.dispose);

      expect(() => sync.local('../bad'), throwsA(isA<AppProblem>()));
      await expectLater(
        () => sync.save(makeWorkspace(semester: '../FA26')),
        throwsA(isA<AppProblem>()),
      );

      auth.current = const TeacherIdentity('valid_uid-1', 'gv@fpt.edu.vn', 'GV');
      await expectLater(
        () => sync.save(makeWorkspace(semester: 'bad/sem')),
        throwsA(isA<AppProblem>()),
      );
    });

    test('saves offline to durable outbox when network fails, then pushes pending on next load()', () async {
      final auth = _FakeAuth();
      final remote = _ScriptedRemote(auth);
      var online = false;
      var serverRevision = 1;
      Map<String, dynamic>? storedRemoteRow;

      remote.onWrite = (pending) async {
        if (!online) throw const SocketException('Offline');
        serverRevision++;
        storedRemoteRow = {
          'revision': serverRevision,
          'workspace': pending['workspace'],
        };
        return {'data': storedRemoteRow};
      };
      remote.onRead = (_) async => {'data': storedRemoteRow};

      final sync = SharedWorkspaceSync(remote, root);
      addTearDown(sync.dispose);
      final ws = makeWorkspace(semester: 'FA26');

      final offlineResult = await sync.save(ws);
      expect(offlineResult.id, ws.id);
      expect(sync.status, 'Đã lưu trên máy · Chờ đồng bộ');
      expect(sync.conflict, isFalse);

      // Simulate restart while still offline -> pending discovered from sync.json even with semester=null
      final syncAfterRestartOffline = SharedWorkspaceSync(remote, root);
      addTearDown(syncAfterRestartOffline.dispose);
      final recoveredOffline = await syncAfterRestartOffline.load();
      expect(recoveredOffline?.id, ws.id);
      expect(syncAfterRestartOffline.status, 'Đã lưu trên máy · Chờ đồng bộ');

      // Now reconnect and call load() -> outbox flushes cleanly to server.
      online = true;
      final syncOnline = SharedWorkspaceSync(remote, root);
      addTearDown(syncOnline.dispose);
      final synced = await syncOnline.load();
      expect(synced?.id, ws.id);
      expect(storedRemoteRow?['revision'], 2);
      expect(syncOnline.status, 'Đã đồng bộ');
    });

    test('smart-merges meeting closure conflict by preserving remote scan marks over local finalize absences', () async {
      final auth = _FakeAuth();
      final remote = _ScriptedRemote(auth);

      // Server currently holds revision 2 where meeting m1 is still active and SE180001 scanned Present.
      final serverWs = makeWorkspace(
        m1State: MeetingState.active,
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
        },
      );

      // Local device closed m1 offline marking both SE180001 & SE180002 Absent (finalize).
      final localClosedWs = makeWorkspace(
        m1State: MeetingState.closed,
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t0,
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t0,
            ),
          },
        },
      );

      var attempt = 0;
      TeacherWorkspace? pushedMerged;
      remote.onWrite = (pending) async {
        attempt++;
        if (attempt == 1) {
          throw const SyncConflict();
        }
        pushedMerged = TeacherWorkspace.fromJson(
          (pending['workspace'] as Map).cast<String, Object?>(),
        );
        return {
          'data': {
            'revision': (pending['revision'] as int) + 1,
            'workspace': pending['workspace'],
          },
        };
      };
      remote.onRead = (_) async => {
        'data': {'revision': 2, 'workspace': serverWs.toJson()},
      };

      final sync = SharedWorkspaceSync(remote, root);
      addTearDown(sync.dispose);
      final confirmed = await sync.save(
        localClosedWs,
        closing: (classId: 'cls-1', meetingId: 'm1'),
      );

      expect(attempt, 2);
      expect(sync.conflict, isFalse);
      expect(sync.status, 'Đã đồng bộ');
      expect(pushedMerged, isNotNull);
      expect(
        confirmed.classes.single.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      expect(
        confirmed.classes.single.recordFor('m1', 'SE180002')?.status,
        AttendanceStatus.absent,
      );
    });

    test('refuses smart-merge and flags conflict when server differs structurally or on manual decision', () async {
      final auth = _FakeAuth();
      final remote = _ScriptedRemote(auth);

      // Server has different classCode (structural mismatch)
      final serverWs = makeWorkspace(
        m1State: MeetingState.active,
        classExtraNote: 'SE1809',
      );
      final localWs = makeWorkspace(m1State: MeetingState.closed);

      remote.onWrite = (_) async => throw const SyncConflict();
      remote.onRead = (_) async => {
        'data': {'revision': 5, 'workspace': serverWs.toJson()},
      };

      final sync = SharedWorkspaceSync(remote, root);
      addTearDown(sync.dispose);

      await sync.save(localWs, closing: (classId: 'cls-1', meetingId: 'm1'));
      expect(sync.conflict, isTrue);
      expect(sync.status, const SyncConflict().message);

      // useServer downloads remote copy, creates a sync.json backup, and clears conflict
      final adopted = await sync.useServer('FA26');
      expect(adopted?.classes.single.classCode, 'SE1809');
      expect(sync.conflict, isFalse);
      expect(sync.status, contains('Đã nhận bản máy chủ'));

      final semDir = Directory('${sync.local('uid-1').rootDirectory.path}/FA26');
      final backupFiles = semDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.backup-'))
          .toList();
      expect(backupFiles, isNotEmpty);
    });
  });
}
