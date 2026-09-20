import 'package:fap_attendance/data/attendance_csv_exporter.dart';
import 'package:fap_attendance/domain/attendance_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:fap_attendance/domain/schedule_service.dart';
import 'package:fap_attendance/network/lan_certificate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final student = const Student(
    rollNumber: 'SE000001',
    email: 'student@example.com',
    fullName: 'Nguyễn Văn A',
  );

  test('schedule 11 maps Monday and Thursday slot 1', () {
    final rule = ScheduleRule(
      scheduleCode: '11',
      semesterStart: DateTime(2026, 9, 7),
      weeks: 2,
    );
    final meetings = ScheduleService().generate(rule, 'class');
    expect(meetings.length, 4);
    expect(meetings.map((m) => m.startAt.weekday), [1, 4, 1, 4]);
    expect(meetings.first.startAt.hour, 7);
  });

  test('schedule supports one selected weekday, holiday and makeup', () {
    final rule = ScheduleRule(
      scheduleCode: '22',
      semesterStart: DateTime(2026, 9, 7),
      weeks: 2,
      meetingsPerWeek: 1,
      weekdays: const [DateTime.friday],
      excludedDates: [DateTime(2026, 9, 11)],
      additionalStarts: [DateTime(2026, 9, 12)],
    );
    final meetings = ScheduleService().generate(rule, 'class');
    expect(meetings.length, 2);
    expect(meetings.first.startAt, DateTime(2026, 9, 12, 9, 30));
    expect(meetings.last.startAt.weekday, DateTime.friday);
  });

  test('each class keeps an independent schedule override', () {
    CourseClass buildClass(String id, ScheduleRule rule) => CourseClass(
      id: id,
      courseCode: 'PRM393',
      classCode: id,
      scheduleCode: rule.scheduleCode,
      students: [student],
      scheduleRule: rule,
      meetings: ScheduleService().generate(rule, id),
    );

    final oneMeetingRule = ScheduleRule(
      scheduleCode: '11',
      semesterStart: DateTime(2026, 9, 7),
      weeks: 5,
      meetingsPerWeek: 1,
      weekdays: const [DateTime.monday],
    );
    final twoMeetingRule = ScheduleRule(
      scheduleCode: '22',
      semesterStart: DateTime(2026, 9, 7),
      weeks: 10,
      meetingsPerWeek: 2,
      weekdays: const [DateTime.tuesday, DateTime.friday],
    );
    final workspace = TeacherWorkspace(
      id: 'workspace',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: [
        buildClass('SE1917', oneMeetingRule),
        buildClass('SE1918', twoMeetingRule),
      ],
    );

    final restored = TeacherWorkspace.decode(workspace.toPrettyJson());
    expect(restored.classes[0].scheduleRule.weeks, 5);
    expect(restored.classes[0].scheduleRule.meetingsPerWeek, 1);
    expect(restored.classes[0].meetings, hasLength(5));
    expect(restored.classes[1].scheduleRule.weeks, 10);
    expect(restored.classes[1].scheduleRule.meetingsPerWeek, 2);
    expect(restored.classes[1].meetings, hasLength(20));
  });

  test('attendance can only start on the meeting date', () {
    CourseClass courseAt(DateTime start) => CourseClass(
      id: 'FA26_PRM393_SE1917',
      courseCode: 'PRM393',
      classCode: 'SE1917',
      scheduleCode: '11',
      students: [student],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [
        Meeting(
          id: 'm1',
          number: 1,
          startAt: start,
          endAt: start.add(const Duration(hours: 2, minutes: 15)),
        ),
      ],
    );

    final service = AttendanceService();
    final today = DateTime(2026, 9, 17, 10);
    final active = service.startMeeting(
      courseAt(DateTime(2026, 9, 17, 7)),
      'm1',
      now: today,
    );
    expect(active.meetings.single.state, MeetingState.active);
    expect(
      () => service.startMeeting(
        courseAt(DateTime(2026, 9, 16, 7)),
        'm1',
        now: today,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => service.startMeeting(
        courseAt(DateTime(2026, 9, 18, 7)),
        'm1',
        now: today,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => service.markPresent(
        active,
        meetingId: 'm1',
        email: student.email,
        now: DateTime(2026, 9, 18),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('an upcoming slot cannot be edited manually', () {
    final course = CourseClass(
      id: 'FA26_PRM393_SE1917',
      courseCode: 'PRM393',
      classCode: 'SE1917',
      scheduleCode: '11',
      students: [student],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [
        Meeting(
          id: 'm1',
          number: 1,
          startAt: DateTime(2026, 9, 18, 7),
          endAt: DateTime(2026, 9, 18, 9, 15),
        ),
      ],
    );
    expect(
      () => AttendanceService().overrideStatus(
        course,
        meetingId: 'm1',
        rollNumber: student.rollNumber,
        status: AttendanceStatus.present,
        reason: 'Test',
        auditId: 'audit-1',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('overdue slots are finalized with every blank student absent', () {
    final secondStudent = const Student(
      rollNumber: 'SE000002',
      email: 'student2@example.com',
      fullName: 'Trần Văn B',
    );
    final course = CourseClass(
      id: 'FA26_PRM393_SE1917',
      courseCode: 'PRM393',
      classCode: 'SE1917',
      scheduleCode: '11',
      students: [student, secondStudent],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [
        Meeting(
          id: 'm1',
          number: 1,
          startAt: DateTime(2026, 9, 16, 7),
          endAt: DateTime(2026, 9, 16, 9, 15),
        ),
      ],
    );
    final finalized = AttendanceService().finalizeOverdueMeetings(
      course,
      now: DateTime(2026, 9, 17),
    );
    expect(finalized.meetings.single.state, MeetingState.closed);
    expect(
      finalized.recordFor('m1', student.rollNumber)?.status,
      AttendanceStatus.absent,
    );
    expect(
      finalized.recordFor('m1', secondStudent.rollNumber)?.status,
      AttendanceStatus.absent,
    );
  });

  test('close fills blank students with A and CSV has UTF-8 BOM', () {
    final meeting = Meeting(
      id: 'm1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7),
      endAt: DateTime(2026, 9, 7, 9, 15),
      state: MeetingState.active,
    );
    var course = CourseClass(
      id: 'FA26_PRM393_SE1917',
      courseCode: 'PRM393',
      classCode: 'SE1917',
      scheduleCode: '11',
      students: [student],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [meeting],
    );
    course = AttendanceService().closeMeeting(course, 'm1');
    final workspace = TeacherWorkspace(
      id: 'w1',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: [course],
    );
    final csv = AttendanceCsvExporter().encode(
      workspace,
      course,
      course.meetings.first,
    );
    expect(
      course.recordFor('m1', student.rollNumber)!.status,
      AttendanceStatus.absent,
    );
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('Nguyễn Văn A,A,'));
  });

  test('rolling QR expires and challenge is one-time/device-bound', () {
    final issuer = RollingQrIssuer(secret: 'test-secret');
    final now = DateTime.utc(2026, 9, 7, 0, 0);
    final payload = issuer.issue(
      endpoint: 'https://192.168.1.2:8787',
      classId: 'c1',
      meetingId: 'm1',
      certificateFingerprint: 'abc',
      mode: QrMode.otp,
      now: now,
    );
    final store = ChallengeStore(issuer);
    final challenge = store.create(payload, 'device-1', now: now);
    expect(
      () => store.consume(
        challenge.id,
        deviceId: 'device-2',
        email: 'student@example.com',
        otp: challenge.otp,
        now: now,
      ),
      throwsStateError,
    );
    store.consume(
      challenge.id,
      deviceId: 'device-1',
      email: 'student@example.com',
      otp: challenge.otp,
      now: now,
    );
    expect(
      store
          .consume(
            challenge.id,
            deviceId: 'device-1',
            email: 'student@example.com',
            otp: challenge.otp,
            now: now,
          )
          .used,
      isTrue,
    );
    expect(
      issuer.verify(payload, now: now.add(const Duration(seconds: 21))),
      isFalse,
    );
  });

  test('generates a pinned LAN certificate', () {
    final certificate = LanCertificate.create('192.168.1.20');
    expect(certificate.fingerprint.replaceAll(':', ''), hasLength(40));
  });
}
