import 'dart:io';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/attendance_link_service.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/ui/desktop/class_detail_page.dart';
import 'package:fap_attendance/ui/desktop/shared_qr_page.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAuth implements AuthService {
  @override
  TeacherIdentity? current = const TeacherIdentity(
    'teacher-1',
    'gv@fpt.edu.vn',
    'Giảng viên',
  );

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<String> token() async => 'stub-token';
}

class _StubLinks extends HttpAttendanceLinkService {
  _StubLinks(super.auth) : super(baseUrl: 'https://relay.example.com');

  @override
  bool get configured => true;

  @override
  Future<LinkSession> create(CourseClass course, Meeting meeting) async =>
      createQr(course, meeting);

  @override
  Future<LinkSession> createQr(
    CourseClass course,
    Meeting meeting, {
    bool otp = false,
  }) async => LinkSession(
    id: 'l-1',
    classId: course.id,
    meetingId: meeting.id,
    url: 'https://fap.test/join/l-1',
    expiresAt: DateTime.now().add(const Duration(minutes: 10)),
  );

  @override
  Future<LinkSession?> current() async => null;

  @override
  Future<LinkUpdate> poll(LinkSession session) async =>
      LinkUpdate(session, const []);

  @override
  Future<void> stop(LinkSession session) async {}
}

void main() {
  late Directory tempDir;
  late AttendanceController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('class_detail_widget_');
    controller = AttendanceController(
      teacherAuth: _StubAuth(),
      documentsDirectory: tempDir,
    );
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedClass({
    required DateTime m1Start,
    MeetingState m1State = MeetingState.upcoming,
    List<Meeting>? extraMeetings,
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
    List<AuditEvent> auditEvents = const [],
  }) async {
    controller.workspace = TeacherWorkspace(
      id: 'ws-detail',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      teacherEmail: 'gv@fpt.edu.vn',
      classes: [
        CourseClass(
          id: 'cls-1',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          scheduleCode: '11',
          students: const [
            Student(
              rollNumber: 'SE180001',
              email: 'an@fpt.edu.vn',
              fullName: 'Nguyen Van An',
            ),
            Student(
              rollNumber: 'SE180002',
              email: 'binh@fpt.edu.vn',
              fullName: 'Tran Thi Binh',
            ),
          ],
          scheduleRule: ScheduleRule(
            scheduleCode: '11',
            semesterStart: DateTime(2026, 9, 7),
          ),
          meetings: [
            Meeting(
              id: 'm1',
              number: 1,
              startAt: m1Start,
              endAt: m1Start.add(const Duration(hours: 2)),
              state: m1State,
            ),
            ...?extraMeetings,
          ],
          attendance: attendance,
          auditEvents: auditEvents,
        ),
      ],
    );
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    String? initialMeetingId,
    Size size = const Size(1440, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ClassDetailPage(
          controller: controller,
          classId: 'cls-1',
          initialMeetingId: initialMeetingId,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ClassDetailPage rendering & action states', () {
    testWidgets('shows summary metrics, table headers, students, and Điểm danh today', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      await seedClass(m1Start: todayStart, m1State: MeetingState.upcoming);

      await pumpDetail(tester, initialMeetingId: 'm1');

      expect(find.text('PRM392 · SE1801'), findsOneWidget);
      expect(find.text('Cấu hình lịch'), findsOneWidget);
      expect(find.text('Điểm danh'), findsOneWidget);
      expect(find.text('Sinh viên'), findsOneWidget);
      expect(find.text('Có mặt'), findsOneWidget);
      expect(find.text('Vắng'), findsOneWidget);
      expect(find.text('Tiến độ'), findsOneWidget);
      expect(find.text('0/1'), findsOneWidget);
      expect(find.text('MSSV'), findsOneWidget);
      expect(find.text('Họ tên'), findsOneWidget);
      expect(find.text('SE180001'), findsOneWidget);
      expect(find.text('Nguyen Van An'), findsOneWidget);
      expect(find.text('SE180002'), findsOneWidget);
      expect(find.text('Tran Thi Binh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows Chưa đến ngày for future upcoming meeting', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final future = DateTime.now().add(const Duration(days: 5));
      await seedClass(m1Start: future, m1State: MeetingState.upcoming);

      await pumpDetail(tester, initialMeetingId: 'm1');
      expect(find.text('Chưa đến ngày'), findsOneWidget);
    });

    testWidgets('shows Đang tự động chốt for past upcoming meeting', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final past = DateTime.now().subtract(const Duration(days: 2));
      await seedClass(m1Start: past, m1State: MeetingState.upcoming);

      await pumpDetail(tester, initialMeetingId: 'm1');
      expect(find.text('Đang tự động chốt'), findsOneWidget);
    });

    testWidgets('shows Mở QR and Chốt danh sách for active meeting today', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      await seedClass(m1Start: todayStart, m1State: MeetingState.active);

      await pumpDetail(tester, initialMeetingId: 'm1');
      expect(find.text('Mở QR'), findsOneWidget);
      expect(find.text('Chốt danh sách'), findsOneWidget);
    });

    testWidgets('shows Chốt slot quá hạn for past active meeting', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final past = DateTime.now().subtract(const Duration(days: 1));
      await seedClass(m1Start: past, m1State: MeetingState.active);

      await pumpDetail(tester, initialMeetingId: 'm1');
      expect(find.text('Chốt slot quá hạn'), findsNWidgets(2));
    });
  });

  group('ClassDetailPage interactions', () {
    testWidgets('switches selected meeting from dropdown and updates action button', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      final futureStart = todayStart.add(const Duration(days: 4));

      await seedClass(
        m1Start: todayStart,
        m1State: MeetingState.upcoming,
        extraMeetings: [
          Meeting(
            id: 'm2',
            number: 2,
            startAt: futureStart,
            endAt: futureStart.add(const Duration(hours: 2)),
            state: MeetingState.upcoming,
          ),
        ],
      );

      await pumpDetail(tester);
      expect(find.text('Điểm danh'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Slot 2').last);
      await tester.pumpAndSettle();

      expect(find.text('Chưa đến ngày'), findsOneWidget);
    });

    testWidgets('confirms Chốt danh sách dialog and closes active meeting', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      await seedClass(m1Start: todayStart, m1State: MeetingState.active);

      await pumpDetail(tester, initialMeetingId: 'm1');

      await tester.tap(find.text('Chốt danh sách'));
      await tester.pumpAndSettle();

      expect(find.text('Chốt danh sách?'), findsOneWidget);
      expect(
        find.text('Tất cả sinh viên chưa có P sẽ được đánh dấu A.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Chốt'));
      await tester.pumpAndSettle();

      expect(controller.meetingById('cls-1', 'm1').state, MeetingState.closed);
      expect(find.text('Xuất báo cáo'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
    });

    testWidgets('opens status override dialog on closed meeting cell and saves reason', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      await seedClass(
        m1Start: now,
        m1State: MeetingState.closed,
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.manual,
              recordedAt: now,
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: now,
            ),
          },
        },
      );

      await pumpDetail(tester, initialMeetingId: 'm1');

      // Tap 'A' badge for SE180001
      await tester.tap(find.text('A').last);
      await tester.pumpAndSettle();

      expect(find.text('SE180001 · Nguyen Van An'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Lý do chỉnh sửa'),
        'Approved medical excuse',
      );
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(
        controller.classById('cls-1').recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    });

    testWidgets('shows note & audit history dialog and allows Sửa tiếp', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      await seedClass(
        m1Start: now,
        m1State: MeetingState.closed,
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: now,
              note: 'Latest note text',
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'ev-1',
            createdAt: now,
            action: 'attendance_override',
            reason: 'Initial correction reason',
            rollNumber: 'SE180001',
            meetingId: 'm1',
            oldValue: 'A',
            newValue: 'P',
          ),
        ],
      );

      await pumpDetail(tester, initialMeetingId: 'm1');

      await tester.tap(find.byIcon(Icons.sticky_note_2_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Ghi chú chỉnh sửa điểm danh'), findsOneWidget);
      expect(find.text('Latest note text'), findsOneWidget);
      expect(find.text('Lịch sử chỉnh sửa'), findsOneWidget);
      expect(find.text('Initial correction reason'), findsOneWidget);
      expect(find.text('Sửa tiếp'), findsOneWidget);

      await tester.tap(find.text('Sửa tiếp'));
      await tester.pumpAndSettle();
      expect(find.text('SE180001 · Nguyen Van An'), findsOneWidget);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
    });

    testWidgets('opens mode picker and navigates to SharedQrPage when sharedLinks set', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      controller.sharedLinks = _StubLinks(controller.desktopAuth);
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      await seedClass(m1Start: todayStart, m1State: MeetingState.upcoming);

      await pumpDetail(tester, initialMeetingId: 'm1');

      await tester.tap(find.text('Điểm danh'));
      await tester.pumpAndSettle();

      expect(find.text('Chọn chế độ QR'), findsOneWidget);
      await tester.tap(find.text('QR + mã bí mật'));
      await tester.pumpAndSettle();

      expect(find.byType(SharedQrPage), findsOneWidget);
      expect(controller.meetingById('cls-1', 'm1').state, MeetingState.active);
    });

    testWidgets('re-opens SharedQrPage directly when active and sharedLinks set', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      controller.sharedLinks = _StubLinks(controller.desktopAuth);
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      await seedClass(m1Start: todayStart, m1State: MeetingState.active);

      await pumpDetail(tester, initialMeetingId: 'm1');

      await tester.tap(find.text('Mở QR'));
      await tester.pumpAndSettle();

      expect(find.byType(SharedQrPage), findsOneWidget);
    });

    testWidgets('exports CSV report from popup menu on closed meeting', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() => controller.initialize());
      final now = DateTime.now();
      await seedClass(
        m1Start: now,
        m1State: MeetingState.closed,
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: now,
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.manual,
              recordedAt: now,
            ),
          },
        },
      );
      await tester.runAsync(() => controller.save());

      await pumpDetail(tester, initialMeetingId: 'm1');

      await tester.tap(find.text('Xuất báo cáo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xuất CSV'));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.textContaining('Đã xuất').evaluate().isNotEmpty ||
            find.byType(SnackBar).evaluate().isNotEmpty) {
          await tester.pump(const Duration(milliseconds: 250));
          break;
        }
      }
      final snackTexts = find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .toList();
      expect(
        find.textContaining('Đã xuất'),
        findsOneWidget,
        reason: 'SnackBar texts were: $snackTexts',
      );
    });

    testWidgets('opens schedule settings dialog and regenerates meetings', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final future = DateTime.now().add(const Duration(days: 5));
      await seedClass(m1Start: future, m1State: MeetingState.upcoming);

      await pumpDetail(tester, initialMeetingId: 'm1');

      await tester.tap(find.text('Cấu hình lịch'));
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình lịch riêng'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần giảng dạy'),
        '4',
      );
      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();

      expect(controller.classById('cls-1').meetings, hasLength(8));
    });
  });
}
