import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/data/workspace_store.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late WorkspaceStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ws_store_comp_');
    store = WorkspaceStore(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  TeacherWorkspace buildWorkspace({
    String semester = 'FA26',
    MeetingState state = MeetingState.upcoming,
  }) {
    final m1 = Meeting(
      id: 'cls-1-m1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7, 30),
      endAt: DateTime(2026, 9, 7, 9, 15),
      state: state,
    );
    final cls = CourseClass(
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
      meetings: [m1],
      attendance: state == MeetingState.closed
          ? {
              'cls-1-m1': {
                'SE180001': AttendanceRecord(
                  status: AttendanceStatus.present,
                  source: AttendanceSource.scan,
                  recordedAt: DateTime(2026, 9, 7, 7, 35),
                ),
              },
            }
          : const {},
    );
    return TeacherWorkspace(
      id: 'ws-$semester',
      semester: semester,
      semesterStart: DateTime(2026, 9, 7),
      teacherEmail: 'gv@fpt.edu.vn',
      classes: [cls],
    );
  }

  test('saveWorkspace, loadWorkspace, listSemesters, and loadMostRecentWorkspace', () async {
    expect(await store.listSemesters(), isEmpty);
    expect(await store.loadMostRecentWorkspace(), isNull);

    final ws1 = buildWorkspace(semester: 'SP26');
    await store.saveWorkspace(ws1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final ws2 = buildWorkspace(semester: 'FA26');
    await store.saveWorkspace(ws2);

    final semesters = await store.listSemesters();
    expect(semesters, containsAll(['SP26', 'FA26']));
    expect(semesters.first, 'FA26');

    final loaded = await store.loadMostRecentWorkspace();
    expect(loaded?.semester, 'FA26');

    final indexFile = File(p.join(tempDir.path, 'FA26', 'index.json'));
    expect(await indexFile.exists(), isTrue);
    final indexJson = jsonDecode(await indexFile.readAsString()) as Map;
    expect(indexJson['semester'], 'FA26');
    expect((indexJson['classes'] as List).length, 1);
  });

  test('loadWorkspace falls back to .bak when workspace.json is corrupted or missing', () async {
    final ws = buildWorkspace(semester: 'FA26');
    await store.saveWorkspace(ws);
    // Second save creates .bak
    await store.saveWorkspace(ws.copyWith(teacherEmail: 'v2@fpt.edu.vn'));

    final mainFile = File(p.join(tempDir.path, 'FA26', 'workspace.json'));
    await mainFile.writeAsString('{broken-json');

    final recovered = await store.loadWorkspace('FA26');
    expect(recovered, isNotNull);
    expect(recovered!.semester, 'FA26');

    await mainFile.delete();
    final fromBakOnly = await store.loadWorkspace('FA26');
    expect(fromBakOnly?.semester, 'FA26');
  });

  test('saveSource archives existing source files on overwrite', () async {
    final f1 = await store.saveSource(
      semester: 'FA26',
      fileName: 'C:\\path\\roster.xlsx',
      bytes: [1, 2, 3],
    );
    expect(await f1.readAsBytes(), [1, 2, 3]);

    final f2 = await store.saveSource(
      semester: 'FA26',
      fileName: 'roster.xlsx',
      bytes: [4, 5, 6],
    );
    expect(await f2.readAsBytes(), [4, 5, 6]);

    final archiveDir = Directory(p.join(tempDir.path, 'FA26', 'source', 'archive'));
    expect(await archiveDir.exists(), isTrue);
    expect(await archiveDir.list().length, 1);
  });

  test('archiveClass moves class directory to trash and returns null if missing', () async {
    final ws = buildWorkspace(semester: 'FA26');
    await store.saveWorkspace(ws);

    final archived = await store.archiveClass(ws, ws.classes.first);
    expect(archived, isNotNull);
    expect(await archived!.exists(), isTrue);

    final secondAttempt = await store.archiveClass(ws, ws.classes.first);
    expect(secondAttempt, isNull);
  });

  test('saveWorkingSession, saveFinalVersion, and migrateLegacySessions manage single-file snapshots', () async {
    final ws = buildWorkspace(semester: 'FA26', state: MeetingState.closed);
    final cls = ws.classes.first;
    final meeting = cls.meetings.first;

    final working = await store.saveWorkingSession(ws, cls, meeting);
    expect(await working.exists(), isTrue);
    var decoded = jsonDecode(await working.readAsString()) as Map;
    expect(decoded['revision'], 0);

    final v1 = await store.saveFinalVersion(ws, cls, meeting);
    decoded = jsonDecode(await v1.readAsString()) as Map;
    expect(decoded['revision'], 1);
    expect(decoded['state'], 'final');

    final v2 = await store.saveFinalVersion(ws, cls, meeting);
    decoded = jsonDecode(await v2.readAsString()) as Map;
    expect(decoded['revision'], 2);

    // Create a legacy file and verify migrateLegacySessions archives it
    final sessionsDir = working.parent;
    final legacyFile = File(
      p.join(sessionsDir.path, 'M01_2026-09-07_v005_final.json'),
    );
    await legacyFile.writeAsString(jsonEncode({'revision': 5, 'finalizedAt': '2026-09-07T10:00:00Z'}));

    final migratedCount = await store.migrateLegacySessions(ws);
    expect(migratedCount, 1);
    expect(await legacyFile.exists(), isFalse);
  });

  test('exportDirectory creates class exports folder', () async {
    final ws = buildWorkspace(semester: 'FA26');
    final dir = await store.exportDirectory(ws, ws.classes.first);
    expect(await dir.exists(), isTrue);
    expect(dir.path, endsWith(p.join('PRM392_SE1801', 'exports')));
  });
}
