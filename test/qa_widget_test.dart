import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/ui/teacher_app.dart';
import 'package:fap_attendance/lab3/ui/screens.dart';
import 'package:fap_attendance/lab3/ui/components.dart';
import 'package:fap_attendance/lab3/ui/mobile_theme.dart';

import 'lab3/fakes.dart';

Directory _createTempDir() => Directory.systemTemp.createTempSync('fap_qa_widget_');

void _cleanupDir(Directory dir) {
  if (dir.existsSync()) {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('1. Widget Test - Rendering with Valid Data', () {
    testWidgets('should render TeacherMobileApp and display DashboardPage when workspace is loaded', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Act
      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.text('PRM393'), findsOneWidget);
      expect(find.byKey(const ValueKey('timetable-nav-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('timetable-nav-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('timetable-nav-2')), findsOneWidget);
    });

    testWidgets('should render SectionCard and StatusTag correctly with provided content', (
      WidgetTester tester,
    ) async {
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          theme: mobileTheme(),
          home: const Scaffold(
            body: SectionCard(
              child: StatusTag('P · Có mặt', color: Colors.green),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('P · Có mặt'), findsOneWidget);
    });

    testWidgets('should render AttendancePage displaying class info and mode segments', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });
      await tester.binding.setSurfaceSize(const Size(412, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Act
      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator).first).push(
        MaterialPageRoute<void>(
          builder: (_) => const AttendancePage(classId: 'c1', meetingId: 'm1'),
        ),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('PRM393'), findsOneWidget);
      expect(find.text('Qua link'), findsOneWidget);
      expect(find.text('Thủ công'), findsOneWidget);
      expect(find.text('Nguyễn Thị Minh Anh'), findsOneWidget);
      expect(find.textContaining('S1 · Chi tiết'), findsOneWidget);
    });
  });

  group('2. Widget Test - Loading and Error States', () {
    testWidgets('should display CircularProgressIndicator when loadingWorkspace is true', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Simulate loading state
      h.vm.loadingWorkspace = true;
      h.vm.notifyListeners();

      // Act
      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pump();

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(DashboardPage), findsNothing);
    });

    testWidgets('should display error screen with retry button when workspace load fails', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Simulate load failed state
      h.vm.loadingWorkspace = false;
      h.vm.workspaceLoadFailed = true;
      h.vm.error = 'Lỗi nạp workspace';
      h.vm.notifyListeners();

      // Act
      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Mở dữ liệu'), findsOneWidget);
      expect(find.text('Chưa mở được dữ liệu trên thiết bị. Hãy thử lại trước khi tạo workspace mới.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Thử lại'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Đăng xuất / Đổi tài khoản'), findsOneWidget);
    });

    testWidgets('should call retryLoad when tapping Thử lại on error screen', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      h.vm.loadingWorkspace = false;
      h.vm.workspaceLoadFailed = true;
      h.vm.notifyListeners();

      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.widgetWithText(FilledButton, 'Thử lại'));
      await tester.pumpAndSettle();

      // Assert: After retry, workspace should recover to DashboardPage
      expect(find.byType(DashboardPage), findsOneWidget);
    });

    testWidgets('should display empty message when NotificationsPage has no notifications', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Act: Render NotificationsPage directly
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: h.vm,
          child: MaterialApp(
            theme: mobileTheme(),
            home: const NotificationsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert: Empty notification guidance is displayed
      expect(find.text('Chưa có thông báo. Kéo làm mới sau khi nhận thông báo mới.'), findsOneWidget);
    });
  });

  group('3. Widget Test - User Interactions (Tap, Scroll, Text Input)', () {
    testWidgets('should switch to Notifications tab and back when tapping navigation items', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      // Act: Tap 'Thông báo'
      await tester.tap(find.byKey(const ValueKey('timetable-nav-1')));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(NotificationsPage), findsOneWidget);

      // Act: Tap 'Lịch & lớp'
      await tester.tap(find.byKey(const ValueKey('timetable-nav-0')));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(DashboardPage), findsOneWidget);
    });

    testWidgets('should filter student list in AttendancePage when typing in search TextField', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });
      await tester.binding.setSurfaceSize(const Size(412, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator).first).push(
        MaterialPageRoute<void>(
          builder: (_) => const AttendancePage(classId: 'c1', meetingId: 'm1'),
        ),
      );
      await tester.pumpAndSettle();

      // Initially top students are shown
      expect(find.text('Nguyễn Thị Minh Anh'), findsOneWidget);
      expect(find.text('Trần Nguyễn Hoàng Phương Thảo'), findsOneWidget);

      // Act: Enter 'Minh Anh' into search field
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Minh Anh');
      await tester.pumpAndSettle();

      // Assert: Filtered to only Minh Anh
      expect(find.text('Nguyễn Thị Minh Anh'), findsOneWidget);
      expect(find.text('Lê Quốc Bảo'), findsNothing);

      // Act: Clear search by tapping suffix icon
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Assert: Reset to all students
      expect(find.text('DANH SÁCH SINH VIÊN (3/3)'), findsOneWidget);
      expect(find.text('Nguyễn Thị Minh Anh'), findsOneWidget);
    });

    testWidgets('should switch attendance mode to manual and allow toggling P/A status', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });
      await tester.binding.setSurfaceSize(const Size(412, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator).first).push(
        MaterialPageRoute<void>(
          builder: (_) => const AttendancePage(classId: 'c1', meetingId: 'm1'),
        ),
      );
      await tester.pumpAndSettle();

      // Act: Switch mode to 'Thủ công'
      await tester.tap(find.text('Thủ công'));
      await tester.pumpAndSettle();

      // Assert: Manual mode instructions visible
      expect(find.textContaining('Chọn Present hoặc Absent'), findsOneWidget);

      // Act: Tap 'P · Có mặt' for first student
      final presentBtn = find.text('P · Có mặt');
      await tester.tap(presentBtn.first);
      await tester.pumpAndSettle();

      // Assert: Student S1 marked present in ViewModel
      expect(h.vm.course('c1').recordFor('m1', 'S1')?.status, equals(AttendanceStatus.present));
    });

    testWidgets('should open confirmation dialog when tapping Chốt danh sách button', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });
      await tester.binding.setSurfaceSize(const Size(412, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator).first).push(
        MaterialPageRoute<void>(
          builder: (_) => const AttendancePage(classId: 'c1', meetingId: 'm1'),
        ),
      );
      await tester.pumpAndSettle();

      final closeBtn = find.widgetWithText(FilledButton, 'Chốt danh sách');
      await tester.scrollUntilVisible(
        closeBtn,
        150,
        scrollable: find.descendant(
          of: find.byType(AttendancePage),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.pumpAndSettle();

      // Act: Tap 'Chốt danh sách'
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // Assert: Confirmation dialog is displayed
      expect(find.text('Xác nhận chốt danh sách'), findsOneWidget);
      expect(find.text('Đồng ý chốt'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);
    });

    testWidgets('should scroll vertically without layout overflow when list is long', (
      WidgetTester tester,
    ) async {
      // Arrange: Seed 10 students
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      final manyStudents = List.generate(
        10,
        (i) => Student(
          rollNumber: 'SE1900${i.toString().padLeft(2, '0')}',
          email: 's$i@fpt.edu.vn',
          fullName: 'Sinh Viên Thứ $i',
        ),
      );
      final customWorkspace = fixtureWorkspace().copyWith(
        classes: [
          fixtureWorkspace().classes.first.copyWith(students: manyStudents),
        ],
      );
      await h.repo.save('teacher1', customWorkspace);
      await h.initialize(seed: false);
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });
      await tester.binding.setSurfaceSize(const Size(412, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();

      tester.state<NavigatorState>(find.byType(Navigator).first).push(
        MaterialPageRoute<void>(
          builder: (_) => const AttendancePage(classId: 'c1', meetingId: 'm1'),
        ),
      );
      await tester.pumpAndSettle();

      // Act: Drag / scroll down
      await tester.drag(
        find.descendant(of: find.byType(AttendancePage), matching: find.byType(Scrollable)).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();

      // Assert: Scrolled items visible without overflow error
      expect(tester.takeException(), isNull);
    });
  });
}
