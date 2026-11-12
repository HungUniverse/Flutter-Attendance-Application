import 'package:attendance_core/attendance_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('attendance_core Package - Models & AttendanceService Hardening', () {
    final service = AttendanceService();
    final now = DateTime(2026, 11, 13, 8, 30);

    CourseClass buildClass({MeetingState state = MeetingState.active}) {
      return CourseClass(
        id: 'c1',
        courseCode: 'PRN232',
        classCode: 'SE1920',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE194673',
            email: 'duytt@fpt.edu.vn',
            fullName: 'Dương Thành Thanh Duy',
            memberCode: 'DuyTT',
          ),
          Student(
            rollNumber: 'SE190001',
            email: 'anv@fpt.edu.vn',
            fullName: 'Nguyễn Văn A',
            memberCode: 'ANV',
          ),
        ],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: now),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: now,
            endAt: now.add(const Duration(hours: 2)),
            state: state,
          ),
        ],
      );
    }

    test('CourseClass.recordFor resolves case-variant and whitespace-padded roll numbers', () {
      final course = buildClass().copyWith(
        attendance: {
          'm1': {
            'se194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: now,
            ),
          },
        },
      );

      expect(
        course.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );
      expect(
        course.recordFor('m1', '  se194673  ')?.status,
        equals(AttendanceStatus.present),
      );
      expect(course.recordFor('m1', 'SE999999'), isNull);
    });

    test('markManual and overrideStatus normalize rollNumber to canonical student rollNumber', () {
      var course = buildClass();

      course = service.markManual(
        course,
        meetingId: 'm1',
        rollNumber: '  se194673 ',
        status: AttendanceStatus.present,
        now: now,
      );

      expect(course.attendance['m1']?.containsKey('SE194673'), isTrue);
      expect(
        course.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );

      course = service.overrideStatus(
        course,
        meetingId: 'm1',
        rollNumber: 'se194673',
        status: AttendanceStatus.absent,
        reason: 'Điểm danh nhầm MSSV',
        auditId: 'aud-1',
        now: now,
      );

      expect(
        course.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.absent),
      );
      expect(course.auditEvents.single.rollNumber, equals('SE194673'));
      expect(course.auditEvents.single.oldValue, equals('P'));
      expect(course.auditEvents.single.newValue, equals('A'));
    });

    test('closeMeeting throws StateError on unknown meetingId and preserves case-variant present records', () {
      final course = buildClass().copyWith(
        attendance: {
          'm1': {
            'se194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: now,
            ),
          },
        },
      );

      expect(
        () => service.closeMeeting(course, 'nonexistent-meeting', now: now),
        throwsStateError,
      );

      final closed = service.closeMeeting(course, 'm1', now: now);
      expect(
        closed.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );
      expect(
        closed.recordFor('m1', 'SE190001')?.status,
        equals(AttendanceStatus.absent),
      );
    });
  });
}
