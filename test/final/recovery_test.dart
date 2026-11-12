import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/firestore_attendance_links.dart';

import '../lab3/fakes.dart';

class _DeniedRemote implements WorkspaceRemote {
  @override
  final FakeAuth auth = FakeAuth();
  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) async =>
      throw const WorkspaceAccessDenied();
  @override
  Future<Map<String, dynamic>> writeWorkspace(
    Map<String, dynamic> pending,
  ) async => throw const WorkspaceAccessDenied();
}

class _RecoveredLinks extends FakeLinks implements LiveAttendanceLinks {
  @override
  Stream<void> changes(LinkSession session) => const Stream.empty();
  @override
  Future<LinkSession?> current() async => null;
  @override
  Future<LinkSession?> forMeeting(CourseClass course, Meeting meeting) async =>
      session;
}

void main() {
  test(
    'missing teacher role cannot fall back to a protected cached workspace',
    () async {
      final root = await Directory.systemTemp.createTemp('fap-role-denial-');
      final remote = _DeniedRemote();
      final sync = SharedWorkspaceSync(remote, root);
      addTearDown(() async {
        sync.dispose();
        await remote.auth.controller.close();
        await root.delete(recursive: true);
      });
      await sync.local('teacher1').saveWorkspace(fixtureWorkspace());
      await expectLater(sync.load(), throwsA(isA<WorkspaceAccessDenied>()));
    },
  );
  test(
    'close recovers an unsaved remote session and imports accepted submissions',
    () async {
      final links = _RecoveredLinks()
        ..submissions = [LinkSubmission('two@example.com', fixtureNow)];
      final h = Harness(
        await Directory.systemTemp.createTemp('fap-session-recovery-'),
        linkService: links,
      );
      await h.initialize();
      addTearDown(h.dispose);
      expect(h.vm.link, isNull);
      expect(await h.vm.close('c1', 'm1'), true);
      expect(links.receiving, false);
      expect(h.vm.counts('c1', 'm1')[AttendanceStatus.present], 1);
      expect(h.vm.counts('c1', 'm1')[AttendanceStatus.absent], 2);
    },
  );
}
