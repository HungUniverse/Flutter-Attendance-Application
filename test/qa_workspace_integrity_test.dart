import 'package:flutter_test/flutter_test.dart';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/workspace_integrity_validator.dart';

CourseClass _validCourse() {
  final start = DateTime(2026, 11, 2, 7, 0);
  return CourseClass(
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
      Student(
        rollNumber: 'SE190002',
        email: 'anhntm@fpt.edu.vn',
        fullName: 'Nguyễn Thị Minh Anh',
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
        state: MeetingState.active,
      ),
    ],
    attendance: {
      'm1': {
        'SE194673': AttendanceRecord(
          status: AttendanceStatus.present,
          source: AttendanceSource.manual,
          recordedAt: start,
        ),
        'SE190002': AttendanceRecord(
          status: AttendanceStatus.absent,
          source: AttendanceSource.finalize,
          recordedAt: start,
        ),
      },
    },
    auditEvents: [
      AuditEvent(
        id: 'a1',
        createdAt: start,
        action: 'attendance_override',
        reason: 'Bổ sung giấy phép hợp lệ',
        rollNumber: 'SE194673',
        meetingId: 'm1',
        oldValue: 'A',
        newValue: 'P',
      ),
    ],
  );
}

void main() {
  const validator = WorkspaceIntegrityValidator();

  group('WorkspaceIntegrityValidator - Valid & Clean States', () {
    test('should report zero errors and isValid true for a compliant workspace', () {
      // Arrange
      final workspace = TeacherWorkspace(
        id: 'w1',
        semester: 'FA26',
        semesterStart: DateTime(2026, 11, 2),
        classes: [_validCourse()],
      );

      // Act
      final report = validator.validateWorkspace(workspace);

      // Assert
      expect(report.isValid, isTrue);
      expect(report.errorCount, equals(0));
      expect(report.warningCount, equals(0));
      expect(report.issues, isEmpty);
      expect(report.toJson()['isValid'], isTrue);
    });

    test('should accept whitespace-padded valid scheduleCode consistent with ScheduleRule', () {
      final course = _validCourse().copyWith(scheduleCode: ' 11 ');
      final issues = validator.validateClass(course);
      expect(issues, isEmpty);
    });
  });

  group('WorkspaceIntegrityValidator - Anomaly Detection', () {
    test('should detect duplicate student roll numbers and emails within a class', () {
      // Arrange
      final course = _validCourse().copyWith(
        students: const [
          Student(
            rollNumber: 'SE194673',
            email: 'duy@fpt.edu.vn',
            fullName: 'Sinh Viên 1',
          ),
          Student(
            rollNumber: 'se194673',
            email: 'DUY@FPT.EDU.VN',
            fullName: 'Sinh Viên 2',
          ),
        ],
      );

      // Act
      final issues = validator.validateClass(course);

      // Assert
      expect(issues.map((i) => i.code), contains('DUPLICATE_STUDENT_ROLL'));
      expect(issues.map((i) => i.code), contains('DUPLICATE_STUDENT_EMAIL'));
    });

    test('should flag multiple simultaneous active meetings and invalid time ranges', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 9, 0);
      final course = _validCourse().copyWith(
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: start,
            endAt: start.subtract(const Duration(hours: 1)), // End before start
            state: MeetingState.active,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: start.add(const Duration(days: 1)),
            endAt: start.add(const Duration(days: 1, hours: 2)),
            state: MeetingState.active,
          ),
        ],
      );

      // Act
      final issues = validator.validateClass(course);

      // Assert
      expect(issues.map((i) => i.code), contains('MULTIPLE_ACTIVE_MEETINGS'));
      expect(issues.map((i) => i.code), contains('INVALID_MEETING_TIME_RANGE'));
    });

    test('should detect unmarked students in closed meetings and empty audit reasons', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final course = _validCourse().copyWith(
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: start,
            ),
            // SE190002 is missing in closed meeting m1
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'bad_audit',
            createdAt: start,
            action: 'attendance_override',
            reason: '   ', // Blank reason
          ),
        ],
      );

      // Act
      final issues = validator.validateClass(course);

      // Assert
      expect(issues.map((i) => i.code), contains('CLOSED_MEETING_UNMARKED_STUDENT'));
      expect(issues.map((i) => i.code), contains('AUDIT_EMPTY_REASON'));
    });

    test('should warn on orphaned attendance records for unknown meetings or students', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final base = _validCourse();
      final course = base.copyWith(
        attendance: {
          ...base.attendance,
          'm_ghost': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: start,
            ),
          },
          'm2': {
            'SE_GHOST': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: start,
            ),
          },
        },
      );

      // Act
      final issues = validator.validateClass(course);

      // Assert
      expect(issues.map((i) => i.code), contains('ORPHANED_MEETING_ATTENDANCE'));
      expect(issues.map((i) => i.code), contains('ORPHANED_STUDENT_ATTENDANCE'));
    });

    test('should repair orphaned records and backfill closed meeting gaps automatically', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final broken = _validCourse().copyWith(
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: start,
            ),
            'SE_GHOST': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: start,
            ),
          },
          'm_ghost': {},
        },
      );

      // Act
      final repaired = validator.repairCourseClass(broken, now: start);
      final issuesAfter = validator.validateClass(repaired);

      // Assert
      expect(issuesAfter, isEmpty);
      expect(repaired.attendance.containsKey('m_ghost'), isFalse);
      expect(repaired.attendance['m1']!.containsKey('SE_GHOST'), isFalse);
      expect(
        repaired.recordFor('m1', 'SE190002')?.status,
        equals(AttendanceStatus.absent),
      );
    });

    test('should normalize case-variant attendance keys, demote extra active meetings, and fill blank audit reasons on repair', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final broken = _validCourse().copyWith(
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: start,
            endAt: start.add(const Duration(hours: 2)),
            state: MeetingState.active,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: start.add(const Duration(days: 3)),
            endAt: start.add(const Duration(days: 3, hours: 2)),
            state: MeetingState.active,
          ),
        ],
        attendance: {
          'm1': {
            'se194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: start,
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'a_empty',
            createdAt: start,
            action: 'attendance_override',
            reason: '   ',
          ),
        ],
      );

      // Act
      final repaired = validator.repairCourseClass(broken, now: start);
      final issuesAfter = validator.validateClass(repaired);

      // Assert
      expect(issuesAfter, isEmpty);
      expect(
        repaired.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );
      expect(
        repaired.meetings.where((m) => m.state == MeetingState.active),
        hasLength(1),
      );
      expect(repaired.auditEvents.single.reason.trim(), isNotEmpty);
    });
  });
}
