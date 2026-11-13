import 'dart:io';
import 'dart:typed_data';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/mobile_workspace_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late FileMobileWorkspaceRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mob_repo_test_');
    repo = FileMobileWorkspaceRepository(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  TeacherWorkspace makeWorkspace() {
    final meeting = Meeting(
      id: 'm1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7, 30),
      endAt: DateTime(2026, 9, 7, 9, 15),
      state: MeetingState.closed,
    );
    final course = CourseClass(
      id: 'cls-1',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      scheduleCode: '11',
      students: const [
        Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'An'),
      ],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [meeting],
      attendance: {
        'm1': {
          'SE180001': AttendanceRecord(
            status: AttendanceStatus.present,
            source: AttendanceSource.scan,
            recordedAt: DateTime(2026, 9, 7, 7, 35),
          ),
        },
      },
    );
    return TeacherWorkspace(
      id: 'ws-mob',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: [course],
    );
  }

  test('save, listSemesters, load, saveSource, export (csv/json), and archive work per uid', () async {
    final ws = makeWorkspace();
    await repo.save('teacher-1', ws);
    await repo.saveSource('teacher-1', 'FA26', 'roster.xlsx', Uint8List.fromList([1, 2, 3]));

    expect(await repo.listSemesters('teacher-1'), ['FA26']);
    expect(await repo.listSemesters('teacher-2'), isEmpty);

    final loaded = await repo.load('teacher-1', semester: 'FA26');
    expect(loaded?.id, 'ws-mob');

    final csvFile = await repo.export(
      'teacher-1',
      ws,
      ws.classes.first,
      ws.classes.first.meetings.first,
      'csv',
    );
    expect(await csvFile.exists(), isTrue);
    expect(csvFile.path, endsWith('.csv'));

    final jsonFile = await repo.export(
      'teacher-1',
      ws,
      ws.classes.first,
      ws.classes.first.meetings.first,
      'json',
    );
    expect(await jsonFile.exists(), isTrue);
    expect(jsonFile.path, endsWith('.json'));

    await expectLater(
      repo.export(
        'teacher-1',
        ws,
        ws.classes.first,
        ws.classes.first.meetings.first,
        'xlsx',
      ),
      throwsA(isA<AppProblem>()),
    );

    await repo.archive('teacher-1', ws, ws.classes.first);
  });

  test('saveLink and loadLink manage active-link.json and reject unsafe identifiers', () async {
    expect(await repo.loadLink('teacher-1'), isNull);

    final session = LinkSession(
      id: 'link-1',
      classId: 'cls-1',
      meetingId: 'm1',
      url: 'https://fap.web.app/s/link-1',
      expiresAt: DateTime.utc(2026, 9, 7, 9, 0),
    );
    await repo.saveLink('teacher-1', session);
    final loaded = await repo.loadLink('teacher-1');
    expect(loaded?.id, 'link-1');

    await repo.saveLink('teacher-1', null);
    expect(await repo.loadLink('teacher-1'), isNull);

    expect(() => repo.load('../bad'), throwsA(isA<AppProblem>()));
  });
}
