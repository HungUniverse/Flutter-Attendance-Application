import '../../data/shared_workspace_sync.dart';
import '../../domain/models.dart';
import 'mobile_workspace_repository.dart';

class SyncedMobileWorkspaceRepository extends FileMobileWorkspaceRepository {
  SyncedMobileWorkspaceRepository(super.root, this.sync);
  final SharedWorkspaceSync sync;
  void _check(String uid) {
    if (uid != sync.owner) throw StateError('Tài khoản đã thay đổi.');
  }

  @override
  Future<TeacherWorkspace?> load(String uid, {String? semester}) {
    _check(uid);
    return sync.load(semester: semester);
  }

  @override
  Future<void> save(String uid, TeacherWorkspace workspace) async {
    _check(uid);
    await sync.save(workspace);
  }
}
