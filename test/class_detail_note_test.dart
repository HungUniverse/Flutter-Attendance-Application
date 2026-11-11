import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/ui/desktop/class_detail_page.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'past corrected attendance shows its note and can be edited again',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final past = DateTime.now().subtract(const Duration(days: 2));
      final start = DateTime(past.year, past.month, past.day, 7);
      final meeting = Meeting(
        id: 'meeting-1',
        number: 1,
        startAt: start,
        endAt: start.add(const Duration(hours: 2, minutes: 15)),
        state: MeetingState.closed,
      );
      const student = Student(
        rollNumber: 'SE000001',
        email: 'student@example.com',
        fullName: 'Nguyễn Văn A',
      );
      final course = CourseClass(
        id: 'class-1',
        courseCode: 'PRM393',
        classCode: 'SE1917',
        scheduleCode: '11',
        students: const [student],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
        meetings: [meeting],
        attendance: {
          meeting.id: {
            student.rollNumber: AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: start.add(const Duration(hours: 3)),
              note: 'Máy quét QR bị lỗi',
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'audit-1',
            createdAt: start.add(const Duration(hours: 3)),
            action: 'attendance_override',
            reason: 'Máy quét QR bị lỗi',
            rollNumber: student.rollNumber,
            meetingId: meeting.id,
            oldValue: 'A',
            newValue: 'P',
          ),
        ],
      );
      final controller = AttendanceController()
        ..workspace = TeacherWorkspace(
          id: 'workspace-1',
          semester: 'FA26',
          semesterStart: start,
          classes: [course],
        );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ClassDetailPage(controller: controller, classId: course.id),
        ),
      );
      await tester.pumpAndSettle();

      final noteIcon = find.byIcon(Icons.sticky_note_2_outlined);
      expect(noteIcon, findsOneWidget);
      await tester.tap(noteIcon);
    await tester.pumpAndSettle();
    expect(find.text('Ghi chú chỉnh sửa điểm danh'), findsOneWidget);
    expect(find.text('Máy quét QR bị lỗi'), findsNWidgets(2));
    expect(find.text('Sửa tiếp'), findsOneWidget);

      await tester.tap(find.text('Sửa tiếp'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Đã đối soát lại');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(
        controller
            .classById(course.id)
            .recordFor(meeting.id, student.rollNumber)
            ?.note,
        'Đã đối soát lại',
      );
      expect(noteIcon, findsOneWidget);
      await tester.tap(noteIcon);
      await tester.pumpAndSettle();
      expect(find.text('Đã đối soát lại'), findsNWidgets(2));
      expect(find.text('Máy quét QR bị lỗi'), findsOneWidget);
    },
  );
}
