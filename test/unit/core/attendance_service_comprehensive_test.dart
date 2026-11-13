import 'package:attendance_core/attendance_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AttendanceService service;
  late DateTime todayMorning;
  late DateTime yesterdayMorning;
  late DateTime tomorrowMorning;

  CourseClass createSampleClass({
    List<Meeting>? meetings,
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
  }) {
    return CourseClass(
      id: 'cls-1',
      courseCode: 'SWD392',
      classCode: 'SE1802',
      scheduleCode: '11',
      students: const [
        Student(
          rollNumber: 'SE180001',
          memberCode: 'AnNV',
          email: 'annv@fpt.edu.vn',
          fullName: 'Nguyen Van An',
        ),
        Student(
          rollNumber: 'SE180002',
          memberCode: 'BinhTT',
          email: 'binhtt@fpt.edu.vn',
          fullName: 'Tran Thi Binh',
        ),
        Student(
          rollNumber: 'SE180003',
          memberCode: 'CuongLH',
          email: 'cuonglh@fpt.edu.vn',
          fullName: 'Le Hoang Cuong',
        ),
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
              startAt: yesterdayMorning,
              endAt: yesterdayMorning.add(const Duration(hours: 2)),
              state: MeetingState.closed,
            ),
            Meeting(
              id: 'm2',
              number: 2,
              startAt: todayMorning,
              endAt: todayMorning.add(const Duration(hours: 2)),
              state: MeetingState.upcoming,
            ),
            Meeting(
              id: 'm3',
              number: 3,
              startAt: tomorrowMorning,
              endAt: tomorrowMorning.add(const Duration(hours: 2)),
              state: MeetingState.upcoming,
            ),
          ],
      attendance: attendance,
    );
  }

  setUp(() {
    service = AttendanceService();
    todayMorning = DateTime(2026, 9, 10, 7, 30);
    yesterdayMorning = DateTime(2026, 9, 7, 7, 30);
    tomorrowMorning = DateTime(2026, 9, 14, 7, 30);
  });

  group('startMeeting', () {
    test('transitions upcoming meeting on current date to active', () {
      final cls = createSampleClass();
      final started = service.startMeeting(cls, 'm2', now: todayMorning);
      expect(started.meetings.firstWhere((m) => m.id == 'm2').state,
          MeetingState.active);
      expect(cls.meetings.firstWhere((m) => m.id == 'm2').state,
          MeetingState.upcoming);
    });

    test('throws if another meeting is already active', () {
      final cls = createSampleClass(
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: todayMorning,
            endAt: todayMorning.add(const Duration(hours: 2)),
            state: MeetingState.active,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: todayMorning,
            endAt: todayMorning.add(const Duration(hours: 2)),
            state: MeetingState.upcoming,
          ),
        ],
      );
      expect(
        () => service.startMeeting(cls, 'm2', now: todayMorning),
        throwsStateError,
      );
    });

    test('throws if meeting is closed', () {
      final cls = createSampleClass();
      expect(
        () => service.startMeeting(cls, 'm1', now: yesterdayMorning),
        throwsStateError,
      );
    });

    test('throws if meeting is before today (overdue)', () {
      final cls = createSampleClass(
        meetings: [
          Meeting(
            id: 'm-old',
            number: 1,
            startAt: yesterdayMorning,
            endAt: yesterdayMorning.add(const Duration(hours: 2)),
            state: MeetingState.upcoming,
          ),
        ],
      );
      expect(
        () => service.startMeeting(cls, 'm-old', now: todayMorning),
        throwsStateError,
      );
    });

    test('throws if meeting is in the future', () {
      final cls = createSampleClass();
      expect(
        () => service.startMeeting(cls, 'm3', now: todayMorning),
        throwsStateError,
      );
    });
  });

  group('markPresent', () {
    test('marks matching student present using case-insensitive email', () {
      final cls = service.startMeeting(createSampleClass(), 'm2', now: todayMorning);
      final updated = service.markPresent(
        cls,
        meetingId: 'm2',
        email: '  AnNV@FPT.EDU.VN ',
        now: todayMorning.add(const Duration(minutes: 5)),
      );

      final rec = updated.recordFor('m2', 'SE180001');
      expect(rec, isNotNull);
      expect(rec!.status, AttendanceStatus.present);
      expect(rec.source, AttendanceSource.scan);
    });

    test('is idempotent and preserves existing teacher decision and note', () {
      final cls = service.startMeeting(createSampleClass(), 'm2', now: todayMorning);
      final overridden = service.overrideStatus(
        cls,
        meetingId: 'm2',
        rollNumber: 'SE180001',
        status: AttendanceStatus.absent,
        reason: 'Cheating check-in',
        auditId: 'aud-1',
        now: todayMorning,
      );

      final afterScan = service.markPresent(
        overridden,
        meetingId: 'm2',
        email: 'annv@fpt.edu.vn',
        now: todayMorning.add(const Duration(minutes: 10)),
      );
      final rec = afterScan.recordFor('m2', 'SE180001');
      expect(rec?.status, AttendanceStatus.absent);
      expect(rec?.note, 'Cheating check-in');
    });

    test('cleans up non-canonical roll number keys when marking present', () {
      final base = createSampleClass(
        meetings: [
          Meeting(
            id: 'm2',
            number: 2,
            startAt: todayMorning,
            endAt: todayMorning.add(const Duration(hours: 2)),
            state: MeetingState.active,
          ),
        ],
        attendance: {
          'm2': {
            'se180001 ': AttendanceRecord(
              status: AttendanceStatus.unmarked,
              source: AttendanceSource.manual,
              recordedAt: todayMorning,
            ),
          },
        },
      );

      final updated = service.markPresent(
        base,
        meetingId: 'm2',
        email: 'annv@fpt.edu.vn',
        now: todayMorning,
      );
      expect(updated.attendance['m2']!.keys, ['SE180001']);
    });

    test('throws when meeting not active, wrong date, or unknown email', () {
      final inactive = createSampleClass();
      expect(
        () => service.markPresent(
          inactive,
          meetingId: 'm2',
          email: 'annv@fpt.edu.vn',
          now: todayMorning,
        ),
        throwsStateError,
      );

      final active = service.startMeeting(inactive, 'm2', now: todayMorning);
      expect(
        () => service.markPresent(
          active,
          meetingId: 'm2',
          email: 'annv@fpt.edu.vn',
          now: tomorrowMorning,
        ),
        throwsStateError,
      );

      expect(
        () => service.markPresent(
          active,
          meetingId: 'm2',
          email: 'stranger@fpt.edu.vn',
          now: todayMorning,
        ),
        throwsStateError,
      );
    });
  });

  group('markManual', () {
    test('records present or absent manually for active today meeting', () {
      final active = service.startMeeting(createSampleClass(), 'm2', now: todayMorning);
      final updated = service.markManual(
        active,
        meetingId: 'm2',
        rollNumber: 'se180002',
        status: AttendanceStatus.absent,
        now: todayMorning,
      );
      final rec = updated.recordFor('m2', 'SE180002');
      expect(rec?.status, AttendanceStatus.absent);
      expect(rec?.source, AttendanceSource.manual);
    });

    test('throws if record already exists, status unmarked, unknown student, or inactive', () {
      final cls = createSampleClass();
      expect(
        () => service.markManual(
          cls,
          meetingId: 'm2',
          rollNumber: 'SE180001',
          status: AttendanceStatus.present,
          now: todayMorning,
        ),
        throwsStateError,
      );

      final active = service.startMeeting(cls, 'm2', now: todayMorning);
      expect(
        () => service.markManual(
          active,
          meetingId: 'm2',
          rollNumber: 'SE180001',
          status: AttendanceStatus.unmarked,
          now: todayMorning,
        ),
        throwsArgumentError,
      );
      expect(
        () => service.markManual(
          active,
          meetingId: 'm2',
          rollNumber: 'SE999999',
          status: AttendanceStatus.present,
          now: todayMorning,
        ),
        throwsArgumentError,
      );

      final marked = service.markManual(
        active,
        meetingId: 'm2',
        rollNumber: 'SE180001',
        status: AttendanceStatus.present,
        now: todayMorning,
      );
      expect(
        () => service.markManual(
          marked,
          meetingId: 'm2',
          rollNumber: 'SE180001',
          status: AttendanceStatus.absent,
          now: todayMorning,
        ),
        throwsStateError,
      );
    });
  });

  group('closeMeeting and finalizeOverdueMeetings', () {
    test('closeMeeting marks unmarked students absent and preserves marked ones', () {
      final active = service.startMeeting(createSampleClass(), 'm2', now: todayMorning);
      final withOneScan = service.markPresent(
        active,
        meetingId: 'm2',
        email: 'annv@fpt.edu.vn',
        now: todayMorning,
      );
      final closed = service.closeMeeting(withOneScan, 'm2', now: todayMorning);

      expect(closed.meetings.firstWhere((m) => m.id == 'm2').state,
          MeetingState.closed);
      expect(closed.recordFor('m2', 'SE180001')?.status, AttendanceStatus.present);
      expect(closed.recordFor('m2', 'SE180002')?.status, AttendanceStatus.absent);
      expect(closed.recordFor('m2', 'SE180002')?.source, AttendanceSource.finalize);
      expect(closed.recordFor('m2', 'SE180003')?.status, AttendanceStatus.absent);
    });

    test('finalizeOverdueMeetings closes past upcoming/active meetings only', () {
      final cls = createSampleClass(
        meetings: [
          Meeting(
            id: 'm-past-up',
            number: 1,
            startAt: yesterdayMorning,
            endAt: yesterdayMorning.add(const Duration(hours: 2)),
            state: MeetingState.upcoming,
          ),
          Meeting(
            id: 'm-today',
            number: 2,
            startAt: todayMorning,
            endAt: todayMorning.add(const Duration(hours: 2)),
            state: MeetingState.upcoming,
          ),
          Meeting(
            id: 'm-future',
            number: 3,
            startAt: tomorrowMorning,
            endAt: tomorrowMorning.add(const Duration(hours: 2)),
            state: MeetingState.upcoming,
          ),
        ],
      );

      final finalized = service.finalizeOverdueMeetings(cls, now: todayMorning);
      expect(finalized.meetings[0].state, MeetingState.closed);
      expect(finalized.meetings[1].state, MeetingState.upcoming);
      expect(finalized.meetings[2].state, MeetingState.upcoming);
      expect(finalized.recordFor('m-past-up', 'SE180001')?.status,
          AttendanceStatus.absent);
    });
  });

  group('overrideStatus and absenceRate', () {
    test('overrideStatus creates audit event and updates attendance', () {
      final cls = createSampleClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: yesterdayMorning,
            ),
          },
        },
      );

      final updated = service.overrideStatus(
        cls,
        meetingId: 'm1',
        rollNumber: 'se180001',
        status: AttendanceStatus.present,
        reason: '  Approved excuse  ',
        auditId: 'aud-99',
        now: todayMorning,
      );

      final rec = updated.recordFor('m1', 'SE180001');
      expect(rec?.status, AttendanceStatus.present);
      expect(rec?.note, 'Approved excuse');
      expect(updated.auditEvents, hasLength(1));
      expect(updated.auditEvents.first.oldValue, 'A');
      expect(updated.auditEvents.first.newValue, 'P');
      expect(updated.auditEvents.first.reason, 'Approved excuse');
    });

    test('overrideStatus validates reason, status, student, and meeting state', () {
      final cls = createSampleClass();
      expect(
        () => service.overrideStatus(
          cls,
          meetingId: 'm1',
          rollNumber: 'SE180001',
          status: AttendanceStatus.present,
          reason: '   ',
          auditId: 'a1',
        ),
        throwsArgumentError,
      );
      expect(
        () => service.overrideStatus(
          cls,
          meetingId: 'm1',
          rollNumber: 'SE180001',
          status: AttendanceStatus.unmarked,
          reason: 'Valid',
          auditId: 'a2',
        ),
        throwsArgumentError,
      );
      expect(
        () => service.overrideStatus(
          cls,
          meetingId: 'm1',
          rollNumber: 'UNKNOWN',
          status: AttendanceStatus.present,
          reason: 'Valid',
          auditId: 'a3',
        ),
        throwsArgumentError,
      );
      expect(
        () => service.overrideStatus(
          cls,
          meetingId: 'm2',
          rollNumber: 'SE180001',
          status: AttendanceStatus.present,
          reason: 'Valid',
          auditId: 'a4',
        ),
        throwsStateError,
      );
    });

    test('absenceRate calculates ratio over total meetings and handles zero meetings', () {
      final empty = createSampleClass(meetings: []);
      expect(service.absenceRate(empty, 'SE180001'), 0);

      final cls = createSampleClass(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: yesterdayMorning,
            ),
          },
        },
      );
      expect(service.absenceRate(cls, 'SE180001'), closeTo(1 / 3, 1e-9));
      expect(service.absenceRate(cls, 'SE180002'), 0);
    });
  });
}
