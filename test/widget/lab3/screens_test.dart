import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/ui/mobile_theme.dart';
import 'package:fap_attendance/lab3/ui/screens.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../lab3/fakes.dart';

class _HistoryNotices extends FakeNotices {
  List<AppNotice> items = [];

  @override
  Future<List<AppNotice>> history(String uid) async => items;
}

void main() {
  late Directory tempDir;
  late Harness harness;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('screens_widget_test_');
    harness = Harness(tempDir, inMemory: true);
    await harness.initialize();
  });

  tearDown(() async {
    await harness.dispose();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Widget wrapScreen(Widget child, {Size size = const Size(412, 920)}) {
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

  group('WorkspaceStartPage', () {
    testWidgets('displays account email, local status, and navigates to ImportPage', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrapScreen(const WorkspaceStartPage()));
      await tester.pumpAndSettle();

      expect(find.text('FAP Attendance'), findsNWidgets(2));
      expect(find.text('teacher@example.com'), findsOneWidget);
      expect(find.text('Nạp danh sách lớp'), findsOneWidget);

      await tester.tap(find.text('Nạp danh sách lớp'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportPage), findsOneWidget);
      expect(find.text('TỆP NGUỒN'), findsOneWidget);
    });
  });

  group('ImportPage', () {
    testWidgets('validates missing file on submit and cancels back cleanly', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrapScreen(const ImportPage()));
      await tester.pumpAndSettle();

      expect(find.text('Chọn tệp'), findsOneWidget);
      expect(find.text('CẤU HÌNH HỌC KỲ'), findsOneWidget);

      await tester.ensureVisible(find.text('Xem trước danh sách lớp'));
      await tester.tap(find.text('Xem trước danh sách lớp'));
      await tester.pump();

      expect(find.text('Hãy chọn tệp danh sách lớp.'), findsOneWidget);

      // Invalid semester format validation
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Học kỳ'),
        'BAD SEMESTER!',
      );
      await tester.ensureVisible(find.text('Xem trước danh sách lớp'));
      await tester.tap(find.text('Xem trước danh sách lớp'));
      await tester.pump();

      expect(find.text('Nhập học kỳ gồm chữ và số.'), findsOneWidget);
    });
  });

  group('DashboardPage', () {
    testWidgets('renders semester summary, toggles weekly grid, and expands class card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrapScreen(const DashboardPage()));
      await tester.pumpAndSettle();

      expect(find.text('Lịch tuần & lớp học'), findsOneWidget);
      expect(find.text('Học kỳ FA26'), findsOneWidget);
      expect(find.text('1 lớp · 3 sinh viên'), findsOneWidget);
      expect(find.text('Dữ liệu lưu trên thiết bị'), findsOneWidget);
      expect(find.text('PRM393 · SE1901'), findsOneWidget);
      expect(find.text('Tuần này'), findsNothing);

      // Toggle to weekly schedule view
      await tester.tap(find.text('Lịch tuần'));
      await tester.pumpAndSettle();
      expect(find.text('Tuần này'), findsOneWidget);
      expect(find.text('02/11 – 08/11/2026'), findsOneWidget);

      // Toggle back to class list and expand PRM393
      await tester.tap(find.text('Danh sách lớp'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('PRM393 · SE1901'));
      await tester.tap(find.text('PRM393 · SE1901'));
      await tester.pumpAndSettle();

      expect(find.text('Lịch sử'), findsOneWidget);
      expect(find.text('Xem lịch'), findsOneWidget);
      expect(find.text('Xóa lớp'), findsOneWidget);
      expect(find.text('Vào buổi học'), findsOneWidget);

      await tester.ensureVisible(find.text('Vào buổi học'));
      await tester.tap(find.text('Vào buổi học'));
      await tester.pumpAndSettle();

      expect(find.byType(AttendancePage), findsOneWidget);
    });

    testWidgets('switches bottom NavigationBar tabs to NotificationsPage and back', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrapScreen(const DashboardPage()));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Thông báo'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsPage), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Lịch & lớp'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Học kỳ FA26'), findsOneWidget);
    });

    testWidgets('deletes class from expanded class card after confirmation', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await harness.vm.close('c1', 'm1');

      await tester.pumpWidget(wrapScreen(const DashboardPage()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('PRM393 · SE1901'));
      await tester.tap(find.text('PRM393 · SE1901'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Xóa lớp'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Xóa lớp'));
      await tester.pumpAndSettle();

      expect(find.text('Xóa lớp?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa lớp'));
      await tester.runAsync(() async {
        for (var i = 0; i < 120; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          if (harness.vm.workspace!.classes.isEmpty && !harness.vm.busy) break;
        }
      });
      await tester.pumpAndSettle();

      expect(harness.vm.workspace!.classes, isEmpty);
      expect(find.text('Nạp danh sách lớp để bắt đầu.'), findsOneWidget);
    });
  });

  group('SchedulePage', () {
    testWidgets('allows editing unlocked schedule and saving updated weeks', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final upcomingWs = fixtureWorkspace(state: MeetingState.upcoming);
      await harness.repo.save('teacher1', upcomingWs);
      await harness.vm.initialize(timers: false);

      await tester.pumpWidget(wrapScreen(const SchedulePage(classId: 'c1')));
      await tester.pumpAndSettle();

      expect(find.text('Cấu hình lịch lớp'), findsOneWidget);
      expect(
        find.text('Được phép sửa trước khi lớp bắt đầu điểm danh.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần (1–52)'),
        '6',
      );
      await tester.ensureVisible(find.text('Lưu cấu hình'));
      await tester.tap(find.text('Lưu cấu hình'));
      await tester.pumpAndSettle();

      expect(harness.vm.course('c1').scheduleRule.weeks, 6);
      expect(harness.vm.course('c1').meetings, hasLength(12));
    });

    testWidgets('locks schedule controls once a meeting has started', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrapScreen(const SchedulePage(classId: 'c1')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Không thể đổi lịch vì lớp đã có buổi bắt đầu hoặc đã chốt.',
        ),
        findsOneWidget,
      );
      expect(find.text('Thêm ngày nghỉ'), findsNothing);
    });
  });

  group('NotificationsPage and AccountPage', () {
    testWidgets('NotificationsPage displays empty state, requests permission, and renders notice', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final notices = _HistoryNotices();
      final customVm = TeacherViewModel(
        auth: harness.auth,
        repository: harness.repo,
        telemetry: harness.telemetry,
        config: harness.config,
        notifications: notices,
        uploads: harness.upload,
        device: harness.device,
        links: harness.links,
        clock: () => fixtureNow,
      );
      await customVm.initialize(timers: false);
      addTearDown(customVm.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<TeacherViewModel>.value(
          value: customVm,
          child: MaterialApp(
            theme: mobileTheme(),
            home: const NotificationsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Chưa có thông báo. Kéo làm mới sau khi nhận thông báo mới.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Bật thông báo'));
      await tester.pumpAndSettle();

      notices.items = [
        AppNotice(
          id: 'n1',
          title: 'Thông báo test',
          body: 'Nội dung chi tiết',
          at: fixtureNow,
          classId: 'missing',
          meetingId: 'm1',
        ),
      ];
      await customVm.refresh();
      await tester.pumpAndSettle();

      expect(find.text('Thông báo test'), findsOneWidget);
      await tester.tap(find.text('Xem buổi học'));
      await tester.pump();
      expect(
        find.text('Không tìm thấy buổi học trên thiết bị này.'),
        findsOneWidget,
      );
    });

    testWidgets('AccountPage displays profile, config refresh, and sign out dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapScreen(
          Consumer<TeacherViewModel>(
            builder: (_, vm, _) => vm.user == null
                ? const Scaffold(body: Text('Đã đăng xuất'))
                : const AccountPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tài khoản & cài đặt'), findsOneWidget);
      expect(find.text('Giảng viên'), findsOneWidget);
      expect(find.text('teacher@example.com'), findsOneWidget);
      expect(find.text('Tạo link: Đang bật'), findsOneWidget);

      await tester.tap(find.text('Cập nhật cấu hình'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Đăng xuất'));
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();

      expect(find.text('Đăng xuất?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng xuất').last);
      await tester.pumpAndSettle();

      expect(harness.vm.user, isNull);
      expect(find.text('Đã đăng xuất'), findsOneWidget);
    });
  });
}
