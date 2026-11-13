import 'dart:io';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/ui/desktop/class_detail_page.dart';
import 'package:fap_attendance/ui/desktop/desktop_app.dart';
import 'package:fap_attendance/ui/desktop/weekly_timetable.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAuth implements AuthService {
  @override
  TeacherIdentity? current;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {
    current = const TeacherIdentity('t-1', 'gv@fpt.edu.vn', 'Giang vien');
  }

  @override
  Future<void> signOut() async {
    current = null;
  }

  @override
  Future<String> token() async => 'stub-token';
}

void main() {
  late Directory tempDir;
  late AttendanceController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('desktop_app_widget_');
    controller = AttendanceController(
      teacherAuth: _StubAuth(),
      documentsDirectory: tempDir,
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  TeacherWorkspace buildWorkspace({required DateTime todayMeetingStart}) {
    return TeacherWorkspace(
      id: 'ws-desktop',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      teacherEmail: 'gv@fpt.edu.vn',
      classes: [
        CourseClass(
          id: 'cls-1',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          scheduleCode: '11',
          students: const [
            Student(
              rollNumber: 'SE180001',
              email: 'an@fpt.edu.vn',
              fullName: 'Nguyen Van An',
            ),
            Student(
              rollNumber: 'SE180002',
              email: 'binh@fpt.edu.vn',
              fullName: 'Tran Thi Binh',
            ),
          ],
          scheduleRule: ScheduleRule(
            scheduleCode: '11',
            semesterStart: DateTime(2026, 9, 7),
            weeks: 2,
          ),
          meetings: [
            Meeting(
              id: 'm1',
              number: 1,
              startAt: todayMeetingStart,
              endAt: todayMeetingStart.add(const Duration(hours: 2)),
              state: MeetingState.closed,
            ),
            Meeting(
              id: 'm2',
              number: 2,
              startAt: todayMeetingStart.add(const Duration(days: 3)),
              endAt: todayMeetingStart
                  .add(const Duration(days: 3))
                  .add(const Duration(hours: 2)),
              state: MeetingState.upcoming,
            ),
          ],
        ),
        CourseClass(
          id: 'cls-2',
          courseCode: 'SWD392',
          classCode: 'SE1802',
          scheduleCode: '22',
          students: const [
            Student(
              rollNumber: 'SE180003',
              email: 'cuong@fpt.edu.vn',
              fullName: 'Le Van Cuong',
            ),
          ],
          scheduleRule: ScheduleRule(
            scheduleCode: '22',
            semesterStart: DateTime(2026, 9, 7),
            weeks: 5,
          ),
          meetings: [
            Meeting(
              id: 'm3',
              number: 1,
              startAt: todayMeetingStart.add(const Duration(days: 5)),
              endAt: todayMeetingStart
                  .add(const Duration(days: 5))
                  .add(const Duration(hours: 2)),
              state: MeetingState.upcoming,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DesktopHomePage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('DesktopHomePage empty state', () {
    testWidgets('renders wide two-pane onboarding screen when workspace is null', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpHome(tester, size: const Size(1440, 900));

      expect(find.text('FAP ATTENDANCE'), findsOneWidget);
      expect(find.text('Chào mừng trở lại!'), findsOneWidget);
      expect(
        find.text('Nhập email giảng viên để bắt đầu workspace học kỳ.'),
        findsOneWidget,
      );
      expect(find.text('Tiếp tục với markbook'), findsOneWidget);
      expect(find.text('Không gian điểm danh'), findsOneWidget);
      expect(find.text('Import roster'), findsOneWidget);
      expect(find.text('Điểm danh QR'), findsOneWidget);
      expect(find.text('Lưu an toàn'), findsOneWidget);
      expect(find.text('Điểm danh gọn hơn mỗi ngày'), findsOneWidget);
      expect(find.text('Đăng nhập Google để đồng bộ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides marketing preview column on compact width (< 900px)', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpHome(tester, size: const Size(820, 900));

      expect(find.text('Chào mừng trở lại!'), findsOneWidget);
      expect(find.text('Không gian điểm danh'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('DesktopHomePage workspace dashboard', () {
    testWidgets('renders metrics, timetable, and expandable class manager', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      controller.workspace = buildWorkspace(todayMeetingStart: todayStart);
      await tester.runAsync(() => controller.save());

      await pumpHome(tester, size: const Size(1440, 1000));

      expect(find.text('FAP ATTENDANCE WORKSPACE'), findsOneWidget);
      expect(find.text('Cập nhật danh sách lớp'), findsOneWidget);
      expect(find.text('Chào ngày dạy mới!'), findsOneWidget);
      expect(find.textContaining('Học kỳ FA26'), findsOneWidget);
      expect(find.text('Lớp đang dạy'), findsOneWidget);
      expect(find.text('Lớp hôm nay'), findsOneWidget);
      expect(find.text('Sinh viên'), findsOneWidget);
      expect(find.byType(WeeklyTimetable), findsOneWidget);
      expect(find.text('Quản lý lớp'), findsOneWidget);

      // Expand Quản lý lớp
      await tester.ensureVisible(find.text('Quản lý lớp'));
      await tester.tap(find.text('Quản lý lớp'));
      await tester.pumpAndSettle();

      expect(find.text('PRM392'), findsOneWidget);
      expect(find.text('SE1801'), findsOneWidget);
      expect(find.text('SWD392'), findsOneWidget);
      expect(find.text('SE1802'), findsOneWidget);
      expect(find.text('1/2 slot đã chốt'), findsOneWidget);
      expect(find.text('0/1 slot đã chốt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens ClassDetailPage when tapping Mở lớp', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      controller.workspace = buildWorkspace(todayMeetingStart: todayStart);
      await tester.runAsync(() => controller.save());

      await pumpHome(tester, size: const Size(1440, 1000));

      await tester.ensureVisible(find.text('Quản lý lớp'));
      await tester.tap(find.text('Quản lý lớp'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Mở lớp').first);
      await tester.tap(find.text('Mở lớp').first);
      await tester.pumpAndSettle();

      expect(find.byType(ClassDetailPage), findsOneWidget);
      expect(find.text('PRM392 · SE1801'), findsOneWidget);
    });

    testWidgets('deletes class after confirmation dialog', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      controller.workspace = buildWorkspace(todayMeetingStart: todayStart);
      await tester.runAsync(() => controller.save());

      await pumpHome(tester, size: const Size(1440, 1000));

      await tester.ensureVisible(find.text('Quản lý lớp'));
      await tester.tap(find.text('Quản lý lớp'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Xóa').last);
      await tester.tap(find.text('Xóa').last);
      await tester.pumpAndSettle();

      expect(find.text('Xóa lớp khỏi workspace?'), findsOneWidget);
      var notified = false;
      void onNotify() => notified = true;
      controller.addListener(onNotify);
      addTearDown(() => controller.removeListener(onNotify));
      await tester.tap(find.text('Xóa lớp'));
      await tester.pump();
      for (var i = 0; i < 80 && !notified; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
      }
      await tester.pumpAndSettle();

      expect(notified, isTrue);
      expect(controller.workspace!.classes, hasLength(1));
      final remainingCode = controller.workspace!.classes.single.courseCode;
      final removedCode = remainingCode == 'PRM392' ? 'SWD392' : 'PRM392';
      expect(find.text(removedCode), findsNothing);
    });

    testWidgets('displays lastMessage banner on dashboard', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      controller.workspace = buildWorkspace(todayMeetingStart: todayStart);
      controller.lastMessage = 'Đã đồng bộ dữ liệu mẫu';
      await tester.runAsync(() => controller.save());

      await pumpHome(tester, size: const Size(1440, 1000));

      expect(find.text('Đã đồng bộ dữ liệu mẫu'), findsOneWidget);
    });
  });
}
