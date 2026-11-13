import 'dart:io';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAuth implements AuthService {
  @override
  TeacherIdentity? current;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {
    current = const TeacherIdentity('teacher-1', 'gv@fpt.edu.vn', 'Giảng viên');
  }

  @override
  Future<void> signOut() async {
    current = null;
  }

  @override
  Future<String> token() async => 'stub-token';
}

void main() {
  late Directory tempDir;
  late AttendanceController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('att_ctrl_test_');
    controller = AttendanceController(
      teacherAuth: _StubAuth(),
      documentsDirectory: tempDir,
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  TeacherWorkspace makeWorkspace({
    required DateTime meetingStart,
    MeetingState state = MeetingState.upcoming,
  }) {
    return TeacherWorkspace(
      id: 'ws-ctrl',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      teacherEmail: 'gv@fpt.edu.vn',
      classes: [
        CourseClass(
          id: 'cls-1',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          scheduleCode: '11',
          students: const [
            Student(
              rollNumber: 'SE180001',
              email: 'an@fpt.edu.vn',
              fullName: 'Nguyen Van An',
            ),
            Student(
              rollNumber: 'SE180002',
              email: 'binh@fpt.edu.vn',
              fullName: 'Tran Thi Binh',
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
              startAt: meetingStart,
              endAt: meetingStart.add(const Duration(hours: 2)),
              state: state,
            ),
          ],
        ),
        CourseClass(
          id: 'cls-2',
          courseCode: 'SWD392',
          classCode: 'SE1802',
          scheduleCode: '22',
          students: const [],
          scheduleRule: ScheduleRule(
            scheduleCode: '22',
            semesterStart: DateTime(2026, 9, 7),
          ),
          meetings: [
            Meeting(
              id: 'cls-2-m1',
              number: 1,
              startAt: meetingStart,
              endAt: meetingStart.add(const Duration(hours: 2)),
              state: MeetingState.upcoming,
            ),
          ],
        ),
      ],
    );
  }

  test('starts meeting, marks present, closes meeting, overrides status, and exports CSV', () async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
    controller.workspace = makeWorkspace(meetingStart: todayStart);
    await controller.save();

    await controller.startMeeting('cls-1', 'cls-1-m1');
    expect(
      controller.meetingById('cls-1', 'cls-1-m1').state,
      MeetingState.active,
    );

    // Cannot start a second active meeting across classes
    await expectLater(
      controller.startMeeting('cls-2', 'cls-2-m1'),
      throwsStateError,
    );

    await controller.markPresent('cls-1', 'cls-1-m1', 'an@fpt.edu.vn');
    expect(
      controller.classById('cls-1').recordFor('cls-1-m1', 'SE180001')?.status,
      AttendanceStatus.present,
    );

    await controller.closeMeeting('cls-1', 'cls-1-m1');
    expect(
      controller.meetingById('cls-1', 'cls-1-m1').state,
      MeetingState.closed,
    );
    expect(
      controller.classById('cls-1').recordFor('cls-1-m1', 'SE180002')?.status,
      AttendanceStatus.absent,
    );
    expect(controller.absenceRate('cls-1', 'SE180002'), 1.0);

    await controller.overrideStatus(
      classId: 'cls-1',
      meetingId: 'cls-1-m1',
      rollNumber: 'SE180002',
      status: AttendanceStatus.present,
      reason: 'Late arrival approved',
    );
    expect(controller.absenceRate('cls-1', 'SE180002'), 0.0);

    final csvFile = await controller.exportMeeting('cls-1', 'cls-1-m1');
    expect(await csvFile.exists(), isTrue);
    expect(controller.lastMessage, contains('Đã xuất'));
  });

  test('finalizeOverdueMeetings closes past meetings and updates lastMessage', () async {
    final past = DateTime.now().subtract(const Duration(days: 3));
    controller.workspace = makeWorkspace(meetingStart: past);
    await controller.save();

    final count = await controller.finalizeOverdueMeetings();
    expect(count, 2);
    expect(
      controller.meetingById('cls-1', 'cls-1-m1').state,
      MeetingState.closed,
    );
    expect(controller.lastMessage, contains('Đã tự động chốt 2 slot quá ngày'));
  });

  test('updateSchedule regenerates upcoming meetings and blocks if any slot started', () async {
    final future = DateTime.now().add(const Duration(days: 3));
    controller.workspace = makeWorkspace(meetingStart: future);
    await controller.save();

    final newRule = ScheduleRule(
      scheduleCode: '23',
      semesterStart: DateTime(2026, 9, 7),
      weeks: 3,
      meetingsPerWeek: 2,
    );
    await controller.updateSchedule('cls-1', newRule);
    expect(controller.classById('cls-1').meetings, hasLength(6));
    expect(controller.classById('cls-1').scheduleRule.scheduleCode, '23');

    // Now make one meeting closed and confirm updateSchedule rejects
    controller.workspace = makeWorkspace(
      meetingStart: future,
      state: MeetingState.closed,
    );
    await expectLater(
      controller.updateSchedule('cls-1', newRule),
      throwsStateError,
    );
  });

  test('deleteClass archives class and blocks deleting class with active meeting', () async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
    controller.workspace = makeWorkspace(
      meetingStart: todayStart,
      state: MeetingState.active,
    );
    await controller.save();

    await expectLater(controller.deleteClass('cls-1'), throwsStateError);

    await controller.deleteClass('cls-2');
    expect(controller.workspace!.classes.map((c) => c.id), ['cls-1']);
    expect(controller.lastMessage, contains('Đã xóa lớp SWD392'));
  });

  test('loadSemester reloads saved semester from disk', () async {
    final future = DateTime.now().add(const Duration(days: 5));
    controller.workspace = makeWorkspace(meetingStart: future);
    await controller.save();

    controller.workspace = null;
    await controller.loadSemester('FA26');
    expect(controller.workspace, isNotNull);
    expect(controller.workspace!.semester, 'FA26');
  });
}
