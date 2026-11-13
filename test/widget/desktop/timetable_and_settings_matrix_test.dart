import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/schedule_service.dart';
import 'package:fap_attendance/ui/desktop/schedule_settings_dialog.dart';
import 'package:fap_attendance/ui/desktop/weekly_timetable.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CourseClass _buildClass({
  required String id,
  required String courseCode,
  required String classCode,
  required String scheduleCode,
  required List<Meeting> meetings,
  List<Student> students = const [
    Student(rollNumber: 'SE190001', fullName: 'Nguyen An', email: 'an@fpt.edu.vn'),
    Student(rollNumber: 'SE190002', fullName: 'Tran Binh', email: 'binh@fpt.edu.vn'),
  ],
  int weeks = 10,
  int meetingsPerWeek = 2,
  List<int> weekdays = const [],
  List<DateTime> excludedDates = const [],
  List<DateTime> additionalStarts = const [],
}) => CourseClass(
  id: id,
  courseCode: courseCode,
  classCode: classCode,
  scheduleCode: scheduleCode,
  students: students,
  scheduleRule: ScheduleRule(
    scheduleCode: scheduleCode,
    semesterStart: DateTime(2026, 11, 2),
    weeks: weeks,
    meetingsPerWeek: meetingsPerWeek,
    weekdays: weekdays,
    excludedDates: excludedDates,
    additionalStarts: additionalStarts,
  ),
  meetings: meetings,
);

Widget _host(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('WeeklyTimetable slot grid, status badges, navigation & callbacks', () {
    final fixedNow = DateTime(2026, 11, 4, 10, 0); // Wednesday, Slot 2 window
    final weekMonday = DateTime(2026, 11, 2); // Mon 02/11 -> Sun 08/11

    testWidgets('renders all 7 day headers, 4 slot rows, and weekly slot summary count', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final classes = [
        _buildClass(
          id: 'c1',
          courseCode: 'SWD392',
          classCode: 'SE1901',
          scheduleCode: '11', // Mon/Thu Slot 1
          meetings: [
            Meeting(
              id: 'm1',
              number: 1,
              startAt: DateTime(2026, 11, 2, 7, 30),
              endAt: DateTime(2026, 11, 2, 9, 15),
              state: MeetingState.closed,
            ),
            Meeting(
              id: 'm2',
              number: 2,
              startAt: DateTime(2026, 11, 5, 7, 30),
              endAt: DateTime(2026, 11, 5, 9, 15),
              state: MeetingState.upcoming,
            ),
          ],
        ),
        _buildClass(
          id: 'c2',
          courseCode: 'PRM392',
          classCode: 'SE1902',
          scheduleCode: '32', // Wed/Sat Slot 2
          meetings: [
            Meeting(
              id: 'm3',
              number: 1,
              startAt: DateTime(2026, 11, 4, 9, 30),
              endAt: DateTime(2026, 11, 4, 11, 45),
              state: MeetingState.active,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        _host(
          WeeklyTimetable(
            classes: classes,
            now: fixedNow,
            onOpenMeeting: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thời khóa biểu tuần'), findsOneWidget);
      expect(find.text('02/11/2026 – 08/11/2026 · 3 slot học'), findsOneWidget);
      expect(find.text('Slot 1'), findsOneWidget);
      expect(find.text('Slot 2'), findsOneWidget);
      expect(find.text('Slot 3'), findsOneWidget);
      expect(find.text('Slot 4'), findsOneWidget);
      expect(find.text('07:30\n09:15'), findsOneWidget);
      expect(find.text('09:30\n11:45'), findsOneWidget);
      expect(find.text('12:30\n14:45'), findsOneWidget);
      expect(find.text('15:00\n17:15'), findsOneWidget);
      expect(find.text('SWD392 · SE1901'), findsNWidgets(2));
      expect(find.text('PRM392 · SE1902'), findsOneWidget);
      expect(find.text('Đã chốt'), findsOneWidget);
      expect(find.text('Đang điểm danh'), findsOneWidget);
      expect(find.text('Sắp tới'), findsOneWidget);
    });

    testWidgets('shows overdue label for unclosed past meeting and empty banner on empty week', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final pastUnclosed = Meeting(
        id: 'm-overdue',
        number: 1,
        startAt: DateTime(2026, 11, 2, 7, 30), // Monday
        endAt: DateTime(2026, 11, 2, 9, 15),
        state: MeetingState.upcoming,
      );
      final classes = [
        _buildClass(
          id: 'c1',
          courseCode: 'PRN232',
          classCode: 'SE1903',
          scheduleCode: '11',
          meetings: [pastUnclosed],
        ),
      ];

      await tester.pumpWidget(
        _host(
          WeeklyTimetable(
            classes: classes,
            now: fixedNow, // Wednesday -> Monday endAt is before fixedNow
            onOpenMeeting: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PRN232 · SE1903'), findsOneWidget);
      expect(find.text('Đã qua'), findsOneWidget);

      // Navigate to next week where zero classes exist
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();

      expect(
        find.text('09/11/2026 – 15/11/2026 · 0 slot học'),
        findsOneWidget,
      );
      expect(
        find.text('Tuần này không có lịch dạy. Chọn tuần khác để xem lớp.'),
        findsOneWidget,
      );

      // Return via Tuần trước & verify count returns
      await tester.tap(find.byTooltip('Tuần trước'));
      await tester.pumpAndSettle();
      expect(find.text('02/11/2026 – 08/11/2026 · 1 slot học'), findsOneWidget);

      // Navigate two weeks ahead then reset via Tuần này button
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();
      expect(find.text('16/11/2026 – 22/11/2026 · 0 slot học'), findsOneWidget);

      await tester.tap(find.text('Tuần này'));
      await tester.pumpAndSettle();
      expect(find.text('02/11/2026 – 08/11/2026 · 1 slot học'), findsOneWidget);
    });

    testWidgets('preserves multiple stacked meetings in a single cell and fires onOpenMeeting', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      (CourseClass, Meeting)? opened;
      final mA = Meeting(
        id: 'm-a',
        number: 1,
        startAt: DateTime(2026, 11, 2, 7, 30),
        endAt: DateTime(2026, 11, 2, 9, 15),
        state: MeetingState.closed,
      );
      final mB = Meeting(
        id: 'm-b',
        number: 4,
        startAt: DateTime(2026, 11, 2, 7, 30),
        endAt: DateTime(2026, 11, 2, 9, 15),
        state: MeetingState.upcoming,
      );
      final cA = _buildClass(
        id: 'ca',
        courseCode: 'SWP391',
        classCode: 'SE1901',
        scheduleCode: '11',
        meetings: [mA],
      );
      final cB = _buildClass(
        id: 'cb',
        courseCode: 'SWR302',
        classCode: 'SE1902',
        scheduleCode: '11',
        meetings: [mB],
      );

      await tester.pumpWidget(
        _host(
          WeeklyTimetable(
            classes: [cA, cB],
            now: weekMonday,
            onOpenMeeting: (course, meeting) => opened = (course, meeting),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('02/11/2026 – 08/11/2026 · 2 slot học'), findsOneWidget);
      expect(find.text('SWP391 · SE1901'), findsOneWidget);
      expect(find.text('SWR302 · SE1902'), findsOneWidget);

      await tester.tap(find.text('SWR302 · SE1902'));
      await tester.pumpAndSettle();

      expect(opened?.$1.id, 'cb');
      expect(opened?.$2.id, 'm-b');
    });

    testWidgets('jumps to selected week via Chọn tuần date picker dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final classes = [
        _buildClass(
          id: 'c-future',
          courseCode: 'IOT102',
          classCode: 'SE1909',
          scheduleCode: '23', // Tue/Fri Slot 3
          meetings: [
            Meeting(
              id: 'mf',
              number: 5,
              startAt: DateTime(2026, 11, 17, 12, 30), // Tuesday 17/11
              endAt: DateTime(2026, 11, 17, 14, 45),
              state: MeetingState.upcoming,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        _host(
          WeeklyTimetable(
            classes: classes,
            now: weekMonday,
            onOpenMeeting: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('02/11/2026 – 08/11/2026 · 0 slot học'), findsOneWidget);

      await tester.tap(find.text('Chọn tuần'));
      await tester.pumpAndSettle();

      // Switch to input mode in DatePicker or tap day 18
      await tester.tap(find.text('18'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('16/11/2026 – 22/11/2026 · 1 slot học'), findsOneWidget);
      expect(find.text('IOT102 · SE1909'), findsOneWidget);
    });

    testWidgets('renders horizontal scrollbar cleanly on narrow desktop width <1220px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(820, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _host(
          WeeklyTimetable(
            classes: const [],
            now: weekMonday,
            onOpenMeeting: (_, _) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsWidgets);
      expect(find.text('Thời khóa biểu tuần'), findsOneWidget);
    });
  });

  group('showScheduleSettingsDialog form, validation & rule generation', () {
    testWidgets('displays initial rule values and updates estimated slot preview live', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final course = _buildClass(
        id: 'c1',
        courseCode: 'PRN232',
        classCode: 'SE1901',
        scheduleCode: '11', // Group 1: Thứ Hai + Thứ Năm
        weeks: 10,
        meetingsPerWeek: 2,
        meetings: const [],
      );

      ScheduleRule? dialogResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  dialogResult = await showScheduleSettingsDialog(context, course);
                },
                child: const Text('Mở cấu hình'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở cấu hình'));
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình lịch riêng'), findsOneWidget);
      expect(find.text('PRN232 · SE1901'), findsOneWidget);
      expect(find.text('Thứ Hai'), findsOneWidget);
      expect(find.text('Thứ Năm'), findsOneWidget);
      expect(
        find.text(
          'Dự kiến 20 slot trước khi trừ ngày nghỉ và cộng lịch học bù.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần giảng dạy'),
        '12',
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Dự kiến 24 slot trước khi trừ ngày nghỉ và cộng lịch học bù.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(dialogResult, isNull);
    });

    testWidgets('allows switching to 1 slot/week, choosing single weekday, and returns updated ScheduleRule', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final course = _buildClass(
        id: 'c2',
        courseCode: 'SWD392',
        classCode: 'SE1905',
        scheduleCode: '22', // Group 2: Thứ Ba + Thứ Sáu
        weeks: 10,
        meetingsPerWeek: 2,
        excludedDates: [DateTime(2026, 11, 10)],
        additionalStarts: [DateTime(2026, 11, 14)],
        meetings: const [],
      );

      ScheduleRule? dialogResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  dialogResult = await showScheduleSettingsDialog(context, course);
                },
                child: const Text('Mở cấu hình'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở cấu hình'));
      await tester.pumpAndSettle();

      expect(find.text('Thứ Ba'), findsOneWidget);
      expect(find.text('Thứ Sáu'), findsOneWidget);

      // Switch slot per week dropdown from 2 slot -> 1 slot
      await tester.tap(find.text('2 slot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 slot').last);
      await tester.pumpAndSettle();

      // Now 10 * 1 = 10 slots estimated, and Thứ Sáu chip is selectable
      expect(
        find.text(
          'Dự kiến 10 slot trước khi trừ ngày nghỉ và cộng lịch học bù.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Thứ Sáu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.meetingsPerWeek, 1);
      expect(dialogResult!.weekdays, [DateTime.friday]);
      expect(dialogResult!.weeks, 10);
      expect(dialogResult!.excludedDates, [DateTime(2026, 11, 10)]);
      expect(dialogResult!.additionalStarts, [DateTime(2026, 11, 14)]);
    });

    testWidgets('validates weeks range (1..52) and strict yyyy-MM-dd dates in advanced section', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final course = _buildClass(
        id: 'c3',
        courseCode: 'PRM393',
        classCode: 'SE1908',
        scheduleCode: '34', // Group 3: Thứ Tư + Thứ Bảy
        meetings: const [],
      );

      ScheduleRule? dialogResult;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  dialogResult = await showScheduleSettingsDialog(context, course);
                },
                child: const Text('Mở cấu hình'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở cấu hình'));
      await tester.pumpAndSettle();

      expect(find.text('Thứ Tư'), findsOneWidget);
      expect(find.text('Thứ Bảy'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần giảng dạy'),
        '99',
      );

      // Expand advanced excluded & makeup dates
      await tester.tap(find.text('Ngày nghỉ và học bù'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày nghỉ'),
        '15/11/2026',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày học bù'),
        '2026-13-40',
      );

      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();

      expect(find.text('Nhập từ 1 đến 52 tuần'), findsOneWidget);
      expect(find.text('Ngày "15/11/2026" không đúng yyyy-MM-dd.'), findsOneWidget);
      expect(find.text('Ngày "2026-13-40" không đúng yyyy-MM-dd.'), findsOneWidget);
      expect(dialogResult, isNull);

      // Enter valid values and submit
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần giảng dạy'),
        '8',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày nghỉ'),
        '2026-11-11, 2026-11-18',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày học bù'),
        '2026-11-22',
      );

      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.weeks, 8);
      expect(dialogResult!.excludedDates, [
        DateTime(2026, 11, 11),
        DateTime(2026, 11, 18),
      ]);
      expect(dialogResult!.additionalStarts, [DateTime(2026, 11, 22)]);
      expect(ScheduleService().generate(dialogResult!, 'c3').length, 15);
    });
  });
}
