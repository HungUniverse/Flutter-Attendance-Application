import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/roster_importer.dart';
import '../../data/shared_workspace_sync.dart';
import '../services/attendance_link_service.dart';
import '../services/firestore_attendance_links.dart';
import '../../domain/attendance_service.dart';
import '../../domain/models.dart';
import '../../domain/roster_merge_service.dart';
import '../../domain/schedule_service.dart';
import '../services/contracts.dart';
import '../services/report_destination.dart';
import '../services/synced_workspace_repository.dart';
import '../services/ai_attendance_review.dart';

enum AttendanceMode { link, manual }

class TeacherViewModel extends ChangeNotifier {
  TeacherViewModel({
    required this.auth,
    required this.repository,
    required this.telemetry,
    required this.config,
    required this.notifications,
    this.uploads,
    required this.device,
    required this.links,
    this.sync,
    this.ai,
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;

  final AuthService auth;
  final SharedWorkspaceSync? sync;
  final MobileWorkspaceRepository repository;
  final TelemetryService telemetry;
  final ConfigService config;
  final NotificationService notifications;
  final UploadService? uploads;
  final DeviceService device;
  final AttendanceLinkService links;
  final AttendanceReviewService? ai;
  AiAttendanceReview? aiReview;
  final DateTime Function() now;
  final attendance = AttendanceService();
  TeacherIdentity? user;
  TeacherWorkspace? workspace;
  AttendanceMode mode = AttendanceMode.link;
  bool busy = false;
  bool loadingWorkspace = false;
  bool workspaceLoadFailed = false;
  bool disposed = false;
  String? error;
  String? message;
  String? linkError;
  String? cloudUrl;
  String? permission;
  String? messagingToken;
  double uploadProgress = 0;
  File? exportedFile;
  ReportDestination? reportDestination;
  LinkSession? link;
  List<AppNotice> notices = [];
  AppNotice? pendingNotice;
  StreamSubscription<TeacherIdentity?>? _authSub;
  StreamSubscription<AppNotice>? _noticeSub;
  Timer? _timer;
  Timer? _liveTimer;
  StreamSubscription<void>? _linkSub;
  String? _watchingLinkId;
  Completer<void>? _activeOperation;
  DateTime? _noticesFetchedAt;
  bool _foreground = true;
  int _generation = 0;

  String get uid =>
      user?.uid ?? (throw const AppProblem('Vui lòng đăng nhập.'));
  FeatureSettings get settings => config.current;

  Future<void> initialize({bool timers = true}) async {
    sync?.addListener(_notify);
    _noticeSub = notifications.opened.listen((notice) {
      pendingNotice = notice;
      _notify();
    });
    await _bind(auth.current);
    _authSub = auth.changes.listen((identity) {
      if (identity?.uid != user?.uid) unawaited(_bind(identity));
    });
    if (timers) {
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_foreground && user != null && !busy && !loadingWorkspace) {
          unawaited(refreshInBackground());
        }
      });
    }
  }

  Future<void> _bind(TeacherIdentity? identity) async {
    final generation = ++_generation;
    user = identity;
    workspace = null;
    aiReview = null;
    link = null;
    _watchLink();
    linkError = null;
    cloudUrl = null;
    exportedFile = null;
    reportDestination = null;
    notices = [];
    _noticesFetchedAt = null;
    permission = null;
    messagingToken = null;
    error = null;
    workspaceLoadFailed = false;
    mode = AttendanceMode.link;
    loadingWorkspace = identity != null;
    _notify();
    try {
      await _safe(() => telemetry.identify(identity?.uid));
      if (identity == null) return;
      final loaded = await repository.load(identity.uid);
      final savedLink = await repository.loadLink(identity.uid);
      if (generation != _generation || disposed) return;
      workspace = loaded;
      link = savedLink;
      _watchLink();
      await _clearClosedLink(identity.uid, savedLink);
      if (generation != _generation || disposed) return;
      if (workspace != null) await _reconcile();
      await _safe(() => config.refresh());
      if (generation != _generation || disposed) return;
      await _safe(() => notifications.start(identity.uid));
      if (generation != _generation || disposed) return;
      await _refreshNotices(identity.uid);
      if (generation != _generation || disposed) return;
      if (link != null) await _refreshLink();
    } on Object catch (e, stack) {
      if (generation == _generation) {
        error = _friendly(e);
        workspaceLoadFailed = true;
      }
      await _safe(() => telemetry.error(e, stack, 'load_workspace'));
    } finally {
      if (generation == _generation) {
        loadingWorkspace = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!disposed) notifyListeners();
  }

  static String _friendly(Object error) {
    if (error is AppProblem) return error.message;
    if (error is RosterImportException) return error.message;
    if (error is StateError) return error.message.toString();
    if (error is ArgumentError) {
      return error.message?.toString() ?? 'Dữ liệu không hợp lệ.';
    }
    if (error is FormatException) return error.message;
    if (error is SocketException || error is TimeoutException) {
      return 'Không có kết nối. Dữ liệu đã lưu trên máy được giữ lại.';
    }
    return 'Không thể hoàn tất thao tác. Kiểm tra kết nối, quyền truy cập và thử lại.';
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      /* auxiliary services never break local work */
    }
  }

  Future<bool> _run(
    String operation,
    Future<void> Function() action, {
    bool quiet = false,
    bool allowAccountChange = false,
  }) async {
    if (busy || loadingWorkspace || disposed) return false;
    // Background work stays serialized with edits, but does not disable the UI.
    // A foreground edit may wait for one in-flight refresh; timer ticks never queue.
    if (quiet && _activeOperation != null) return false;
    final generation = _generation;
    final previous = _activeOperation?.future;
    final completion = Completer<void>();
    _activeOperation = completion;
    if (!quiet) {
      busy = true;
      error = null;
      message = null;
    }
    _notify();
    try {
      if (previous != null) await previous;
      if (disposed || generation != _generation) return false;
      await action();
      return allowAccountChange || generation == _generation;
    } on Object catch (e, stack) {
      if (generation == _generation && (!quiet || e is WorkspaceAccessDenied)) {
        error = _friendly(e);
      }
      await _safe(() => telemetry.error(e, stack, operation));
      return false;
    } finally {
      if (!quiet) busy = false;
      if (identical(_activeOperation, completion)) _activeOperation = null;
      completion.complete();
      _watchLink();
      _notify();
    }
  }

  void _watchLink() {
    if (links is! LiveAttendanceLinks || _watchingLinkId == link?.id) return;
    unawaited(_linkSub?.cancel());
    _liveTimer?.cancel();
    _watchingLinkId = link?.id;
    _linkSub = link == null
        ? null
        : (links as LiveAttendanceLinks)
              .changes(link!)
              .listen(
                (_) => _scheduleLiveRefresh(),
                onError: (Object error) {
                  linkError = _friendly(error);
                  _notify();
                },
              );
  }

  void _scheduleLiveRefresh() {
    _liveTimer?.cancel();
    _liveTimer = Timer(const Duration(milliseconds: 250), () {
      if (disposed || !_foreground || link == null) return;
      if (busy || loadingWorkspace || _activeOperation != null) {
        _scheduleLiveRefresh();
      } else {
        unawaited(_run('live_check_in', _refreshLink, quiet: true));
      }
    });
  }

  Future<bool> signIn() => _run('google_sign_in', () async {
    await auth.signIn();
    await _safe(() => telemetry.event('login', {'method': 'google'}));
  }, allowAccountChange: true);
  Future<bool> signOut() => _run('sign_out', () async {
    // Stop the remote session first; do not leave a receiving link behind.
    if (link != null) await _stopLink();
    await _safe(() => notifications.stop());
    await _safe(() => telemetry.event('logout'));
    await auth.signOut();
  }, allowAccountChange: true);
  Future<void> retryLoad() => _bind(auth.current);
  void dismissMessage() {
    message = null;
    error = null;
    _notify();
  }

  CourseClass course(String id) =>
      workspace!.classes.singleWhere((c) => c.id == id);
  Meeting meeting(String classId, String meetingId) =>
      course(classId).meetings.singleWhere((m) => m.id == meetingId);
  Future<void> _persist(TeacherWorkspace value) async {
    final owner = uid;
    final generation = _generation;
    final updated = value.copyWith(updatedAt: now().toUtc());
    await repository.save(owner, updated);
    if (generation != _generation || disposed) {
      throw const AppProblem(
        'Workspace đã thay đổi. Hãy kiểm tra lại dữ liệu.',
      );
    }
    workspace = updated;
    _notify();
  }

  Future<void> _replace(CourseClass updated) => _persist(
    workspace!.copyWith(
      classes: workspace!.classes
          .map((c) => c.id == updated.id ? updated : c)
          .toList(),
    ),
  );

  RosterImportResult previewImport(
    Uint8List bytes,
    String filename,
    String semester,
    DateTime start,
    int weeks,
    int perWeek,
  ) => RosterImporter().importBytes(
    bytes,
    fileName: filename,
    semester: semester,
    semesterStart: start,
    weeks: weeks,
    meetingsPerWeek: perWeek,
  );
  Future<bool> importRoster({
    required Uint8List bytes,
    required String filename,
    required String semester,
    required DateTime start,
    required int weeks,
    required int perWeek,
  }) => _run('markbook_import', () async {
    final key = semester.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9_-]{1,32}$').hasMatch(key)) {
      throw const AppProblem(
        'Học kỳ chỉ gồm chữ, số, gạch ngang hoặc gạch dưới.',
      );
    }
    if (link != null) {
      throw const AppProblem('Hãy dừng nhận link trước khi nạp danh sách lớp.');
    }
    final parsed = previewImport(bytes, filename, key, start, weeks, perWeek);
    final previous = await repository.load(uid, semester: key);
    var value =
        previous?.copyWith(
          semesterStart: previous.classes.isEmpty ? start : null,
          classes: RosterMergeService()
              .merge(
                existing: previous.classes,
                imported: parsed.classes,
                now: now(),
              )
              .classes,
        ) ??
        TeacherWorkspace(
          id: const Uuid().v4(),
          semester: key,
          semesterStart: start,
          teacherEmail: user!.email,
          classes: parsed.classes,
        );
    value = value.copyWith(
      classes: value.classes
          .map((c) => attendance.finalizeOverdueMeetings(c, now: now()))
          .toList(),
    );
    // Save the source before publishing a success result.
    await repository.saveSource(uid, key, filename, bytes);
    await _persist(value);
    await _safe(
      () => telemetry.event('markbook_import', {
        'class_count': value.classes.length,
      }),
    );
    message = 'Đã nạp danh sách của ${parsed.classes.length} lớp.';
  });

  Future<bool> begin(String classId, String meetingId) => _run(
    'start_attendance',
    () async {
      final current = meeting(classId, meetingId);
      if (current.state == MeetingState.active) return;
      if (workspace!.classes.any(
        (c) => c.meetings.any((m) => m.state == MeetingState.active),
      )) {
        throw const AppProblem('Chỉ mở một buổi điểm danh tại một thời điểm.');
      }
      await _replace(
        attendance.startMeeting(course(classId), meetingId, now: now()),
      );
    },
  );
  void selectMode(AttendanceMode value) {
    if (mode == value) return;
    mode = value;
    _notify();
    unawaited(
      _safe(
        () => telemetry.event('attendance_mode_selected', {'mode': value.name}),
      ),
    );
  }

  Future<bool> mark(
    String classId,
    String meetingId,
    String roll,
    AttendanceStatus status, {
    String? reason,
  }) => _run('attendance_mark', () async {
    final c = course(classId);
    final old = c.recordFor(meetingId, roll);
    final updated = old == null || old.status == AttendanceStatus.unmarked
        ? attendance.markManual(
            c,
            meetingId: meetingId,
            rollNumber: roll,
            status: status,
            now: now(),
          )
        : attendance.overrideStatus(
            c,
            meetingId: meetingId,
            rollNumber: roll,
            status: status,
            reason: reason ?? '',
            auditId: const Uuid().v4(),
            now: now(),
          );
    await _replace(updated);
    await _safe(
      () => telemetry.event('attendance_marked', {
        'mode': 'manual',
        'status': attendanceCode(status),
      }),
    );
    message = 'Đã lưu trên thiết bị.';
  });
  Future<bool> edit(
    String classId,
    String meetingId,
    String roll,
    AttendanceStatus status,
    String reason,
  ) => _run('attendance_edit', () async {
    await _replace(
      attendance.overrideStatus(
        course(classId),
        meetingId: meetingId,
        rollNumber: roll,
        status: status,
        reason: reason,
        auditId: const Uuid().v4(),
        now: now(),
      ),
    );
    message = 'Đã lưu thay đổi và lý do.';
  });
  Map<AttendanceStatus, int> counts(String classId, String meetingId) {
    final c = course(classId);
    final result = {for (final s in AttendanceStatus.values) s: 0};
    for (final student in c.students) {
      final status =
          c.recordFor(meetingId, student.rollNumber)?.status ??
          AttendanceStatus.unmarked;
      result[status] = result[status]! + 1;
    }
    return result;
  }

  Future<bool> close(String classId, String meetingId) =>
      _run('close_attendance', () async {
        if (meeting(classId, meetingId).state != MeetingState.active) {
          throw const AppProblem('Buổi học chưa mở hoặc đã chốt.');
        }
        if (links is LiveAttendanceLinks) {
          link = await (links as LiveAttendanceLinks).forMeeting(
            course(classId),
            meeting(classId, meetingId),
          );
          await repository.saveLink(uid, link);
        }
        if (link != null) {
          // Freeze the server, then retrieve all accepted submissions before finalizing.
          await links.stop(link!);
          await _refreshLink();
          if (linkError != null) {
            throw const AppProblem(
              'Chưa lấy đủ kết quả từ link. Hãy thử lại trước khi chốt.',
            );
          }
          await repository.saveLink(uid, null);
          link = null;
        }
        await _replace(
          attendance.closeMeeting(course(classId), meetingId, now: now()),
        );
        final totals = counts(classId, meetingId);
        await _safe(
          () => telemetry.event('attendance_closed', {
            'present_count': totals[AttendanceStatus.present]!,
            'absent_count': totals[AttendanceStatus.absent]!,
          }),
        );
        message = 'Đã chốt. Các ô chưa ghi đã chuyển thành Absent.';
      });

  Future<bool> requestAiReview(String classId, String meetingId) => _run(
    'ai_review',
    () async {
      aiReview = null;
      if (ai == null || !settings.enableAi) {
        throw const AppProblem('Gợi ý AI đang tắt. Bạn có thể tiếp tục chốt.');
      }
      final owner = uid;
      final totals = counts(classId, meetingId);
      final review = await ai!.review(
        present: totals[AttendanceStatus.present]!,
        absent: totals[AttendanceStatus.absent]!,
        unmarked: totals[AttendanceStatus.unmarked]!,
      );
      if (uid == owner && !disposed) aiReview = review;
    },
  );

  Future<bool> acceptAiReview(String edited) => _run('ai_accept', () async {
    if (aiReview == null || ai == null) {
      throw const AppProblem('Hãy lấy gợi ý AI trước.');
    }
    await ai!.accept(edited);
    aiReview = AiAttendanceReview(edited.trim(), const []);
    message = 'Đã xác nhận nội dung kiểm tra AI.';
  });
  Future<bool> createLink(String classId, String meetingId) =>
      _run('create_link', () async {
        if (link != null) {
          if (link!.classId != classId || link!.meetingId != meetingId) {
            throw const AppProblem('Đang có link của buổi học khác.');
          }
          await _refreshLink();
          if (linkError != null) {
            throw const AppProblem(
              'Chưa kiểm tra được link hiện có. Hãy thử lại khi có mạng.',
            );
          }
          if (link!.receiving && link!.expiresAt.isAfter(now())) return;
          await _stopLink();
        }
        if (!settings.enableLink) {
          throw const AppProblem('Tạo link đang tạm tắt. Hãy dùng Thủ công.');
        }
        final m = meeting(classId, meetingId);
        if (m.state != MeetingState.active || !m.isOnDate(now())) {
          throw const AppProblem('Hãy bắt đầu buổi học hôm nay trước.');
        }
        final created = await links.create(course(classId), m);
        // Retain the server handle even if local persistence fails, so Stop remains available.
        link = created;
        await repository.saveLink(uid, created);
        linkError = null;
        await _safe(() => telemetry.event('attendance_link_created'));
      });
  Future<void> _refreshLink() async {
    final current = link;
    if (current == null) return;
    final generation = _generation;
    bool isCurrent() =>
        generation == _generation && !disposed && identical(link, current);
    try {
      final owner = uid;
      final update = await links.poll(current);
      if (!isCurrent()) return;
      final original = course(current.classId);
      var c = original;
      final m = meeting(current.classId, current.meetingId);
      if (m.state == MeetingState.active) {
        for (final submission in update.submissions) {
          if (!m.isOnDate(submission.at) ||
              (links is! LiveAttendanceLinks && submission.at.isAfter(now()))) {
            throw const AppProblem(
              'Dịch vụ link trả về thời điểm không hợp lệ.',
            );
          }
          c = attendance.markPresent(
            c,
            meetingId: m.id,
            email: submission.email,
            now: submission.at,
          );
        }
        if (!identical(c, original)) await _replace(c);
      }
      if (!isCurrent()) return;
      final updated = update.session;
      if (current.receiving != updated.receiving ||
          current.expiresAt != updated.expiresAt) {
        await repository.saveLink(owner, updated);
      }
      if (!isCurrent()) return;
      link = updated;
      linkError = null;
    } on Object catch (e) {
      if (isCurrent()) linkError = _friendly(e);
    }
  }

  Future<void> _stopLink() async {
    final current = link;
    if (current == null) return;
    await links.stop(current);
    await _refreshLink();
    if (linkError != null) {
      throw const AppProblem(
        'Link đã dừng nhưng chưa tải đủ kết quả. Thử lại để lưu kết quả.',
      );
    }
    await repository.saveLink(uid, null);
    link = null;
    linkError = null;
  }

  Future<bool> stopLink() => _run('stop_link', _stopLink);
  Future<bool> refresh() => _run('refresh', _refresh);
  Future<bool> refreshInBackground() =>
      _run('refresh_attendance', () => _refresh(background: true), quiet: true);

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    if (value) {
      unawaited(refreshInBackground());
    } else {
      _liveTimer?.cancel();
    }
  }

  Future<bool> receiveServerWorkspace() => _run('resolve_sync', () async {
    if (sync != null && workspace != null) {
      final owner = uid;
      final generation = _generation;
      final received = await sync!.useServer(workspace!.semester);
      if (generation != _generation || disposed) return;
      workspace = received;
      await _clearClosedLink(owner, link);
    }
    _notify();
  });

  Meeting? _meetingForLink(LinkSession session) => workspace?.classes
      .firstWhereOrNull((c) => c.id == session.classId)
      ?.meetings
      .firstWhereOrNull((m) => m.id == session.meetingId);

  Future<void> _clearClosedLink(String owner, LinkSession? session) async {
    if (session == null) return;
    final storedMeeting = _meetingForLink(session);
    if (storedMeeting != null && storedMeeting.state != MeetingState.closed) {
      return;
    }
    if (link?.id == session.id) {
      link = null;
      linkError = null;
    }
    final generation = _generation;
    try {
      // Keep the saved handle when the relay is unavailable so cleanup can retry.
      if (storedMeeting != null &&
          session.receiving &&
          session.expiresAt.isAfter(now())) {
        await links.stop(session);
      }
      if (generation != _generation || disposed || link != null) return;
      await repository.saveLink(owner, null);
    } on Object catch (e, stack) {
      await _safe(() => telemetry.error(e, stack, 'clear_closed_link'));
    }
  }

  Future<void> _refreshNotices(String owner, {bool force = true}) async {
    if (!force &&
        _noticesFetchedAt != null &&
        now().difference(_noticesFetchedAt!) < const Duration(minutes: 1)) {
      return;
    }
    final generation = _generation;
    try {
      final history = await notifications.history(owner);
      if (generation == _generation && !disposed) {
        notices = history;
        _noticesFetchedAt = now();
      }
    } on Object catch (e, stack) {
      await _safe(() => telemetry.error(e, stack, 'notification_history'));
    }
  }

  Future<void> _refresh({bool background = false}) async {
    if (user == null) return;
    final owner = uid;
    final generation = _generation;
    if (sync != null) {
      final loaded = await repository.load(
        owner,
        semester: workspace?.semester,
      );
      if (generation != _generation || disposed) return;
      workspace = loaded;
      await _clearClosedLink(owner, link);
      if (generation != _generation || disposed) return;
      if (link == null &&
          workspace != null &&
          workspace!.classes.any(
            (c) => c.meetings.any((m) => m.state == MeetingState.active),
          ) &&
          (links is HttpAttendanceLinkService ||
              links is LiveAttendanceLinks)) {
        final recovered = links is LiveAttendanceLinks
            ? await (links as LiveAttendanceLinks).current()
            : await (links as HttpAttendanceLinkService).current();
        if (generation != _generation || disposed) return;
        if (recovered != null) {
          final meeting = _meetingForLink(recovered);
          if (meeting?.state == MeetingState.closed) {
            await _clearClosedLink(owner, recovered);
            if (generation != _generation || disposed) return;
          } else if (meeting != null) {
            await repository.saveLink(owner, recovered);
            if (generation != _generation || disposed) return;
            link = recovered;
          }
        }
      }
      _notify();
    }
    await _refreshLink();
    if (generation != _generation || disposed) return;
    await _reconcile();
    if (generation != _generation || disposed) return;
    await _refreshNotices(owner, force: !background);
  }

  Future<void> _reconcile() async {
    final value = workspace;
    if (value == null) return;
    if (value.classes.any(
      (c) => c.meetings.any(
        (m) => m.state != MeetingState.closed && m.isBeforeDate(now()),
      ),
    )) {
      if (link == null && links is LiveAttendanceLinks) {
        for (final c in value.classes) {
          for (final m in c.meetings.where(
            (m) => m.state == MeetingState.active && m.isBeforeDate(now()),
          )) {
            link = await (links as LiveAttendanceLinks).forMeeting(c, m);
            if (link != null) await repository.saveLink(uid, link);
          }
        }
      }
      // Retrieve last accepted link results while the session is still locally active.
      if (link != null &&
          meeting(link!.classId, link!.meetingId).isBeforeDate(now())) {
        await _stopLink();
      }
      await _persist(
        workspace!.copyWith(
          classes: workspace!.classes
              .map((c) => attendance.finalizeOverdueMeetings(c, now: now()))
              .toList(),
        ),
      );
    }
  }

  Future<bool> updateSchedule(String classId, ScheduleRule rule) =>
      _run('save_schedule', () async {
        final c = course(classId);
        if (c.meetings.any((m) => m.state != MeetingState.upcoming)) {
          throw const AppProblem(
            'Không thể đổi lịch vì lớp đã có buổi bắt đầu hoặc đã chốt.',
          );
        }
        await _replace(
          c.copyWith(
            scheduleRule: rule,
            meetings: ScheduleService().generate(rule, c.id),
          ),
        );
        message = 'Đã lưu cấu hình lịch.';
      });
  Future<bool> deleteClass(String classId) => _run('delete_class', () async {
    final c = course(classId);
    if (c.meetings.any((m) => m.state == MeetingState.active)) {
      throw const AppProblem('Hãy chốt buổi đang điểm danh trước khi xóa lớp.');
    }
    await repository.archive(uid, workspace!, c);
    await _persist(
      workspace!.copyWith(
        classes: workspace!.classes.where((c) => c.id != classId).toList(),
      ),
    );
    message = 'Đã lưu trữ và xóa lớp khỏi danh sách.';
  });
  Future<bool> export(String classId, String meetingId, String format) => _run(
    'export_report',
    () async {
      final owner = uid;
      final snapshot = workspace!;
      final exportedCourse = course(classId);
      final exportedMeeting = meeting(classId, meetingId);
      final file = await repository.export(
        owner,
        snapshot,
        exportedCourse,
        exportedMeeting,
        format,
      );
      if (user?.uid != owner) throw const AppProblem('Tài khoản đã thay đổi.');
      final destination = ReportDestination.forExport(
        uid: owner,
        workspace: snapshot,
        course: exportedCourse,
        meeting: exportedMeeting,
        fileName: file.uri.pathSegments.last,
      );
      exportedFile = file;
      reportDestination = destination;
      cloudUrl = null;
      uploadProgress = 0;
      await _safe(
        () => telemetry.event('attendance_exported', {'format': format}),
      );
      final reports = repository is SyncedMobileWorkspaceRepository
          ? (repository as SyncedMobileWorkspaceRepository).reports
          : null;
      message = reports?.warning ?? 'Đã lưu file trên thiết bị.';
    },
  );
  Future<bool> upload() => _run('upload_report', () async {
    final file = exportedFile;
    final destination = reportDestination;
    if (file == null || destination == null || destination.ownerUid != uid) {
      throw const AppProblem('Hãy xuất file trước khi sao lưu.');
    }
    cloudUrl = null;
    uploadProgress = 0;
    if (uploads == null) {
      throw const AppProblem(
        'Báo cáo Final được lưu và chia sẻ trên thiết bị.',
      );
    }
    cloudUrl = await uploads!.upload(file, destination, (progress) {
      uploadProgress = progress;
      _notify();
    });
    await _safe(
      () => telemetry.event('report_uploaded', {
        'format': file.path.endsWith('.csv') ? 'csv' : 'json',
      }),
    );
    message = 'Đã sao lưu Firebase Storage. File local được giữ lại.';
  });
  Future<bool> shareExport() => _run('share_report', () async {
    if (exportedFile == null) {
      throw const AppProblem('Chưa có file để chia sẻ.');
    }
    await device.shareFile(exportedFile!);
  });
  Future<bool> shareLink({bool copy = false}) => _run('share_link', () async {
    if (link == null ||
        linkError != null ||
        !link!.receiving ||
        !link!.expiresAt.isAfter(now())) {
      throw const AppProblem('Link không ở trạng thái nhận điểm danh.');
    }
    if (copy) {
      await device.copy(link!.url);
      message = 'Đã sao chép link điểm danh.';
    } else {
      await device.shareText(link!.url);
    }
  });
  void studentViewed() =>
      unawaited(_safe(() => telemetry.event('student_detail_viewed')));
  Future<bool> refreshConfig() => _run('remote_config', () async {
    await config.refresh();
    message = 'Đã cập nhật cấu hình. Kết quả điểm danh được giữ nguyên.';
  });
  Future<bool> requestNotifications() =>
      _run('notification_permission', () async {
        permission = await notifications.requestPermission();
        messagingToken = await notifications.token();
        notices = await notifications.history(uid);
      });
  Future<bool> demoCrash() => _run('demo_crash', telemetry.crashForDemo);
  void consumeNotice() {
    pendingNotice = null;
  }

  @override
  void dispose() {
    disposed = true;
    sync?.removeListener(_notify);
    sync?.dispose();
    _generation++;
    _timer?.cancel();
    _liveTimer?.cancel();
    unawaited(_linkSub?.cancel());
    unawaited(_authSub?.cancel());
    unawaited(_noticeSub?.cancel());
    super.dispose();
  }
}
