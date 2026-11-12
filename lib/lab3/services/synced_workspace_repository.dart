import 'dart:io';

import '../../data/firestore_report_metadata.dart';
import '../../data/shared_workspace_sync.dart';
import '../../domain/models.dart';
import 'mobile_workspace_repository.dart';

class SyncedMobileWorkspaceRepository extends FileMobileWorkspaceRepository {
  SyncedMobileWorkspaceRepository(super.root, this.sync, {this.reports});
  final SharedWorkspaceSync sync;
  final FirestoreReportMetadata? reports;
  void _check(String uid) {
    if (uid != sync.owner) throw StateError('Tài khoản đã thay đổi.');
  }

  @override
  Future<TeacherWorkspace?> load(String uid, {String? semester}) async {
    _check(uid);
    final value = await sync.load(semester: semester);
    await reports?.flush(uid);
    return value;
  }

  @override
  Future<File> export(
    String uid,
    TeacherWorkspace workspace,
    CourseClass course,
    Meeting meeting,
    String format,
  ) async {
    _check(uid);
    final file = await super.export(uid, workspace, course, meeting, format);
    await reports?.record(uid, workspace, course, meeting, file, format);
    return file;
  }

  @override
  Future<void> save(String uid, TeacherWorkspace workspace) async {
    _check(uid);
    await sync.save(workspace);
  }
}
