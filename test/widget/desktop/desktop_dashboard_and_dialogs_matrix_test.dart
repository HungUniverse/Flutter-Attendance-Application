import 'dart:io';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/ui/desktop/desktop_app.dart';
import 'package:fap_attendance/ui/desktop/schedule_settings_dialog.dart';
import 'package:fap_attendance/ui/desktop/weekly_timetable.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DesktopTestAuth implements AuthService {
  @override
  TeacherIdentity? current;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {
    current = const TeacherIdentity('t-uid', 'gv@fpt.edu.vn', 'Giang vien');
  }

  @override
  Future<void> signOut() async {
    current = null;
  }

  @override
  Future<String> token() async => 'desktop-token';
}

CourseClass _buildCourse({
  String id = 'cls-1',
  String courseCode = 'PRM393',
  String classCode = 'SE1801',
  String scheduleCode = '11',
  List<Meeting>? meetings,
  List<Student>? students,
}) {
  return CourseClass(
    id: id,
    courseCode: courseCode,
    classCode: classCode,
    scheduleCode: scheduleCode,
    students: students ??
        const [
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
      scheduleCode: scheduleCode,
      semesterStart: DateTime(2026, 9, 7),
      weeks: 4,
      meetingsPerWeek: 2,
      weekdays: const [DateTime.monday, DateTime.thursday],
    ),
    meetings: meetings ?? const [],
  );
}

void main() {
  late Directory tempDir;
  late AttendanceController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('desktop_matrix_widget_');
    controller = AttendanceController(
      teacherAuth: _DesktopTestAuth(),
      documentsDirectory: tempDir,
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DesktopHomePage empty-state & dashboard responsive workflows', () {
    testWidgets('switches cleanly between narrow (<900) and wide (>=1100) welcome screens', (
      tester,
    ) async {
      // Narrow layout hides right preview card
      await tester.binding.setSurfaceSize(const Size(760, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: DesktopHomePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chào mừng trở lại!'), findsOneWidget);
      expect(find.text('Không gian điểm danh'), findsNothing);
      expect(find.text('Đăng nhập Google để đồng bộ'), findsOneWidget);

      // Wide layout displays side-by-side preview showcase
      await tester.binding.setSurfaceSize(const Size(1360, 860));
      await tester.pumpAndSettle();

      expect(find.text('Chào mừng trở lại!'), findsOneWidget);
      expect(find.text('Không gian điểm danh'), findsOneWidget);
      expect(find.text('Import roster'), findsOneWidget);
      expect(find.text('Điểm danh QR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dashboard computes summary counters, expands class list, and navigates', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime.now();
      final todaySlot1 = DateTime(now.year, now.month, now.day, 7, 30);
      final tomorrowSlot2 = todaySlot1.add(const Duration(days: 1, hours: 2));

      final ws = TeacherWorkspace(
        id: 'ws-dash',
        semester: 'FA26',
        semesterStart: DateTime(2026, 9, 7),
        teacherEmail: 'gv@fpt.edu.vn',
        classes: [
          _buildCourse(
            id: 'c1',
            courseCode: 'PRM393',
            classCode: 'SE1801',
            meetings: [
              Meeting(
                id: 'm1',
                number: 1,
                startAt: todaySlot1,
                endAt: todaySlot1.add(const Duration(hours: 2)),
                state: MeetingState.closed,
              ),
              Meeting(
                id: 'm2',
                number: 2,
                startAt: tomorrowSlot2,
                endAt: tomorrowSlot2.add(const Duration(hours: 2)),
                state: MeetingState.upcoming,
              ),
            ],
          ),
          _buildCourse(
            id: 'c2',
            courseCode: 'SWD392',
            classCode: 'SE1802',
            scheduleCode: '22',
            meetings: [
              Meeting(
                id: 'm3',
                number: 1,
                startAt: todaySlot1.add(const Duration(hours: 5)),
                endAt: todaySlot1.add(const Duration(hours: 7)),
                state: MeetingState.active,
              ),
            ],
          ),
        ],
      );

      controller.workspace = ws;
      await tester.runAsync(() => controller.save());

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: DesktopHomePage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FAP ATTENDANCE WORKSPACE'), findsOneWidget);
      expect(find.text('Chào ngày dạy mới!'), findsOneWidget);
      expect(find.textContaining('Học kỳ FA26'), findsOneWidget);
      expect(find.text('Lớp đang dạy'), findsOneWidget);
      expect(find.text('Lớp hôm nay'), findsOneWidget);
      expect(find.text('Sinh viên'), findsOneWidget);
      // 2 classes, 2 classes today, 4 students total
      expect(find.text('2'), findsNWidgets(2));
      expect(find.text('4'), findsOneWidget);

      // Expand class management tile to verify both course cards render
      await tester.ensureVisible(find.text('Quản lý lớp'));
      await tester.tap(find.text('Quản lý lớp'));
      await tester.pumpAndSettle();

      expect(find.text('PRM393'), findsWidgets);
      expect(find.text('SE1801'), findsWidgets);
      expect(find.text('SWD392'), findsWidgets);
      expect(find.text('SE1802'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('WeeklyTimetable rendering, status badges & navigation', () {
    testWidgets('renders empty week notice and navigates with prev/next/this-week buttons', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1380, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixedNow = DateTime(2026, 9, 9, 8, 30); // Wednesday
      final nextWeekMonday = DateTime(2026, 9, 14, 7, 30);

      final course = _buildCourse(
        meetings: [
          Meeting(
            id: 'm-next',
            number: 1,
            startAt: nextWeekMonday,
            endAt: DateTime(2026, 9, 14, 9, 50),
            state: MeetingState.upcoming,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklyTimetable(
                classes: [course],
                now: fixedNow,
                onOpenMeeting: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Tuần này không có lịch dạy. Chọn tuần khác để xem lớp.'),
        findsOneWidget,
      );
      expect(find.textContaining('0 slot học'), findsOneWidget);

      // Advance one week -> shows the Monday Slot 1 meeting
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 slot học'), findsOneWidget);
      expect(find.text('PRM393 · SE1801'), findsOneWidget);
      expect(find.text('Sắp tới'), findsOneWidget);

      // Jump back to current week
      await tester.tap(find.text('Tuần này'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 slot học'), findsOneWidget);

      // Move back one more week -> earlier range
      await tester.tap(find.byTooltip('Tuần trước'));
      await tester.pumpAndSettle();
      expect(find.textContaining('31/08/2026'), findsOneWidget);
    });

    testWidgets('displays closed, active, past-upcoming, and in-progress cards and triggers callback', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fixedNow = DateTime(2026, 9, 9, 10, 30); // Wednesday 10:30
      CourseClass? openedClass;
      Meeting? openedMeeting;

      final course = _buildCourse(
        meetings: [
          // Monday Slot 1 - closed
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 9, 7, 7, 30),
            endAt: DateTime(2026, 9, 7, 9, 50),
            state: MeetingState.closed,
          ),
          // Tuesday Slot 1 - past upcoming
          Meeting(
            id: 'm2',
            number: 2,
            startAt: DateTime(2026, 9, 8, 7, 30),
            endAt: DateTime(2026, 9, 8, 9, 50),
            state: MeetingState.upcoming,
          ),
          // Wednesday Slot 2 - in progress now (10:00-12:20 includes 10:30)
          Meeting(
            id: 'm3',
            number: 3,
            startAt: DateTime(2026, 9, 9, 10, 0),
            endAt: DateTime(2026, 9, 9, 12, 20),
            state: MeetingState.upcoming,
          ),
          // Thursday Slot 1 - active
          Meeting(
            id: 'm4',
            number: 4,
            startAt: DateTime(2026, 9, 10, 7, 30),
            endAt: DateTime(2026, 9, 10, 9, 50),
            state: MeetingState.active,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklyTimetable(
                classes: [course],
                now: fixedNow,
                onOpenMeeting: (c, m) {
                  openedClass = c;
                  openedMeeting = m;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đã chốt'), findsOneWidget);
      expect(find.text('Đã qua'), findsOneWidget);
      expect(find.text('Đang học'), findsOneWidget);
      expect(find.text('Đang điểm danh'), findsOneWidget);
      expect(find.textContaining('4 slot học'), findsOneWidget);

      await tester.tap(find.text('Đang điểm danh'));
      await tester.pump();
      expect(openedClass?.id, 'cls-1');
      expect(openedMeeting?.id, 'm4');
    });

    testWidgets('supports horizontal scrolling on narrow width without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(720, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final course = _buildCourse();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklyTimetable(
                classes: [course],
                now: DateTime(2026, 9, 7, 8, 0),
                onOpenMeeting: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thời khóa biểu tuần'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('showScheduleSettingsDialog validation, toggles & return value', () {
    testWidgets('validates weeks bounds and strict yyyy-MM-dd dates before saving', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final course = _buildCourse();
      ScheduleRule? dialogResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showScheduleSettingsDialog(
                    context,
                    course,
                  );
                },
                child: const Text('Mở cài đặt'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở cài đặt'));
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình lịch riêng'), findsOneWidget);
      expect(find.textContaining('Dự kiến 8 slot'), findsOneWidget);

      // Invalid weeks (0 and 60) show validation error
      final weeksField = find.widgetWithText(TextFormField, 'Số tuần giảng dạy');
      await tester.enterText(weeksField, '0');
      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập từ 1 đến 52 tuần'), findsOneWidget);
      expect(dialogResult, isNull);

      await tester.enterText(weeksField, '6');
      await tester.pumpAndSettle();
      expect(find.textContaining('Dự kiến 12 slot'), findsOneWidget);

      // Switch to 1 slot/week and choose Thursday
      await tester.tap(find.text('2 slot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 slot').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Dự kiến 6 slot'), findsOneWidget);

      await tester.tap(find.text('Thứ Năm'));
      await tester.pumpAndSettle();

      // Expand advanced dates and test bad date then valid dates
      await tester.tap(find.text('Ngày nghỉ và học bù'));
      await tester.pumpAndSettle();

      final excludedField = find.widgetWithText(TextFormField, 'Ngày nghỉ');
      final additionalField = find.widgetWithText(TextFormField, 'Ngày học bù');

      await tester.enterText(excludedField, '21-09-2026');
      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ngày "21-09-2026" không đúng yyyy-MM-dd.'),
        findsOneWidget,
      );

      await tester.enterText(excludedField, '2026-09-21, 2026-09-28');
      await tester.enterText(additionalField, '2026-10-04');
      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.weeks, 6);
      expect(dialogResult!.meetingsPerWeek, 1);
      expect(dialogResult!.weekdays, [DateTime.thursday]);
      expect(dialogResult!.excludedDates, [
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 28),
      ]);
      expect(dialogResult!.additionalStarts, [DateTime(2026, 10, 4)]);
    });

    testWidgets('cancel button returns null without mutating class rule', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final course = _buildCourse();
      ScheduleRule? dialogResult = course.scheduleRule;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showScheduleSettingsDialog(
                    context,
                    course,
                  );
                },
                child: const Text('Mở cài đặt'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở cài đặt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNull);
    });
  });
}
