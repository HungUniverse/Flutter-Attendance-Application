import 'package:fap_attendance/domain/attendance_reconciliation_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AttendanceReconciliationService service;
  late DateTime t1;
  late DateTime t2;

  setUp(() {
    service = const AttendanceReconciliationService();
    t1 = DateTime(2026, 9, 7, 8, 0);
    t2 = DateTime(2026, 9, 7, 8, 15);
  });

  CourseClass buildClass({
    List<Student>? students,
    List<Meeting>? meetings,
    Map<String, Map<String, AttendanceRecord>>? attendance,
    List<AuditEvent>? auditEvents,
  }) {
    return CourseClass(
      id: 'cls-rec',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      scheduleCode: '11',
      students: students ??
          const [
            Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'S1'),
            Student(rollNumber: 'SE180002', email: 's2@fpt.edu.vn', fullName: 'S2'),
          ],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: meetings ??
          [
            Meeting(
              id: 'm1',
              number: 1,
              startAt: DateTime(2026, 9, 7, 7, 30),
              endAt: DateTime(2026, 9, 7, 9, 15),
              state: MeetingState.upcoming,
            ),
          ],
      attendance: attendance ?? const {},
      auditEvents: auditEvents ?? const [],
    );
  }

  group('diffClasses', () {
    test('detects added students, removed students, and cell diffs with conflicts', () {
      final base = buildClass(
        students: const [
          Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'S1'),
          Student(rollNumber: 'SE180002', email: 's2@fpt.edu.vn', fullName: 'S2'),
        ],
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t1,
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.manual,
              recordedAt: t1,
              note: 'Teacher marked',
            ),
          },
        },
      );

      final incoming = buildClass(
        students: const [
          Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'S1'),
          Student(rollNumber: 'SE180003', email: 's3@fpt.edu.vn', fullName: 'S3'),
        ],
        attendance: {
          'm1': {
            'se180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t2,
            ),
            'SE180003': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t2,
            ),
          },
        },
      );

      final diff = service.diffClasses(base, incoming);
      expect(diff.hasChanges, isTrue);
      expect(diff.addedStudents.map((s) => s.rollNumber), ['SE180003']);
      expect(diff.removedStudents.map((s) => s.rollNumber), ['SE180002']);
      expect(diff.conflictCount, 1);

      final json = diff.toJson();
      expect(json['classId'], 'cls-rec');
      expect(json['hasChanges'], isTrue);
      expect(json['conflictCount'], 1);
      expect((json['cellDiffs'] as List), hasLength(3));
    });

    test('reports hasChanges false when classes are identical', () {
      final base = buildClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t1,
            ),
          },
        },
      );
      final diff = service.diffClasses(base, base);
      expect(diff.hasChanges, isFalse);
      expect(diff.conflictCount, 0);
      expect(diff.cellDiffs, isEmpty);
    });
  });

  group('reconcile', () {
    test('fills unmarked records, upgrades meeting states monotonically, and merges new students', () {
      final base = buildClass(
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 9, 7, 7, 30),
            endAt: DateTime(2026, 9, 7, 9, 15),
            state: MeetingState.upcoming,
          ),
        ],
      );
      final incoming = buildClass(
        students: const [
          Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'S1'),
          Student(rollNumber: 'SE180002', email: 's2@fpt.edu.vn', fullName: 'S2'),
          Student(rollNumber: 'SE180003', email: 's3@fpt.edu.vn', fullName: 'S3'),
        ],
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 9, 7, 7, 30),
            endAt: DateTime(2026, 9, 7, 9, 15),
            state: MeetingState.closed,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: DateTime(2026, 9, 10, 7, 30),
            endAt: DateTime(2026, 9, 10, 9, 15),
            state: MeetingState.active,
          ),
        ],
        attendance: {
          'm1': {
            'SE180003': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t1,
            ),
          },
        },
      );

      final outcome = service.reconcile(base: base, incoming: incoming, now: t2);
      expect(outcome.appliedChanges, 1);
      expect(outcome.resolvedConflicts, 0);
      expect(outcome.mergedClass.students, hasLength(3));
      expect(outcome.mergedClass.meetings, hasLength(2));
      expect(outcome.mergedClass.meetings[0].state, MeetingState.closed);
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180003')?.status,
        AttendanceStatus.present,
      );
    });

    test('applies all ConflictResolutionStrategy modes correctly', () {
      final baseManualAbsent = buildClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.manual,
              recordedAt: t1,
              note: 'Teacher note',
            ),
          },
        },
      );
      final incomingScanPresent = buildClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t2,
            ),
          },
        },
      );

      // preferTeacherManual keeps manual absent over scan present
      final manualOutcome = service.reconcile(
        base: baseManualAbsent,
        incoming: incomingScanPresent,
        strategy: ConflictResolutionStrategy.preferTeacherManual,
        now: t2,
      );
      expect(
        manualOutcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.absent,
      );
      expect(manualOutcome.resolvedConflicts, 1);
      expect(manualOutcome.appliedChanges, 0);

      // preferPresent picks incoming present
      final presentOutcome = service.reconcile(
        base: baseManualAbsent,
        incoming: incomingScanPresent,
        strategy: ConflictResolutionStrategy.preferPresent,
        now: t2,
      );
      expect(
        presentOutcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      expect(presentOutcome.appliedChanges, 1);
      expect(presentOutcome.mergedClass.auditEvents.last.action, 'reconcile_conflict');

      // preferBase keeps base
      final baseOutcome = service.reconcile(
        base: baseManualAbsent,
        incoming: incomingScanPresent,
        strategy: ConflictResolutionStrategy.preferBase,
        now: t2,
      );
      expect(
        baseOutcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.absent,
      );

      // preferIncoming overwrites with incoming
      final incomingOutcome = service.reconcile(
        base: baseManualAbsent,
        incoming: incomingScanPresent,
        strategy: ConflictResolutionStrategy.preferIncoming,
        now: t2,
      );
      expect(
        incomingOutcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
    });

    test('preferTeacherManual prefers incoming manual over base scan and breaks ties by timestamp', () {
      final baseScan = buildClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t1,
            ),
          },
        },
      );
      final incomingManual = buildClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.manual,
              recordedAt: t1,
              note: 'Not in room',
            ),
          },
        },
      );

      final outcome = service.reconcile(
        base: baseScan,
        incoming: incomingManual,
        strategy: ConflictResolutionStrategy.preferTeacherManual,
        now: t2,
      );
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.absent,
      );
      expect(outcome.mergedClass.auditEvents.last.reason, 'Not in room');
    });

    test('updates note when status matches and incoming carries new note', () {
      final base = buildClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t1,
            ),
          },
        },
      );
      final incoming = buildClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: t2,
              note: 'Verified ID card',
            ),
          },
        },
      );
      final outcome = service.reconcile(base: base, incoming: incoming, now: t2);
      expect(outcome.appliedChanges, 1);
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180001')?.note,
        'Verified ID card',
      );
    });
  });
}
