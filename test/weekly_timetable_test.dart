import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/ui/desktop/class_detail_page.dart';
import 'package:fap_attendance/ui/desktop/weekly_timetable.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CourseClass course(String id, List<Meeting> meetings) => CourseClass(
  id: id,
  courseCode: id,
  classCode: 'SE1920',
  scheduleCode: '13',
  students: const [],
  scheduleRule: ScheduleRule(
    scheduleCode: '13',
    semesterStart: DateTime(2026, 10, 5),
  ),
  meetings: meetings,
);

Meeting meeting(String id, DateTime date, {int number = 1}) => Meeting(
  id: id,
  number: number,
  startAt: date,
  endAt: date.add(const Duration(hours: 2, minutes: 15)),
);

void main() {
  testWidgets('class page selects the meeting opened from timetable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = meeting('first', DateTime(2026, 10, 5, 12, 30));
    final chosen = meeting('chosen', DateTime(2026, 10, 8, 12, 30), number: 2);
    final controller = AttendanceController()
      ..workspace = TeacherWorkspace(
        id: 'workspace',
        semester: 'FA26',
        semesterStart: first.startAt,
        classes: [
          course('PRN232', [first, chosen]),
        ],
      );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ClassDetailPage(
          controller: controller,
          classId: 'PRN232',
          initialMeetingId: chosen.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      chosen.id,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('week navigation, make-up Sunday and matching callback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = meeting('mon', DateTime(2026, 10, 5, 12, 30));
    final sunday = meeting('sun', DateTime(2026, 10, 11, 12, 30));
    final next = meeting('next', DateTime(2026, 10, 12, 12, 30));
    final courses = [
      course('PRN232', [first, next]),
      course('MAKEUP', [sunday]),
      course('OVERLAP', [meeting('overlap', first.startAt)]),
    ];
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklyTimetable(
              classes: courses,
              now: DateTime(2026, 10, 10, 10),
              onOpenMeeting: (course, value) =>
                  selected = '${course.id}/${value.id}',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('05/10/2026 – 11/10/2026'), findsOneWidget);
    expect(find.text('MAKEUP · SE1920'), findsOneWidget);
    expect(find.text('OVERLAP · SE1920'), findsOneWidget);
    expect(find.text('Slot 1'), findsOneWidget);
    expect(find.text('Slot 4'), findsOneWidget);
    await tester.tap(find.text('PRN232 · SE1920'));
    expect(selected, 'PRN232/mon');
    await tester.tap(find.byTooltip('Tuần sau'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12/10/2026 – 18/10/2026'), findsOneWidget);
    expect(find.text('MAKEUP · SE1920'), findsNothing);
    await tester.tap(find.text('PRN232 · SE1920'));
    expect(selected, 'PRN232/next');
    await tester.tap(find.byTooltip('Tuần trước'));
    await tester.pumpAndSettle();
    expect(find.text('OVERLAP · SE1920'), findsOneWidget);
    await tester.tap(find.byTooltip('Tuần trước'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tuần này không có lịch dạy.'), findsOneWidget);
    await tester.tap(find.text('Tuần này'));
    await tester.pumpAndSettle();
    expect(find.text('MAKEUP · SE1920'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout scrolls without overflow and week crosses year', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sunday = meeting('sun', DateTime(2027, 1, 3, 12, 30));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklyTimetable(
              classes: [
                course('PRN232_LONG_COURSE_NAME', [sunday]),
              ],
              now: DateTime(2027, 1, 1),
              onOpenMeeting: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('28/12/2026 – 03/01/2027'), findsOneWidget);
    final scroller = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    await tester.drag(scroller, const Offset(-1200, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
