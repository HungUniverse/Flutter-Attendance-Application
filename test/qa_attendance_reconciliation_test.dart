import 'package:flutter_test/flutter_test.dart';

import 'package:fap_attendance/domain/attendance_reconciliation_service.dart';
import 'package:fap_attendance/domain/models.dart';

CourseClass _sampleClass({
  required List<Student> students,
  required Map<String, Map<String, AttendanceRecord>> attendance,
}) {
  final start = DateTime(2026, 11, 2, 7, 0);
  return CourseClass(
    id: 'c1',
    courseCode: 'PRM393',
    classCode: 'SE1901',
    scheduleCode: '11',
    students: students,
    scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
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
        state: MeetingState.closed,
      ),
    ],
    attendance: attendance,
  );
}

void main() {
  const service = AttendanceReconciliationService();
  final t0 = DateTime(2026, 11, 13, 8, 0);
  final t1 = DateTime(2026, 11, 13, 8, 30);

  const student1 = Student(
    rollNumber: 'SE194673',
    email: 'duongthanhduy@fpt.edu.vn',
    fullName: 'Dương Thành Thanh Duy',
  );
  const student2 = Student(
    rollNumber: 'SE190002',
    email: 'anhntm@fpt.edu.vn',
    fullName: 'Nguyễn Thị Minh Anh',
  );
  const student3 = Student(
    rollNumber: 'SE190003',
    email: 'baolq@fpt.edu.vn',
    fullName: 'Lê Quốc Bảo',
  );

  group('AttendanceReconciliationService - Diffing', () {
    test('should detect added/removed students and non-conflicting vs conflicting cell diffs', () {
      // Arrange
      final base = _sampleClass(
        students: [student1, student2],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t0,
            ),
          },
        },
      );

      final incoming = _sampleClass(
        students: [student1, student3], // student2 removed, student3 added
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: t1,
              note: 'Bổ sung điểm danh có phép',
            ),
            'SE190003': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t1,
            ),
          },
        },
      );

      // Act
      final diff = service.diffClasses(base, incoming);

      // Assert
      expect(diff.hasChanges, isTrue);
      expect(diff.addedStudents.map((s) => s.rollNumber), equals(['SE190003']));
      expect(diff.removedStudents.map((s) => s.rollNumber), equals(['SE190002']));
      expect(diff.conflictCount, equals(1));
      expect(diff.toJson()['conflictCount'], equals(1));
    });
  });

  group('AttendanceReconciliationService - Conflict Resolution Strategies', () {
    test('should preserve manual teacher override over automated finalize record under preferTeacherManual', () {
      // Arrange: Base has manual Present with note, incoming has automated finalize Absent
      final base = _sampleClass(
        students: [student1],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: t0,
              note: 'Giảng viên duyệt có mặt',
            ),
          },
        },
      );
      final incoming = _sampleClass(
        students: [student1],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t1,
            ),
          },
        },
      );

      // Act
      final outcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferTeacherManual,
        now: t1,
      );

      // Assert
      expect(outcome.resolvedConflicts, equals(1));
      expect(outcome.appliedChanges, equals(0));
      expect(
        outcome.mergedClass.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );
      expect(
        outcome.mergedClass.recordFor('m1', 'SE194673')?.note,
        equals('Giảng viên duyệt có mặt'),
      );
    });

    test('should apply incoming manual override over base finalize record and append audit event', () {
      // Arrange: Base has finalize Absent, incoming has manual Present
      final base = _sampleClass(
        students: [student1],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t0,
            ),
          },
        },
      );
      final incoming = _sampleClass(
        students: [student1, student2],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: t1,
              note: 'Đã xác minh đơn xin phép',
            ),
            'SE190002': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t1,
            ),
          },
        },
      );

      // Act
      final outcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferTeacherManual,
        now: t1,
      );

      // Assert
      expect(outcome.resolvedConflicts, equals(1));
      expect(outcome.appliedChanges, equals(2));
      expect(outcome.mergedClass.students, hasLength(2));
      expect(
        outcome.mergedClass.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );
      expect(
        outcome.mergedClass.recordFor('m1', 'SE190002')?.status,
        equals(AttendanceStatus.present),
      );
      expect(outcome.mergedClass.auditEvents, hasLength(1));
      expect(
        outcome.mergedClass.auditEvents.single.reason,
        equals('Đã xác minh đơn xin phép'),
      );
    });

    test('should honor preferPresent and preferBase conflict strategies accurately', () {
      // Arrange
      final base = _sampleClass(
        students: [student1],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.manual,
              recordedAt: t1,
            ),
          },
        },
      );
      final incoming = _sampleClass(
        students: [student1],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
        },
      );

      // Act
      final presentOutcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferPresent,
      );
      final baseOutcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferBase,
      );

      // Assert
      expect(
        presentOutcome.mergedClass.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );
      expect(
        baseOutcome.mergedClass.recordFor('m1', 'SE194673')?.status,
        equals(AttendanceStatus.absent),
      );
    });

    test('should merge incoming meetings and normalize case-variant attendance keys without duplicates', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final base = _sampleClass(
        students: [student1],
        attendance: {
          'm1': {
            'se194673': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t0,
            ),
          },
        },
      );
      final incoming = base.copyWith(
        meetings: [
          ...base.meetings,
          Meeting(
            id: 'm3',
            number: 3,
            startAt: start.add(const Duration(days: 7)),
            endAt: start.add(const Duration(days: 7, hours: 2)),
            state: MeetingState.active,
          ),
        ],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: t1,
              note: 'Bổ sung điểm danh',
            ),
          },
          'm3': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t1,
            ),
          },
        },
      );

      // Act
      final outcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferIncoming,
        now: t1,
      );

      // Assert
      expect(outcome.mergedClass.meetings.map((m) => m.id), contains('m3'));
      expect(outcome.mergedClass.attendance['m1']!.keys.toList(), equals(['SE194673']));
      expect(
        outcome.mergedClass.recordFor('m3', 'SE194673')?.status,
        equals(AttendanceStatus.present),
      );
    });
  });
}
