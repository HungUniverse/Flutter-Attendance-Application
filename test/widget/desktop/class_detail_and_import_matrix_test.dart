import 'dart:io';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/ui/desktop/class_detail_page.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TeacherWorkspace _detailWorkspace() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 2));

  return TeacherWorkspace(
    id: 'ws-detail',
    semester: 'FA26',
    semesterStart: today.subtract(const Duration(days: 7)),
    teacherEmail: 'teacher@fpt.edu.vn',
    classes: [
      CourseClass(
        id: 'c1',
        courseCode: 'SWD392',
        classCode: 'SE1801',
        scheduleCode: '22',
        students: const [
          Student(
            rollNumber: 'SE180001',
            fullName: 'Nguyen Van An',
            email: 'an@fpt.edu.vn',
          ),
          Student(
            rollNumber: 'SE180002',
            fullName: 'Tran Thi Binh',
            email: 'binh@fpt.edu.vn',
          ),
          Student(
            rollNumber: 'SE180003',
            fullName: 'Le Hoang Cuong',
            email: 'cuong@fpt.edu.vn',
          ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '22',
          semesterStart: today.subtract(const Duration(days: 7)),
          weeks: 10,
        ),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: yesterday.add(const Duration(hours: 7)),
            endAt: yesterday.add(const Duration(hours: 9)),
            state: MeetingState.closed,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: today.add(const Duration(hours: 7)),
            endAt: today.add(const Duration(hours: 9)),
            state: MeetingState.upcoming,
          ),
          Meeting(
            id: 'm3',
            number: 3,
            startAt: tomorrow.add(const Duration(hours: 7)),
            endAt: tomorrow.add(const Duration(hours: 9)),
            state: MeetingState.upcoming,
          ),
        ],
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: yesterday.add(const Duration(hours: 8)),
              note: 'Da xac nhan the sinh vien',
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: yesterday.add(const Duration(hours: 9)),
            ),
            'SE180003': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: yesterday.add(const Duration(hours: 7, minutes: 35)),
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'ev1',
            meetingId: 'm1',
            rollNumber: 'SE180001',
            action: 'override',
            oldValue: 'absent',
            newValue: 'present',
            reason: 'Da xac nhan the sinh vien',
            createdAt: yesterday.add(const Duration(hours: 9, minutes: 10)),
          ),
        ],
      ),
    ],
  );
}

void main() {
  late Directory tempDir;
  late AttendanceController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('class_detail_matrix_');
    controller = AttendanceController(documentsDirectory: tempDir);
    await controller.initialize();
    controller.workspace = _detailWorkspace();
    await controller.save();
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Widget wrap(Widget child) => MaterialApp(
    theme: buildAppTheme(),
    home: child,
  );

  group('ClassDetailPage summary metrics, slot switching & status actions', () {
    testWidgets('renders roster table columns, summary counters, and switches meeting slots', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1360, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          ClassDetailPage(
            controller: controller,
            classId: 'c1',
            initialMeetingId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SWD392 · SE1801'), findsOneWidget);
      expect(find.text('Sinh viên'), findsOneWidget);
      expect(find.text('Có mặt'), findsOneWidget);
      expect(find.text('Vắng'), findsOneWidget);
      expect(find.text('Tiến độ'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('Xuất báo cáo'), findsOneWidget);

      expect(find.text('Nguyen Van An'), findsOneWidget);
      expect(find.text('Tran Thi Binh'), findsOneWidget);
      expect(find.text('Le Hoang Cuong'), findsOneWidget);

      // Switch slot dropdown to today upcoming slot (m2) -> shows 'Điểm danh'
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Slot 2').last);
      await tester.pumpAndSettle();
      expect(find.text('Điểm danh'), findsOneWidget);

      // Switch slot dropdown to future slot (m3) -> shows disabled 'Chưa đến ngày'
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Slot 3').last);
      await tester.pumpAndSettle();
      expect(find.text('Chưa đến ngày'), findsOneWidget);
    });

    testWidgets('opens note history modal, transitions to Sửa tiếp dialog, validates reason, and overrides status', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1360, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          ClassDetailPage(
            controller: controller,
            classId: 'c1',
            initialMeetingId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the sticky note badge cell for SE180001 in slot m1
      await tester.tap(find.byIcon(Icons.sticky_note_2_outlined).first);
      await tester.pumpAndSettle();

      expect(find.text('Ghi chú chỉnh sửa điểm danh'), findsOneWidget);
      expect(find.text('Da xac nhan the sinh vien'), findsWidgets);
      expect(find.text('Sửa tiếp'), findsOneWidget);

      await tester.tap(find.text('Sửa tiếp'));
      await tester.pumpAndSettle();

      expect(find.text('SE180001 · Nguyen Van An'), findsOneWidget);
      expect(find.text('Lý do chỉnh sửa'), findsOneWidget);

      // Empty reason keeps dialog open
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.text('SE180001 · Nguyen Van An'), findsOneWidget);

      // Enter non-empty reason and submit status change to Absent
      await tester.enterText(
        find.widgetWithText(TextField, 'Lý do chỉnh sửa'),
        'Ve som khong xin phep',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Lưu'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(
        controller.classById('c1').recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.absent,
      );
      expect(
        controller.classById('c1').recordFor('m1', 'SE180001')?.note,
        'Ve som khong xin phep',
      );
    });

    testWidgets('edits unmarked/absent cell directly and triggers CSV/PDF report exports on closed meeting', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1360, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          ClassDetailPage(
            controller: controller,
            classId: 'c1',
            initialMeetingId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'A' badge on row SE180002 to open edit dialog (index 0 is header 'A')
      await tester.tap(find.text('A').last);
      await tester.pumpAndSettle();

      expect(find.text('SE180002 · Tran Thi Binh'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Lý do chỉnh sửa'),
        'Bo sung minh chung co mat',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Lưu'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(
        controller.classById('c1').recordFor('m1', 'SE180002')?.status,
        AttendanceStatus.present,
      );

      // Export CSV via PopupMenuButton
      await tester.tap(find.text('Xuất báo cáo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xuất CSV'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 25 && controller.lastMessage == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pump();

      expect(controller.lastMessage, startsWith('Đã xuất '));
      expect(find.textContaining('Đã xuất '), findsOneWidget);
    });

    testWidgets('closes an active overdue meeting via Chốt danh sách? confirmation dialog', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await controller.startMeeting('c1', 'm2');
      });

      await tester.binding.setSurfaceSize(const Size(1360, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          ClassDetailPage(
            controller: controller,
            classId: 'c1',
            initialMeetingId: 'm2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chốt danh sách'), findsOneWidget);
      await tester.tap(find.text('Chốt danh sách'));
      await tester.pumpAndSettle();

      expect(find.text('Chốt danh sách?'), findsOneWidget);
      expect(
        find.text('Tất cả sinh viên chưa có P sẽ được đánh dấu A.'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Chốt'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(controller.meetingById('c1', 'm2').state, MeetingState.closed);
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('opens Chọn chế độ QR dialog when starting today upcoming slot', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1360, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          ClassDetailPage(
            controller: controller,
            classId: 'c1',
            initialMeetingId: 'm2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Điểm danh'));
      await tester.pumpAndSettle();

      expect(find.text('Chọn chế độ QR'), findsOneWidget);
      expect(find.text('QR thường'), findsOneWidget);
      expect(find.text('QR + mã bí mật'), findsOneWidget);

      // Dismiss without leaving running server page
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Chọn chế độ QR'), findsNothing);
    });

    testWidgets('opens schedule settings dialog via Cấu hình lịch action button', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1360, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          ClassDetailPage(
            controller: controller,
            classId: 'c1',
            initialMeetingId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cấu hình lịch'));
      await tester.pumpAndSettle();

      expect(find.text('Lưu và sinh lại lịch'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      expect(find.text('Lưu và sinh lại lịch'), findsNothing);
    });
  });
}
