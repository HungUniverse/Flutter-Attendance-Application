import 'package:flutter_test/flutter_test.dart';

import 'package:fap_attendance/domain/attendance_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/roster_merge_service.dart';
import 'package:fap_attendance/domain/schedule_service.dart';

void main() {
  group('RosterMergeService - Edge Cases & Data Preservation', () {
    final mergeService = RosterMergeService();
    final now = DateTime(2026, 11, 13, 10, 0);

    test('should preserve past attendance when student roll number is renamed by email match', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final existingClass = CourseClass(
        id: 'c1',
        courseCode: 'PRM393',
        classCode: 'SE1901',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'OLD_ROLL_01',
            email: 'duongthanhduy@fpt.edu.vn',
            fullName: 'Dương Thành Thanh Duy',
          ),
        ],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: start,
            endAt: start.add(const Duration(hours: 2)),
            state: MeetingState.closed,
          ),
        ],
        attendance: {
          'm1': {
            'OLD_ROLL_01': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: start,
            ),
          },
        },
      );

      final incomingClass = existingClass.copyWith(
        students: const [
          Student(
            rollNumber: 'SE194673', // Renamed rollNumber, same email
            email: 'duongthanhduy@fpt.edu.vn',
            fullName: 'Dương Thành Thanh Duy',
          ),
        ],
        attendance: const {},
      );

      // Act
      final result = mergeService.merge(
        existing: [existingClass],
        imported: [incomingClass],
        now: now,
      );

      // Assert
      expect(result.updatedClasses, equals(1));
      expect(result.addedClasses, equals(0));
      final merged = result.classes.single;
      expect(merged.students.single.rollNumber, equals('SE194673'));
      expect(
        merged.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
        reason: 'Renamed roll number must retain previous attendance record',
      );
      expect(merged.recordFor('m1', 'OLD_ROLL_01'), isNull);
    });

    test('should backfill closed meetings as absent with explanatory note for newly added students', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final existingClass = CourseClass(
        id: 'c1',
        courseCode: 'PRM393',
        classCode: 'SE1901',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE194673',
            email: 'duongthanhduy@fpt.edu.vn',
            fullName: 'Dương Thành Thanh Duy',
          ),
        ],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: start,
            endAt: start.add(const Duration(hours: 2)),
            state: MeetingState.closed,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: start.add(const Duration(days: 3)),
            endAt: start.add(const Duration(days: 3, hours: 2)),
            state: MeetingState.upcoming,
          ),
        ],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: start,
            ),
          },
        },
      );

      final incomingClass = existingClass.copyWith(
        students: const [
          Student(
            rollNumber: 'SE194673',
            email: 'duongthanhduy@fpt.edu.vn',
            fullName: 'Dương Thành Thanh Duy',
          ),
          Student(
            rollNumber: 'SE199999',
            email: 'newstudent@fpt.edu.vn',
            fullName: 'Sinh Viên Chuyển Lớp',
          ),
        ],
        attendance: const {},
      );

      // Act
      final result = mergeService.merge(
        existing: [existingClass],
        imported: [incomingClass],
        now: now,
      );

      // Assert
      expect(result.addedStudents, equals(1));
      final merged = result.classes.single;
      final backfilled = merged.recordFor('m1', 'SE199999');
      expect(backfilled, isNotNull);
      expect(backfilled!.status, equals(AttendanceStatus.absent));
      expect(backfilled.source, equals(AttendanceSource.finalize));
      expect(backfilled.note, contains('Tự động bổ sung'));
      expect(
        merged.recordFor('m2', 'SE199999'),
        isNull,
        reason: 'Upcoming meeting must not be backfilled',
      );
    });

    test('should retain existing classes and students not present in partial import', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final classA = CourseClass(
        id: 'cA',
        courseCode: 'PRM393',
        classCode: 'SE1901',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'S1',
            email: 's1@fpt.edu.vn',
            fullName: 'Sinh Viên 1',
          ),
          Student(
            rollNumber: 'S2',
            email: 's2@fpt.edu.vn',
            fullName: 'Sinh Viên 2',
          ),
        ],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
        meetings: const [],
      );
      final classB = CourseClass(
        id: 'cB',
        courseCode: 'SWP391',
        classCode: 'SE1902',
        scheduleCode: '22',
        students: const [
          Student(
            rollNumber: 'S3',
            email: 's3@fpt.edu.vn',
            fullName: 'Sinh Viên 3',
          ),
        ],
        scheduleRule: ScheduleRule(scheduleCode: '22', semesterStart: start),
        meetings: const [],
      );

      final incomingA = classA.copyWith(
        students: const [
          Student(
            rollNumber: 'S1',
            email: 's1@fpt.edu.vn',
            fullName: 'Sinh Viên 1',
          ),
        ],
      );

      // Act
      final result = mergeService.merge(
        existing: [classA, classB],
        imported: [incomingA],
        now: now,
      );

      // Assert
      expect(result.classes, hasLength(2));
      expect(result.retainedStudents, equals(1)); // S2 retained in classA
      expect(result.classes.first.students, hasLength(2));
    });
  });

  group('ScheduleService & AttendanceService - Boundary Conditions', () {
    final scheduleService = ScheduleService();
    final attendanceService = AttendanceService();

    test('should detect currentMeeting at exact startAt and endAt boundary timestamps', () {
      // Arrange
      final startAt = DateTime(2026, 11, 13, 7, 0);
      final endAt = DateTime(2026, 11, 13, 9, 15);
      final course = CourseClass(
        id: 'c1',
        courseCode: 'PRM393',
        classCode: 'SE1901',
        scheduleCode: '11',
        students: const [],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: startAt),
        meetings: [
          Meeting(id: 'm1', number: 1, startAt: startAt, endAt: endAt),
        ],
      );

      // Act & Assert
      expect(scheduleService.currentMeeting(course, startAt)?.id, equals('m1'));
      expect(scheduleService.currentMeeting(course, endAt)?.id, equals('m1'));
      expect(
        scheduleService.currentMeeting(
          course,
          startAt.subtract(const Duration(seconds: 1)),
        ),
        isNull,
      );
      expect(
        scheduleService.currentMeeting(
          course,
          endAt.add(const Duration(seconds: 1)),
        ),
        isNull,
      );
    });

    test('should reject invalid week count, invalid meetingsPerWeek, and mismatched weekday group', () {
      // Arrange
      final start = DateTime(2026, 11, 2);

      // Act & Assert
      expect(
        () => scheduleService.generate(
          ScheduleRule(scheduleCode: '11', semesterStart: start, weeks: 0),
          'c1',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => scheduleService.generate(
          ScheduleRule(scheduleCode: '11', semesterStart: start, weeks: 53),
          'c1',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => scheduleService.generate(
          ScheduleRule(
            scheduleCode: '11', // Group 1 is Mon/Thu
            semesterStart: start,
            meetingsPerWeek: 1,
            weekdays: const [DateTime.friday], // Mismatched weekday
          ),
          'c1',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should calculate absenceRate accurately and prevent duplicate manual mark without override reason', () {
      // Arrange
      final today = DateTime(2026, 11, 13, 8, 0);
      const student = Student(
        rollNumber: 'SE194673',
        email: 'duongthanhduy@fpt.edu.vn',
        fullName: 'Dương Thành Thanh Duy',
      );
      var course = CourseClass(
        id: 'c1',
        courseCode: 'PRM393',
        classCode: 'SE1901',
        scheduleCode: '11',
        students: const [student],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: today),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: today,
            endAt: today.add(const Duration(hours: 2)),
            state: MeetingState.active,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: today.add(const Duration(days: 3)),
            endAt: today.add(const Duration(days: 3, hours: 2)),
            state: MeetingState.upcoming,
          ),
        ],
      );

      // Act: Mark absent manually
      course = attendanceService.markManual(
        course,
        meetingId: 'm1',
        rollNumber: 'SE194673',
        status: AttendanceStatus.absent,
        now: today,
      );

      // Assert: 1 absent out of 2 meetings = 0.5
      expect(attendanceService.absenceRate(course, 'SE194673'), closeTo(0.5, 1e-6));

      // Attempting a second markManual on the same student & meeting throws StateError
      expect(
        () => attendanceService.markManual(
          course,
          meetingId: 'm1',
          rollNumber: 'SE194673',
          status: AttendanceStatus.present,
          now: today,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
