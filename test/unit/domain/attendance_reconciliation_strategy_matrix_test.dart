import 'package:fap_attendance/domain/attendance_reconciliation_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = AttendanceReconciliationService();
  final t0 = DateTime(2026, 9, 10, 8, 0);

  Student student(String roll, {String? name}) => Student(
    rollNumber: roll,
    email: '${roll.toLowerCase()}@fpt.edu.vn',
    fullName: name ?? 'Student $roll',
  );

  Meeting meeting(
    String id,
    int number, {
    MeetingState state = MeetingState.upcoming,
    int dayOffset = 0,
  }) {
    final start = DateTime(2026, 9, 7 + dayOffset, 7, 30);
    return Meeting(
      id: id,
      number: number,
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      state: state,
    );
  }

  AttendanceRecord record(
    AttendanceStatus status, {
    AttendanceSource source = AttendanceSource.scan,
    DateTime? at,
    String? note,
  }) => AttendanceRecord(
    status: status,
    source: source,
    recordedAt: at ?? t0,
    note: note,
  );

  CourseClass buildClass({
    required List<Student> students,
    required List<Meeting> meetings,
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
    List<AuditEvent> auditEvents = const [],
  }) => CourseClass(
    id: 'cls-reconcile',
    courseCode: 'SWD392',
    classCode: 'SE1802',
    scheduleCode: '12',
    students: students,
    scheduleRule: ScheduleRule(
      scheduleCode: '12',
      semesterStart: DateTime(2026, 9, 7),
    ),
    meetings: meetings,
    attendance: attendance,
    auditEvents: auditEvents,
  );

  group('AttendanceReconciliationService diffClasses', () {
    test('reports empty diff for case-insensitive identical rosters and records', () {
      final base = buildClass(
        students: [student('SE180001'), student('SE180002')],
        meetings: [meeting('m1', 1, state: MeetingState.closed)],
        attendance: {
          'm1': {
            'SE180001': record(AttendanceStatus.present, note: 'On time'),
            'SE180002': record(AttendanceStatus.absent),
          },
        },
      );
      final incoming = buildClass(
        students: [student('se180001 '), student('SE180002')],
        meetings: [meeting('m1', 1, state: MeetingState.closed)],
        attendance: {
          'm1': {
            'se180001': record(AttendanceStatus.present, note: 'On time'),
            'se180002 ': record(AttendanceStatus.absent),
          },
        },
      );

      final diff = service.diffClasses(base, incoming);

      expect(diff.hasChanges, isFalse);
      expect(diff.addedStudents, isEmpty);
      expect(diff.removedStudents, isEmpty);
      expect(diff.cellDiffs, isEmpty);
      expect(diff.conflictCount, 0);
      expect(diff.toJson()['hasChanges'], isFalse);
    });

    test('identifies added/removed students, unmarked fills, note edits, and conflicts', () {
      final base = buildClass(
        students: [student('SE180001'), student('SE180002')],
        meetings: [meeting('m1', 1), meeting('m2', 2)],
        attendance: {
          'm1': {
            'SE180001': record(AttendanceStatus.present, note: 'Old note'),
            'SE180002': record(AttendanceStatus.present),
          },
        },
      );
      final incoming = buildClass(
        students: [student('SE180002'), student('SE180003')],
        meetings: [meeting('m1', 1), meeting('m2', 2)],
        attendance: {
          'm1': {
            'SE180001': record(AttendanceStatus.present, note: 'Updated note'),
            'SE180002': record(AttendanceStatus.absent),
          },
          'm2': {
            'SE180003': record(AttendanceStatus.present),
          },
        },
      );

      final diff = service.diffClasses(base, incoming);

      expect(diff.hasChanges, isTrue);
      expect(diff.addedStudents.map((s) => s.rollNumber), ['SE180003']);
      expect(diff.removedStudents.map((s) => s.rollNumber), ['SE180001']);
      expect(diff.conflictCount, 1);
      expect(diff.cellDiffs, hasLength(3));

      final noteDiff = diff.cellDiffs.firstWhere(
        (d) => d.meetingId == 'm1' && d.rollNumber == 'SE180001',
      );
      expect(noteDiff.isConflict, isFalse);
      expect(noteDiff.oldNote, 'Old note');
      expect(noteDiff.newNote, 'Updated note');

      final conflictDiff = diff.cellDiffs.firstWhere(
        (d) => d.meetingId == 'm1' && d.rollNumber == 'SE180002',
      );
      expect(conflictDiff.isConflict, isTrue);
      expect(conflictDiff.oldStatus, AttendanceStatus.present);
      expect(conflictDiff.newStatus, AttendanceStatus.absent);

      final newCellDiff = diff.cellDiffs.firstWhere(
        (d) => d.meetingId == 'm2' && d.rollNumber == 'SE180003',
      );
      expect(newCellDiff.isConflict, isFalse);
      expect(newCellDiff.oldStatus, AttendanceStatus.unmarked);
      expect(newCellDiff.newStatus, AttendanceStatus.present);
      expect(newCellDiff.toJson()['oldStatus'], '');
      expect(newCellDiff.toJson()['newStatus'], 'P');
    });
  });

  group('AttendanceReconciliationService conflict resolution strategies', () {
    CourseClass makeBaseConflictClass({
      required AttendanceRecord s1Rec,
      required AttendanceRecord s2Rec,
    }) => buildClass(
      students: [student('SE180001'), student('SE180002')],
      meetings: [
        meeting('m2', 2, state: MeetingState.upcoming, dayOffset: 3),
        meeting('m1', 1, state: MeetingState.active, dayOffset: 0),
      ],
      attendance: {
        'm1': {
          'se180001': s1Rec,
          'SE180002': s2Rec,
        },
      },
    );

    CourseClass makeIncomingConflictClass({
      required AttendanceRecord s1Rec,
      required AttendanceRecord s2Rec,
    }) => buildClass(
      students: [
        student('SE180001'),
        student('SE180002'),
        student('SE180003'),
      ],
      meetings: [
        meeting('m1', 1, state: MeetingState.closed, dayOffset: 0),
        meeting('m3', 3, state: MeetingState.upcoming, dayOffset: 6),
      ],
      attendance: {
        'm1': {
          'SE180001': s1Rec,
          'SE180002': s2Rec,
        },
        'm3': {
          'SE180003': record(AttendanceStatus.present),
        },
      },
    );

    test('preferBase retains base records during conflicts but accepts non-conflicting fills & added students', () {
      final base = makeBaseConflictClass(
        s1Rec: record(AttendanceStatus.absent, source: AttendanceSource.scan),
        s2Rec: record(AttendanceStatus.present, source: AttendanceSource.scan),
      );
      final incoming = makeIncomingConflictClass(
        s1Rec: record(AttendanceStatus.present, source: AttendanceSource.manual),
        s2Rec: record(AttendanceStatus.absent, source: AttendanceSource.manual),
      );

      final outcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferBase,
        now: t0,
      );

      expect(outcome.resolvedConflicts, 2);
      // m3/SE180003 fill = 1 applied change.
      expect(outcome.appliedChanges, 1);
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.absent,
      );
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180002')?.status,
        AttendanceStatus.present,
      );
      expect(
        outcome.mergedClass.recordFor('m3', 'SE180003')?.status,
        AttendanceStatus.present,
      );
      expect(outcome.mergedClass.auditEvents, isEmpty);
      expect(outcome.mergedClass.students, hasLength(3));
      expect(
        outcome.mergedClass.meetings.map((m) => m.id).toList(),
        ['m1', 'm2', 'm3'],
      );
      expect(
        outcome.mergedClass.meetings.firstWhere((m) => m.id == 'm1').state,
        MeetingState.closed,
      );
    });

    test('preferIncoming overwrites all conflicts and appends reconcile_conflict audit events', () {
      final base = makeBaseConflictClass(
        s1Rec: record(AttendanceStatus.absent, source: AttendanceSource.manual),
        s2Rec: record(AttendanceStatus.present, source: AttendanceSource.manual),
      );
      final incoming = makeIncomingConflictClass(
        s1Rec: record(
          AttendanceStatus.present,
          source: AttendanceSource.scan,
          note: 'Late check-in verified',
        ),
        s2Rec: record(AttendanceStatus.absent, source: AttendanceSource.scan),
      );

      final outcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferIncoming,
        now: t0,
      );

      expect(outcome.resolvedConflicts, 2);
      expect(outcome.appliedChanges, 3);
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180002')?.status,
        AttendanceStatus.absent,
      );
      expect(outcome.mergedClass.auditEvents, hasLength(2));
      expect(
        outcome.mergedClass.auditEvents.map((e) => e.action),
        everyElement('reconcile_conflict'),
      );
      expect(
        outcome.mergedClass.auditEvents.first.reason,
        'Late check-in verified',
      );
      expect(
        outcome.mergedClass.auditEvents.last.reason,
        contains('preferIncoming'),
      );
    });

    test('preferPresent promotes absent -> present without demoting present -> absent', () {
      final base = makeBaseConflictClass(
        s1Rec: record(AttendanceStatus.absent),
        s2Rec: record(AttendanceStatus.present),
      );
      final incoming = makeIncomingConflictClass(
        s1Rec: record(AttendanceStatus.present),
        s2Rec: record(AttendanceStatus.absent),
      );

      final outcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferPresent,
        now: t0,
      );

      expect(outcome.resolvedConflicts, 2);
      expect(outcome.appliedChanges, 2);
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180002')?.status,
        AttendanceStatus.present,
      );
      expect(outcome.mergedClass.auditEvents, hasLength(1));
      expect(outcome.mergedClass.auditEvents.single.oldValue, 'A');
      expect(outcome.mergedClass.auditEvents.single.newValue, 'P');
    });

    test('preferTeacherManual prioritizes manual/annotated records, breaking ties by latest recordedAt', () {
      final earlier = t0;
      final later = t0.add(const Duration(minutes: 15));

      final base = buildClass(
        students: [
          student('SE180001'),
          student('SE180002'),
          student('SE180003'),
        ],
        meetings: [meeting('m1', 1, state: MeetingState.closed)],
        attendance: {
          'm1': {
            // SE180001: base is scan (later), incoming is manual -> incoming wins
            'SE180001': record(
              AttendanceStatus.absent,
              source: AttendanceSource.scan,
              at: later,
            ),
            // SE180002: base has non-empty note -> treated as manual vs incoming scan
            'SE180002': record(
              AttendanceStatus.present,
              source: AttendanceSource.scan,
              note: 'Teacher annotated',
              at: earlier,
            ),
            // SE180003: both manual -> newer timestamp (incoming) wins
            'SE180003': record(
              AttendanceStatus.absent,
              source: AttendanceSource.manual,
              at: earlier,
            ),
          },
        },
      );
      final incoming = buildClass(
        students: [
          student('SE180001'),
          student('SE180002'),
          student('SE180003'),
        ],
        meetings: [meeting('m1', 1, state: MeetingState.upcoming)],
        attendance: {
          'm1': {
            'SE180001': record(
              AttendanceStatus.present,
              source: AttendanceSource.manual,
              at: earlier,
            ),
            'SE180002': record(
              AttendanceStatus.absent,
              source: AttendanceSource.scan,
              at: later,
            ),
            'SE180003': record(
              AttendanceStatus.present,
              source: AttendanceSource.manual,
              at: later,
            ),
          },
        },
      );

      final outcome = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferTeacherManual,
        now: later,
      );

      expect(outcome.resolvedConflicts, 3);
      expect(outcome.appliedChanges, 2);
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180002')?.status,
        AttendanceStatus.present,
      );
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180003')?.status,
        AttendanceStatus.present,
      );
      // Meeting state never downgrades from closed -> upcoming.
      expect(outcome.mergedClass.meetings.single.state, MeetingState.closed);
    });

    test('updates non-conflicting note when incoming introduces a non-empty note', () {
      final base = buildClass(
        students: [student('SE180001')],
        meetings: [meeting('m1', 1)],
        attendance: {
          'm1': {'SE180001': record(AttendanceStatus.present)},
        },
      );
      final incoming = buildClass(
        students: [student('SE180001')],
        meetings: [meeting('m1', 1)],
        attendance: {
          'm1': {
            'SE180001': record(
              AttendanceStatus.present,
              note: 'Verified ID card',
            ),
          },
        },
      );

      final outcome = service.reconcile(base: base, incoming: incoming, now: t0);
      expect(outcome.resolvedConflicts, 0);
      expect(outcome.appliedChanges, 1);
      expect(
        outcome.mergedClass.recordFor('m1', 'SE180001')?.note,
        'Verified ID card',
      );
      expect(outcome.mergedClass.auditEvents, isEmpty);
    });

    test('is idempotent when reconciling merged output with same incoming using preferIncoming', () {
      final base = buildClass(
        students: [student('SE180001')],
        meetings: [meeting('m1', 1)],
        attendance: {
          'm1': {'SE180001': record(AttendanceStatus.absent)},
        },
      );
      final incoming = buildClass(
        students: [student('SE180001')],
        meetings: [meeting('m1', 1, state: MeetingState.closed)],
        attendance: {
          'm1': {'SE180001': record(AttendanceStatus.present)},
        },
      );

      final first = service.reconcile(
        base: base,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferIncoming,
        now: t0,
      );
      final second = service.reconcile(
        base: first.mergedClass,
        incoming: incoming,
        strategy: ConflictResolutionStrategy.preferIncoming,
        now: t0,
      );

      expect(second.diff.hasChanges, isFalse);
      expect(second.appliedChanges, 0);
      expect(second.resolvedConflicts, 0);
      expect(second.mergedClass.auditEvents, hasLength(1));
    });
  });
}
