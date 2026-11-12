import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/attendance_csv_exporter.dart';
import '../data/attendance_pdf_exporter.dart';
import '../data/firestore_report_metadata.dart';
import '../data/desktop_teacher_auth.dart';
import '../data/firestore_workspace_remote.dart';
import '../lab3/services/firestore_attendance_links.dart';
import '../data/shared_workspace_sync.dart';
import '../data/synced_desktop_store.dart';
import '../lab3/services/attendance_link_service.dart';
import '../lab3/services/contracts.dart';
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
    AuthService? teacherAuth,
    this.finalFirebase = false,
  }) : _importer = importer ?? RosterImporter(),
       _attendanceService = attendanceService ?? AttendanceService(),
       _csvExporter = csvExporter ?? AttendanceCsvExporter(),
       _rosterMergeService = rosterMergeService ?? RosterMergeService(),
       desktopAuth = teacherAuth ?? DesktopTeacherAuth();

  final RosterImporter _importer;
  final AttendanceService _attendanceService;
  final AttendanceCsvExporter _csvExporter;
  final RosterMergeService _rosterMergeService;
  WorkspaceStore? _store;
  Timer? _calendarReconciliation;
  bool _reconcilingCalendar = false;

  TeacherWorkspace? workspace;
  String? workspacePath;
  String? lastMessage;
  bool busy = false;
  final AuthService desktopAuth;
  final bool finalFirebase;
  SharedWorkspaceSync? sync;
  TeacherWorkspace? _legacyWorkspace;
  bool get canMigrateLegacy =>
      sync != null && workspace == null && _legacyWorkspace != null;
  Future<void> migrateLegacy() async {
    if (!canMigrateLegacy || busy) return;
    busy = true;
    notifyListeners();
    try {
      final remote = await sync!.api.readWorkspace();
      if (remote['data'] != null) {
        throw const AppProblem(
          'Tài khoản đã có dữ liệu. Đồng bộ trước để đối chiếu, không ghi đè dữ liệu cũ.',
        );
      }
      final value = _legacyWorkspace!.copyWith(
        teacherEmail: desktopAuth.current!.email,
      );
      await sync!.save(value);
      workspace = value;
      _legacyWorkspace = null;
      lastMessage = sync!.status;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  AttendanceLinkService? sharedLinks;
  String get syncLabel => sync?.status ?? 'Lưu trên thiết bị';
  Future<void> disconnectAccount() async {
    if (busy) return;
    busy = true;
    try {
      await desktopAuth.signOut();
    } finally {
      sync?.removeListener(notifyListeners);
      sync?.dispose();
      sync = null;
      sharedLinks = null;
      workspace = null;
      workspacePath = null;
      final documents = await getApplicationDocumentsDirectory();
      _store = WorkspaceStore(Directory('${documents.path}/FAP Attendance'));
      busy = false;
      notifyListeners();
    }
  }

  Future<void> connectAccount() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      await desktopAuth.signIn();
      final remote = finalFirebase ? FirestoreWorkspaceRemote(FirebaseFirestore.instance, desktopAuth) : null;
      if (remote != null) {
        try { await remote.requireTeacher(); }
        on Object { await desktopAuth.signOut(); rethrow; }
      }
      if (sync == null && workspace != null) _legacyWorkspace = workspace;
      final documents = await getApplicationDocumentsDirectory();
      sync?.removeListener(notifyListeners);
      sync?.dispose();
      sync = SharedWorkspaceSync(
        remote ?? SharedApi(desktopAuth),
        Directory('${documents.path}/FAP Attendance Shared'),
      );
      sync!.addListener(notifyListeners);
      _store = SyncedDesktopStore(sync!, desktopAuth.current!.uid);
      sharedLinks = finalFirebase
          ? FirestoreAttendanceLinks(FirebaseFirestore.instance, desktopAuth, () => workspace?.semester,
              hostingUrl: 'https://${FirebaseFirestore.instance.app.options.projectId}.web.app')
          : HttpAttendanceLinkService(desktopAuth);
      workspace = await _store!.loadMostRecentWorkspace();
      lastMessage =
          'Đã đăng nhập ${desktopAuth.current!.email}. Dữ liệu cũ trên máy được giữ riêng; import vào tài khoản nếu cần.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refreshShared({bool useServer = false}) async {
    if (sync == null || busy) return;
    busy = true;
    notifyListeners();
    try {
      workspace = useServer && workspace != null
          ? await sync!.useServer(workspace!.semester)
          : await sync!.load(semester: workspace?.semester);
      lastMessage = sync!.status;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<LinkUpdate> sharedResults(LinkSession session) async {
    await refreshShared();
    final update = await sharedLinks!.poll(session);
    final c = classById(session.classId);
    if (meetingById(c.id, session.meetingId).state == MeetingState.closed) {
      return update;
    }
    var updated = c;
    for (final submission in update.submissions) {
      final student = c.students
          .where((s) => s.normalizedEmail == submission.email)
          .firstOrNull;
      if (student != null &&
          updated.recordFor(session.meetingId, student.rollNumber) == null) {
        updated = _attendanceService.markPresent(
          updated,
          meetingId: session.meetingId,
          email: submission.email,
          source: AttendanceSource.scan,
          now: submission.at,
        );
      }
    }
    if (!identical(c, updated)) {
      _replaceClass(updated);
      await save();
    }
    return update;
  }

  Future<void> initialize() async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${documents.path}${Platform.pathSeparator}FAP Attendance',
    );
    _store = WorkspaceStore(root);
    workspace = await _store!.loadMostRecentWorkspace();
    if (finalFirebase) {
      _legacyWorkspace = workspace;
      workspace = null;
    }
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
    if (finalFirebase && sync == null) throw const AppProblem('Vui lòng đăng nhập Google trước khi nạp lớp vào Firebase.');
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

  Future<void> save({({String classId, String meetingId})? closing}) async {
    final value = workspace;
    if (value == null || _store == null) return;
    final updated = value.copyWith(updatedAt: DateTime.now().toUtc());
    workspace = updated;
    final shared = sync;
    if (shared != null && closing != null) {
      workspace = await shared.save(updated, closing: closing);
      workspacePath =
          '${_store!.rootDirectory.path}${Platform.pathSeparator}${updated.semester}${Platform.pathSeparator}workspace.json';
    } else {
      final file = await _store!.saveWorkspace(updated);
      workspacePath = file.path;
    }
    notifyListeners();
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
    if (sharedLinks != null) {
      final service = sharedLinks!;
      final session = service is LiveAttendanceLinks
          ? await service.current()
          : await (service as HttpAttendanceLinkService).current();
      if (session != null &&
          session.classId == classId &&
          session.meetingId == meetingId) {
        await sharedLinks!.stop(session);
        await sharedResults(session);
      }
    }
    final updated = _attendanceService.closeMeeting(
      classById(classId),
      meetingId,
    );
    _replaceClass(updated);
    if (sync != null) {
      await save(closing: (classId: classId, meetingId: meetingId));
    }
    await _store?.saveFinalVersion(
      workspace!,
      classById(classId),
      meetingById(classId, meetingId),
    );
    if (sync == null) await save();
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

  Future<File> exportMeeting(String classId, String meetingId, {String format = 'csv'}) async {
    if (_store == null) throw StateError('Storage chưa khởi tạo.');
    final courseClass = classById(classId);
    final meeting = meetingById(classId, meetingId);
    final directory = await _store!.exportDirectory(workspace!, courseClass);
    final file = format == 'pdf' ? await AttendancePdfExporter().export(directory, workspace!, courseClass, meeting) : await _csvExporter.export(
      directory,
      workspace!,
      courseClass,
      meeting,
    );
    lastMessage = 'Đã xuất ${file.path}';
    if (finalFirebase && sync != null) {
      final reports = FirestoreReportMetadata(FirebaseFirestore.instance, sync!.root);
      await reports.record(desktopAuth.current!.uid, workspace!, courseClass, meeting, file, format);
      lastMessage = reports.warning ?? lastMessage;
    }
    notifyListeners();
    return file;
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
    sync?.removeListener(notifyListeners);
    sync?.dispose();
    _calendarReconciliation?.cancel();
    super.dispose();
  }
}
