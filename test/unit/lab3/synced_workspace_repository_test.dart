import 'dart:io';

import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/synced_workspace_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuth implements AuthService {
  _FakeAuth(this.uid);
  String uid;

  @override
  TeacherIdentity? get current => TeacherIdentity(uid, '$uid@fpt.edu.vn', 'GV');

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<String> token() async => 'tok';
}

class _MemoryRemote implements WorkspaceRemote {
  _MemoryRemote(this.auth);

  @override
  final _FakeAuth auth;
  Map<String, dynamic>? row;
  int rev = 1;

  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) async => {
        'data': row,
      };

  @override
  Future<Map<String, dynamic>> writeWorkspace(Map<String, dynamic> pending) async {
    row = {'workspace': pending['workspace'], 'revision': rev++};
    return {'data': row};
  }
}

void main() {
  late Directory tempDir;
  late _FakeAuth auth;
  late SharedWorkspaceSync sync;
  late SyncedMobileWorkspaceRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('synced_repo_test_');
    auth = _FakeAuth('teacher-A');
    sync = SharedWorkspaceSync(_MemoryRemote(auth), tempDir);
    repo = SyncedMobileWorkspaceRepository(tempDir, sync);
  });

  tearDown(() async {
    sync.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('delegates save/load to sync and rejects mismatched uid', () async {
    final ws = TeacherWorkspace(
      id: 'ws-1',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: const [],
    );

    await repo.save('teacher-A', ws);
    final loaded = await repo.load('teacher-A', semester: 'FA26');
    expect(loaded?.id, 'ws-1');

    await expectLater(repo.load('teacher-B'), throwsStateError);
    await expectLater(repo.save('teacher-B', ws), throwsStateError);
  });
}
