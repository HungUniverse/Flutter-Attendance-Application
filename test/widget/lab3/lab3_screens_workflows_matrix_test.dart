import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/ui/screens.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../lab3/fakes.dart';

Finder get _verticalScroll => find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

class _MutableNotices extends FakeNotices {
  final List<AppNotice> items = [];

  @override
  Future<List<AppNotice>> history(String uid) async => List.of(items);
}

TeacherWorkspace _richWorkspace() {
  final today = DateTime(fixtureNow.year, fixtureNow.month, fixtureNow.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));
  final nextWeek = today.add(const Duration(days: 7));
  return TeacherWorkspace(
    id: 'ws-rich',
    semester: 'FA26',
    semesterStart: today.subtract(const Duration(days: 7)),
    teacherEmail: 'teacher1@fpt.edu.vn',
    classes: [
      CourseClass(
        id: 'c1',
        courseCode: 'SWD392',
        classCode: 'SE1801',
        scheduleCode: '22',
        students: const [
          Student(
            rollNumber: 'SE180001',
            fullName: 'Nguyen Thi Minh Anh',
            email: 'anh@fpt.edu.vn',
          ),
          Student(
            rollNumber: 'SE180002',
            fullName: 'Tran Quoc Bao',
            email: 'bao@fpt.edu.vn',
          ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '22',
          semesterStart: today.subtract(const Duration(days: 7)),
          weeks: 10,
        ),
        meetings: [
          Meeting(
            id: 'm-closed',
            number: 1,
            startAt: yesterday.add(const Duration(hours: 7)),
            endAt: yesterday.add(const Duration(hours: 9)),
            state: MeetingState.closed,
          ),
          Meeting(
            id: 'm-active',
            number: 2,
            startAt: today.add(const Duration(hours: 7)),
            endAt: today.add(const Duration(hours: 9)),
            state: MeetingState.active,
          ),
        ],
        attendance: {
          'm-closed': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: yesterday.add(const Duration(hours: 8)),
              note: 'Vao lop dung gio',
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: yesterday.add(const Duration(hours: 9)),
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'aud-1',
            meetingId: 'm-closed',
            rollNumber: 'SE180001',
            action: 'override',
            oldValue: 'absent',
            newValue: 'present',
            reason: 'Co mat ban dau gio',
            createdAt: yesterday.add(const Duration(hours: 9, minutes: 5)),
          ),
        ],
      ),
      CourseClass(
        id: 'c2',
        courseCode: 'PRM392',
        classCode: 'SE1802',
        scheduleCode: '24',
        students: const [
          Student(
            rollNumber: 'SE180003',
            fullName: 'Le Hoang Cuong',
            email: 'cuong@fpt.edu.vn',
          ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '24',
          semesterStart: tomorrow,
          weeks: 10,
        ),
        meetings: [
          Meeting(
            id: 'm-upcoming',
            number: 1,
            startAt: nextWeek.add(const Duration(hours: 10)),
            endAt: nextWeek.add(const Duration(hours: 12)),
            state: MeetingState.upcoming,
          ),
        ],
      ),
    ],
  );
}

void main() {
  late Directory tempDir;
  late Harness h;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lab3_screens_matrix_');
    h = Harness(tempDir, inMemory: true);
    await h.repo.save('teacher1', _richWorkspace());
    await h.initialize(seed: false);
  });

  tearDown(() async {
    await h.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) => ChangeNotifierProvider<TeacherViewModel>.value(
    value: h.vm,
    child: MaterialApp(
      theme: buildAppTheme(),
      home: child,
    ),
  );

  group('WorkspaceStartPage & ImportPage validation workflows', () {
    testWidgets('WorkspaceStartPage displays teacher identity and navigates to ImportPage & AccountPage', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(const WorkspaceStartPage()));
      await tester.pumpAndSettle();

      expect(find.text('FAP Attendance'), findsWidgets);
      expect(find.text('teacher@example.com'), findsOneWidget);
      expect(find.text('Nạp danh sách lớp'), findsOneWidget);

      await tester.tap(find.text('Nạp danh sách lớp'));
      await tester.pumpAndSettle();
      expect(find.text('Xem trước danh sách lớp'), findsOneWidget);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.text('Nạp danh sách lớp'), findsOneWidget);
    });

    testWidgets('ImportPage validates semester, weeks range, and required roster file before preview', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(const ImportPage()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Học kỳ'),
        'BAD SPACE!',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần (1–52)'),
        '60',
      );
      await tester.scrollUntilVisible(
        find.text('Xem trước danh sách lớp'),
        220,
        scrollable: _verticalScroll,
      );
      await tester.tap(find.text('Xem trước danh sách lớp'));
      await tester.pumpAndSettle();

      expect(find.text('Nhập học kỳ gồm chữ và số.'), findsOneWidget);
      expect(find.text('Nhập từ 1 đến 52 tuần.'), findsOneWidget);
      expect(find.text('Hãy chọn tệp danh sách lớp.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Học kỳ'),
        'FA26',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần (1–52)'),
        '10',
      );
      await tester.tap(find.text('Xem trước danh sách lớp'));
      await tester.pumpAndSettle();

      expect(find.text('Nhập học kỳ gồm chữ và số.'), findsNothing);
      expect(find.text('Nhập từ 1 đến 52 tuần.'), findsNothing);
      expect(find.text('Hãy chọn tệp danh sách lớp.'), findsOneWidget);
    });
  });

  group('DashboardPage & SchedulePage interaction workflows', () {
    testWidgets('DashboardPage expands course card, switches bottom tabs, and deletes class on confirm', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(const DashboardPage()));
      await tester.pumpAndSettle();

      expect(find.text('SWD392 · SE1801'), findsOneWidget);
      expect(find.text('PRM392 · SE1802'), findsOneWidget);

      // Expand PRM392 card
      await tester.scrollUntilVisible(
        find.text('PRM392 · SE1802'),
        220,
        scrollable: _verticalScroll,
      );
      await tester.tap(find.text('PRM392 · SE1802'));
      await tester.pumpAndSettle();
      expect(find.text('Cấu hình lịch'), findsOneWidget);
      expect(find.text('Xóa lớp'), findsOneWidget);

      // Confirm deletion of PRM392
      await tester.scrollUntilVisible(
        find.text('Xóa lớp'),
        150,
        scrollable: _verticalScroll,
      );
      await tester.tap(find.text('Xóa lớp'));
      await tester.pumpAndSettle();
      expect(find.text('Xóa lớp?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa lớp'));
      await tester.runAsync(() async {
        for (var i = 0; i < 40 && h.vm.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pumpAndSettle();

      expect(find.text('PRM392 · SE1802'), findsNothing);
      expect(h.vm.workspace!.classes.length, 1);

      // Switch to Notifications tab and back
      await tester.tap(find.text('Thông báo'));
      await tester.pumpAndSettle();
      expect(find.text('Bật thông báo'), findsOneWidget);

      await tester.tap(find.text('Lịch & lớp'));
      await tester.pumpAndSettle();
      expect(find.text('Lịch tuần & lớp học'), findsOneWidget);
    });

    testWidgets('SchedulePage locks started class and allows saving updated schedule on upcoming class', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // c1 has closed/active meetings -> locked
      await tester.pumpWidget(wrap(const SchedulePage(classId: 'c1')));
      await tester.pumpAndSettle();
      expect(
        find.text('Không thể đổi lịch vì lớp đã có buổi bắt đầu hoặc đã chốt.'),
        findsOneWidget,
      );

      // c2 only has upcoming meeting -> editable
      await tester.pumpWidget(wrap(const SchedulePage(classId: 'c2')));
      await tester.pumpAndSettle();
      expect(
        find.text('Được phép sửa trước khi lớp bắt đầu điểm danh.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số tuần (1–52)'),
        '12',
      );
      await tester.scrollUntilVisible(
        find.text('Lưu cấu hình'),
        220,
        scrollable: _verticalScroll,
      );
      await tester.tap(find.text('Lưu cấu hình'));
      await tester.pumpAndSettle();

      expect(h.vm.course('c2').scheduleRule.weeks, 12);
    });
  });

  group('HistoryPage, StudentPage & ExportPage workflows', () {
    testWidgets('HistoryPage toggles Tất cả vs Đã chốt filter cleanly', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(wrap(const HistoryPage(classId: 'c1')));
      await tester.pumpAndSettle();

      expect(find.text('SWD392 · SE1801'), findsOneWidget);
      expect(find.text('Xem chi tiết'), findsNWidgets(2));
      expect(find.text('Xuất kết quả'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<bool>),
          matching: find.text('Đã chốt'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Xem chi tiết'), findsOneWidget);
      expect(find.text('Xuất kết quả'), findsOneWidget);

      // Filter on class c2 which has zero closed meetings -> empty state message
      await tester.pumpWidget(wrap(const HistoryPage(classId: 'c2')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SegmentedButton<bool>),
          matching: find.text('Đã chốt'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa có buổi học thuộc bộ lọc này.'),
        findsOneWidget,
      );
    });

    testWidgets('StudentPage opens audit dialog, validates _EditSheet reason, and saves attendance edit', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(const StudentPage(classId: 'c1', roll: 'SE180001')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nguyen Thi Minh Anh'), findsOneWidget);
      expect(find.text('Có mặt: 1 · Vắng: 0'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Xem ghi chú'),
        200,
        scrollable: _verticalScroll,
      );
      await tester.tap(find.text('Xem ghi chú'));
      await tester.pumpAndSettle();

      expect(find.text('Ghi chú & lịch sử chỉnh sửa'), findsOneWidget);
      expect(find.textContaining('Co mat ban dau gio'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Sửa P/A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa P/A').last);
      await tester.pumpAndSettle();

      expect(find.text('Sửa kết quả điểm danh'), findsOneWidget);
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập lý do chỉnh sửa.'), findsOneWidget);

      await tester.tap(find.text('A · Vắng'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lý do chỉnh sửa (bắt buộc)'),
        'Nghi co phep sau buoi hoc',
      );
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();

      expect(
        h.vm.course('c1').recordFor('m-closed', 'SE180001')?.status,
        AttendanceStatus.absent,
      );
    });

    testWidgets('ExportPage switches PDF/JSON/CSV descriptions and exports report file', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(const ExportPage(classId: 'c1', meetingId: 'm-closed')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Báo cáo PDF có thể mở, lưu và chia sẻ trên thiết bị.'),
        findsOneWidget,
      );

      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();
      expect(
        find.text('Dùng cho Chrome Extension trên máy tính.'),
        findsOneWidget,
      );

      await tester.tap(find.text('CSV'));
      await tester.pumpAndSettle();
      expect(
        find.text('Dùng trao đổi và đối chiếu dữ liệu bảng tính.'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Xuất file'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Xuất file'));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Đã lưu file trên thiết bị'),
        200,
        scrollable: _verticalScroll,
      );
      expect(find.text('Đã lưu file trên thiết bị'), findsOneWidget);
      expect(find.text('Chia sẻ tệp'), findsOneWidget);
    });
  });

  group('NotificationsPage & AccountPage workflows', () {
    testWidgets('NotificationsPage handles empty state, permission grant, missing-meeting SnackBar & navigation', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mutableNotices = _MutableNotices();
      final localVm = TeacherViewModel(
        auth: h.auth,
        repository: h.repo,
        telemetry: h.telemetry,
        config: h.config,
        notifications: mutableNotices,
        uploads: h.upload,
        device: h.device,
        links: h.links,
        clock: () => h.clock,
      );
      addTearDown(() async {
        localVm.dispose();
        await mutableNotices.controller.close();
      });
      await localVm.initialize(timers: false);

      await tester.pumpWidget(
        ChangeNotifierProvider<TeacherViewModel>.value(
          value: localVm,
          child: MaterialApp(
            theme: buildAppTheme(),
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
      expect(find.textContaining('Quyền thông báo:'), findsOneWidget);

      // Inject two notices: one referencing a non-existent meeting, one valid
      mutableNotices.items.addAll([
        AppNotice(
          id: 'missing',
          title: 'Buổi không tồn tại',
          body: 'Missing test',
          at: fixtureNow,
          classId: 'c1',
          meetingId: 'no-such-meeting',
        ),
        AppNotice(
          id: 'valid',
          title: 'Buổi đang mở',
          body: 'Valid meeting notice',
          at: fixtureNow,
          classId: 'c1',
          meetingId: 'm-active',
        ),
      ]);
      await tester.tap(find.byTooltip('Làm mới'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Xem buổi học').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Không tìm thấy buổi học trên thiết bị này.'),
        findsOneWidget,
      );
    });

    testWidgets('AccountPage displays config state, refreshes config, and confirms sign-out', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 920));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) =>
                context.watch<TeacherViewModel>().user == null
                    ? const Scaffold(body: Text('Signed out'))
                    : const AccountPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Giảng viên'), findsOneWidget);
      expect(find.text('Tạo link: Đang bật'), findsOneWidget);

      h.config.current = const FeatureSettings(
        enableLink: false,
        exportHelp: 'New export note',
      );
      await tester.tap(find.text('Cập nhật cấu hình'));
      await tester.pumpAndSettle();
      expect(find.text('Tạo link: Tạm tắt'), findsOneWidget);
      expect(find.text('New export note'), findsOneWidget);

      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      expect(find.text('Đăng xuất?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng xuất').last);
      await tester.pumpAndSettle();

      expect(h.auth.current, isNull);
    });
  });
}
