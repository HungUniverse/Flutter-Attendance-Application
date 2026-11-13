import 'package:fap_attendance/domain/attendance_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = AttendanceService();
  final todayMorning = DateTime(2026, 9, 14, 7, 30);
  final todayCheckIn = DateTime(2026, 9, 14, 7, 45);
  final yesterday = DateTime(2026, 9, 13, 7, 30);
  final tomorrow = DateTime(2026, 9, 15, 7, 30);

  Student s(String roll, {String? email, String? name}) => Student(
    rollNumber: roll,
    email: email ?? '${roll.toLowerCase()}@fpt.edu.vn',
    fullName: name ?? 'Student $roll',
  );

  Meeting m(
    String id,
    int number,
    DateTime start, {
    MeetingState state = MeetingState.upcoming,
  }) => Meeting(
    id: id,
    number: number,
    startAt: start,
    endAt: start.add(const Duration(hours: 2)),
    state: state,
  );

  CourseClass buildClass({
    List<Student>? students,
    List<Meeting>? meetings,
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
    List<AuditEvent> auditEvents = const [],
  }) => CourseClass(
    id: 'cls-svc',
    courseCode: 'PRM393',
    classCode: 'SE1801',
    scheduleCode: '11',
    students: students ??
        [
          s('SE180001', email: 'AnNV@FPT.EDU.VN', name: 'Nguyen Van An'),
          s('SE180002', email: 'BinhTT@FPT.EDU.VN', name: 'Tran Thi Binh'),
          s('SE180003', email: 'ChiLH@FPT.EDU.VN', name: 'Le Hoang Chi'),
        ],
    scheduleRule: ScheduleRule(
      scheduleCode: '11',
      semesterStart: DateTime(2026, 9, 7),
    ),
    meetings: meetings ??
        [
          m('m-past', 1, yesterday, state: MeetingState.upcoming),
          m('m-today', 2, todayMorning, state: MeetingState.upcoming),
          m('m-future', 3, tomorrow, state: MeetingState.upcoming),
        ],
    attendance: attendance,
    auditEvents: auditEvents,
  );

  group('AttendanceService startMeeting lifecycle guards', () {
    test('activates today upcoming meeting immutably and leaves others unchanged', () {
      final original = buildClass();
      final started = service.startMeeting(
        original,
        'm-today',
        now: todayCheckIn,
      );

      expect(
        original.meetings.firstWhere((e) => e.id == 'm-today').state,
        MeetingState.upcoming,
      );
      expect(
        started.meetings.firstWhere((e) => e.id == 'm-today').state,
        MeetingState.active,
      );
      expect(
        started.meetings.firstWhere((e) => e.id == 'm-past').state,
        MeetingState.upcoming,
      );
      expect(
        started.meetings.firstWhere((e) => e.id == 'm-future').state,
        MeetingState.upcoming,
      );
    });

    test('blocks starting when another meeting in class is already active', () {
      final course = buildClass(
        meetings: [
          m('m1', 1, todayMorning, state: MeetingState.active),
          m('m2', 2, todayMorning.add(const Duration(hours: 3))),
        ],
      );

      expect(
        () => service.startMeeting(course, 'm2', now: todayCheckIn),
        throwsStateError,
      );
    });

    test('rejects starting closed, past, or future meetings', () {
      final pastAndFuture = buildClass();
      expect(
        () => service.startMeeting(pastAndFuture, 'm-past', now: todayCheckIn),
        throwsStateError,
      );
      expect(
        () =>
            service.startMeeting(pastAndFuture, 'm-future', now: todayCheckIn),
        throwsStateError,
      );

      final closedCourse = buildClass(
        meetings: [m('m-closed', 1, todayMorning, state: MeetingState.closed)],
      );
      expect(
        () => service.startMeeting(closedCourse, 'm-closed', now: todayCheckIn),
        throwsStateError,
      );
    });
  });

  group('AttendanceService markPresent & markManual transitions', () {
    test('markPresent accepts normalized email, canonicalizes legacy key casing, and respects sources', () {
      final course = buildClass(
        meetings: [m('m-today', 1, todayMorning, state: MeetingState.active)],
        attendance: {
          'm-today': {
            ' se180001 ': AttendanceRecord(
              status: AttendanceStatus.unmarked,
              source: AttendanceSource.manual,
              recordedAt: todayMorning,
            ),
          },
        },
      );

      final afterScan = service.markPresent(
        course,
        meetingId: 'm-today',
        email: '  annv@fpt.edu.vn  ',
        source: AttendanceSource.scan,
        now: todayCheckIn,
      );
      final afterLink = service.markPresent(
        afterScan,
        meetingId: 'm-today',
        email: 'BINHTT@fpt.edu.vn',
        source: AttendanceSource.simulator,
        now: todayCheckIn.add(const Duration(minutes: 2)),
      );

      final recs = afterLink.attendance['m-today']!;
      expect(recs.containsKey(' se180001 '), isFalse);
      expect(recs['SE180001']?.status, AttendanceStatus.present);
      expect(recs['SE180001']?.source, AttendanceSource.scan);
      expect(recs['SE180002']?.status, AttendanceStatus.present);
      expect(recs['SE180002']?.source, AttendanceSource.simulator);
    });

    test('markPresent is idempotent and never overwrites an existing teacher decision', () {
      final course = buildClass(
        meetings: [m('m-today', 1, todayMorning, state: MeetingState.active)],
        attendance: {
          'm-today': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.manual,
              recordedAt: todayCheckIn,
              note: 'Walked out early',
            ),
          },
        },
      );

      final repeated = service.markPresent(
        course,
        meetingId: 'm-today',
        email: 'annv@fpt.edu.vn',
        source: AttendanceSource.simulator,
        now: todayCheckIn.add(const Duration(minutes: 5)),
      );

      expect(identical(repeated, course), isTrue);
      expect(
        repeated.recordFor('m-today', 'SE180001')?.status,
        AttendanceStatus.absent,
      );
      expect(
        repeated.recordFor('m-today', 'SE180001')?.note,
        'Walked out early',
      );
    });

    test('markPresent rejects inactive meeting, off-day check-in, and unknown email', () {
      final upcomingCourse = buildClass();
      expect(
        () => service.markPresent(
          upcomingCourse,
          meetingId: 'm-today',
          email: 'annv@fpt.edu.vn',
          now: todayCheckIn,
        ),
        throwsStateError,
      );

      final activeWrongDay = buildClass(
        meetings: [m('m-today', 1, todayMorning, state: MeetingState.active)],
      );
      expect(
        () => service.markPresent(
          activeWrongDay,
          meetingId: 'm-today',
          email: 'annv@fpt.edu.vn',
          now: tomorrow,
        ),
        throwsStateError,
      );
      expect(
        () => service.markPresent(
          activeWrongDay,
          meetingId: 'm-today',
          email: 'stranger@fpt.edu.vn',
          now: todayCheckIn,
        ),
        throwsStateError,
      );
    });

    test('markManual records initial status once and refuses silent second overwrite', () {
      final active = buildClass(
        meetings: [m('m-today', 1, todayMorning, state: MeetingState.active)],
      );

      final marked = service.markManual(
        active,
        meetingId: 'm-today',
        rollNumber: ' se180002 ',
        status: AttendanceStatus.absent,
        now: todayCheckIn,
      );

      expect(
        marked.recordFor('m-today', 'SE180002')?.status,
        AttendanceStatus.absent,
      );
      expect(
        marked.recordFor('m-today', 'SE180002')?.source,
        AttendanceSource.manual,
      );

      expect(
        () => service.markManual(
          marked,
          meetingId: 'm-today',
          rollNumber: 'SE180002',
          status: AttendanceStatus.present,
          now: todayCheckIn,
        ),
        throwsStateError,
      );
      expect(
        () => service.markManual(
          active,
          meetingId: 'm-today',
          rollNumber: 'SE180001',
          status: AttendanceStatus.unmarked,
          now: todayCheckIn,
        ),
        throwsArgumentError,
      );
      expect(
        () => service.markManual(
          active,
          meetingId: 'm-today',
          rollNumber: 'SE999999',
          status: AttendanceStatus.present,
          now: todayCheckIn,
        ),
        throwsArgumentError,
      );
    });
  });

  group('AttendanceService closeMeeting, finalizeOverdueMeetings, overrideStatus & absenceRate', () {
    test('closeMeeting converts unmarked students to absent(finalize) and preserves marked cells', () {
      final course = buildClass(
        meetings: [m('m-today', 1, todayMorning, state: MeetingState.active)],
        attendance: {
          'm-today': {
            'se180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: todayCheckIn,
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.unmarked,
              source: AttendanceSource.manual,
              recordedAt: todayMorning,
            ),
          },
        },
      );

      final closed = service.closeMeeting(
        course,
        'm-today',
        now: todayCheckIn.add(const Duration(hours: 1)),
      );

      expect(closed.meetings.single.state, MeetingState.closed);
      expect(
        closed.recordFor('m-today', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      expect(
        closed.recordFor('m-today', 'SE180001')?.source,
        AttendanceSource.scan,
      );
      expect(closed.attendance['m-today']!.containsKey('se180001'), isFalse);

      for (final absentRoll in ['SE180002', 'SE180003']) {
        final rec = closed.recordFor('m-today', absentRoll);
        expect(rec?.status, AttendanceStatus.absent);
        expect(rec?.source, AttendanceSource.finalize);
      }
    });

    test('finalizeOverdueMeetings closes past upcoming/active meetings without touching today or future', () {
      final course = buildClass(
        meetings: [
          m('m1', 1, yesterday.subtract(const Duration(days: 3)), state: MeetingState.closed),
          m('m2', 2, yesterday, state: MeetingState.active),
          m('m3', 3, todayMorning, state: MeetingState.active),
          m('m4', 4, tomorrow, state: MeetingState.upcoming),
        ],
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: yesterday,
            ),
          },
          'm2': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: yesterday,
            ),
          },
        },
      );

      final finalized = service.finalizeOverdueMeetings(
        course,
        now: todayCheckIn,
      );

      expect(
        finalized.meetings.map((e) => (e.id, e.state)).toList(),
        [
          ('m1', MeetingState.closed),
          ('m2', MeetingState.closed),
          ('m3', MeetingState.active),
          ('m4', MeetingState.upcoming),
        ],
      );
      // m1 was already closed, so its missing cells are untouched.
      expect(finalized.recordFor('m1', 'SE180002'), isNull);
      // m2 was active & overdue, so unmarked students became absent.
      expect(
        finalized.recordFor('m2', 'SE180002')?.status,
        AttendanceStatus.absent,
      );
      expect(
        finalized.recordFor('m2', 'SE180003')?.status,
        AttendanceStatus.absent,
      );
    });

    test('overrideStatus validates reason, blocks upcoming, updates active/closed, and logs audit history', () {
      final course = buildClass(
        meetings: [
          m('m-up', 1, todayMorning, state: MeetingState.upcoming),
          m('m-act', 2, todayMorning, state: MeetingState.active),
          m('m-cls', 3, yesterday, state: MeetingState.closed),
        ],
        attendance: {
          'm-cls': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: yesterday,
            ),
          },
        },
      );

      expect(
        () => service.overrideStatus(
          course,
          meetingId: 'm-cls',
          rollNumber: 'SE180001',
          status: AttendanceStatus.present,
          reason: '   ',
          auditId: 'a0',
        ),
        throwsArgumentError,
      );
      expect(
        () => service.overrideStatus(
          course,
          meetingId: 'm-cls',
          rollNumber: 'SE180001',
          status: AttendanceStatus.unmarked,
          reason: 'Valid reason',
          auditId: 'a0',
        ),
        throwsArgumentError,
      );
      expect(
        () => service.overrideStatus(
          course,
          meetingId: 'm-up',
          rollNumber: 'SE180001',
          status: AttendanceStatus.present,
          reason: 'Valid reason',
          auditId: 'a0',
        ),
        throwsStateError,
      );

      // Override active cell from unmarked ('') -> 'P'
      final afterActive = service.overrideStatus(
        course,
        meetingId: 'm-act',
        rollNumber: 'se180002',
        status: AttendanceStatus.present,
        reason: '  QR scanner failed  ',
        auditId: 'audit-1',
        now: todayCheckIn,
      );
      expect(afterActive.auditEvents.single.oldValue, '');
      expect(afterActive.auditEvents.single.newValue, 'P');
      expect(afterActive.auditEvents.single.reason, 'QR scanner failed');
      expect(afterActive.auditEvents.single.rollNumber, 'SE180002');
      expect(
        afterActive.recordFor('m-act', 'SE180002')?.note,
        'QR scanner failed',
      );

      // Override closed cell from 'A' -> 'P'
      final afterClosed = service.overrideStatus(
        afterActive,
        meetingId: 'm-cls',
        rollNumber: 'SE180001',
        status: AttendanceStatus.present,
        reason: 'Medical excuse',
        auditId: 'audit-2',
        now: todayCheckIn,
      );
      expect(afterClosed.auditEvents, hasLength(2));
      expect(afterClosed.auditEvents[1].oldValue, 'A');
      expect(afterClosed.auditEvents[1].newValue, 'P');
      expect(afterClosed.auditEvents[1].action, 'attendance_override');
    });

    test('absenceRate computes exact fraction and handles empty meeting list', () {
      final noMeetings = buildClass(meetings: const []);
      expect(service.absenceRate(noMeetings, 'SE180001'), 0.0);

      final fourMeetings = buildClass(
        meetings: [
          m('m1', 1, yesterday, state: MeetingState.closed),
          m('m2', 2, todayMorning, state: MeetingState.closed),
          m('m3', 3, tomorrow, state: MeetingState.upcoming),
          m('m4', 4, tomorrow.add(const Duration(days: 2)), state: MeetingState.upcoming),
        ],
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: yesterday,
            ),
          },
          'm2': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: todayCheckIn,
            ),
          },
        },
      );

      expect(service.absenceRate(fourMeetings, 'SE180001'), closeTo(0.25, 1e-9));
      expect(service.absenceRate(fourMeetings, 'SE180002'), 0.0);
    });
  });
}
