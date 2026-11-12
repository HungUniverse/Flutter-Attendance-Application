import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../data/workspace_store.dart';
import '../../data/attendance_csv_exporter.dart';
import '../../data/report_file_writer.dart';
import '../../domain/models.dart';
import 'contracts.dart';

/// Account-scoped storage. Desktop workspaces are never silently reassigned.
class FileMobileWorkspaceRepository implements MobileWorkspaceRepository {
  FileMobileWorkspaceRepository(this.root);
  final Directory root;
  WorkspaceStore _store(String uid) =>
      WorkspaceStore(Directory(p.join(root.path, 'teachers', _safe(uid))));
  static String _safe(String text) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(text)) {
      throw const AppProblem('Tên học kỳ hoặc tài khoản không hợp lệ.');
    }
    return text;
  }

  @override
  Future<TeacherWorkspace?> load(String uid, {String? semester}) =>
      semester == null
      ? _store(uid).loadMostRecentWorkspace()
      : _store(uid).loadWorkspace(_safe(semester));
  @override
  Future<void> save(String uid, TeacherWorkspace workspace) async {
    _safe(workspace.semester);
    for (final course in workspace.classes) {
      _safe(course.courseCode);
      _safe(course.classCode);
      _safe(course.id);
    }
    await _store(uid).saveWorkspace(workspace);
  }

  @override
  Future<void> saveSource(
    String uid,
    String semester,
    String name,
    Uint8List bytes,
  ) async {
    await _store(uid)
        .saveSource(semester: _safe(semester), fileName: name, bytes: bytes);
  }

  @override
  Future<File> export(
    String uid,
    TeacherWorkspace workspace,
    CourseClass course,
    Meeting meeting,
    String format,
  ) async {
    _safe(workspace.semester);
    _safe(course.courseCode);
    _safe(course.classCode);
    // Also validates complete P/A for JSON exports.
    AttendanceCsvExporter().encode(workspace, course, meeting);
    final directory = await _store(uid).exportDirectory(workspace, course);
    if (format == 'csv') {
      final file = await AttendanceCsvExporter().export(
        directory,
        workspace,
        course,
        meeting,
      );
      return file;
    }
    if (format != 'json') throw const AppProblem('Định dạng không hợp lệ.');
    final date = meeting.startAt.toIso8601String().split('T').first;
    final name =
        '${workspace.semester}_${course.courseCode}_${course.classCode}_M${meeting.number.toString().padLeft(2, '0')}_$date.json';
    final file = File(p.join(directory.path, name));
    final session = await _store(uid)
        .saveFinalVersion(workspace, course, meeting);
    return writeReportAtomically(file, session.openRead());
  }

  @override
  Future<void> archive(
    String uid,
    TeacherWorkspace workspace,
    CourseClass course,
  ) async {
    _safe(workspace.semester);
    _safe(course.courseCode);
    _safe(course.classCode);
    await _store(uid).archiveClass(workspace, course);
  }

  File _linkFile(String uid) =>
      File(p.join(root.path, 'teachers', _safe(uid), 'active-link.json'));
  @override
  Future<LinkSession?> loadLink(String uid) async {
    final file = _linkFile(uid);
    if (!await file.exists()) return null;
    return LinkSession.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> saveLink(String uid, LinkSession? session) async {
    final file = _linkFile(uid);
    await file.parent.create(recursive: true);
    if (session == null) {
      if (await file.exists()) await file.delete();
    } else {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(session.toJson()), flush: true);
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }
}
