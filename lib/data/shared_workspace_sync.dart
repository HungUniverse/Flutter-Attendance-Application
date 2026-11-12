import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../lab3/services/contracts.dart';
import 'report_file_writer.dart';
import 'workspace_store.dart';

abstract class WorkspaceRemote {
  AuthService get auth;
  Future<Map<String, dynamic>> readWorkspace({String? semester});
  Future<Map<String, dynamic>> writeWorkspace(Map<String, dynamic> pending);
}

class SharedApi implements WorkspaceRemote {
  SharedApi(this.auth, {String? baseUrl, http.Client? client})
    : base = baseUrl ?? const String.fromEnvironment('ATTENDANCE_API_URL'),
      client = client ?? http.Client();
  @override
  final AuthService auth;
  final String base;
  final http.Client client;
  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) => request(
    'GET',
    '/api/workspaces${semester == null ? '' : '?semester=${Uri.encodeComponent(semester)}'}',
  );
  @override
  Future<Map<String, dynamic>> writeWorkspace(Map<String, dynamic> pending) =>
      request('PUT', '/api/workspaces', pending);
  bool get configured =>
      Uri.tryParse(base)?.scheme == 'https' &&
      Uri.tryParse(base)?.host.isNotEmpty == true;
  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Object? body,
  ]) async {
    if (!configured) {
      throw const AppProblem('Chưa cấu hình máy chủ đồng bộ HTTPS.');
    }
    final owner = auth.current?.uid;
    final token = await auth.token();
    if (owner != auth.current?.uid) {
      throw const AppProblem('Tài khoản đã thay đổi.');
    }
    final response = await client
        .send(
          http.Request(
              method,
              Uri.parse('${base.replaceFirst(RegExp(r'/+$'), '')}$path'),
            )
            ..headers.addAll({
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            })
            ..body = body == null ? '' : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final text = await response.stream.bytesToString().timeout(
      const Duration(seconds: 15),
    );
    if (owner != auth.current?.uid) {
      throw const AppProblem('Tài khoản đã thay đổi.');
    }
    if (response.statusCode == 409) throw const SyncConflict();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AppProblem(
        'Cần đăng nhập lại hoặc cấp quyền giảng viên trên máy chủ.',
      );
    }
    if (response.statusCode != 200) {
      throw AppProblem('Máy chủ chưa nhận dữ liệu (${response.statusCode}).');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }
}

class SyncConflict extends AppProblem {
  const SyncConflict()
    : super(
        'Có thay đổi trên thiết bị khác. Bản trên máy được giữ; cần đối chiếu trước khi tiếp tục.',
      );
}

class WorkspaceAccessDenied extends AppProblem {
  const WorkspaceAccessDenied()
    : super('Tài khoản chưa được cấp quyền giảng viên trong Firebase.');
}

/// Durable local outbox + optimistic server revision; never silently overwrites
/// another device. One queue serializes polling, local edits and retries.
class SharedWorkspaceSync extends ChangeNotifier {
  SharedWorkspaceSync(this.api, this.root);
  final WorkspaceRemote api;
  final Directory root;
  String status = 'Chưa đồng bộ';
  bool conflict = false;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  String get owner =>
      api.auth.current?.uid ?? (throw const AppProblem('Vui lòng đăng nhập.'));
  WorkspaceStore local(String uid) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(uid)) {
      throw const AppProblem('UID không hợp lệ.');
    }
    return WorkspaceStore(Directory('${root.path}/teachers/$uid'));
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _status(String value, {bool isConflict = false}) {
    if (status == value && conflict == isConflict) return;
    status = value;
    conflict = isConflict;
    if (!_disposed) notifyListeners();
  }

  File _meta(String uid, String semester) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(semester)) {
      throw const AppProblem('Học kỳ không hợp lệ.');
    }
    return File('${local(uid).rootDirectory.path}/$semester/sync.json');
  }

  Future<Map<String, dynamic>> _read(File file) async => await file.exists()
      ? jsonDecode(await file.readAsString()) as Map<String, dynamic>
      : {'revision': 0};
  Future<void> _write(File file, Object value) async {
    await file.parent.create(recursive: true);
    await writeReportAtomically(
      file,
      Stream.value(utf8.encode(jsonEncode(value))),
    );
  }

  Future<TeacherWorkspace?> _push(
    String uid,
    File file,
    Map<String, dynamic> state,
  ) async {
    final pending = state['pending'] as Map<String, dynamic>?;
    if (pending == null) return null;
    if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
    Map<String, dynamic> result;
    try {
      result = await api.writeWorkspace(pending);
    } on SyncConflict {
      final closing = pending['closing'] as Map?;
      if (closing == null) rethrow;
      final localWorkspace = TeacherWorkspace.fromJson(
        (pending['workspace'] as Map).cast<String, Object?>(),
      );
      final latest = await api.readWorkspace(semester: localWorkspace.semester);
      final row = latest['data'] as Map?;
      if (row == null) rethrow;
      final serverWorkspace = TeacherWorkspace.fromJson(
        (row['workspace'] as Map).cast<String, Object?>(),
      );
      final merged = _mergeClosure(
        localWorkspace,
        serverWorkspace,
        classId: closing['classId'] as String,
        meetingId: closing['meetingId'] as String,
      );
      if (merged == null) rethrow;
      final retry = {
        ...pending,
        'workspace': merged.toJson(),
        'revision': row['revision'],
      };
      if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
      result = await api.writeWorkspace(retry);
    }
    final row = result['data'] as Map;
    TeacherWorkspace? confirmed;
    if (pending['closing'] != null) {
      confirmed = TeacherWorkspace.fromJson(
        (row['workspace'] as Map).cast<String, Object?>(),
      );
      await local(uid).saveWorkspace(confirmed);
    }
    state['revision'] = row['revision'];
    state.remove('pending');
    await _write(file, state);
    return confirmed;
  }

  // Retry a close only when the difference is confined to the same meeting.
  // A mark recorded on the server takes precedence over a default absence.
  TeacherWorkspace? _mergeClosure(
    TeacherWorkspace localWorkspace,
    TeacherWorkspace serverWorkspace, {
    required String classId,
    required String meetingId,
  }) {
    final localClass = localWorkspace.classes.firstWhereOrNull(
      (c) => c.id == classId,
    );
    final serverClass = serverWorkspace.classes.firstWhereOrNull(
      (c) => c.id == classId,
    );
    final localMeeting = localClass?.meetings.firstWhereOrNull(
      (m) => m.id == meetingId,
    );
    final serverMeeting = serverClass?.meetings.firstWhereOrNull(
      (m) => m.id == meetingId,
    );
    if (localClass == null ||
        serverClass == null ||
        localMeeting?.state != MeetingState.closed ||
        serverMeeting?.state != MeetingState.active) {
      return null;
    }
    TeacherWorkspace withoutResult(
      TeacherWorkspace value,
      CourseClass course,
    ) => value.copyWith(
      updatedAt: serverWorkspace.updatedAt,
      classes: [
        for (final c in value.classes)
          if (c.id == classId)
            course.copyWith(
              meetings: [
                for (final m in course.meetings)
                  m.id == meetingId
                      ? m.copyWith(state: MeetingState.active)
                      : m,
              ],
              attendance: {...course.attendance}..remove(meetingId),
            )
          else
            c,
      ],
    );
    if (!const DeepCollectionEquality().equals(
      withoutResult(localWorkspace, localClass).toJson(),
      withoutResult(serverWorkspace, serverClass).toJson(),
    )) {
      return null;
    }

    final records = {...?localClass.attendance[meetingId]};
    for (final entry in (serverClass.attendance[meetingId] ?? {}).entries) {
      final remoteMark = entry.value;
      if (remoteMark.status == AttendanceStatus.unmarked) continue;
      final localMark = records[entry.key];
      if (localMark != null &&
          localMark.status != AttendanceStatus.unmarked &&
          localMark.status != remoteMark.status &&
          localMark.source != AttendanceSource.finalize) {
        return null;
      }
      records[entry.key] = remoteMark;
    }
    return localWorkspace.copyWith(
      classes: [
        for (final course in localWorkspace.classes)
          if (course.id == classId)
            course.copyWith(
              attendance: {...course.attendance, meetingId: records},
            )
          else
            course,
      ],
    );
  }

  Future<TeacherWorkspace> save(
    TeacherWorkspace workspace, {
    ({String classId, String meetingId})? closing,
  }) {
    final uid = owner;
    return _serial(() async {
      if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
      final file = _meta(uid, workspace.semester);
      final state = await _read(file);
      state['pending'] = {
        'workspace': workspace.toJson(),
        'revision': state['revision'],
        'mutationId': const Uuid().v4(),
        if (closing != null)
          'closing': {
            'classId': closing.classId,
            'meetingId': closing.meetingId,
          },
      };
      await _write(
        file,
        state,
      ); // outbox first, recoverable even if local write fails
      await local(uid).saveWorkspace(workspace);
      try {
        final confirmed = await _push(uid, file, state);
        _status('Đã đồng bộ');
        return confirmed ?? workspace;
      } on WorkspaceAccessDenied {
        rethrow;
      } on SyncConflict {
        _status(const SyncConflict().message, isConflict: true);
      } on Object {
        _status('Đã lưu trên máy · Chờ đồng bộ');
      }
      return workspace;
    });
  }

  Future<TeacherWorkspace?> load({String? semester}) {
    final uid = owner;
    return _serial(() async {
      if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
      final disk = local(uid);
      var cached = semester == null
          ? await disk.loadMostRecentWorkspace()
          : await disk.loadWorkspace(semester);
      var key = semester ?? cached?.semester;
      if (key == null && await disk.rootDirectory.exists()) {
        final pendingFiles = <File>[];
        await for (final dir in disk.rootDirectory.list()) {
          if (dir is Directory) {
            final file = File('${dir.path}/sync.json');
            if (await file.exists() && (await _read(file))['pending'] != null) {
              pendingFiles.add(file);
            }
          }
        }
        pendingFiles.sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
        if (pendingFiles.isNotEmpty) {
          key = pendingFiles.first.parent.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last;
        }
      }
      if (key != null) {
        final file = _meta(uid, key), state = await _read(_meta(uid, key));
        if (state['pending'] != null) {
          final pending = TeacherWorkspace.fromJson(
            Map<String, Object?>.from(
              (state['pending'] as Map)['workspace'] as Map,
            ),
          );
          try {
            final confirmed = await _push(uid, file, state);
            if (confirmed == null) await disk.saveWorkspace(pending);
            cached = confirmed ?? pending;
          } on WorkspaceAccessDenied {
            rethrow;
          } on SyncConflict {
            _status(const SyncConflict().message, isConflict: true);
            return pending;
          } on Object {
            _status('Đã lưu trên máy · Chờ đồng bộ');
            return pending;
          }
        }
      }
      try {
        final result = await api.readWorkspace(semester: key);
        final row = result['data'] as Map?;
        if (row == null) {
          _status('Chưa có bản trên máy chủ');
          return cached;
        }
        final workspace = TeacherWorkspace.fromJson(
          Map<String, Object?>.from(row['workspace'] as Map),
        );
        final metadata = await _read(_meta(uid, workspace.semester));
        if (cached?.semester == workspace.semester &&
            metadata['revision'] == row['revision'] &&
            metadata['pending'] == null) {
          _status('Đã đồng bộ');
          return cached;
        }
        if (cached != null && !await _meta(uid, workspace.semester).exists()) {
          await _write(
            File(
              '${disk.rootDirectory.path}/${cached.semester}/before-sync-${DateTime.now().millisecondsSinceEpoch}.json',
            ),
            cached.toJson(),
          );
        }
        await disk.saveWorkspace(workspace);
        await _write(_meta(uid, workspace.semester), {
          'revision': row['revision'],
        });
        _status('Đã đồng bộ');
        return workspace;
      } on WorkspaceAccessDenied {
        rethrow;
      } on Object {
        _status('Đang dùng bản trên máy · Chưa kết nối');
        return cached;
      }
    });
  }

  Future<TeacherWorkspace?> useServer(String semester) {
    final uid = owner;
    return _serial(() async {
      if (uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
      final file = _meta(uid, semester);
      final result = await api.readWorkspace(semester: semester);
      final row = result['data'] as Map?;
      if (row == null) throw const AppProblem('Không có bản trên máy chủ.');
      final state = await _read(file);
      await _write(
        File('${file.path}.backup-${DateTime.now().millisecondsSinceEpoch}'),
        state,
      );
      final workspace = TeacherWorkspace.fromJson(
        Map<String, Object?>.from(row['workspace'] as Map),
      );
      await local(uid).saveWorkspace(workspace);
      await _write(file, {'revision': row['revision']});
      _status('Đã nhận bản máy chủ · Đã giữ bản đối chiếu trên máy');
      return workspace;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
