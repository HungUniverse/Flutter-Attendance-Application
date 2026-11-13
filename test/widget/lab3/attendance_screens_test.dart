import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/ai_attendance_review.dart';
import 'package:fap_attendance/lab3/ui/attendance_screens.dart';
import 'package:fap_attendance/lab3/ui/mobile_theme.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../lab3/fakes.dart';

class _FakeAiService implements AttendanceReviewService {
  AiAttendanceReview nextReview = const AiAttendanceReview(
    '1 sinh viên chưa có trạng thái.',
    ['Kiểm tra lại S2', 'Xác nhận trước khi chốt'],
  );
  String? lastAccepted;

  @override
  Future<AiAttendanceReview> review({
    required int present,
    required int absent,
    required int unmarked,
  }) async => nextReview;

  @override
  Future<void> accept(String text) async {
    lastAccepted = text;
  }
}

void main() {
  late Directory tempDir;
  late Harness harness;
  late _FakeAiService aiService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('attendance_screens_test_');
    aiService = _FakeAiService();
    harness = Harness(tempDir, inMemory: true, ai: aiService);
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

  group('AttendancePage', () {
    testWidgets('filters students by name or roll number and clears search', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapScreen(const AttendancePage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Điểm danh lớp'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('DANH SÁCH SINH VIÊN (3/3)'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('DANH SÁCH SINH VIÊN (3/3)'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Tìm họ tên hoặc MSSV'),
        'S2',
      );
      await tester.pump();

      expect(find.text('DANH SÁCH SINH VIÊN (1/3)'), findsOneWidget);
      expect(find.text('Trần Nguyễn Hoàng Phương Thảo'), findsOneWidget);
      expect(find.text('Nguyễn Thị Minh Anh'), findsNothing);

      // Search with zero matches
      await tester.enterText(
        find.widgetWithText(TextField, 'Tìm họ tên hoặc MSSV'),
        'ZZZZZZ',
      );
      await tester.pump();
      expect(find.text('Không có sinh viên khớp tìm kiếm.'), findsOneWidget);

      // Clear search button restores all 3 students
      await tester.tap(find.byTooltip('Xóa tìm kiếm'));
      await tester.pump();
      expect(find.text('DANH SÁCH SINH VIÊN (3/3)'), findsOneWidget);
    });

    testWidgets('switches to manual mode, marks P/A, and opens draft dialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapScreen(const AttendancePage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thủ công'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Chọn Present hoặc Absent. Kết quả lưu trên thiết bị; sửa kết quả đã ghi cần lý do.',
        ),
        findsOneWidget,
      );

      // Mark first student Present
      await tester.scrollUntilVisible(
        find.text('P · Có mặt'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('P · Có mặt').first);
      await tester.tap(find.text('P · Có mặt').first);
      await tester.pumpAndSettle();

      expect(harness.vm.draftCount, 1);

      // Open draft review dialog (at top of list)
      await tester.scrollUntilVisible(
        find.text('Xem bản nháp'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, 140));
      await tester.pumpAndSettle();
      expect(
        find.text('1 lựa chọn trong bản nháp trên máy'),
        findsOneWidget,
      );
      await tester.tap(find.text('Xem bản nháp'));
      await tester.pumpAndSettle();

      expect(find.text('Bản nháp điểm danh trên máy'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    });

    testWidgets('requests AI review, accepts edited note, and closes meeting', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapScreen(const AttendancePage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI · Gợi ý kiểm tra trước khi chốt'));
      await tester.pumpAndSettle();

      expect(find.text('Gợi ý do AI tạo'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nội dung kiểm tra'),
        'Reviewed all 3 students',
      );
      await tester.tap(find.text('Xác nhận gợi ý'));
      await tester.pumpAndSettle();

      expect(aiService.lastAccepted, 'Reviewed all 3 students');
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      // Close attendance via confirmation dialog
      await tester.scrollUntilVisible(
        find.text('Chốt danh sách'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Chốt danh sách'));
      await tester.tap(find.text('Chốt danh sách'));
      await tester.pumpAndSettle();

      expect(find.text('Xác nhận chốt danh sách'), findsOneWidget);
      await tester.tap(find.text('Đồng ý chốt'));
      await tester.pumpAndSettle();

      expect(harness.vm.meeting('c1', 'm1').state, MeetingState.closed);
      expect(find.text('Kết quả điểm danh'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Xuất kết quả'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Xuất kết quả'), findsOneWidget);
    });

    testWidgets('starts an upcoming meeting on today date', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await harness.repo.save(
        'teacher1',
        fixtureWorkspace(state: MeetingState.upcoming),
      );
      await harness.vm.initialize(timers: false);

      await tester.pumpWidget(
        wrapScreen(const AttendancePage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bắt đầu điểm danh'), findsOneWidget);
      await tester.tap(find.text('Bắt đầu điểm danh'));
      await tester.pumpAndSettle();

      expect(harness.vm.meeting('c1', 'm1').state, MeetingState.active);
    });
  });

  group('LinkPage', () {
    testWidgets('creates, shares/copies, and stops attendance link', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrapScreen(const LinkPage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Link điểm danh'), findsOneWidget);
      expect(find.text('Tạo link điểm danh'), findsOneWidget);

      await tester.tap(find.text('Tạo link điểm danh'));
      await tester.pumpAndSettle();

      expect(find.text('Đang nhận qua link'), findsOneWidget);
      expect(find.text('Sao chép'), findsOneWidget);
      expect(find.text('Chia sẻ'), findsOneWidget);

      await tester.tap(find.text('Sao chép'));
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Dừng nhận qua link'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Dừng nhận qua link'));
      expect(find.text('Dừng nhận qua link'), findsOneWidget);
      await tester.tap(find.text('Dừng nhận qua link'));
      await tester.pumpAndSettle();

      expect(find.text('Dừng nhận qua link?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Dừng nhận'));
      await tester.pumpAndSettle();

      expect(find.text('Link tạm ngừng'), findsOneWidget);
    });
  });

  group('HistoryPage, StudentPage, and ExportPage', () {
    testWidgets('HistoryPage toggles Tất cả / Đã chốt filter and opens detail', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrapScreen(const HistoryPage(classId: 'c1')));
      await tester.pumpAndSettle();

      expect(find.text('Lịch sử điểm danh lớp'), findsOneWidget);
      expect(find.text('Xem chi tiết'), findsOneWidget);

      await tester.tap(find.text('Đã chốt'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có buổi học thuộc bộ lọc này.'), findsOneWidget);

      await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Xem chi tiết'));
      await tester.tap(find.text('Xem chi tiết'));
      await tester.pumpAndSettle();

      expect(find.byType(AttendancePage), findsOneWidget);
    });

    testWidgets('StudentPage shows stats, opens Sửa P/A sheet, validates, and saves', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await harness.vm.close('c1', 'm1');

      await tester.pumpWidget(
        wrapScreen(const StudentPage(classId: 'c1', roll: 'S1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chi tiết sinh viên'), findsOneWidget);
      expect(find.text('Nguyễn Thị Minh Anh'), findsOneWidget);
      expect(find.text('Sửa P/A'), findsOneWidget);

      await tester.ensureVisible(find.text('Sửa P/A'));
      await tester.tap(find.text('Sửa P/A'));
      await tester.pumpAndSettle();

      expect(find.text('Sửa kết quả điểm danh'), findsOneWidget);

      // Submit empty reason triggers validation error
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pump();
      expect(find.text('Vui lòng nhập lý do chỉnh sửa.'), findsOneWidget);

      // Switch to P and enter reason
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('P · Có mặt'),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lý do chỉnh sửa (bắt buộc)'),
        'Medical verification provided',
      );
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();

      expect(
        harness.vm.course('c1').recordFor('m1', 'S1')?.status,
        AttendanceStatus.present,
      );
      expect(find.text('Xem ghi chú'), findsOneWidget);

      await tester.ensureVisible(find.text('Xem ghi chú'));
      await tester.tap(find.text('Xem ghi chú'));
      await tester.pumpAndSettle();
      expect(find.text('Ghi chú & lịch sử chỉnh sửa'), findsOneWidget);
      expect(find.textContaining('Medical verification provided'), findsWidgets);
    });

    testWidgets('ExportPage exports CSV/JSON/PDF and renders saved file card', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await harness.vm.close('c1', 'm1');

      await tester.pumpWidget(
        wrapScreen(const ExportPage(classId: 'c1', meetingId: 'm1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Xuất kết quả điểm danh'), findsOneWidget);

      await tester.tap(find.text('CSV'));
      await tester.pump();
      expect(
        find.text('Dùng trao đổi và đối chiếu dữ liệu bảng tính.'),
        findsOneWidget,
      );

      await tester.tap(find.text('JSON'));
      await tester.pump();
      expect(
        find.text('Dùng cho Chrome Extension trên máy tính.'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('Xuất file'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Xuất file'));
      await tester.tap(find.text('Xuất file'));
      await tester.pump();
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (find.text('Đã lưu file trên thiết bị').evaluate().isNotEmpty &&
            harness.vm.exportedFile != null &&
            !harness.vm.busy) {
          break;
        }
      }
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Đã lưu file trên thiết bị'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Đã lưu file trên thiết bị'), findsOneWidget);
      expect(find.text('Chia sẻ tệp'), findsOneWidget);
      expect(harness.vm.exportedFile, isNotNull);
    });
  });
}
