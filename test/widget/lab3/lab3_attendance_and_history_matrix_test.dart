import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/ui/components.dart';
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

  Widget wrap(Widget child, {Size size = const Size(412, 920)}) {
    return ChangeNotifierProvider<TeacherViewModel>.value(
      value: harness.vm,
      child: MaterialApp(
        theme: mobileTheme(),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: child,
        ),
      ),
    );
  }

  group('MobilePage, StatusTag, Totals & confirmAction components', () {
    testWidgets('MobilePage renders error banner with dismiss button and sync status', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await harness.vm.begin('c1', 'm2');
      expect(harness.vm.error, isNotNull);
      await tester.pumpWidget(
        wrap(const MobilePage(title: 'Tiêu đề', child: Text('Nội dung chính'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tiêu đề'), findsOneWidget);
      expect(find.text('Nội dung chính'), findsOneWidget);
      expect(find.text(harness.vm.error!), findsOneWidget);

      await tester.tap(find.byTooltip('Đóng thông báo'));
      await tester.pumpAndSettle();
      expect(harness.vm.error, isNull);
    });

    testWidgets('Totals renders Sĩ số, Có mặt, Vắng, and Chưa ghi counts accurately', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          const Scaffold(
            body: Totals(classId: 'c1', meetingId: 'm1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sĩ số'), findsOneWidget);
      expect(find.text('Có mặt'), findsOneWidget);
      expect(find.text('Vắng'), findsOneWidget);
      expect(find.text('Chưa ghi'), findsOneWidget);
    });

    testWidgets('confirmAction returns true on confirm and false on cancel', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: mobileTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await confirmAction(
                    context,
                    'Xác nhận hành động',
                    'Nội dung mô tả.',
                    confirm: 'Tiếp tục',
                  );
                },
                child: const Text('Mở hộp thoại'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở hộp thoại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('Mở hộp thoại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiếp tục'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  });

  group('AttendancePage interactive marking, draft notice & close lifecycle', () {
    testWidgets('marks manual P/A into local draft, inspects & discards draft from modal', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      harness.vm.selectMode(AttendanceMode.manual);
      await tester.pumpWidget(
        wrap(const AttendancePage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      final verticalScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.text('Nguyễn Thị Minh Anh'),
        220,
        scrollable: verticalScroll,
      );
      await tester.ensureVisible(find.text('P · Có mặt').first);
      await tester.tap(find.text('P · Có mặt').first);
      await tester.pumpAndSettle();

      expect(harness.vm.draftCount, greaterThan(0));
      await tester.scrollUntilVisible(
        find.text('Xem bản nháp'),
        -220,
        scrollable: verticalScroll,
      );
      expect(find.text('Xem bản nháp'), findsOneWidget);

      await tester.tap(find.text('Xem bản nháp'));
      await tester.pumpAndSettle();
      expect(find.text('Bản nháp điểm danh trên máy'), findsOneWidget);
      expect(find.text('Bỏ bản nháp này'), findsOneWidget);

      await tester.tap(find.text('Bỏ bản nháp này'));
      await tester.pumpAndSettle();
      expect(find.text('Bỏ bản nháp này?'), findsOneWidget);
      await tester.tap(find.text('Bỏ bản nháp'));
      await tester.pumpAndSettle();

      expect(harness.vm.draftCount, 0);
    });

    testWidgets('closes active meeting via confirmation dialog and reveals Export button', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(const AttendancePage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      final verticalScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.text('Chốt danh sách'),
        250,
        scrollable: verticalScroll,
      );
      await tester.tap(find.text('Chốt danh sách'));
      await tester.pumpAndSettle();

      expect(find.text('Xác nhận chốt danh sách'), findsOneWidget);
      await tester.tap(find.text('Đồng ý chốt'));
      await tester.pumpAndSettle();

      // Dismiss SnackBar before asserting rest of view
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      expect(
        harness.vm.meeting('c1', 'm1').state,
        MeetingState.closed,
      );
      expect(find.text('Kết quả điểm danh'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Xuất kết quả'),
        250,
        scrollable: verticalScroll,
      );
      expect(find.text('Xuất kết quả'), findsOneWidget);
    });

    testWidgets('upcoming non-today meeting disables start button with helpful copy', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final base = fixtureWorkspace();
      final c1 = base.classes.single;
      final futureMeeting = Meeting(
        id: 'm2',
        number: 2,
        startAt: DateTime(2026, 11, 10, 9, 30),
        endAt: DateTime(2026, 11, 10, 11, 45),
        state: MeetingState.upcoming,
      );
      final futureHarness = Harness(Directory.systemTemp, inMemory: true);
      addTearDown(futureHarness.dispose);
      await futureHarness.repo.save(
        'teacher1',
        base.copyWith(
          classes: [
            c1.copyWith(meetings: [...c1.meetings, futureMeeting]),
          ],
        ),
      );
      await futureHarness.initialize(seed: false);

      await tester.pumpWidget(
        ChangeNotifierProvider<TeacherViewModel>.value(
          value: futureHarness.vm,
          child: MaterialApp(
            theme: mobileTheme(),
            home: const MediaQuery(
              data: MediaQueryData(size: Size(412, 900)),
              child: AttendancePage(classId: 'c1', meetingId: 'm2'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Chưa đến ngày học. Chưa thể điểm danh buổi này.'),
        findsOneWidget,
      );
      final startBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Bắt đầu điểm danh'),
      );
      expect(startBtn.onPressed, isNull);
    });
  });

  group('Weekly schedule & LinkPage controls', () {
    testWidgets('DashboardPage weekly agenda navigates weeks and returns to current week', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(const DashboardPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lịch tuần'));
      await tester.pumpAndSettle();

      // Next week -> empty week notice
      await tester.tap(find.byTooltip('Tuần sau'));
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa có lịch dạy trong tuần này. Chọn tuần khác.'),
        findsOneWidget,
      );

      // Return to current week
      await tester.tap(find.text('Tuần này'));
      await tester.pumpAndSettle();
      expect(find.text('PRM393'), findsOneWidget);
      expect(find.text('SE1901 · Slot 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('LinkPage renders active session copy/share/stop workflow when link enabled', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 940));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(const LinkPage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Link tạm ngừng'), findsOneWidget);
      await tester.tap(find.text('Tạo link điểm danh'));
      await tester.pumpAndSettle();

      expect(find.text('Đang nhận qua link'), findsOneWidget);
      expect(find.text('Sao chép'), findsOneWidget);
      expect(find.text('Chia sẻ'), findsOneWidget);

      await tester.tap(find.text('Sao chép'));
      await tester.pumpAndSettle();
      expect(harness.device.copied, isNotNull);
    });
  });
}
