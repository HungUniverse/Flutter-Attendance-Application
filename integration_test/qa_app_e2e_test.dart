import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/ui/teacher_app.dart';
import 'package:fap_attendance/lab3/ui/screens.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';

import '../test/lab3/fakes.dart';

Directory _createTempDir() => Directory.systemTemp.createTempSync('fap_qa_integ_');

void _cleanupDir(Directory dir) {
  if (dir.existsSync()) {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final roboto = File('assets/fonts/Roboto.ttf');
    final arial = File('C:/Windows/Fonts/arial.ttf');
    final fontFile = roboto.existsSync() ? roboto : (arial.existsSync() ? arial : null);
    if (fontFile != null) {
      final bytes = ByteData.sublistView(fontFile.readAsBytesSync());
      for (final family in ['Roboto', 'Segoe UI']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });

  group('End-to-End Integration Flow', () {
    testWidgets('should complete full user journey: login -> dashboard -> mark attendance -> finalize -> audit edit -> sign out', (
      WidgetTester tester,
    ) async {
      // 1. Arrange & Launch App
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      h.auth.current = null; // Start unauthenticated
      await h.initialize(seed: true);
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      // 2. Auth Flow: Login
      expect(find.byType(TeacherSignInPage), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập với Google'));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.text('PRM393'), findsOneWidget);

      // 3. Navigation Flow: Bottom Navigation Bar
      await tester.tap(find.byKey(const ValueKey('timetable-nav-1')));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('timetable-nav-0')));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);

      // 4. Core Business Flow: Expand Class Card -> Enter Attendance
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PRM393 · SE1901').first);
      await tester.pumpAndSettle();

      final enterMeetingBtn = find.text('Vào buổi học');
      expect(enterMeetingBtn, findsOneWidget);
      await tester.tap(enterMeetingBtn);
      await tester.pumpAndSettle();

      expect(find.byType(AttendancePage), findsOneWidget);

      // Switch to manual mode
      await tester.tap(find.text('Thủ công'));
      await tester.pumpAndSettle();
      expect(h.vm.mode, equals(AttendanceMode.manual));

      // Mark S1 present
      final presentSegment = find.text('P · Có mặt').first;
      await tester.tap(presentSegment);
      await tester.pumpAndSettle();
      expect(h.vm.course('c1').recordFor('m1', 'S1')?.status, equals(AttendanceStatus.present));

      // Dismiss SnackBar from previous action so it doesn't obscure buttons
      ScaffoldMessenger.of(tester.element(find.byType(AttendancePage))).clearSnackBars();
      await tester.pumpAndSettle();

      // Finalize meeting
      final closeButton = find.widgetWithText(FilledButton, 'Chốt danh sách');
      final scrollableFinder = find.descendant(
        of: find.byType(AttendancePage),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(
        closeButton,
        150,
        scrollable: scrollableFinder,
      );
      await tester.pumpAndSettle();

      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      // Confirm closure
      expect(find.text('Xác nhận chốt danh sách'), findsOneWidget);
      await tester.tap(find.text('Đồng ý chốt'));
      await tester.pumpAndSettle();

      expect(h.vm.meeting('c1', 'm1').state, equals(MeetingState.closed));
      expect(h.vm.course('c1').recordFor('m1', 'S2')?.status, equals(AttendanceStatus.absent));

      // 5. Audit Edit Flow: Edit S2 attendance with reason via true UI navigation
      final s2Card = find.text('S2 · Chi tiết');
      await tester.scrollUntilVisible(
        s2Card,
        100,
        scrollable: scrollableFinder,
      );
      await tester.pumpAndSettle();

      // Tap on student S2 to open StudentPage
      await tester.tap(s2Card);
      await tester.pumpAndSettle();
      expect(find.byType(StudentPage), findsOneWidget);

      // Open Edit Sheet
      await tester.tap(find.widgetWithText(FilledButton, 'Sửa P/A'));
      await tester.pumpAndSettle();

      expect(find.text('Sửa kết quả điểm danh'), findsOneWidget);
      await tester.tap(find.text('P · Có mặt'));
      await tester.pumpAndSettle();

      final reasonField = find.widgetWithText(TextFormField, 'Lý do chỉnh sửa (bắt buộc)');
      await tester.enterText(reasonField, 'Có đơn xin nghỉ ốm hợp lệ được duyệt');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Lưu thay đổi'));
      await tester.pumpAndSettle();

      expect(h.vm.course('c1').recordFor('m1', 'S2')?.status, equals(AttendanceStatus.present));
      expect(h.vm.course('c1').recordFor('m1', 'S2')?.note, contains('Có đơn xin nghỉ ốm'));

      // Return to AttendancePage via UI BackButton
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(AttendancePage), findsOneWidget);

      // Return to ClassManagementPage and then DashboardPage via UI BackButton
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Danh sách lớp'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardPage), findsOneWidget);

      // 6. Sign Out Flow: Navigate to Account and Sign Out
      await tester.tap(find.byKey(const ValueKey('timetable-nav-2')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsOneWidget);

      final signOutBtn = find.widgetWithText(FilledButton, 'Đăng xuất');
      await tester.scrollUntilVisible(
        signOutBtn,
        150,
        scrollable: find.descendant(
          of: find.byType(AccountPage),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(signOutBtn);
      await tester.pumpAndSettle();

      expect(find.text('Đăng xuất?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng xuất').last);
      await tester.pumpAndSettle();

      expect(h.vm.user, isNull);
      expect(find.byType(TeacherSignInPage), findsOneWidget);
    });
  });
}
