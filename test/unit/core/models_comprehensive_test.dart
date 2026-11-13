import 'dart:convert';

import 'package:attendance_core/attendance_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttendanceStatus helpers', () {
    test('attendanceCode maps every AttendanceStatus to expected code', () {
      expect(attendanceCode(AttendanceStatus.present), 'P');
      expect(attendanceCode(AttendanceStatus.absent), 'A');
      expect(attendanceCode(AttendanceStatus.unmarked), '');
    });

    test('attendanceStatusFromCode handles canonical, lowercase, whitespace, and unknown', () {
      expect(attendanceStatusFromCode('P'), AttendanceStatus.present);
      expect(attendanceStatusFromCode('p'), AttendanceStatus.present);
      expect(attendanceStatusFromCode('  p  '), AttendanceStatus.present);
      expect(attendanceStatusFromCode('A'), AttendanceStatus.absent);
      expect(attendanceStatusFromCode('a'), AttendanceStatus.absent);
      expect(attendanceStatusFromCode(' a '), AttendanceStatus.absent);
      expect(attendanceStatusFromCode(''), AttendanceStatus.unmarked);
      expect(attendanceStatusFromCode('   '), AttendanceStatus.unmarked);
      expect(attendanceStatusFromCode('X'), AttendanceStatus.unmarked);
      expect(attendanceStatusFromCode('present'), AttendanceStatus.unmarked);
    });
  });

  group('Student model', () {
    test('normalizes email by trimming and lowercasing', () {
      const student = Student(
        rollNumber: 'SE180001',
        memberCode: 'AnNVSE180001',
        email: '  AnNVSE180001@FPT.EDU.VN  ',
        fullName: 'Nguyen Van An',
      );
      expect(student.normalizedEmail, 'annvse180001@fpt.edu.vn');
    });

    test('default memberCode is empty string', () {
      const student = Student(
        rollNumber: 'SE180002',
        email: 'binh@fpt.edu.vn',
        fullName: 'Tran Binh',
      );
      expect(student.memberCode, '');
    });

    test('toJson and fromJson roundtrip preserves all fields', () {
      const original = Student(
        rollNumber: 'SE180003',
        memberCode: 'CuongLM',
        email: 'cuonglm@fpt.edu.vn',
        fullName: 'Le Minh Cuong',
      );
      final json = original.toJson();
      final decoded = Student.fromJson(json);

      expect(decoded.rollNumber, original.rollNumber);
      expect(decoded.memberCode, original.memberCode);
      expect(decoded.email, original.email);
      expect(decoded.fullName, original.fullName);
    });

    test('fromJson defaults missing or null memberCode to empty string', () {
      final decoded = Student.fromJson({
        'rollNumber': 'SE180004',
        'email': 'dung@fpt.edu.vn',
        'fullName': 'Pham Dung',
      });
      expect(decoded.memberCode, '');

      final decodedNull = Student.fromJson({
        'rollNumber': 'SE180005',
        'memberCode': null,
        'email': 'em@fpt.edu.vn',
        'fullName': 'Hoang Em',
      });
      expect(decodedNull.memberCode, '');
    });
  });

  group('ScheduleRule model', () {
    test('dayGroup and dailySlot parse valid two-digit schedule codes', () {
      final start = DateTime(2026, 9, 7);
      final r11 = ScheduleRule(scheduleCode: '11', semesterStart: start);
      expect(r11.dayGroup, 1);
      expect(r11.dailySlot, 1);

      final r24 = ScheduleRule(scheduleCode: ' 24 ', semesterStart: start);
      expect(r24.dayGroup, 2);
      expect(r24.dailySlot, 4);

      final r32 = ScheduleRule(scheduleCode: '32', semesterStart: start);
      expect(r32.dayGroup, 3);
      expect(r32.dailySlot, 2);
    });

    test('dayGroup and dailySlot return 0 for empty, short, or non-numeric codes', () {
      final start = DateTime(2026, 9, 7);
      expect(ScheduleRule(scheduleCode: '', semesterStart: start).dayGroup, 0);
      expect(ScheduleRule(scheduleCode: '', semesterStart: start).dailySlot, 0);
      expect(ScheduleRule(scheduleCode: '2', semesterStart: start).dayGroup, 2);
      expect(ScheduleRule(scheduleCode: '2', semesterStart: start).dailySlot, 0);
      expect(ScheduleRule(scheduleCode: 'ab', semesterStart: start).dayGroup, 0);
      expect(ScheduleRule(scheduleCode: 'ab', semesterStart: start).dailySlot, 0);
    });

    test('toJson and fromJson roundtrip preserves lists and dates', () {
      final rule = ScheduleRule(
        scheduleCode: '23',
        semesterStart: DateTime(2026, 9, 7),
        weeks: 12,
        meetingsPerWeek: 2,
        weekdays: const [DateTime.tuesday, DateTime.friday],
        excludedDates: [DateTime(2026, 9, 15), DateTime(2026, 10, 2)],
        additionalStarts: [DateTime(2026, 11, 28)],
      );

      final json = rule.toJson();
      final decoded = ScheduleRule.fromJson(json);

      expect(decoded.scheduleCode, '23');
      expect(decoded.semesterStart, DateTime(2026, 9, 7));
      expect(decoded.weeks, 12);
      expect(decoded.meetingsPerWeek, 2);
      expect(decoded.weekdays, [DateTime.tuesday, DateTime.friday]);
      expect(decoded.excludedDates, [DateTime(2026, 9, 15), DateTime(2026, 10, 2)]);
      expect(decoded.additionalStarts, [DateTime(2026, 11, 28)]);
    });

    test('fromJson provides sensible defaults when optional fields omitted', () {
      final decoded = ScheduleRule.fromJson({
        'scheduleCode': '12',
        'semesterStart': '2026-09-07T00:00:00.000',
      });
      expect(decoded.weeks, 10);
      expect(decoded.meetingsPerWeek, 2);
      expect(decoded.weekdays, isEmpty);
      expect(decoded.excludedDates, isEmpty);
      expect(decoded.additionalStarts, isEmpty);
    });
  });

  group('Meeting model', () {
    final meeting = Meeting(
      id: 'm-1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7, 30),
      endAt: DateTime(2026, 9, 7, 9, 15),
      state: MeetingState.upcoming,
    );

    test('copyWith updates state while preserving identity and times', () {
      final active = meeting.copyWith(state: MeetingState.active);
      expect(active.id, 'm-1');
      expect(active.number, 1);
      expect(active.startAt, meeting.startAt);
      expect(active.endAt, meeting.endAt);
      expect(active.state, MeetingState.active);

      final unchanged = meeting.copyWith();
      expect(unchanged.state, MeetingState.upcoming);
    });

    test('isOnDate, isBeforeDate, and isAfterDate compare calendar dates', () {
      expect(meeting.isOnDate(DateTime(2026, 9, 7, 23, 59)), isTrue);
      expect(meeting.isOnDate(DateTime(2026, 9, 8, 0, 0)), isFalse);

      expect(meeting.isBeforeDate(DateTime(2026, 9, 8, 0, 1)), isTrue);
      expect(meeting.isBeforeDate(DateTime(2026, 9, 7, 23, 59)), isFalse);
      expect(meeting.isBeforeDate(DateTime(2026, 9, 6, 12, 0)), isFalse);

      expect(meeting.isAfterDate(DateTime(2026, 9, 6, 23, 59)), isTrue);
      expect(meeting.isAfterDate(DateTime(2026, 9, 7, 0, 0)), isFalse);
      expect(meeting.isAfterDate(DateTime(2026, 9, 8, 0, 0)), isFalse);
    });

    test('toJson and fromJson roundtrip for all MeetingState values', () {
      for (final state in MeetingState.values) {
        final m = meeting.copyWith(state: state);
        final decoded = Meeting.fromJson(m.toJson());
        expect(decoded.id, m.id);
        expect(decoded.number, m.number);
        expect(decoded.startAt, m.startAt);
        expect(decoded.endAt, m.endAt);
        expect(decoded.state, state);
      }
    });
  });

  group('AttendanceRecord & AuditEvent models', () {
    test('AttendanceRecord toJson omits null note and roundtrips', () {
      final withoutNote = AttendanceRecord(
        status: AttendanceStatus.present,
        source: AttendanceSource.scan,
        recordedAt: DateTime(2026, 9, 7, 7, 45),
      );
      final jsonNoNote = withoutNote.toJson();
      expect(jsonNoNote.containsKey('note'), isFalse);
      final decodedNoNote = AttendanceRecord.fromJson(jsonNoNote);
      expect(decodedNoNote.status, AttendanceStatus.present);
      expect(decodedNoNote.source, AttendanceSource.scan);
      expect(decodedNoNote.note, isNull);

      final withNote = AttendanceRecord(
        status: AttendanceStatus.absent,
        source: AttendanceSource.manual,
        recordedAt: DateTime(2026, 9, 7, 8, 0),
        note: 'Left early',
      );
      final jsonWithNote = withNote.toJson();
      expect(jsonWithNote['note'], 'Left early');
      final decodedWithNote = AttendanceRecord.fromJson(jsonWithNote);
      expect(decodedWithNote.status, AttendanceStatus.absent);
      expect(decodedWithNote.source, AttendanceSource.manual);
      expect(decodedWithNote.note, 'Left early');
    });

    test('AttendanceRecord handles all AttendanceSource enum values', () {
      for (final source in AttendanceSource.values) {
        final rec = AttendanceRecord(
          status: AttendanceStatus.present,
          source: source,
          recordedAt: DateTime(2026, 9, 7),
        );
        final decoded = AttendanceRecord.fromJson(rec.toJson());
        expect(decoded.source, source);
      }
    });

    test('AuditEvent toJson and fromJson roundtrip with optional fields', () {
      final full = AuditEvent(
        id: 'evt-1',
        createdAt: DateTime(2026, 9, 7, 10, 0),
        action: 'attendance_override',
        reason: 'Medical excuse',
        rollNumber: 'SE180001',
        meetingId: 'm-1',
        oldValue: 'A',
        newValue: 'P',
      );
      final decodedFull = AuditEvent.fromJson(full.toJson());
      expect(decodedFull.id, 'evt-1');
      expect(decodedFull.action, 'attendance_override');
      expect(decodedFull.reason, 'Medical excuse');
      expect(decodedFull.rollNumber, 'SE180001');
      expect(decodedFull.meetingId, 'm-1');
      expect(decodedFull.oldValue, 'A');
      expect(decodedFull.newValue, 'P');

      final minimal = AuditEvent(
        id: 'evt-2',
        createdAt: DateTime(2026, 9, 7, 11, 0),
        action: 'finalize',
        reason: 'Auto close',
      );
      final decodedMin = AuditEvent.fromJson(minimal.toJson());
      expect(decodedMin.rollNumber, isNull);
      expect(decodedMin.meetingId, isNull);
      expect(decodedMin.oldValue, isNull);
      expect(decodedMin.newValue, isNull);
    });
  });

  group('CourseClass & TeacherWorkspace models', () {
    CourseClass buildClass() {
      return CourseClass(
        id: 'cls-1',
        courseCode: 'PRM392',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE180001',
            email: 'a@fpt.edu.vn',
            fullName: 'Student A',
          ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [
          Meeting(
            id: 'cls-1-m1',
            number: 1,
            startAt: DateTime(2026, 9, 7, 7, 30),
            endAt: DateTime(2026, 9, 7, 9, 15),
          ),
        ],
        attendance: {
          'cls-1-m1': {
            'se180001 ': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: DateTime(2026, 9, 7, 7, 35),
            ),
          },
        },
        auditEvents: [
          AuditEvent(
            id: 'aud-1',
            createdAt: DateTime(2026, 9, 7, 9, 0),
            action: 'test',
            reason: 'init',
          ),
        ],
      );
    }

    test('recordFor performs exact lookup and normalized fallback lookup', () {
      final cls = buildClass();
      expect(cls.recordFor('missing-meeting', 'SE180001'), isNull);
      expect(cls.recordFor('cls-1-m1', 'SE999999'), isNull);
      expect(cls.recordFor('cls-1-m1', 'SE180001')?.status, AttendanceStatus.present);
      expect(cls.recordFor('cls-1-m1', 'se180001 ')?.status, AttendanceStatus.present);
    });

    test('CourseClass copyWith selectively replaces fields', () {
      final cls = buildClass();
      final updated = cls.copyWith(scheduleCode: '22', auditEvents: []);
      expect(updated.id, cls.id);
      expect(updated.courseCode, cls.courseCode);
      expect(updated.classCode, cls.classCode);
      expect(updated.scheduleCode, '22');
      expect(updated.students, hasLength(1));
      expect(updated.auditEvents, isEmpty);
    });

    test('TeacherWorkspace toPrettyJson and decode roundtrip preserves everything', () {
      final workspace = TeacherWorkspace(
        schemaVersion: 2,
        id: 'ws-2026-fall',
        semester: 'FALL2026',
        semesterStart: DateTime(2026, 9, 7),
        teacherEmail: 'lecturer@fpt.edu.vn',
        classes: [buildClass()],
        updatedAt: DateTime(2026, 9, 8, 12, 0),
      );

      final encoded = workspace.toPrettyJson();
      expect(() => jsonDecode(encoded), returnsNormally);

      final decoded = TeacherWorkspace.decode(encoded);
      expect(decoded.schemaVersion, 2);
      expect(decoded.id, 'ws-2026-fall');
      expect(decoded.semester, 'FALL2026');
      expect(decoded.teacherEmail, 'lecturer@fpt.edu.vn');
      expect(decoded.updatedAt, DateTime(2026, 9, 8, 12, 0));
      expect(decoded.classes, hasLength(1));
      expect(decoded.classes.first.recordFor('cls-1-m1', 'SE180001')?.status,
          AttendanceStatus.present);
    });

    test('TeacherWorkspace copyWith and null updatedAt roundtrip', () {
      final workspace = TeacherWorkspace(
        id: 'ws-1',
        semester: 'SP26',
        semesterStart: DateTime(2026, 1, 5),
        classes: const [],
      );
      final decoded = TeacherWorkspace.decode(workspace.toPrettyJson());
      expect(decoded.schemaVersion, 1);
      expect(decoded.teacherEmail, '');
      expect(decoded.updatedAt, isNull);

      final modified = decoded.copyWith(
        teacherEmail: 'new@fpt.edu.vn',
        updatedAt: DateTime(2026, 1, 6),
      );
      expect(modified.teacherEmail, 'new@fpt.edu.vn');
      expect(modified.updatedAt, DateTime(2026, 1, 6));
    });
  });
}
