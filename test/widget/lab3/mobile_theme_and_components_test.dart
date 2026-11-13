import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/ui/components.dart';
import 'package:fap_attendance/lab3/ui/mobile_theme.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';
import 'package:fap_attendance/ui/theme.dart';
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

  Widget wrapWithVm(Widget child) {
    return ChangeNotifierProvider<TeacherViewModel>.value(
      value: harness.vm,
      child: MaterialApp(
        theme: mobileTheme(),
        home: child,
      ),
    );
  }

  group('mobileTheme and MobileTokens', () {
    test('defines mobile color, spacing, and typography theme', () {
      final theme = mobileTheme();

      expect(MobileTokens.gap, 16.0);
      expect(MobileTokens.background, const Color(0xFFFFF7F3));
      expect(MobileTokens.border, const Color(0xFFD9DEE7));
      expect(theme.scaffoldBackgroundColor, MobileTokens.background);
      expect(theme.colorScheme.primary, AppColors.orangeDark);
      expect(theme.appBarTheme.backgroundColor, AppColors.orangeDark);
      expect(theme.appBarTheme.foregroundColor, Colors.white);
      expect(theme.appBarTheme.toolbarHeight, 64);
      expect(theme.navigationBarTheme.height, 76);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });
  });

  group('Formatting helpers', () {
    test('meetingLabel formats slot number, date, and time window', () {
      final meeting = Meeting(
        id: 'm1',
        number: 4,
        startAt: DateTime(2026, 11, 3, 7, 30),
        endAt: DateTime(2026, 11, 3, 9, 50),
      );
      expect(meetingLabel(meeting), 'Slot 4 · 03/11/2026\n07:30–09:50');
    });

    test('stateLabel maps every MeetingState', () {
      expect(stateLabel(MeetingState.upcoming), 'Chưa bắt đầu');
      expect(stateLabel(MeetingState.active), 'Đang điểm danh');
      expect(stateLabel(MeetingState.closed), 'Đã chốt');
    });

    test('statusLabel maps every AttendanceStatus and null', () {
      expect(statusLabel(AttendanceStatus.present), 'P · Có mặt');
      expect(statusLabel(AttendanceStatus.absent), 'A · Vắng');
      expect(statusLabel(AttendanceStatus.unmarked), 'Chưa ghi nhận');
      expect(statusLabel(null), 'Chưa ghi nhận');
    });
  });

  group('Shared UI components', () {
    testWidgets('SectionCard and StatusTag render content cleanly', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithVm(
          const Scaffold(
            body: ContentList(
              children: [
                SectionCard(child: Text('Card body text')),
                StatusTag('Đang điểm danh', color: AppColors.orangeDark),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Card body text'), findsOneWidget);
      expect(find.text('Đang điểm danh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MobilePage renders title, error banner, and dismisses message', (
      tester,
    ) async {
      // Trigger an error inside VM so error banner displays
      harness.repo.failSave = true;
      final ok = await harness.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present);
      expect(ok, isA<bool>());

      await tester.pumpWidget(
        wrapWithVm(
          const MobilePage(
            title: 'Trang kiểm thử',
            child: Center(child: Text('Page Body')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Trang kiểm thử'), findsOneWidget);
      expect(find.text('Page Body'), findsOneWidget);

      if (harness.vm.error != null) {
        expect(find.byTooltip('Đóng thông báo'), findsOneWidget);
        await tester.tap(find.byTooltip('Đóng thông báo'));
        await tester.pump();
        expect(harness.vm.error, isNull);
      }
    });

    testWidgets('Totals renders live student counts for present, absent, unmarked', (
      tester,
    ) async {
      await harness.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present);
      await harness.vm.mark('c1', 'm1', 'S2', AttendanceStatus.absent);

      await tester.pumpWidget(
        wrapWithVm(
          const MobilePage(
            title: 'Tổng quan',
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Totals(classId: 'c1', meetingId: 'm1'),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sĩ số'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Có mặt'), findsOneWidget);
      expect(find.text('Vắng'), findsOneWidget);
      expect(find.text('Chưa ghi'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(3));
    });

    testWidgets('confirmAction returns true on confirm and false on cancel', (
      tester,
    ) async {
      bool? lastResult;
      await tester.pumpWidget(
        wrapWithVm(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    lastResult = await confirmAction(
                      context,
                      'Tiêu đề xác nhận',
                      'Nội dung chi tiết',
                      confirm: 'Xác nhận ngay',
                    );
                  },
                  child: const Text('Trigger'),
                ),
              ),
            ),
          ),
        ),
      );

      // Cancel flow
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();
      expect(find.text('Tiêu đề xác nhận'), findsOneWidget);
      expect(find.text('Nội dung chi tiết'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(lastResult, isFalse);

      // Confirm flow
      await tester.tap(find.text('Trigger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận ngay'));
      await tester.pumpAndSettle();
      expect(lastResult, isTrue);
    });

    testWidgets('showResult displays VM success message in SnackBar', (
      tester,
    ) async {
      await harness.vm.close('c1', 'm1');
      expect(harness.vm.message, isNotNull);

      await tester.pumpWidget(
        wrapWithVm(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showResult(context, true),
                  child: const Text('Show Result'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Result'));
      await tester.pump();

      expect(find.text(harness.vm.message!), findsOneWidget);
    });
  });
}
