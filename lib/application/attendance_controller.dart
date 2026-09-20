import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/attendance_csv_exporter.dart';
import '../data/drive_sync_service.dart';
import '../data/google_drive_auth.dart';
import '../data/roster_importer.dart';
import '../data/workspace_store.dart';
import '../domain/attendance_service.dart';
import '../domain/models.dart';
import '../domain/roster_merge_service.dart';
import '../domain/schedule_service.dart';

class AttendanceController extends ChangeNotifier {
  AttendanceController({
    RosterImporter? importer,
    AttendanceService? attendanceService,
    AttendanceCsvExporter? csvExporter,
    RosterMergeService? rosterMergeService,
  }) : _importer = importer ?? RosterImporter(),
       _attendanceService = attendanceService ?? AttendanceService(),
       _csvExporter = csvExporter ?? AttendanceCsvExporter(),
       _rosterMergeService = rosterMergeService ?? RosterMergeService();

  final RosterImporter _importer;
  final AttendanceService _attendanceService;
  final AttendanceCsvExporter _csvExporter;
  final RosterMergeService _rosterMergeService;
  WorkspaceStore? _store;
  final GoogleDriveAuth _driveAuth = GoogleDriveAuth();
  AutoRefreshingAuthClient? _driveClient;
  DriveSyncService? _driveSync;
  Timer? _syncDebounce;
  Timer? _leaseRenewal;
  Timer? _calendarReconciliation;
  Future<void>? _syncOperation;
  bool _reconcilingCalendar = false;

  TeacherWorkspace? workspace;
  String? workspacePath;
  String? lastMessage;
  bool busy = false;

  Future<void> initialize() async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${documents.path}${Platform.pathSeparator}FAP Attendance',
    );
    _store = WorkspaceStore(root);
    workspace = await _store!.loadMostRecentWorkspace();
    if (workspace != null) {
      final migratedSessions = await _store!.migrateLegacySessions(workspace!);
      workspacePath =
          '${root.path}${Platform.pathSeparator}${workspace!.semester}${Platform.pathSeparator}workspace.json';
      lastMessage =
          workspace!.classes.any(
            (course) => course.meetings.any(
              (meeting) => meeting.state == MeetingState.active,
            ),
          )
          ? 'Có slot điểm danh chưa chốt. Mở lớp để tiếp tục hoặc chốt danh sách.'
          : null;
      if (migratedSessions > 0) {
        lastMessage =
            'Đã chuyển $migratedSessions slot sang định dạng một file duy nhất.';
      }
      await finalizeOverdueMeetings();
    }
    _startCalendarReconciliation();
  }

  Future<List<String>> importRoster({
    required Uint8List bytes,
    required String fileName,
    required String semester,
    required DateTime semesterStart,
    String teacherEmail = '',
    int weeks = 10,
    int meetingsPerWeek = 2,
  }) async {
    busy = true;
    lastMessage = null;
    notifyListeners();
    try {
      final result = _importer.importBytes(
        bytes,
        fileName: fileName,
        semester: semester,
        semesterStart: semesterStart,
        weeks: weeks,
        meetingsPerWeek: meetingsPerWeek,
      );
      var previous = workspace;
      if (previous == null ||
          previous.semester.trim().toUpperCase() !=
              semester.trim().toUpperCase()) {
        previous = await _store!.loadWorkspace(semester);
      }
      RosterMergeResult? mergeResult;
      if (previous != null &&
          previous.semester.trim().toUpperCase() ==
              semester.trim().toUpperCase()) {
        mergeResult = _rosterMergeService.merge(
          existing: previous.classes,
          imported: result.classes,
        );
        workspace = previous.copyWith(
          classes: mergeResult.classes,
          teacherEmail: teacherEmail.trim().isEmpty
              ? previous.teacherEmail
              : teacherEmail.trim().toLowerCase(),
          updatedAt: DateTime.now().toUtc(),
        );
      } else {
        workspace = TeacherWorkspace(
          id: const Uuid().v4(),
          semester: semester,
          semesterStart: semesterStart,
          teacherEmail: teacherEmail.trim().toLowerCase(),
          classes: result.classes,
          updatedAt: DateTime.now().toUtc(),
        );
      }
      await save();
      final migratedSessions = await _store!.migrateLegacySessions(workspace!);
      await finalizeOverdueMeetings();
      await _store!.saveSource(
        semester: semester,
        fileName: fileName,
        bytes: bytes,
      );
      lastMessage = mergeResult == null
          ? 'Đã import ${result.classes.length} lớp cho học kỳ $semester.'
          : 'Đã cập nhật ${mergeResult.updatedClasses} lớp, thêm ${mergeResult.addedClasses} lớp mới và giữ nguyên toàn bộ lịch sử điểm danh.';
      if (migratedSessions > 0) {
        lastMessage =
            '$lastMessage Đã gộp $migratedSessions slot cũ về một file cho mỗi slot.';
      }
      return result.warnings;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> save() async {
    final value = workspace;
    if (value == null || _store == null) return;
    final updated = value.copyWith(
      syncState: _driveSync == null
          ? (value.syncState == SyncState.synced
                ? SyncState.pendingSync
                : value.syncState)
          : SyncState.pendingSync,
      updatedAt: DateTime.now().toUtc(),
    );
    workspace = updated;
    final file = await _store!.saveWorkspace(updated);
    workspacePath = file.path;
    _scheduleDriveSync();
    notifyListeners();
  }

  bool get driveConnected => _driveSync != null;
  bool get syncingDrive => _syncOperation != null;

  Future<List<DriveSourceFile>> driveSourceFiles() async {
    if (_driveSync == null) throw StateError('Hãy kết nối Google Drive trước.');
    return _driveSync!.listSourceFiles();
  }

  Future<Uint8List> downloadDriveSource(String fileId) async {
    if (_driveSync == null) throw StateError('Hãy kết nối Google Drive trước.');
    return Uint8List.fromList(await _driveSync!.downloadSource(fileId));
  }

  Future<void> connectDrive({
    required String clientId,
    required String clientSecret,
  }) async {
    if (clientId.trim().isEmpty) {
      throw StateError('Thiếu GOOGLE_OAUTH_CLIENT_ID.');
    }
    busy = true;
    notifyListeners();
    try {
      _driveClient =
          await _driveAuth.restore(
            clientId: clientId,
            clientSecret: clientSecret,
          ) ??
          await _driveAuth.signIn(
            clientId: clientId,
            clientSecret: clientSecret,
          );
      _driveSync = DriveSyncService(drive.DriveApi(_driveClient!));
      await syncNow();
      _leaseRenewal?.cancel();
      _leaseRenewal = Timer.periodic(const Duration(minutes: 1), (_) async {
        final value = workspace;
        if (value == null) return;
        try {
          await _driveSync?.acquireLease(value.id);
        } on Object {
          // Lần đồng bộ kế tiếp sẽ hiển thị lỗi lease cho giảng viên.
        }
      });
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> syncNow() {
    final active = _syncOperation;
    if (active != null) return active;
    final value = workspace;
    if (value == null || _store == null || _driveSync == null) {
      return Future.value();
    }
    _syncDebounce?.cancel();
    _syncDebounce = null;
    late final Future<void> operation;
    operation = _performSync(value).whenComplete(() {
      if (identical(_syncOperation, operation)) {
        _syncOperation = null;
        notifyListeners();
      }
    });
    _syncOperation = operation;
    notifyListeners();
    return operation;
  }

  Future<void> _performSync(TeacherWorkspace value) async {
    try {
      final result = await _driveSync!.syncDirectory(
        semesterDirectory: _store!.semesterDirectory(value.semester),
        workspaceId: value.id,
      );
      final latest = workspace;
      if (latest == null || latest.id != value.id) return;
      final changedDuringSync = !_sameUpdatedAt(
        latest.updatedAt,
        value.updatedAt,
      );
      workspace = latest.copyWith(
        syncState: changedDuringSync ? SyncState.pendingSync : SyncState.synced,
      );
      await _store!.saveWorkspace(workspace!);
      lastMessage = changedDuringSync
          ? 'Dữ liệu thay đổi trong lúc đồng bộ; app sẽ đồng bộ thêm một lượt.'
          : 'Đã đồng bộ Google Drive: ${result.uploaded} file cập nhật, ${result.unchanged} file không đổi${result.cleanedFolders == 0 ? '' : ', đã dọn ${result.cleanedFolders} thư mục cũ sai cấu trúc'}${result.cleanedFiles == 0 ? '' : ', đã dọn ${result.cleanedFiles} file phiên bản cũ'}.';
      if (changedDuringSync) _scheduleDriveSync();
    } on DriveConflictException catch (error) {
      final latest = workspace;
      if (latest != null && latest.id == value.id) {
        workspace = latest.copyWith(syncState: SyncState.conflict);
        await _store!.saveWorkspace(workspace!);
      }
      lastMessage = '$error Các bản Drive được lưu với đuôi .drive-conflict.';
      rethrow;
    } on Object {
      final latest = workspace;
      if (latest != null && latest.id == value.id) {
        workspace = latest.copyWith(syncState: SyncState.pendingSync);
        await _store!.saveWorkspace(workspace!);
      }
      rethrow;
    }
  }

  bool _sameUpdatedAt(DateTime? first, DateTime? second) {
    if (first == null || second == null) return first == second;
    return first.isAtSameMomentAs(second);
  }

  void _scheduleDriveSync() {
    if (_driveSync == null) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 10), () async {
      try {
        await syncNow();
      } on Object {
        // Trạng thái pending/conflict đã được cập nhật để thử lại về sau.
      }
    });
  }

  Future<void> loadSemester(String semester) async {
    if (_store == null) await initialize();
    workspace = await _store!.loadWorkspace(semester);
    workspacePath = workspace == null
        ? null
        : '${_store!.rootDirectory.path}${Platform.pathSeparator}$semester${Platform.pathSeparator}workspace.json';
    if (workspace != null) {
      final migratedSessions = await _store!.migrateLegacySessions(workspace!);
      if (migratedSessions > 0) {
        lastMessage =
            'Đã chuyển $migratedSessions slot sang định dạng một file duy nhất.';
      }
    }
    await finalizeOverdueMeetings();
    notifyListeners();
  }

  Future<int> finalizeOverdueMeetings({DateTime? now}) async {
    final value = workspace;
    if (value == null || _store == null || _reconcilingCalendar) return 0;
    _reconcilingCalendar = true;
    try {
      final current = now ?? DateTime.now();
      final finalized = <(String, String)>[];
      final updatedClasses = value.classes.map((courseClass) {
        for (final meeting in courseClass.meetings) {
          if (meeting.state != MeetingState.closed &&
              meeting.isBeforeDate(current)) {
            finalized.add((courseClass.id, meeting.id));
          }
        }
        return _attendanceService.finalizeOverdueMeetings(
          courseClass,
          now: current,
        );
      }).toList();
      if (finalized.isEmpty) return 0;

      workspace = value.copyWith(classes: updatedClasses);
      for (final item in finalized) {
        final courseClass = classById(item.$1);
        await _store!.saveFinalVersion(
          workspace!,
          courseClass,
          meetingById(item.$1, item.$2),
        );
      }
      lastMessage =
          'Đã tự động chốt ${finalized.length} slot quá ngày và đánh dấu A cho các ô còn trống.';
      await save();
      return finalized.length;
    } finally {
      _reconcilingCalendar = false;
    }
  }

  void _startCalendarReconciliation() {
    _calendarReconciliation?.cancel();
    _calendarReconciliation = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(finalizeOverdueMeetings());
    });
  }

  CourseClass classById(String classId) => workspace!.classes.singleWhere(
    (courseClass) => courseClass.id == classId,
  );

  Future<void> startMeeting(String classId, String meetingId) async {
    final otherActive = workspace!.classes.any(
      (course) => course.meetings.any(
        (meeting) =>
            meeting.state == MeetingState.active && meeting.id != meetingId,
      ),
    );
    if (otherActive) {
      throw StateError('Chỉ được mở một slot điểm danh tại một thời điểm.');
    }
    final courseClass = classById(classId);
    _replaceClass(_attendanceService.startMeeting(courseClass, meetingId));
    await _store?.saveWorkingSession(
      workspace!,
      classById(classId),
      meetingById(classId, meetingId),
    );
    await save();
  }

  Future<void> markPresent(
    String classId,
    String meetingId,
    String email, {
    AttendanceSource source = AttendanceSource.simulator,
  }) async {
    final updated = _attendanceService.markPresent(
      classById(classId),
      meetingId: meetingId,
      email: email,
      source: source,
    );
    _replaceClass(updated);
    await _store?.saveWorkingSession(
      workspace!,
      updated,
      meetingById(classId, meetingId),
    );
    await save();
  }

  Future<void> closeMeeting(String classId, String meetingId) async {
    final updated = _attendanceService.closeMeeting(
      classById(classId),
      meetingId,
    );
    _replaceClass(updated);
    await _store?.saveFinalVersion(
      workspace!,
      updated,
      meetingById(classId, meetingId),
    );
    await save();
    await _syncCritical();
  }

  Future<void> overrideStatus({
    required String classId,
    required String meetingId,
    required String rollNumber,
    required AttendanceStatus status,
    required String reason,
  }) async {
    final courseClass = classById(classId);
    final updated = _attendanceService.overrideStatus(
      courseClass,
      meetingId: meetingId,
      rollNumber: rollNumber,
      status: status,
      reason: reason,
      auditId: const Uuid().v4(),
    );
    _replaceClass(updated);
    final meeting = meetingById(classId, meetingId);
    if (meeting.state == MeetingState.closed) {
      await _store?.saveFinalVersion(workspace!, updated, meeting);
    } else {
      await _store?.saveWorkingSession(workspace!, updated, meeting);
    }
    await save();
  }

  Future<File> exportMeeting(String classId, String meetingId) async {
    if (_store == null) throw StateError('Storage chưa khởi tạo.');
    final courseClass = classById(classId);
    final meeting = meetingById(classId, meetingId);
    final directory = await _store!.exportDirectory(workspace!, courseClass);
    final file = await _csvExporter.export(
      directory,
      workspace!,
      courseClass,
      meeting,
    );
    lastMessage = 'Đã xuất ${file.path}';
    notifyListeners();
    await _syncCritical();
    return file;
  }

  Future<void> _syncCritical() async {
    _syncDebounce?.cancel();
    if (_driveSync == null) return;
    try {
      await syncNow();
    } on Object {
      // Dữ liệu local vẫn an toàn và sẽ được thử lại ở lần đồng bộ kế tiếp.
    }
  }

  Meeting meetingById(String classId, String meetingId) =>
      classById(classId).meetings
          .singleWhere((meeting) => meeting.id == meetingId);

  double absenceRate(String classId, String rollNumber) =>
      _attendanceService.absenceRate(classById(classId), rollNumber);

  Future<void> updateSchedule(String classId, ScheduleRule rule) async {
    final courseClass = classById(classId);
    if (courseClass.meetings.any(
      (meeting) => meeting.state != MeetingState.upcoming,
    )) {
      throw StateError(
        'Không thể đổi lịch sau khi đã bắt đầu điểm danh một slot.',
      );
    }
    final updated = courseClass.copyWith(
      scheduleRule: rule,
      meetings: ScheduleService().generate(rule, courseClass.id),
      attendance: const {},
    );
    _replaceClass(updated);
    await save();
  }

  Future<void> deleteClass(String classId) async {
    final value = workspace;
    if (value == null || _store == null) return;
    final courseClass = classById(classId);
    if (courseClass.meetings.any(
      (meeting) => meeting.state == MeetingState.active,
    )) {
      throw StateError('Hãy chốt slot đang điểm danh trước khi xóa lớp.');
    }
    await _store!.archiveClass(value, courseClass);
    workspace = value.copyWith(
      classes: value.classes
          .where((item) => item.id != classId)
          .toList(growable: false),
    );
    lastMessage =
        'Đã xóa lớp ${courseClass.courseCode} · ${courseClass.classCode} khỏi workspace.';
    await save();
    await _syncCritical();
  }

  void _replaceClass(CourseClass updated) {
    final value = workspace!;
    workspace = value.copyWith(
      classes: value.classes
          .map(
            (courseClass) =>
                courseClass.id == updated.id ? updated : courseClass,
          )
          .toList(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _leaseRenewal?.cancel();
    _calendarReconciliation?.cancel();
    _driveClient?.close();
    super.dispose();
  }
}
