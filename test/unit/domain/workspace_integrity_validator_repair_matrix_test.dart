import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/workspace_integrity_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = WorkspaceIntegrityValidator();
  final t0 = DateTime(2026, 9, 10, 8, 0);

  Student student(
    String roll, {
    String email = '',
    String fullName = '',
  }) => Student(
    rollNumber: roll,
    email: email,
    fullName: fullName,
  );

  Meeting meeting(
    String id,
    int number, {
    DateTime? startAt,
    DateTime? endAt,
    MeetingState state = MeetingState.upcoming,
  }) {
    final start = startAt ?? DateTime(2026, 9, 7, 7, 30);
    return Meeting(
      id: id,
      number: number,
      startAt: start,
      endAt: endAt ?? start.add(const Duration(hours: 2)),
      state: state,
    );
  }

  CourseClass validClass({String id = 'cls-1'}) => CourseClass(
    id: id,
    courseCode: 'PRM393',
    classCode: 'SE1801',
    scheduleCode: '11',
    students: [
      student('SE180001', email: 'an@fpt.edu.vn', fullName: 'Nguyen Van An'),
      student('SE180002', email: 'binh@fpt.edu.vn', fullName: 'Tran Thi Binh'),
    ],
    scheduleRule: ScheduleRule(
      scheduleCode: '11',
      semesterStart: DateTime(2026, 9, 7),
    ),
    meetings: [
      meeting('m1', 1, state: MeetingState.closed),
      meeting('m2', 2, startAt: DateTime(2026, 9, 10, 7, 30), state: MeetingState.active),
    ],
    attendance: {
      'm1': {
        'SE180001': AttendanceRecord(
          status: AttendanceStatus.present,
          source: AttendanceSource.scan,
          recordedAt: t0,
        ),
        'SE180002': AttendanceRecord(
          status: AttendanceStatus.absent,
          source: AttendanceSource.finalize,
          recordedAt: t0,
        ),
      },
    },
    auditEvents: [
      AuditEvent(
        id: 'aud-1',
        createdAt: t0,
        action: 'attendance_override',
        reason: 'Valid reason',
        rollNumber: 'SE180002',
        meetingId: 'm1',
        oldValue: 'P',
        newValue: 'A',
      ),
    ],
  );

  group('WorkspaceIntegrityValidator diagnostics', () {
    test('returns valid empty report for well-formed workspace', () {
      final ws = TeacherWorkspace(
        id: 'ws-ok',
        semester: 'FA26',
        semesterStart: DateTime(2026, 9, 7),
        classes: [validClass()],
      );

      final report = validator.validateWorkspace(ws);

      expect(report.isValid, isTrue);
      expect(report.errorCount, 0);
      expect(report.warningCount, 0);
      expect(report.infoCount, 0);
      expect(report.issues, isEmpty);
      expect(report.toJson()['isValid'], isTrue);
    });

    test('reports workspace-level empty ID, empty semester, and duplicate class IDs', () {
      final ws = TeacherWorkspace(
        id: '   ',
        semester: '',
        semesterStart: DateTime(2026, 9, 7),
        classes: [validClass(id: 'dup'), validClass(id: ' dup ')],
      );

      final report = validator.validateWorkspace(ws);
      final codes = report.issues.map((i) => i.code).toList();

      expect(report.isValid, isFalse);
      expect(
        codes,
        containsAll([
          'WORKSPACE_EMPTY_ID',
          'WORKSPACE_EMPTY_SEMESTER',
          'DUPLICATE_CLASS_ID',
        ]),
      );
      expect(report.errorCount, 3);
    });

    test('detects all class, student, meeting, attendance, and audit violations', () {
      final broken = CourseClass(
        id: 'cls-broken',
        courseCode: 'PRM393',
        classCode: 'SE1899',
        scheduleCode: '99',
        students: [
          student('', email: 'bad-email', fullName: ''),
          student('SE180001', email: 'dup@fpt.edu.vn', fullName: 'First'),
          student('se180001', email: 'other@fpt.edu.vn', fullName: 'Second Roll Dup'),
          student('SE180002', email: 'DUP@fpt.edu.vn', fullName: 'Email Dup'),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [
          meeting(
            'm1',
            1,
            startAt: DateTime(2026, 9, 7, 10, 0),
            endAt: DateTime(2026, 9, 7, 9, 0),
            state: MeetingState.closed,
          ),
          meeting(
            'm1',
            1,
            startAt: DateTime(2026, 9, 8, 7, 30),
            state: MeetingState.active,
          ),
          meeting(
            'm3',
            3,
            startAt: DateTime(2026, 9, 9, 7, 30),
            state: MeetingState.active,
          ),
        ],
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.unmarked,
              source: AttendanceSource.manual,
              recordedAt: t0,
            ),
            'UNKNOWN_ROLL': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
          'orphan-meeting': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'aud-empty',
            createdAt: t0,
            action: 'attendance_override',
            reason: '   ',
            rollNumber: 'SE180001',
            meetingId: 'm1',
            oldValue: 'A',
            newValue: 'P',
          ),
        ],
      );

      final issues = validator.validateClass(broken);
      final codes = issues.map((i) => i.code).toSet();

      expect(
        codes,
        containsAll([
          'INVALID_SCHEDULE_CODE',
          'STUDENT_MISSING_IDENTITY',
          'INVALID_STUDENT_EMAIL',
          'DUPLICATE_STUDENT_ROLL',
          'DUPLICATE_STUDENT_EMAIL',
          'INVALID_MEETING_TIME_RANGE',
          'DUPLICATE_MEETING_ID',
          'DUPLICATE_MEETING_NUMBER',
          'MULTIPLE_ACTIVE_MEETINGS',
          'CLOSED_MEETING_UNMARKED_STUDENT',
          'ORPHANED_MEETING_ATTENDANCE',
          'ORPHANED_STUDENT_ATTENDANCE',
          'AUDIT_EMPTY_REASON',
        ]),
      );

      final report = WorkspaceIntegrityReport(
        workspaceId: 'ws-broken',
        semester: 'FA26',
        issues: issues,
      );
      expect(report.isValid, isFalse);
      expect(report.warningCount, greaterThanOrEqualTo(3));
      expect(report.errorCount, greaterThanOrEqualTo(8));
      expect(report.toJson()['issues'], isNotEmpty);
    });

    test('distinguishes warnings-only report as isValid=true', () {
      final warningOnlyClass = CourseClass(
        id: 'cls-warn',
        courseCode: 'PRM393',
        classCode: 'SE1802',
        scheduleCode: '11',
        students: [
          student('SE180001', email: 'an@fpt.edu.vn', fullName: 'An'),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [
          meeting('m1', 1, state: MeetingState.upcoming),
          meeting('m2', 1, startAt: DateTime(2026, 9, 10, 7, 30)),
        ],
        attendance: {
          'ghost-meeting': {
            'SE999999': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
        },
      );

      final report = validator.validateWorkspace(
        TeacherWorkspace(
          id: 'ws-warn',
          semester: 'FA26',
          semesterStart: DateTime(2026, 9, 7),
          classes: [warningOnlyClass],
        ),
      );

      expect(report.isValid, isTrue);
      expect(report.errorCount, 0);
      expect(report.warningCount, 3);
    });
  });

  group('WorkspaceIntegrityValidator repairCourseClass', () {
    test('deduplicates roster, demotes extra active meetings, strips orphans, fills closed cells, and fixes audit reasons', () {
      final corrupted = CourseClass(
        id: 'cls-repair',
        courseCode: 'SWP391',
        classCode: 'SE1805',
        scheduleCode: '11',
        students: [
          student('', email: 'bad@fpt.edu.vn', fullName: 'Missing Roll'),
          student('SE180001', email: 'an@fpt.edu.vn', fullName: 'Nguyen Van An'),
          student('se180001', email: 'an2@fpt.edu.vn', fullName: 'Dup Roll'),
          student('SE180002', email: 'AN@fpt.edu.vn', fullName: 'Dup Email'),
          student('SE180003', email: 'chi@fpt.edu.vn', fullName: 'Le Chi'),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [
          meeting('m1', 1, state: MeetingState.closed),
          meeting('m1', 1, state: MeetingState.active),
          meeting(
            'm2',
            2,
            startAt: DateTime(2026, 9, 10, 7, 30),
            state: MeetingState.active,
          ),
          meeting(
            'm3',
            3,
            startAt: DateTime(2026, 9, 14, 7, 30),
            state: MeetingState.active,
          ),
        ],
        attendance: {
          'm1': {
            'se180001 ': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
            'SE180003': AttendanceRecord(
              status: AttendanceStatus.unmarked,
              source: AttendanceSource.manual,
              recordedAt: t0,
            ),
            'GHOST': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
          'missing-m': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'a1',
            createdAt: t0,
            action: 'attendance_override',
            reason: '   ',
            rollNumber: 'SE180001',
            meetingId: 'm1',
            oldValue: 'A',
            newValue: 'P',
          ),
          AuditEvent(
            id: 'a2',
            createdAt: t0,
            action: 'attendance_override',
            reason: 'Existing valid reason',
            rollNumber: 'SE180003',
            meetingId: 'm1',
            oldValue: 'P',
            newValue: 'A',
          ),
        ],
      );

      final repaired = validator.repairCourseClass(corrupted, now: t0);

      // Retained valid distinct students: SE180001, SE180003
      expect(
        repaired.students.map((s) => s.rollNumber).toList(),
        ['SE180001', 'SE180003'],
      );
      // Duplicate m1 removed; m2 keeps active; m3 demoted to upcoming.
      expect(
        repaired.meetings.map((m) => (m.id, m.state)).toList(),
        [
          ('m1', MeetingState.closed),
          ('m2', MeetingState.active),
          ('m3', MeetingState.upcoming),
        ],
      );
      // Orphaned meeting stripped; SE180001 canonicalized & preserved P;
      // SE180003 unmarked on closed m1 filled with absent + finalize note.
      expect(repaired.attendance.containsKey('missing-m'), isFalse);
      expect(
        repaired.attendance['m1']?['SE180001']?.status,
        AttendanceStatus.present,
      );
      expect(
        repaired.attendance['m1']?['SE180003']?.status,
        AttendanceStatus.absent,
      );
      expect(
        repaired.attendance['m1']?['SE180003']?.source,
        AttendanceSource.finalize,
      );
      expect(repaired.attendance['m1']?.containsKey('GHOST'), isFalse);

      // Audit event with blank reason received fallback reason.
      expect(repaired.auditEvents[0].reason, isNotEmpty);
      expect(repaired.auditEvents[1].reason, 'Existing valid reason');

      final postIssues = validator.validateClass(repaired);
      expect(postIssues, isEmpty);
    });
  });
}
