import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/schedule_service.dart';
import 'package:fap_attendance/lab3/ui/mobile_theme.dart';
import 'package:fap_attendance/lab3/ui/screens.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../lab3/fakes.dart';

void main() {
  late Harness harness;

  setUp(() async {
    harness = Harness(Directory.systemTemp, inMemory: true);
    await harness.initialize();
  });

  tearDown(() async {
    await harness.dispose();
  });

  Widget wrapWeeklyDashboard({Size size = const Size(412, 892)}) {
    return ChangeNotifierProvider<TeacherViewModel>.value(
      value: harness.vm,
      child: MaterialApp(
        theme: mobileTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const DashboardPage(),
        ),
      ),
    );
  }

  Future<void> openWeeklyTab(WidgetTester tester) async {
    await tester.pumpWidget(wrapWeeklyDashboard());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lịch tuần'));
    await tester.pumpAndSettle();
  }

  group('DashboardPage Weekly Agenda', () {
    testWidgets('renders current week strip, dates, and meeting card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openWeeklyTab(tester);

      expect(find.text('Tuần này'), findsOneWidget);
      expect(find.text('02/11 – 08/11/2026'), findsOneWidget);
      expect(find.text('03/11'), findsOneWidget);
      expect(find.text('PRM393'), findsOneWidget);
      expect(find.text('SE1901 · Slot 1'), findsOneWidget);
      expect(find.text('Không có lịch dạy'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recognizes ScheduleService slots across multiple days', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final slot1 = ScheduleService.slotTimes[1]!;
      final slot2 = ScheduleService.slotTimes[2]!;
      final ws = harness.vm.workspace!;
      final updatedClass = CourseClass(
        id: 'c1',
        courseCode: 'PRM392',
        classCode: 'SE1902',
        scheduleCode: '11',
        students: ws.classes.first.students,
        scheduleRule: ws.classes.first.scheduleRule,
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 11, 2, slot1.startHour, slot1.startMinute),
            endAt: DateTime(2026, 11, 2, slot1.endHour, slot1.endMinute),
            state: MeetingState.closed,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: DateTime(2026, 11, 4, slot2.startHour, slot2.startMinute),
            endAt: DateTime(2026, 11, 4, slot2.endHour, slot2.endMinute),
            state: MeetingState.upcoming,
          ),
          Meeting(
            id: 'm3',
            number: 3,
            startAt: DateTime(2026, 11, 6, 20, 0),
            endAt: DateTime(2026, 11, 6, 22, 0),
            state: MeetingState.active,
          ),
        ],
      );
      await harness.repo.save('teacher1', ws.copyWith(classes: [updatedClass]));
      await harness.vm.initialize(timers: false);

      await openWeeklyTab(tester);

      expect(find.text('Ca 1'), findsOneWidget);
      expect(find.text('Ca 2'), findsOneWidget);
      expect(find.text('PRM392'), findsNWidgets(3));
      expect(find.text('SE1902 · Slot 1'), findsOneWidget);
      expect(find.text('SE1902 · Slot 2'), findsOneWidget);
      expect(find.text('SE1902 · Slot 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigates between weeks and returns to current week with Tuần này', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openWeeklyTab(tester);

      // Move next week (no meetings there -> empty week banner)
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();

      expect(find.text('09/11 – 15/11/2026'), findsOneWidget);
      expect(
        find.text('Chưa có lịch dạy trong tuần này. Chọn tuần khác.'),
        findsOneWidget,
      );
      expect(find.text('PRM393'), findsNothing);

      // Jump back using Tuần này button
      await tester.tap(find.text('Tuần này'));
      await tester.pumpAndSettle();
      expect(find.text('02/11 – 08/11/2026'), findsOneWidget);
      expect(find.text('PRM393'), findsOneWidget);

      // Move previous week
      await tester.tap(find.byTooltip('Tuần trước'));
      await tester.pumpAndSettle();
      expect(find.text('26/10 – 01/11/2026'), findsOneWidget);
      expect(
        find.text('Chưa có lịch dạy trong tuần này. Chọn tuần khác.'),
        findsOneWidget,
      );
    });

    testWidgets('opens date picker from week range button and updates selected week', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openWeeklyTab(tester);

      await tester.tap(find.text('02/11 – 08/11/2026'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('10'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('09/11 – 15/11/2026'), findsOneWidget);
    });

    testWidgets('tapping a meeting row pushes AttendancePage', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await openWeeklyTab(tester);

      await tester.ensureVisible(find.text('PRM393'));
      await tester.tap(find.text('PRM393'));
      await tester.pumpAndSettle();

      expect(find.text('Điểm danh lớp'), findsOneWidget);
    });

    testWidgets('renders without overflow at 360px width and 1.3 textScale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 760),
            textScaler: TextScaler.linear(1.3),
          ),
          child: ChangeNotifierProvider<TeacherViewModel>.value(
            value: harness.vm,
            child: MaterialApp(
              theme: mobileTheme(),
              home: const DashboardPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lịch tuần'));
      await tester.pumpAndSettle();

      expect(find.text('PRM393'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
