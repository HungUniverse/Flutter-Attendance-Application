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
      expect(closed.attendance['m1']?.containsKey('se194673'), isFalse);
      expect(closed.attendance['m1']?.containsKey('SE194673'), isTrue);
      expect(
        closed.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );
      expect(
        closed.recordFor('m1', 'SE190001')?.status,
        equals(AttendanceStatus.absent),
      );
    });

    test('markPresent, markManual, and closeMeeting purge stale non-canonical unmarked keys', () {
      final base = buildClass().copyWith(
        attendance: {
          'm1': {
            'se194673': AttendanceRecord(
              status: AttendanceStatus.unmarked,
              source: AttendanceSource.manual,
              recordedAt: now,
            ),
            'se190001': AttendanceRecord(
              status: AttendanceStatus.unmarked,
              source: AttendanceSource.manual,
              recordedAt: now,
            ),
          },
        },
      );

      final afterPresent = service.markPresent(
        base,
        meetingId: 'm1',
        email: 'DUYTT@fpt.edu.vn',
        now: now,
      );
      expect(afterPresent.attendance['m1']?.containsKey('se194673'), isFalse);
      expect(
        afterPresent.recordFor('m1', 'se194673')?.status,
        equals(AttendanceStatus.present),
      );

      final afterManual = service.markManual(
        base,
        meetingId: 'm1',
        rollNumber: 'se194673',
        status: AttendanceStatus.present,
        now: now,
      );
      expect(afterManual.attendance['m1']?.containsKey('se194673'), isFalse);
      expect(
        afterManual.recordFor('m1', 'se194673')?.status,
        equals(AttendanceStatus.present),
      );

      final afterClose = service.closeMeeting(afterManual, 'm1', now: now);
      expect(afterClose.attendance['m1']?.containsKey('se190001'), isFalse);
      expect(
        afterClose.recordFor('m1', 'se190001')?.status,
        equals(AttendanceStatus.absent),
      );
    });

    test('ScheduleRule and ScheduleService tolerate whitespace-padded scheduleCode', () {
      final rule = ScheduleRule(
        scheduleCode: ' 23 ',
        semesterStart: DateTime(2026, 9, 7),
        weeks: 2,
        meetingsPerWeek: 2,
      );
      expect(rule.dayGroup, equals(2));
      expect(rule.dailySlot, equals(3));

      final meetings = ScheduleService().generate(rule, 'c1');
      expect(meetings, hasLength(4));
      expect(meetings.first.startAt.hour, equals(12));
      expect(meetings.first.startAt.minute, equals(30));
    });
  });
}
