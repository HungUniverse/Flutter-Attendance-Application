import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/schedule_service.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:fap_attendance/data/attendance_csv_exporter.dart';
import 'package:fap_attendance/data/roster_importer.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';

// Mocks for TeacherViewModel dependencies using mocktail
class MockAuthService extends Mock implements AuthService {}
class MockWorkspaceRepository extends Mock implements MobileWorkspaceRepository {}
class MockTelemetryService extends Mock implements TelemetryService {}
class MockConfigService extends Mock implements ConfigService {}
class MockNotificationService extends Mock implements NotificationService {}
class MockAttendanceLinkService extends Mock implements AttendanceLinkService {}
class MockDeviceService extends Mock implements DeviceService {}

void main() {
  setUpAll(() {
    registerFallbackValue(StackTrace.empty);
    registerFallbackValue(Exception('fallback'));
    registerFallbackValue(const TeacherIdentity('id', 'email@fpt.edu.vn', 'Teacher'));
    registerFallbackValue(TeacherWorkspace(
      id: 'w1',
      semester: 'FA26',
      semesterStart: DateTime(2026, 11, 3),
      classes: const [],
    ));
    registerFallbackValue(const FeatureSettings());
  });

  group('1. Unit Test - Models Serialization & Deserialization', () {
    test('should serialize and deserialize Student model correctly when valid json is provided', () {
      // Arrange
      const student = Student(
        rollNumber: 'SE194673',
        email: 'duongthanhduy@fpt.edu.vn',
        fullName: 'Dương Thành Thanh Duy',
        memberCode: 'DuyTT',
      );

      // Act
      final json = student.toJson();
      final fromJson = Student.fromJson(json);

      // Assert
      expect(fromJson.rollNumber, equals('SE194673'));
      expect(fromJson.email, equals('duongthanhduy@fpt.edu.vn'));
      expect(fromJson.fullName, equals('Dương Thành Thanh Duy'));
      expect(fromJson.memberCode, equals('DuyTT'));
      expect(fromJson.normalizedEmail, equals('duongthanhduy@fpt.edu.vn'));
    });

    test('should normalize email with whitespace and uppercase when accessed via normalizedEmail', () {
      // Arrange
      const student = Student(
        rollNumber: 'SE190001',
        email: '  NguyenVanA@FPT.EDU.VN  ',
        fullName: 'Nguyễn Văn A',
      );

      // Act & Assert
      expect(student.normalizedEmail, equals('nguyenvana@fpt.edu.vn'));
    });

    test('should serialize and deserialize Meeting model correctly with all states', () {
      // Arrange
      final now = DateTime(2026, 11, 13, 8, 30);
      final meeting = Meeting(
        id: 'm_01',
        number: 1,
        startAt: now,
        endAt: now.add(const Duration(hours: 2)),
        state: MeetingState.active,
      );

      // Act
      final json = meeting.toJson();
      final parsed = Meeting.fromJson(json);

      // Assert
      expect(parsed.id, equals('m_01'));
      expect(parsed.number, equals(1));
      expect(parsed.state, equals(MeetingState.active));
      expect(parsed.isOnDate(now), isTrue);
      expect(parsed.isBeforeDate(now.add(const Duration(days: 1))), isTrue);
      expect(parsed.isAfterDate(now.subtract(const Duration(days: 1))), isTrue);
    });

    test('should correctly roundtrip AttendanceRecord and AuditEvent models', () {
      // Arrange
      final recordedAt = DateTime(2026, 11, 13, 9, 0);
      final record = AttendanceRecord(
        status: AttendanceStatus.present,
        source: AttendanceSource.manual,
        recordedAt: recordedAt,
        note: 'Đã điểm danh bù',
      );

      final audit = AuditEvent(
        id: 'audit_01',
        createdAt: recordedAt,
        action: 'edit_status',
        reason: 'Sinh viên có đơn xin phép khám bệnh',
        rollNumber: 'SE194673',
        meetingId: 'm_01',
        oldValue: 'A',
        newValue: 'P',
      );

      // Act
      final recordJson = record.toJson();
      final recordParsed = AttendanceRecord.fromJson(recordJson);

      final auditJson = audit.toJson();
      final auditParsed = AuditEvent.fromJson(auditJson);

      // Assert
      expect(recordParsed.status, equals(AttendanceStatus.present));
      expect(recordParsed.source, equals(AttendanceSource.manual));
      expect(recordParsed.note, equals('Đã điểm danh bù'));

      expect(auditParsed.id, equals('audit_01'));
      expect(auditParsed.reason, equals('Sinh viên có đơn xin phép khám bệnh'));
      expect(auditParsed.oldValue, equals('A'));
      expect(auditParsed.newValue, equals('P'));
    });

    test('should correctly serialize and deserialize TeacherWorkspace and CourseClass', () {
      // Arrange
      final start = DateTime(2026, 11, 2, 7, 0);
      final meeting = Meeting(
        id: 'm1',
        number: 1,
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        state: MeetingState.active,
      );
      const student = Student(
        rollNumber: 'SE194673',
        email: 'duongthanhduy@fpt.edu.vn',
        fullName: 'Dương Thành Thanh Duy',
      );
      final courseClass = CourseClass(
        id: 'c1',
        courseCode: 'PRM393',
        classCode: 'SE1901',
        scheduleCode: '11',
        students: const [student],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
        meetings: [meeting],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: start,
            ),
          },
        },
      );
      final workspace = TeacherWorkspace(
        id: 'w1',
        semester: 'FA26',
        semesterStart: start,
        classes: [courseClass],
      );

      // Act
      final json = workspace.toJson();
      final parsed = TeacherWorkspace.fromJson(json);

      // Assert
      expect(parsed.id, equals('w1'));
      expect(parsed.semester, equals('FA26'));
      expect(parsed.classes.length, equals(1));
      final parsedClass = parsed.classes.first;
      expect(parsedClass.courseCode, equals('PRM393'));
      expect(parsedClass.classCode, equals('SE1901'));
      expect(parsedClass.students.first.rollNumber, equals('SE194673'));
      expect(parsedClass.recordFor('m1', 'SE194673')?.status, equals(AttendanceStatus.present));
    });
  });

  group('2. Unit Test - Helper & Utility Functions', () {
    test('should correctly convert AttendanceStatus enum to code string and vice versa', () {
      // Arrange & Act & Assert
      expect(attendanceCode(AttendanceStatus.present), equals('P'));
      expect(attendanceCode(AttendanceStatus.absent), equals('A'));
      expect(attendanceCode(AttendanceStatus.unmarked), equals(''));

      expect(attendanceStatusFromCode('P'), equals(AttendanceStatus.present));
      expect(attendanceStatusFromCode('p'), equals(AttendanceStatus.present));
      expect(attendanceStatusFromCode('  p  '), equals(AttendanceStatus.present));
      expect(attendanceStatusFromCode('A'), equals(AttendanceStatus.absent));
      expect(attendanceStatusFromCode('a'), equals(AttendanceStatus.absent));
      expect(attendanceStatusFromCode('  A  '), equals(AttendanceStatus.absent));
      expect(attendanceStatusFromCode(''), equals(AttendanceStatus.unmarked));
      expect(attendanceStatusFromCode('UNKNOWN'), equals(AttendanceStatus.unmarked));
    });

    test('should safely return 0 for dayGroup and dailySlot when scheduleCode is empty or too short', () {
      // Arrange
      final emptyRule = ScheduleRule(
        scheduleCode: '',
        semesterStart: DateTime(2026, 11, 2),
      );
      final singleCharRule = ScheduleRule(
        scheduleCode: '2',
        semesterStart: DateTime(2026, 11, 2),
      );

      // Act & Assert
      expect(emptyRule.dayGroup, equals(0));
      expect(emptyRule.dailySlot, equals(0));
      expect(singleCharRule.dayGroup, equals(2));
      expect(singleCharRule.dailySlot, equals(0));
    });

    test('should map correct slot times and weekday groups in ScheduleService', () {
      // Arrange
      final slot1 = ScheduleService.slotTimes[1]!;
      final slot2 = ScheduleService.slotTimes[2]!;
      final slot3 = ScheduleService.slotTimes[3]!;
      final slot4 = ScheduleService.slotTimes[4]!;

      // Act & Assert
      expect(ScheduleService.slotTimes.length, equals(4));
      expect(slot1.startHour, equals(7));
      expect(slot1.endHour, equals(9));
      expect(slot2.startHour, equals(9));
      expect(slot2.endHour, equals(11));
      expect(slot3.startHour, equals(12));
      expect(slot3.endHour, equals(14));
      expect(slot4.startHour, equals(15));
      expect(slot4.endHour, equals(17));

      expect(ScheduleService.weekdaysByGroup[1], equals([DateTime.monday, DateTime.thursday]));
      expect(ScheduleService.weekdaysByGroup[2], equals([DateTime.tuesday, DateTime.friday]));
      expect(ScheduleService.weekdaysByGroup[3], equals([DateTime.wednesday, DateTime.saturday]));
    });

    test('should generate correct count of meetings for schedule rule', () {
      // Arrange
      final scheduler = ScheduleService();
      final rule = ScheduleRule(
        scheduleCode: '11', // Mon & Thu, slot 1
        semesterStart: DateTime(2026, 11, 2), // Monday
        weeks: 10,
        meetingsPerWeek: 2,
      );

      // Act
      final meetings = scheduler.generate(rule, 'c1');

      // Assert
      expect(meetings.length, equals(20)); // 10 weeks * 2 meetings
      expect(meetings.first.number, equals(1));
      expect(meetings.last.number, equals(20));
      expect(meetings.first.startAt.weekday, equals(DateTime.monday));
      expect(meetings[1].startAt.weekday, equals(DateTime.thursday));
    });

    test('should encode and decode QrPayload correctly for rolling QR check-in', () {
      // Arrange
      final now = DateTime(2026, 11, 13, 8, 0).toUtc();
      final payload = QrPayload(
        endpoint: 'https://attendance.fpt.edu.vn/api',
        classId: 'c_PRM393',
        meetingId: 'm_01',
        token: 'auth-token-123',
        issuedAt: now,
        expiresAt: now.add(const Duration(minutes: 2)),
        certificateFingerprint: 'SHA256:abcd1234',
        mode: QrMode.otp,
      );

      // Act
      final encoded = payload.encode();
      final decoded = QrPayload.decode(encoded);

      // Assert
      expect(decoded.endpoint, equals(payload.endpoint));
      expect(decoded.classId, equals(payload.classId));
      expect(decoded.meetingId, equals(payload.meetingId));
      expect(decoded.token, equals(payload.token));
      expect(decoded.certificateFingerprint, equals(payload.certificateFingerprint));
      expect(decoded.mode, equals(QrMode.otp));
    });

    test('should generate CSV report with UTF-8 BOM byte marker and exact column schema', () {
      // Arrange
      final exporter = AttendanceCsvExporter();
      final start = DateTime(2026, 11, 13, 7, 30);
      final meeting = Meeting(
        id: 'm1',
        number: 1,
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        state: MeetingState.closed,
      );
      const student = Student(
        rollNumber: 'SE194673',
        email: 'duongthanhduy@fpt.edu.vn',
        fullName: 'Dương Thành Thanh Duy',
        memberCode: 'DuyTT',
      );
      final courseClass = CourseClass(
        id: 'c1',
        courseCode: 'PRM393',
        classCode: 'SE1901',
        scheduleCode: '11',
        students: const [student],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: start,
        ),
        meetings: [meeting],
        attendance: {
          'm1': {
            'SE194673': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: start,
            ),
          },
        },
      );
      final workspace = TeacherWorkspace(
        id: 'w1',
        semester: 'FA26',
        semesterStart: start,
        classes: [courseClass],
      );

      // Act
      final csv = exporter.encode(workspace, courseClass, meeting);

      // Assert
      expect(csv.startsWith('\uFEFF'), isTrue, reason: 'CSV must start with UTF-8 BOM for Excel compatibility');
      expect(csv, contains('schema_version,semester,course_code,class_code'));
      expect(csv, contains('SE194673,DuyTT,duongthanhduy@fpt.edu.vn,Dương Thành Thanh Duy,P'));
    });

    test('should throw RosterImportException when importing unsupported file format in RosterImporter', () {
      // Arrange
      final importer = RosterImporter();
      final invalidBytes = Uint8List.fromList([1, 2, 3, 4]);

      // Act & Assert
      expect(
        () => importer.importBytes(
          invalidBytes,
          fileName: 'roster.pdf',
          semester: 'FA26',
          semesterStart: DateTime(2026, 11, 2),
        ),
        throwsA(isA<RosterImportException>().having((e) => e.message, 'message', contains('.ods hoặc .xlsx'))),
      );
    });
  });

  group('3. Unit Test - State Management (TeacherViewModel)', () {
    late MockAuthService mockAuth;
    late MockWorkspaceRepository mockRepo;
    late MockTelemetryService mockTelemetry;
    late MockConfigService mockConfig;
    late MockNotificationService mockNotices;
    late MockAttendanceLinkService mockLinks;
    late MockDeviceService mockDevice;
    late TeacherIdentity teacherUser;
    late TeacherWorkspace testWorkspace;

    setUp(() {
      mockAuth = MockAuthService();
      mockRepo = MockWorkspaceRepository();
      mockTelemetry = MockTelemetryService();
      mockConfig = MockConfigService();
      mockNotices = MockNotificationService();
      mockLinks = MockAttendanceLinkService();
      mockDevice = MockDeviceService();

      teacherUser = const TeacherIdentity('t1', 'teacher@fpt.edu.vn', 'Thầy Duy');
      final start = DateTime(2026, 11, 13, 8, 0);
      testWorkspace = TeacherWorkspace(
        id: 'w1',
        semester: 'FA26',
        semesterStart: start,
        classes: [
          CourseClass(
            id: 'c1',
            courseCode: 'PRM393',
            classCode: 'SE1901',
            scheduleCode: '11',
            students: const [
              Student(rollNumber: 'S01', email: 's1@fpt.edu.vn', fullName: 'Sinh Viên Một'),
              Student(rollNumber: 'S02', email: 's2@fpt.edu.vn', fullName: 'Sinh Viên Hai'),
            ],
            scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
            meetings: [
              Meeting(
                id: 'm1',
                number: 1,
                startAt: start,
                endAt: start.add(const Duration(hours: 2)),
                state: MeetingState.active,
              ),
            ],
          ),
        ],
      );

      when(() => mockAuth.current).thenReturn(teacherUser);
      when(() => mockAuth.changes).thenAnswer((_) => const Stream.empty());
      when(() => mockNotices.opened).thenAnswer((_) => const Stream.empty());
      when(() => mockRepo.load(any())).thenAnswer((_) async => testWorkspace);
      when(() => mockRepo.loadLink(any())).thenAnswer((_) async => null);
      when(() => mockRepo.save(any(), any())).thenAnswer((_) async {});
      when(() => mockRepo.saveLink(any(), any())).thenAnswer((_) async {});
      when(() => mockConfig.current).thenReturn(const FeatureSettings());
      when(() => mockConfig.refresh()).thenAnswer((_) async {});
      when(() => mockNotices.start(any())).thenAnswer((_) async {});
      when(() => mockNotices.history(any())).thenAnswer((_) async => []);
      when(() => mockTelemetry.identify(any())).thenAnswer((_) async {});
      when(() => mockTelemetry.event(any(), any())).thenAnswer((_) async {});
      when(() => mockTelemetry.error(any(), any(), any())).thenAnswer((_) async {});
      when(() => mockLinks.configured).thenReturn(true);
    });

    test('should initialize and load workspace successfully into state', () async {
      // Arrange
      final vm = TeacherViewModel(
        auth: mockAuth,
        repository: mockRepo,
        telemetry: mockTelemetry,
        config: mockConfig,
        notifications: mockNotices,
        device: mockDevice,
        links: mockLinks,
        clock: () => DateTime(2026, 11, 13, 9, 0),
      );

      var notified = 0;
      vm.addListener(() => notified++);

      // Act
      await vm.initialize(timers: false);

      // Assert
      expect(vm.user?.email, equals('teacher@fpt.edu.vn'));
      expect(vm.workspace?.classes.length, equals(1));
      expect(vm.workspaceLoadFailed, isFalse);
      expect(notified, greaterThan(0));
    });

    test('should toggle attendance mode between link and manual and notify listeners', () async {
      // Arrange
      final vm = TeacherViewModel(
        auth: mockAuth,
        repository: mockRepo,
        telemetry: mockTelemetry,
        config: mockConfig,
        notifications: mockNotices,
        device: mockDevice,
        links: mockLinks,
      );
      await vm.initialize(timers: false);
      expect(vm.mode, equals(AttendanceMode.link));

      var notified = false;
      vm.addListener(() => notified = true);

      // Act
      vm.selectMode(AttendanceMode.manual);

      // Assert
      expect(vm.mode, equals(AttendanceMode.manual));
      expect(notified, isTrue);
    });

    test('should mark student attendance and persist updated state', () async {
      // Arrange
      final vm = TeacherViewModel(
        auth: mockAuth,
        repository: mockRepo,
        telemetry: mockTelemetry,
        config: mockConfig,
        notifications: mockNotices,
        device: mockDevice,
        links: mockLinks,
        clock: () => DateTime(2026, 11, 13, 9, 0),
      );
      await vm.initialize(timers: false);

      // Act
      final success = await vm.mark('c1', 'm1', 'S01', AttendanceStatus.present);

      // Assert
      expect(success, isTrue);
      expect(vm.course('c1').recordFor('m1', 'S01')?.status, equals(AttendanceStatus.present));
      verify(() => mockRepo.save('t1', any())).called(1);
    });

    test('should finalize attendance by closing meeting and auto-marking blank students absent', () async {
      // Arrange
      final vm = TeacherViewModel(
        auth: mockAuth,
        repository: mockRepo,
        telemetry: mockTelemetry,
        config: mockConfig,
        notifications: mockNotices,
        device: mockDevice,
        links: mockLinks,
        clock: () => DateTime(2026, 11, 13, 9, 0),
      );
      await vm.initialize(timers: false);
      await vm.mark('c1', 'm1', 'S01', AttendanceStatus.present);

      // Act: close meeting m1
      final closed = await vm.close('c1', 'm1');

      // Assert
      expect(closed, isTrue);
      expect(vm.meeting('c1', 'm1').state, equals(MeetingState.closed));
      expect(vm.course('c1').recordFor('m1', 'S01')?.status, equals(AttendanceStatus.present));
      expect(vm.course('c1').recordFor('m1', 'S02')?.status, equals(AttendanceStatus.absent),
          reason: 'Blank student S02 must be auto-filled with Absent (A)');
    });

    test('should record audit event with reason when editing attendance in closed meeting', () async {
      // Arrange
      final vm = TeacherViewModel(
        auth: mockAuth,
        repository: mockRepo,
        telemetry: mockTelemetry,
        config: mockConfig,
        notifications: mockNotices,
        device: mockDevice,
        links: mockLinks,
        clock: () => DateTime(2026, 11, 13, 9, 0),
      );
      await vm.initialize(timers: false);
      await vm.close('c1', 'm1');

      // Act
      final edited = await vm.edit(
        'c1',
        'm1',
        'S02',
        AttendanceStatus.present,
        'Có giấy nộp bài thi muộn hợp lệ',
      );

      // Assert
      expect(edited, isTrue);
      expect(vm.course('c1').recordFor('m1', 'S02')?.status, equals(AttendanceStatus.present));
      expect(vm.course('c1').recordFor('m1', 'S02')?.note, contains('Có giấy nộp bài thi'));
      expect(vm.course('c1').auditEvents, isNotEmpty);
      expect(vm.course('c1').auditEvents.last.reason, equals('Có giấy nộp bài thi muộn hợp lệ'));
    });
  });
}
