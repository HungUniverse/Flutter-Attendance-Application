import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/ui/desktop/schedule_settings_dialog.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CourseClass sampleClass({
    String scheduleCode = '11',
    int weeks = 10,
    int meetingsPerWeek = 2,
    List<int> weekdays = const [],
    List<DateTime> excludedDates = const [],
    List<DateTime> additionalStarts = const [],
  }) {
    return CourseClass(
      id: 'cls-1',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      scheduleCode: scheduleCode,
      students: const [],
      scheduleRule: ScheduleRule(
        scheduleCode: scheduleCode,
        semesterStart: DateTime(2026, 9, 7),
        weeks: weeks,
        meetingsPerWeek: meetingsPerWeek,
        weekdays: weekdays,
        excludedDates: excludedDates,
        additionalStarts: additionalStarts,
      ),
      meetings: const [],
    );
  }

  Widget buildHost({
    required CourseClass courseClass,
    required ValueChanged<ScheduleRule?> onResult,
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                final result = await showScheduleSettingsDialog(
                  context,
                  courseClass,
                );
                onResult(result);
              },
              child: const Text('Open Settings'),
            ),
          ),
        ),
      ),
    );
  }

  group('showScheduleSettingsDialog', () {
    testWidgets('displays dialog title, subtitle, controls, and cancels cleanly', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      ScheduleRule? captured = ScheduleRule(
        scheduleCode: 'sentinel',
        semesterStart: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        buildHost(
          courseClass: sampleClass(),
          onResult: (value) => captured = value,
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình lịch riêng'), findsOneWidget);
      expect(find.text('PRM392 · SE1801'), findsOneWidget);
      expect(find.text('Số tuần giảng dạy'), findsOneWidget);
      expect(find.text('Số slot mỗi tuần'), findsOneWidget);
      expect(find.text('2 slot'), findsOneWidget);
      expect(find.text('Ngày học trong tuần'), findsOneWidget);
      expect(find.text('Thứ Hai'), findsOneWidget);
      expect(find.text('Thứ Năm'), findsOneWidget);
      expect(find.text('Ngày nghỉ và học bù'), findsOneWidget);
      expect(
        find.textContaining('Dự kiến 20 slot trước khi trừ ngày nghỉ'),
        findsOneWidget,
      );
      expect(find.text('Hủy'), findsOneWidget);
      expect(find.text('Lưu và sinh lại lịch'), findsOneWidget);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });

    testWidgets('saves updated weeks, 1 slot per week, and selected weekday', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      ScheduleRule? captured;
      await tester.pumpWidget(
        buildHost(
          courseClass: sampleClass(weeks: 10, meetingsPerWeek: 2),
          onResult: (value) => captured = value,
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      // Update weeks text field to 8
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần giảng dạy'),
        '8',
      );
      await tester.pump();
      expect(
        find.textContaining('Dự kiến 16 slot trước khi trừ ngày nghỉ'),
        findsOneWidget,
      );

      // Open dropdown and select 1 slot
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 slot').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Dự kiến 8 slot trước khi trừ ngày nghỉ'),
        findsOneWidget,
      );

      // Select Thứ Năm ChoiceChip (now enabled because meetingsPerWeek == 1)
      await tester.tap(find.widgetWithText(ChoiceChip, 'Thứ Năm'));
      await tester.pump();

      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.weeks, 8);
      expect(captured!.meetingsPerWeek, 1);
      expect(captured!.weekdays, [DateTime.thursday]);
    });

    testWidgets('validates weeks range and date format before saving', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      ScheduleRule? captured;
      await tester.pumpWidget(
        buildHost(
          courseClass: sampleClass(),
          onResult: (value) => captured = value,
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      // Invalid weeks (99 > 52) blocks saving
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần giảng dạy'),
        '99',
      );
      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pump();

      expect(find.text('Nhập từ 1 đến 52 tuần'), findsOneWidget);
      expect(captured, isNull);

      // Fix weeks to 12, then expand advanced section & enter invalid date
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần giảng dạy'),
        '12',
      );
      await tester.tap(find.text('Ngày nghỉ và học bù'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày nghỉ'),
        '21-09-2026',
      );
      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pump();

      expect(find.text('Ngày "21-09-2026" không đúng yyyy-MM-dd.'), findsOneWidget);
      expect(captured, isNull);

      // Fix dates and save
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày nghỉ'),
        '2026-09-21, 2026-10-05',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ngày học bù'),
        '2026-10-11',
      );
      await tester.tap(find.text('Lưu và sinh lại lịch'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.weeks, 12);
      expect(captured!.excludedDates, [
        DateTime(2026, 9, 21),
        DateTime(2026, 10, 5),
      ]);
      expect(captured!.additionalStarts, [DateTime(2026, 10, 11)]);
    });

    testWidgets('prepopulates existing excludedDates and additionalStarts', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildHost(
          courseClass: sampleClass(
            scheduleCode: '22', // Tuesday + Thursday
            excludedDates: [DateTime(2026, 9, 15)],
            additionalStarts: [DateTime(2026, 9, 20)],
          ),
          onResult: (_) {},
        ),
      );

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Thứ Ba'), findsOneWidget);
      expect(find.text('Thứ Sáu'), findsOneWidget);

      await tester.tap(find.text('Ngày nghỉ và học bù'));
      await tester.pumpAndSettle();

      expect(find.text('2026-09-15'), findsOneWidget);
      expect(find.text('2026-09-20'), findsOneWidget);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
    });
  });
}
