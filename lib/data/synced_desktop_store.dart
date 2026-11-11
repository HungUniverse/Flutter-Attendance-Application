import 'dart:io';

import '../domain/models.dart';
import 'shared_workspace_sync.dart';
import 'workspace_store.dart';

class SyncedDesktopStore extends WorkspaceStore {
  SyncedDesktopStore(this.sync, String uid)
    : super(sync.local(uid).rootDirectory);
  final SharedWorkspaceSync sync;
  @override
  Future<TeacherWorkspace?> loadMostRecentWorkspace() => sync.load();
  @override
  Future<TeacherWorkspace?> loadWorkspace(String semester) =>
      sync.load(semester: semester);
  @override
  Future<File> saveWorkspace(TeacherWorkspace workspace) async {
    await sync.save(workspace);
    return File('${rootDirectory.path}/${workspace.semester}/workspace.json');
  }
}
