import 'package:fap_attendance/domain/attendance_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/schedule_service.dart';
import 'package:fap_attendance/domain/spreadsheet_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 10, 8, 0);

  group('Domain models JSON round-trips & normalization', () {
    test('Student normalizes email case/whitespace and serializes cleanly', () {
      const s = Student(
        rollNumber: 'SE180001',
        fullName: 'Nguyen Van An',
        email: '  An.NV@FPT.EDU.VN  ',
      );
      expect(s.normalizedEmail, 'an.nv@fpt.edu.vn');
      final decoded = Student.fromJson(s.toJson());
      expect(decoded.rollNumber, 'SE180001');
      expect(decoded.fullName, 'Nguyen Van An');
      expect(decoded.email, '  An.NV@FPT.EDU.VN  ');
      expect(decoded.normalizedEmail, 'an.nv@fpt.edu.vn');

      final minimal = Student.fromJson({
        'rollNumber': 'SE2',
        'fullName': 'Binh',
        'email': '',
      });
      expect(minimal.email, '');
      expect(minimal.normalizedEmail, '');
    });

    test('ScheduleRule serializes slots, weekdays, excludedDates, additionalStarts', () {
      final start = DateTime.utc(2026, 9, 7, 7, 30);
      final excl = DateTime.utc(2026, 9, 14);
      final extra = DateTime.utc(2026, 10, 4, 9, 15);
      final rule = ScheduleRule(
        scheduleCode: '12',
        semesterStart: start,
        weeks: 10,
        meetingsPerWeek: 2,
        weekdays: const [DateTime.monday, DateTime.wednesday],
        excludedDates: [excl],
        additionalStarts: [extra],
      );

      final roundTrip = ScheduleRule.fromJson(rule.toJson());
      expect(roundTrip.scheduleCode, '12');
      expect(roundTrip.semesterStart, start);
      expect(roundTrip.dayGroup, 1);
      expect(roundTrip.weeks, 10);
      expect(roundTrip.meetingsPerWeek, 2);
      expect(roundTrip.weekdays, [DateTime.monday, DateTime.wednesday]);
      expect(roundTrip.excludedDates, [excl]);
      expect(roundTrip.additionalStarts, [extra]);
    });

    test('ScheduleRule defaults missing optional fields cleanly', () {
      final minimal = ScheduleRule.fromJson({
        'scheduleCode': '31',
        'semesterStart': '2026-09-07T00:00:00.000Z',
        'weeks': 5,
      });
      expect(minimal.dayGroup, 3);
      expect(minimal.scheduleCode, '31');
      expect(minimal.meetingsPerWeek, 2);
      expect(minimal.weekdays, isEmpty);
      expect(minimal.excludedDates, isEmpty);
      expect(minimal.additionalStarts, isEmpty);
    });

    test('Meeting state enum serialization, copyWith & isOnDate checks', () {
      for (final state in MeetingState.values) {
        final m = Meeting(
          id: 'm-${state.name}',
          number: 3,
          startAt: DateTime(2026, 9, 10, 7, 30),
          endAt: DateTime(2026, 9, 10, 9, 50),
          state: state,
        );
        final decoded = Meeting.fromJson(m.toJson());
        expect(decoded.id, m.id);
        expect(decoded.number, 3);
        expect(decoded.state, state);
      }

      final base = Meeting(
        id: 'm1',
        number: 1,
        startAt: DateTime(2026, 9, 10, 7, 30),
        endAt: DateTime(2026, 9, 10, 9, 50),
        state: MeetingState.upcoming,
      );
      expect(base.isOnDate(DateTime(2026, 9, 10, 23, 59)), isTrue);
      expect(base.isOnDate(DateTime(2026, 9, 11, 0, 0)), isFalse);

      final activated = base.copyWith(state: MeetingState.active);
      expect(activated.state, MeetingState.active);
      expect(activated.id, 'm1');
      expect(base.state, MeetingState.upcoming);

      expect(
        () => Meeting.fromJson({
          'id': 'm-unk',
          'number': 2,
          'startAt': '2026-09-10T07:30:00.000',
          'endAt': '2026-09-10T09:50:00.000',
          'state': 'unexpected_future_state',
        }),
        throwsArgumentError,
      );
    });

    test('AttendanceRecord preserves all statuses, sources, note, and recordedAt', () {
      for (final status in AttendanceStatus.values) {
        for (final source in AttendanceSource.values) {
          final record = AttendanceRecord(
            status: status,
            source: source,
            recordedAt: t0,
            note: 'audit-${status.name}-${source.name}',
          );
          final parsed = AttendanceRecord.fromJson(record.toJson());
          expect(parsed.status, status);
          expect(parsed.source, source);
          expect(parsed.recordedAt, t0);
          expect(parsed.note, record.note);
        }
      }

      expect(
        () => AttendanceRecord.fromJson({
          'status': 'bad_status',
          'source': 'bad_source',
          'recordedAt': t0.toIso8601String(),
        }),
        throwsArgumentError,
      );
    });

    test('AuditEvent round-trip preserves metadata fields', () {
      final e1 = AuditEvent(
        id: 'ev-1',
        createdAt: t0,
        action: 'meeting_opened',
        reason: 'Mo buoi 1',
        rollNumber: 'SE180001',
        meetingId: 'm1',
        oldValue: 'upcoming',
        newValue: 'active',
      );
      final r1 = AuditEvent.fromJson(e1.toJson());
      expect(r1.id, 'ev-1');
      expect(r1.createdAt, t0);
      expect(r1.action, 'meeting_opened');
      expect(r1.reason, 'Mo buoi 1');
      expect(r1.rollNumber, 'SE180001');
      expect(r1.meetingId, 'm1');
      expect(r1.oldValue, 'upcoming');
      expect(r1.newValue, 'active');
    });
  });

  group('CourseClass metrics, record lookups, copyWith & serialization', () {
    final attendanceService = AttendanceService();

    CourseClass buildCourse({
      int studentCount = 4,
      Map<String, Map<String, AttendanceRecord>>? attendance,
    }) {
      final students = [
        for (var i = 1; i <= studentCount; i++)
          Student(
            rollNumber: 'SE18000$i',
            fullName: 'Student $i',
            email: 's$i@fpt.edu.vn',
          ),
      ];
      return CourseClass(
        id: 'cls-1',
        courseCode: 'PRM393',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: students,
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
          weeks: 2,
        ),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: DateTime(2026, 9, 7, 7, 30),
            endAt: DateTime(2026, 9, 7, 9, 50),
            state: MeetingState.closed,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: DateTime(2026, 9, 9, 7, 30),
            endAt: DateTime(2026, 9, 9, 9, 50),
            state: MeetingState.active,
          ),
        ],
        attendance: attendance ?? {},
        auditEvents: [
          AuditEvent(
            id: 'a1',
            createdAt: DateTime(2026, 9, 7, 7, 31),
            action: 'create',
            reason: 'Created',
          ),
        ],
      );
    }

    test('computes absenceRate accurately via AttendanceService and recordFor', () {
      final c = buildCourse(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: t0,
            ),
            'SE180003': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t0,
            ),
          },
        },
      );

      expect(attendanceService.absenceRate(c, 'SE180001'), 0.0);
      expect(attendanceService.absenceRate(c, 'SE180003'), 0.5);
      expect(c.recordFor('m1', 'SE180001')?.status, AttendanceStatus.present);
      expect(c.recordFor('m1', 'SE180004'), isNull);
    });

    test('empty class handles absenceRate cleanly without throwing', () {
      final empty = buildCourse(studentCount: 0);
      expect(attendanceService.absenceRate(empty, 'SE180001'), 0.0);
    });

    test('copyWith and full JSON round-trip preserve nested attendance and audits', () {
      final c = buildCourse(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
              note: 'ok',
            ),
          },
        },
      );
      final updated = c.copyWith(scheduleCode: '22');
      expect(updated.scheduleCode, '22');
      expect(updated.courseCode, 'PRM393');
      expect(updated.students.length, 4);

      final parsed = CourseClass.fromJson(c.toJson());
      expect(parsed.id, 'cls-1');
      expect(parsed.meetings.length, 2);
      expect(parsed.auditEvents.length, 1);
      expect(parsed.recordFor('m1', 'SE180001')?.recordedAt, t0);
      expect(parsed.recordFor('m1', 'SE180001')?.note, 'ok');
    });

    test('TeacherWorkspace encode/decode preserves schemaVersion, semester and classes', () {
      final c1 = buildCourse();
      final ws = TeacherWorkspace(
        id: 'ws-fa26',
        schemaVersion: 2,
        semester: 'Fall2026',
        semesterStart: DateTime(2026, 9, 7),
        teacherEmail: 'gv@fpt.edu.vn',
        updatedAt: t0,
        classes: [c1],
      );
      final encoded = ws.toPrettyJson();
      final decoded = TeacherWorkspace.decode(encoded);
      expect(decoded.schemaVersion, 2);
      expect(decoded.semester, 'Fall2026');
      expect(decoded.teacherEmail, 'gv@fpt.edu.vn');
      expect(decoded.classes.length, 1);
      expect(decoded.classes.single.courseCode, 'PRM393');

      final newTime = DateTime.utc(2026, 10, 1);
      final copied = ws.copyWith(updatedAt: newTime, classes: const []);
      expect(copied.updatedAt, newTime);
      expect(copied.classes, isEmpty);
    });
  });

  group('spreadsheetText formula neutralization & ScheduleService slot metadata', () {
    test('neutralizes formula-like cell prefixes across tabs, leading spaces, and operators', () {
      final dangerous = [
        '=SUM(A1:A2)',
        '+1+1',
        '-cmd',
        '@SUM(1,1)',
        '   =HYPERLINK("http://evil")',
        '\t=1+1',
        '\r=1+1',
      ];
      for (final value in dangerous) {
        final escaped = spreadsheetText(value);
        expect(escaped, "'$value");
      }

      final safe = [
        'SE180001',
        'Nguyen Van An',
        'an@fpt.edu.vn',
        '',
        '012345',
      ];
      for (final value in safe) {
        expect(spreadsheetText(value), value);
      }
    });

    test('ScheduleService exposes slotTimes and weekdaysByGroup consistently', () {
      expect(ScheduleService.weekdaysByGroup.keys, containsAll([1, 2, 3]));
      for (var slot = 1; slot <= 4; slot++) {
        final time = ScheduleService.slotTimes[slot]!;
        expect(time.endHour * 60 + time.endMinute, greaterThan(time.startHour * 60 + time.startMinute));
      }
    });
  });
}
