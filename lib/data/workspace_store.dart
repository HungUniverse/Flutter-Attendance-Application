import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/models.dart';

class WorkspaceStore {
  WorkspaceStore(this.rootDirectory);

  final Directory rootDirectory;

  Future<File> saveWorkspace(TeacherWorkspace workspace) async {
    final semesterDir = Directory(
      p.join(rootDirectory.path, workspace.semester),
    );
    await semesterDir.create(recursive: true);
    final file = File(p.join(semesterDir.path, 'workspace.json'));
    await _writeAtomic(file, workspace.toPrettyJson());
    for (final courseClass in workspace.classes) {
      final classFile = File(
        p.join(
          semesterDir.path,
          'classes',
          '${courseClass.courseCode}_${courseClass.classCode}',
          'class.json',
        ),
      );
      await _writeAtomic(
        classFile,
        const JsonEncoder.withIndent('  ').convert(courseClass.toJson()),
      );
    }
    await rebuildIndex(workspace);
    return file;
  }

  Directory semesterDirectory(String semester) =>
      Directory(p.join(rootDirectory.path, semester));

  Future<Directory?> archiveClass(
    TeacherWorkspace workspace,
    CourseClass courseClass,
  ) async {
    final folderName = '${courseClass.courseCode}_${courseClass.classCode}';
    final source = Directory(
      p.join(rootDirectory.path, workspace.semester, 'classes', folderName),
    );
    if (!await source.exists()) return null;
    final archiveRoot = Directory(
      p.join(rootDirectory.path, workspace.semester, 'trash', 'classes'),
    );
    await archiveRoot.create(recursive: true);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    return source.rename(p.join(archiveRoot.path, '${timestamp}_$folderName'));
  }

  Future<File> saveSource({
    required String semester,
    required String fileName,
    required List<int> bytes,
  }) async {
    final safeName = p.basename(fileName);
    final file = File(p.join(rootDirectory.path, semester, 'source', safeName));
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      final archive = Directory(p.join(file.parent.path, 'archive'));
      await archive.create(recursive: true);
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      await file.rename(p.join(archive.path, '${timestamp}_$safeName'));
    }
    return temporary.rename(file.path);
  }

  Future<TeacherWorkspace?> loadWorkspace(String semester) async {
    final file = File(p.join(rootDirectory.path, semester, 'workspace.json'));
    if (!await file.exists()) return null;
    try {
      return TeacherWorkspace.decode(await file.readAsString());
    } on Object {
      final backup = File('${file.path}.bak');
      if (!await backup.exists()) rethrow;
      return TeacherWorkspace.decode(await backup.readAsString());
    }
  }

  Future<TeacherWorkspace?> loadMostRecentWorkspace() async {
    if (!await rootDirectory.exists()) return null;
    final candidates = <File>[];
    await for (final entity in rootDirectory.list()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'workspace.json'));
      if (await file.exists()) candidates.add(file);
    }
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return loadWorkspace(p.basename(candidates.first.parent.path));
  }

  Future<File> saveWorkingSession(
    TeacherWorkspace workspace,
    CourseClass courseClass,
    Meeting meeting,
  ) async {
    final dir = await _sessionDirectory(workspace, courseClass);
    final file = _sessionFile(dir, meeting);
    final existing = await _readSessionMetadata(file);
    await _writeSession(
      file: file,
      workspace: workspace,
      courseClass: courseClass,
      meeting: meeting,
      revision: existing.revision,
      finalizedAt: existing.finalizedAt,
    );
    await _archiveLegacySessionFiles(workspace, courseClass, meeting, dir);
    return file;
  }

  Future<File> saveFinalVersion(
    TeacherWorkspace workspace,
    CourseClass courseClass,
    Meeting meeting,
  ) async {
    final dir = await _sessionDirectory(workspace, courseClass);
    final file = _sessionFile(dir, meeting);
    final existing = await _readSessionMetadata(file);
    final legacyRevision = await _latestLegacyRevision(dir, meeting);
    final currentRevision = existing.revision > legacyRevision
        ? existing.revision
        : legacyRevision;
    final revision = currentRevision < 1 ? 1 : currentRevision + 1;
    final finalizedAt = existing.finalizedAt ?? DateTime.now().toUtc();
    await _writeSession(
      file: file,
      workspace: workspace,
      courseClass: courseClass,
      meeting: meeting,
      revision: revision,
      finalizedAt: finalizedAt,
    );
    await _archiveLegacySessionFiles(workspace, courseClass, meeting, dir);
    return file;
  }

  Future<int> migrateLegacySessions(TeacherWorkspace workspace) async {
    var migrated = 0;
    for (final courseClass in workspace.classes) {
      final dir = await _sessionDirectory(workspace, courseClass);
      for (final meeting in courseClass.meetings) {
        final legacyFiles = await _legacySessionFiles(dir, meeting);
        if (legacyFiles.isEmpty) continue;
        final file = _sessionFile(dir, meeting);
        if (!await file.exists()) {
          final legacyRevision = await _latestLegacyRevision(dir, meeting);
          final legacyMetadata = await _latestLegacyMetadata(
            legacyFiles,
            meeting,
          );
          await _writeSession(
            file: file,
            workspace: workspace,
            courseClass: courseClass,
            meeting: meeting,
            revision: meeting.state == MeetingState.closed
                ? (legacyRevision < 1 ? 1 : legacyRevision)
                : 0,
            finalizedAt: meeting.state == MeetingState.closed
                ? legacyMetadata.finalizedAt
                : null,
          );
        }
        await _archiveLegacySessionFiles(workspace, courseClass, meeting, dir);
        migrated++;
      }
    }
    return migrated;
  }

  Future<File> rebuildIndex(TeacherWorkspace workspace) async {
    final index = {
      'schemaVersion': 1,
      'workspaceId': workspace.id,
      'semester': workspace.semester,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'classes': workspace.classes.map((courseClass) {
        final closed = courseClass.meetings
            .where((m) => m.state == MeetingState.closed)
            .length;
        return {
          'id': courseClass.id,
          'courseCode': courseClass.courseCode,
          'classCode': courseClass.classCode,
          'studentCount': courseClass.students.length,
          'meetingCount': courseClass.meetings.length,
          'closedMeetingCount': closed,
        };
      }).toList(),
    };
    final file = File(
      p.join(rootDirectory.path, workspace.semester, 'index.json'),
    );
    await _writeAtomic(file, const JsonEncoder.withIndent(' ').convert(index));
    return file;
  }

  Future<Directory> exportDirectory(
    TeacherWorkspace workspace,
    CourseClass courseClass,
  ) async {
    final dir = Directory(
      p.join(
        rootDirectory.path,
        workspace.semester,
        'classes',
        '${courseClass.courseCode}_${courseClass.classCode}',
        'exports',
      ),
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _sessionDirectory(
    TeacherWorkspace workspace,
    CourseClass courseClass,
  ) async {
    final dir = Directory(
      p.join(
        rootDirectory.path,
        workspace.semester,
        'classes',
        '${courseClass.courseCode}_${courseClass.classCode}',
        'sessions',
      ),
    );
    await dir.create(recursive: true);
    return dir;
  }

  File _sessionFile(Directory dir, Meeting meeting) =>
      File(p.join(dir.path, '${_meetingPrefix(meeting)}.json'));

  Future<void> _writeSession({
    required File file,
    required TeacherWorkspace workspace,
    required CourseClass courseClass,
    required Meeting meeting,
    required int revision,
    required DateTime? finalizedAt,
  }) => _writeAtomic(
    file,
    const JsonEncoder.withIndent(' ').convert(
      _snapshot(
        workspace,
        courseClass,
        meeting,
        revision: revision,
        finalizedAt: finalizedAt,
      ),
    ),
  );

  Future<_SessionMetadata> _readSessionMetadata(File file) async {
    if (!await file.exists()) return const _SessionMetadata();
    try {
      final json = (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
      return _SessionMetadata(
        revision: (json['revision'] as num?)?.toInt() ?? 0,
        finalizedAt:
            _tryDate(json['finalizedAt']) ??
            (json['state'] == 'final' ? _tryDate(json['updatedAt']) : null),
      );
    } on Object {
      return const _SessionMetadata();
    }
  }

  Future<_SessionMetadata> _latestLegacyMetadata(
    List<File> files,
    Meeting meeting,
  ) async {
    var latestRevision = -1;
    DateTime? finalizedAt;
    for (final file in files) {
      try {
        final json = (jsonDecode(await file.readAsString()) as Map)
            .cast<String, Object?>();
        final revision = (json['revision'] as num?)?.toInt() ?? 0;
        if (revision < latestRevision) continue;
        latestRevision = revision;
        finalizedAt =
            _tryDate(json['finalizedAt']) ??
            _tryDate(json['savedAt']) ??
            finalizedAt;
      } on Object {
        // File cũ lỗi vẫn được đưa vào recovery sau khi snapshot mới đã lưu.
      }
    }
    return _SessionMetadata(
      revision: latestRevision < 0 ? 0 : latestRevision,
      finalizedAt: meeting.state == MeetingState.closed
          ? finalizedAt ?? DateTime.now().toUtc()
          : null,
    );
  }

  DateTime? _tryDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  Future<int> _latestLegacyRevision(Directory dir, Meeting meeting) async {
    var maximum = 0;
    final expression = RegExp(
      '^${RegExp.escape(_meetingPrefix(meeting))}_v(\\d{3})_',
    );
    for (final file in await _legacySessionFiles(dir, meeting)) {
      final match = expression.firstMatch(p.basename(file.path));
      if (match == null) continue;
      final revision = int.parse(match.group(1)!);
      if (revision > maximum) maximum = revision;
    }
    return maximum;
  }

  Future<List<File>> _legacySessionFiles(Directory dir, Meeting meeting) async {
    if (!await dir.exists()) return const [];
    final prefix = RegExp.escape(_meetingPrefix(meeting));
    final expression = RegExp(
      '^$prefix(?:_working|_v\\d{3}_(?:final|correction))\\.json\$',
    );
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && expression.hasMatch(p.basename(entity.path))) {
        files.add(entity);
      }
    }
    return files;
  }

  Future<void> _archiveLegacySessionFiles(
    TeacherWorkspace workspace,
    CourseClass courseClass,
    Meeting meeting,
    Directory dir,
  ) async {
    final files = await _legacySessionFiles(dir, meeting);
    if (files.isEmpty) return;
    final recovery = Directory(
      p.join(
        rootDirectory.path,
        '.recovery',
        workspace.semester,
        '${courseClass.courseCode}_${courseClass.classCode}',
        'sessions',
      ),
    );
    await recovery.create(recursive: true);
    for (final file in files) {
      var target = File(p.join(recovery.path, p.basename(file.path)));
      if (await target.exists()) {
        final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
        target = File(
          p.join(recovery.path, '${stamp}_${p.basename(file.path)}'),
        );
      }
      await file.rename(target.path);
    }
  }

  Map<String, Object?> _snapshot(
    TeacherWorkspace workspace,
    CourseClass courseClass,
    Meeting meeting, {
    required int revision,
    required DateTime? finalizedAt,
  }) {
    final records = courseClass.attendance[meeting.id] ?? const {};
    final rosterCanonical = courseClass.students
        .map((s) => '${s.rollNumber}|${s.normalizedEmail}|${s.fullName}')
        .join('\n');
    return {
      'schemaVersion': 2,
      'sessionId': meeting.id,
      'revision': revision,
      'state': meeting.state == MeetingState.closed ? 'final' : 'working',
      'workspaceId': workspace.id,
      'semester': workspace.semester,
      'courseCode': courseClass.courseCode,
      'classCode': courseClass.classCode,
      'scheduleCode': courseClass.scheduleCode,
      'meeting': meeting.toJson(),
      'rosterHash': sha256.convert(utf8.encode(rosterCanonical)).toString(),
      if (finalizedAt != null)
        'finalizedAt': finalizedAt.toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'attendance': courseClass.students.map((student) {
        final record = records[student.rollNumber];
        return {
          ...student.toJson(),
          'attendance':
              record?.toJson() ??
              {
                'status': '',
                'source': AttendanceSource.finalize.name,
                'recordedAt': DateTime.now().toUtc().toIso8601String(),
              },
        };
      }).toList(),
      'auditEvents': courseClass.auditEvents
          .where((e) => e.meetingId == meeting.id)
          .map((e) => e.toJson())
          .toList(),
    };
  }

  static String _meetingPrefix(Meeting meeting) =>
      'M${meeting.number.toString().padLeft(2, '0')}_${meeting.startAt.year}-${meeting.startAt.month.toString().padLeft(2, '0')}-${meeting.startAt.day.toString().padLeft(2, '0')}';

  static Future<void> _writeAtomic(File target, String content) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await temporary.writeAsString(content, flush: true);
    if (await target.exists()) {
      await target.copy(backup.path);
      await target.delete();
    }
    await temporary.rename(target.path);
  }
}

class _SessionMetadata {
  const _SessionMetadata({this.revision = 0, this.finalizedAt});

  final int revision;
  final DateTime? finalizedAt;
}
