import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/workspace_integrity_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WorkspaceIntegrityValidator validator;

  setUp(() {
    validator = const WorkspaceIntegrityValidator();
  });

  CourseClass validClass({String id = 'cls-1'}) {
    return CourseClass(
      id: id,
      courseCode: 'PRM392',
      classCode: 'SE1801',
      scheduleCode: '11',
      students: const [
        Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'S1'),
        Student(rollNumber: 'SE180002', email: 's2@fpt.edu.vn', fullName: 'S2'),
      ],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [
        Meeting(
          id: '$id-m1',
          number: 1,
          startAt: DateTime(2026, 9, 7, 7, 30),
          endAt: DateTime(2026, 9, 7, 9, 15),
          state: MeetingState.closed,
        ),
        Meeting(
          id: '$id-m2',
          number: 2,
          startAt: DateTime(2026, 9, 10, 7, 30),
          endAt: DateTime(2026, 9, 10, 9, 15),
          state: MeetingState.active,
        ),
      ],
      attendance: {
        '$id-m1': {
          'SE180001': AttendanceRecord(
            status: AttendanceStatus.present,
            source: AttendanceSource.scan,
            recordedAt: DateTime(2026, 9, 7, 7, 35),
          ),
          'SE180002': AttendanceRecord(
            status: AttendanceStatus.absent,
            source: AttendanceSource.finalize,
            recordedAt: DateTime(2026, 9, 7, 9, 15),
          ),
        },
      },
      auditEvents: [
        AuditEvent(
          id: 'aud-1',
          createdAt: DateTime(2026, 9, 7, 10, 0),
          action: 'override',
          reason: 'Valid reason',
        ),
      ],
    );
  }

  group('validateWorkspace & validateClass', () {
    test('returns valid report with zero issues for clean workspace', () {
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

    test('detects workspace-level errors and duplicate class IDs', () {
      final ws = TeacherWorkspace(
        id: '  ',
        semester: '',
        semesterStart: DateTime(2026, 9, 7),
        classes: [validClass(id: 'dup'), validClass(id: 'dup')],
      );

      final report = validator.validateWorkspace(ws);
      expect(report.isValid, isFalse);
      final codes = report.issues.map((i) => i.code).toSet();
      expect(codes, containsAll([
        'WORKSPACE_EMPTY_ID',
        'WORKSPACE_EMPTY_SEMESTER',
        'DUPLICATE_CLASS_ID',
      ]));
    });

    test('detects all class, student, meeting, attendance, and audit violations', () {
      final broken = CourseClass(
        id: 'cls-bad',
        courseCode: 'PRM392',
        classCode: 'SE1801',
        scheduleCode: '99', // invalid
        students: const [
          Student(rollNumber: '', email: 'bad-email', fullName: ''),
          Student(rollNumber: 'SE1', email: 'dup@fpt.edu.vn', fullName: 'One'),
          Student(rollNumber: 'se1', email: 'DUP@fpt.edu.vn', fullName: 'Two'),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '99',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 9, 7, 9, 0),
            endAt: DateTime(2026, 9, 7, 8, 0), // invalid range
            state: MeetingState.closed,
          ),
          Meeting(
            id: 'm1', // duplicate id
            number: 1, // duplicate number (warning)
            startAt: DateTime(2026, 9, 10, 7, 30),
            endAt: DateTime(2026, 9, 10, 9, 15),
            state: MeetingState.active,
          ),
          Meeting(
            id: 'm3',
            number: 2,
            startAt: DateTime(2026, 9, 14, 7, 30),
            endAt: DateTime(2026, 9, 14, 9, 15),
            state: MeetingState.active, // multiple active
          ),
        ],
        attendance: {
          'ghost-meeting': {
            'GHOST_ROLL': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: DateTime(2026, 9, 7),
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'a-bad',
            createdAt: DateTime(2026, 9, 7),
            action: 'override',
            reason: '   ',
          ),
        ],
      );

      final issues = validator.validateClass(broken);
      final codes = issues.map((i) => i.code).toSet();
      expect(codes, containsAll([
        'INVALID_SCHEDULE_CODE',
        'STUDENT_MISSING_IDENTITY',
        'INVALID_STUDENT_EMAIL',
        'DUPLICATE_STUDENT_ROLL',
        'DUPLICATE_STUDENT_EMAIL',
        'DUPLICATE_MEETING_ID',
        'DUPLICATE_MEETING_NUMBER',
        'INVALID_MEETING_TIME_RANGE',
        'CLOSED_MEETING_UNMARKED_STUDENT',
        'MULTIPLE_ACTIVE_MEETINGS',
        'ORPHANED_MEETING_ATTENDANCE',
        'ORPHANED_STUDENT_ATTENDANCE',
        'AUDIT_EMPTY_REASON',
      ]));
    });
  });

  group('repairCourseClass', () {
    test('deduplicates students/meetings, normalizes active slots, fills closed absences, and fixes audit reasons', () {
      final broken = CourseClass(
        id: 'cls-fix',
        courseCode: 'PRM392',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: const [
          Student(rollNumber: '', email: 'bad@fpt.edu.vn', fullName: ''),
          Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'S1'),
          Student(rollNumber: 'se180001', email: 's1dup@fpt.edu.vn', fullName: 'S1 Dup'),
          Student(rollNumber: 'SE180002', email: 's1@fpt.edu.vn', fullName: 'S2 Same Email'),
          Student(rollNumber: 'SE180003', email: 's3@fpt.edu.vn', fullName: 'S3'),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
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
          Meeting(
            id: 'm2', // duplicate meeting id
            number: 2,
            startAt: DateTime(2026, 9, 10, 7, 30),
            endAt: DateTime(2026, 9, 10, 9, 15),
            state: MeetingState.active,
          ),
          Meeting(
            id: 'm3',
            number: 3,
            startAt: DateTime(2026, 9, 14, 7, 30),
            endAt: DateTime(2026, 9, 14, 9, 15),
            state: MeetingState.active, // second active -> downgraded to upcoming
          ),
        ],
        attendance: {
          'm1': {
            'se180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: DateTime(2026, 9, 7, 7, 35),
            ),
          },
          'ghost-m': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: DateTime(2026, 9, 7),
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'aud-empty',
            createdAt: DateTime(2026, 9, 7),
            action: 'override',
            reason: '',
          ),
        ],
      );

      final fixed = validator.repairCourseClass(
        broken,
        now: DateTime(2026, 9, 15),
      );

      expect(fixed.students.map((s) => s.rollNumber), ['SE180001', 'SE180003']);
      expect(fixed.meetings.map((m) => m.id), ['m1', 'm2', 'm3']);
      expect(fixed.meetings[1].state, MeetingState.active);
      expect(fixed.meetings[2].state, MeetingState.upcoming);
      expect(fixed.attendance.containsKey('ghost-m'), isFalse);
      expect(fixed.recordFor('m1', 'SE180001')?.status, AttendanceStatus.present);
      expect(fixed.recordFor('m1', 'SE180003')?.status, AttendanceStatus.absent);
      expect(fixed.auditEvents.first.reason, isNotEmpty);

      final recheck = validator.validateClass(fixed);
      expect(recheck, isEmpty);
    });
  });
}
