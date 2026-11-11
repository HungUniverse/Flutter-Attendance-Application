import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/attendance_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';

import 'fakes.dart';

void main() {
  late Directory root;
  late MockClient client;
  Map<String, dynamic>? server;
  bool online = true;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fap-shared-test-');
    server = null;
    online = true;
    client = MockClient((request) async {
      if (!online) throw const SocketException('offline');
      if (request.method == 'PUT') {
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        if (data['mutationId'] != server?['mutationId']) {
          if (data['revision'] != (server?['revision'] ?? 0)) {
            return http.Response('{}', 409);
          }
          server = {...data, 'revision': data['revision'] + 1};
        }
      }
      return http.Response(
        jsonEncode({'data': server}),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  });
  tearDown(() async {
    client.close();
    await root.delete(recursive: true);
  });
  SharedWorkspaceSync device(String name) => SharedWorkspaceSync(
    SharedApi(FakeAuth(), baseUrl: 'https://attendance.test', client: client),
    Directory('${root.path}/$name'),
  );

  test(
    'queued mutation cannot move into another account after sign-out',
    () async {
      final auth = FakeAuth();
      final sync = SharedWorkspaceSync(
        SharedApi(auth, baseUrl: 'https://attendance.test', client: client),
        root,
      );
      addTearDown(sync.dispose);
      final pending = sync.save(fixtureWorkspace());
      auth.current = const TeacherIdentity(
        'teacher2',
        'other@example.com',
        'Other',
      );
      await expectLater(pending, throwsA(isA<AppProblem>()));
      expect(server, isNull);
      expect(await Directory('${root.path}/teachers/teacher2').exists(), false);
    },
  );

  test('one device imports, second receives same IDs and attendance', () async {
    final a = device('desktop'), b = device('mobile');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.save(fixtureWorkspace());
    final received = await b.load();
    expect(received!.classes.single.id, 'c1');
    expect(received.classes.single.meetings.single.id, 'm1');
    expect(b.status, 'Đã đồng bộ');
  });
  test(
    'offline outbox survives restart and is uploaded on reconnect',
    () async {
      final a = device('mobile');
      await a.load();
      online = false;
      await a.save(fixtureWorkspace());
      expect(a.status, contains('Chờ đồng bộ'));
      a.dispose();
      // Simulate a crash after writing the outbox but before restoring cache.
      await File('${root.path}/mobile/teachers/teacher1/FA26/workspace.json')
          .delete();
      final restarted = device('mobile');
      addTearDown(restarted.dispose);
      online = true;
      expect((await restarted.load())!.id, 'w1');
      expect(server!['revision'], 1);
      expect(restarted.status, 'Đã đồng bộ');
    },
  );
  test('stale device never overwrites server; explicit recovery keeps local backup', () async {
    final a = device('desktop'), b = device('mobile');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.save(fixtureWorkspace());
    await b.load();
    await a.save(
      fixtureWorkspace().copyWith(teacherEmail: 'server@example.com'),
    );
    await b.save(
      fixtureWorkspace().copyWith(teacherEmail: 'pending@example.com'),
    );
    expect(b.conflict, true);
    expect((server!['workspace'] as Map)['teacherEmail'], 'server@example.com');
    final local = await b.load();
    expect(local!.teacherEmail, 'pending@example.com');
    expect(b.conflict, true);
    final received = await b.useServer('FA26');
    expect(received!.teacherEmail, 'server@example.com');
    expect(b.conflict, false);
    final backups = await Directory(
      '${root.path}/mobile/teachers/teacher1/FA26',
    ).list().where((f) => f.path.contains('.backup-')).toList();
    expect(backups, hasLength(1));
    expect(
      await File(backups.single.path).readAsString(),
      contains('pending@example.com'),
    );
  });

  test('closing on Windows retains a concurrent Android QR mark', () async {
    final desktop = device('desktop'), mobile = device('mobile');
    addTearDown(desktop.dispose);
    addTearDown(mobile.dispose);
    final original = fixtureWorkspace();
    final course = original.classes.single;
    final now = course.meetings.single.startAt;
    final attendance = AttendanceService();
    await desktop.save(original);
    await mobile.load();
    await mobile.save(
      original.copyWith(
        classes: [
          attendance.markPresent(
            course,
            meetingId: 'm1',
            email: 'one@example.com',
            now: now,
          ),
        ],
      ),
    );

    final closed = await desktop.save(
      original.copyWith(
        classes: [attendance.closeMeeting(course, 'm1', now: now)],
      ),
      closing: (classId: 'c1', meetingId: 'm1'),
    );
    expect(desktop.conflict, isFalse);
    expect(desktop.status, 'Đã đồng bộ');
    expect(
      closed.classes.single.recordFor('m1', 'S1')?.status,
      AttendanceStatus.present,
    );
    final synced = (await mobile.load())!.classes.single;
    expect(synced.meetings.single.state, MeetingState.closed);
    expect(synced.recordFor('m1', 'S1')?.status, AttendanceStatus.present);
    expect(synced.recordFor('m1', 'S2')?.status, AttendanceStatus.absent);
  });

  test('closing preserves a conflict between two explicit marks', () async {
    final desktop = device('desktop'), mobile = device('mobile');
    addTearDown(desktop.dispose);
    addTearDown(mobile.dispose);
    final original = fixtureWorkspace();
    final course = original.classes.single;
    final now = course.meetings.single.startAt;
    final attendance = AttendanceService();
    await desktop.save(original);
    await mobile.load();
    await mobile.save(
      original.copyWith(
        classes: [
          attendance.markPresent(
            course,
            meetingId: 'm1',
            email: 'one@example.com',
            now: now,
          ),
        ],
      ),
    );
    final manual = attendance.markManual(
      course,
      meetingId: 'm1',
      rollNumber: 'S1',
      status: AttendanceStatus.absent,
      now: now,
    );

    await desktop.save(
      original.copyWith(
        classes: [attendance.closeMeeting(manual, 'm1', now: now)],
      ),
      closing: (classId: 'c1', meetingId: 'm1'),
    );
    expect(desktop.conflict, isTrue);
    final synced = (await mobile.load())!.classes.single;
    expect(synced.meetings.single.state, MeetingState.active);
    expect(synced.recordFor('m1', 'S1')?.status, AttendanceStatus.present);
  });
}
