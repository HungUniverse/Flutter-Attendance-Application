import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/ui/desktop/weekly_timetable.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Student student(String roll, String name) => Student(
    rollNumber: roll,
    email: '$roll@fpt.edu.vn'.toLowerCase(),
    fullName: name,
  );

  CourseClass buildClass({
    required String id,
    required String courseCode,
    required String classCode,
    required String scheduleCode,
    required List<Meeting> meetings,
    int studentCount = 3,
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
  }) {
    final students = List.generate(
      studentCount,
      (i) => student('SE18${id.hashCode.abs() % 90 + 10}$i', 'Student $i'),
    );
    return CourseClass(
      id: id,
      courseCode: courseCode,
      classCode: classCode,
      scheduleCode: scheduleCode,
      students: students,
      scheduleRule: ScheduleRule(
        scheduleCode: scheduleCode,
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: meetings,
      attendance: attendance,
    );
  }

  Widget wrapTimetable({
    required List<CourseClass> classes,
    required void Function(CourseClass, Meeting) onOpenMeeting,
    DateTime? now,
    Size surfaceSize = const Size(1440, 1000),
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: surfaceSize),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: WeeklyTimetable(
              classes: classes,
              onOpenMeeting: onOpenMeeting,
              now: now,
            ),
          ),
        ),
      ),
    );
  }

  group('WeeklyTimetable rendering and structure', () {
    testWidgets('renders header, controls, weekday columns, and all 4 slots', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final baseMonday = DateTime(2026, 9, 7);
      final classes = [
        buildClass(
          id: 'c1',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          scheduleCode: '11',
          studentCount: 28,
          meetings: [
            Meeting(
              id: 'm-1',
              number: 1,
              startAt: DateTime(2026, 9, 7, 7, 30),
              endAt: DateTime(2026, 9, 7, 9, 50),
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        wrapTimetable(
          classes: classes,
          onOpenMeeting: (_, _) {},
          now: baseMonday,
        ),
      );

      expect(find.text('Thời khóa biểu tuần'), findsOneWidget);
      expect(find.textContaining('07/09/2026'), findsOneWidget);
      expect(find.textContaining('13/09/2026'), findsOneWidget);
      expect(find.textContaining('1 slot học'), findsOneWidget);
      expect(find.byTooltip('Tuần trước'), findsOneWidget);
      expect(find.text('Tuần này'), findsOneWidget);
      expect(find.byTooltip('Tuần sau'), findsOneWidget);
      expect(find.text('Chọn tuần'), findsOneWidget);
      expect(find.text('Slot 1'), findsOneWidget);
      expect(find.text('Slot 2'), findsOneWidget);
      expect(find.text('Slot 3'), findsOneWidget);
      expect(find.text('Slot 4'), findsOneWidget);
      expect(find.text('PRM392 · SE1801'), findsOneWidget);
      expect(find.text('Slot học 1 · 28 SV'), findsOneWidget);
      expect(find.text('07:30–09:50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows empty state message when classes have no meetings', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapTimetable(
          classes: const [],
          onOpenMeeting: (_, _) {},
          now: DateTime(2026, 9, 7),
        ),
      );

      expect(
        find.text('Tuần này không có lịch dạy. Chọn tuần khác để xem lớp.'),
        findsOneWidget,
      );
      expect(find.textContaining('0 slot học'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('maps all 4 slot start times and displays status badges', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime(2026, 9, 9, 10, 30);

      final classes = [
        buildClass(
          id: 'c-closed',
          courseCode: 'PRF192',
          classCode: 'SE1801',
          scheduleCode: '11',
          studentCount: 2,
          meetings: [
            Meeting(
              id: 'm-closed',
              number: 1,
              startAt: DateTime(2026, 9, 7, 7, 30),
              endAt: DateTime(2026, 9, 7, 9, 50),
              state: MeetingState.closed,
            ),
          ],
        ),
        buildClass(
          id: 'c-active',
          courseCode: 'PRN212',
          classCode: 'SE1802',
          scheduleCode: '12',
          meetings: [
            Meeting(
              id: 'm-active',
              number: 2,
              startAt: DateTime(2026, 9, 9, 10, 0),
              endAt: DateTime(2026, 9, 9, 12, 20),
              state: MeetingState.active,
            ),
          ],
        ),
        buildClass(
          id: 'c-missed',
          courseCode: 'SWR302',
          classCode: 'SE1803',
          scheduleCode: '23',
          meetings: [
            Meeting(
              id: 'm-past',
              number: 3,
              startAt: DateTime(2026, 9, 8, 12, 50),
              endAt: DateTime(2026, 9, 8, 15, 10),
              state: MeetingState.upcoming,
            ),
          ],
        ),
        buildClass(
          id: 'c-future',
          courseCode: 'SWD392',
          classCode: 'SE1804',
          scheduleCode: '14',
          meetings: [
            Meeting(
              id: 'm-upcoming',
              number: 4,
              startAt: DateTime(2026, 9, 11, 15, 20),
              endAt: DateTime(2026, 9, 11, 17, 40),
              state: MeetingState.upcoming,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        wrapTimetable(classes: classes, onOpenMeeting: (_, _) {}, now: now),
      );

      expect(find.text('PRF192 · SE1801'), findsOneWidget);
      expect(find.text('PRN212 · SE1802'), findsOneWidget);
      expect(find.text('SWR302 · SE1803'), findsOneWidget);
      expect(find.text('SWD392 · SE1804'), findsOneWidget);
      expect(find.text('Đã chốt'), findsOneWidget);
      expect(find.text('Đang điểm danh'), findsOneWidget);
      expect(find.text('Đã qua'), findsOneWidget);
      expect(find.text('Sắp tới'), findsOneWidget);
      expect(find.textContaining('4 slot học'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows in-progress badge for live upcoming slot', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final now = DateTime(2026, 9, 7, 8, 15);
      final classes = [
        buildClass(
          id: 'c-live',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          scheduleCode: '11',
          meetings: [
            Meeting(
              id: 'm-live',
              number: 1,
              startAt: DateTime(2026, 9, 7, 7, 30),
              endAt: DateTime(2026, 9, 7, 9, 50),
              state: MeetingState.upcoming,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        wrapTimetable(classes: classes, onOpenMeeting: (_, _) {}, now: now),
      );

      expect(find.text('Đang học'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('WeeklyTimetable interactions', () {
    testWidgets('navigates between weeks with Tuần sau, Tuần trước, Tuần này', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final week1Start = DateTime(2026, 9, 7, 7, 30);
      final week2Start = DateTime(2026, 9, 14, 7, 30);

      final classes = [
        buildClass(
          id: 'c1',
          courseCode: 'W1_COURSE',
          classCode: 'SE1801',
          scheduleCode: '11',
          meetings: [
            Meeting(
              id: 'm-w1',
              number: 1,
              startAt: week1Start,
              endAt: week1Start.add(const Duration(hours: 2)),
            ),
            Meeting(
              id: 'm-w2',
              number: 2,
              startAt: week2Start,
              endAt: week2Start.add(const Duration(hours: 2)),
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        wrapTimetable(
          classes: classes,
          onOpenMeeting: (_, _) {},
          now: DateTime(2026, 9, 8),
        ),
      );

      expect(find.textContaining('Slot học 1'), findsOneWidget);

      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Slot học 2'), findsOneWidget);
      expect(find.textContaining('Slot học 1'), findsNothing);

      // Moving one more week forward hits an empty week
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tuần này không có lịch dạy. Chọn tuần khác để xem lớp.'),
        findsOneWidget,
      );

      // Return to week 2 via Tuần trước
      await tester.tap(find.byTooltip('Tuần trước'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Slot học 2'), findsOneWidget);

      // Jump back to week 1 via Tuần này
      await tester.tap(find.text('Tuần này'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Slot học 1'), findsOneWidget);
    });

    testWidgets('picks week via date picker and invokes onOpenMeeting on tap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final w1 = DateTime(2026, 9, 7, 7, 30);
      final w2 = DateTime(2026, 9, 14, 10, 0);
      CourseClass? tappedClass;
      Meeting? tappedMeeting;

      final course = buildClass(
        id: 'c1',
        courseCode: 'PRM392',
        classCode: 'SE1899',
        scheduleCode: '11',
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: w1,
            endAt: w1.add(const Duration(hours: 2)),
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: w2,
            endAt: w2.add(const Duration(hours: 2)),
          ),
        ],
      );

      await tester.pumpWidget(
        wrapTimetable(
          classes: [course],
          onOpenMeeting: (c, m) {
            tappedClass = c;
            tappedMeeting = m;
          },
          now: DateTime(2026, 9, 7),
        ),
      );

      // Tap Slot #1 card
      await tester.tap(find.text('PRM392 · SE1899'));
      await tester.pump();
      expect(tappedClass?.id, 'c1');
      expect(tappedMeeting?.id, 'm1');

      // Open date picker via Chọn tuần and pick Sept 16 (Week 2)
      await tester.tap(find.text('Chọn tuần'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('16'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Slot học 2'), findsOneWidget);

      await tester.tap(find.text('PRM392 · SE1899'));
      await tester.pump();
      expect(tappedMeeting?.id, 'm2');
    });

    testWidgets('preserves multiple stacked meetings in the same slot cell', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final slotTime = DateTime(2026, 9, 7, 7, 30);
      final courseA = buildClass(
        id: 'a',
        courseCode: 'PRM392',
        classCode: 'SE1801',
        scheduleCode: '11',
        meetings: [
          Meeting(
            id: 'ma',
            number: 1,
            startAt: slotTime,
            endAt: slotTime.add(const Duration(hours: 2)),
          ),
        ],
      );
      final courseB = buildClass(
        id: 'b',
        courseCode: 'SWD392',
        classCode: 'SE1802',
        scheduleCode: '11',
        meetings: [
          Meeting(
            id: 'mb',
            number: 1,
            startAt: slotTime,
            endAt: slotTime.add(const Duration(hours: 2)),
          ),
        ],
      );

      await tester.pumpWidget(
        wrapTimetable(
          classes: [courseA, courseB],
          onOpenMeeting: (_, _) {},
          now: DateTime(2026, 9, 7),
        ),
      );

      expect(find.text('PRM392 · SE1801'), findsOneWidget);
      expect(find.text('SWD392 · SE1802'), findsOneWidget);
      expect(find.textContaining('2 slot học'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly across narrow and wide desktop sizes', (
      tester,
    ) async {
      final course = buildClass(
        id: 'c1',
        courseCode: 'SWD392',
        classCode: 'SE1805',
        scheduleCode: '34',
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 9, 12, 15, 20), // Saturday Slot 4
            endAt: DateTime(2026, 9, 12, 17, 40),
          ),
        ],
      );

      for (final size in const [
        Size(1024, 768),
        Size(1280, 720),
        Size(1600, 1000),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          wrapTimetable(
            classes: [course],
            onOpenMeeting: (_, _) {},
            now: DateTime(2026, 9, 12, 16, 0),
            surfaceSize: size,
          ),
        );
        await tester.pump();
        expect(find.text('SWD392 · SE1805'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
    });
  });
}
