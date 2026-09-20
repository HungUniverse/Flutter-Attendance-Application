import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/data/workspace_store.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'one stable session file evolves from working to final and correction',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'fap-attendance-test-',
      );
      addTearDown(() async {
        final systemTemp = Directory.systemTemp.absolute.path.toLowerCase();
        final target = root.absolute.path.toLowerCase();
        if (target.startsWith(systemTemp) &&
            target.contains('fap-attendance-test-')) {
          await root.delete(recursive: true);
        }
      });
      final meeting = Meeting(
        id: 'meeting-1',
        number: 1,
        startAt: DateTime(2026, 9, 7, 7),
        endAt: DateTime(2026, 9, 7, 9, 15),
        state: MeetingState.active,
      );
      final course = CourseClass(
        id: 'class-1',
        courseCode: 'PRM393',
        classCode: 'SE1917',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE000001',
            email: 'student@example.com',
            fullName: 'Student',
          ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [meeting],
      );
      final workspace = TeacherWorkspace(
        id: 'workspace-1',
        semester: 'FA26',
        semesterStart: DateTime(2026, 9, 7),
        classes: [course],
      );
      final store = WorkspaceStore(root);
      final workspaceFile = await store.saveWorkspace(workspace);
      await store.saveWorkspace(
        workspace.copyWith(teacherEmail: 'teacher@example.com'),
      );
      expect(File('${workspaceFile.path}.bak').existsSync(), isTrue);
      final working = await store.saveWorkingSession(
        workspace,
        course,
        meeting,
      );
      expect(working.path, endsWith('M01_2026-09-07.json'));
      var session = (jsonDecode(await working.readAsString()) as Map)
          .cast<String, Object?>();
      expect(session['revision'], 0);
      expect(session['state'], 'working');

      final closedMeeting = meeting.copyWith(state: MeetingState.closed);
      final finalizedCourse = course.copyWith(
        meetings: [closedMeeting],
        attendance: {
          meeting.id: {
            'SE000001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.simulator,
              recordedAt: DateTime.utc(2026, 9, 7, 7, 5),
            ),
          },
        },
      );
      final finalizedWorkspace = workspace.copyWith(classes: [finalizedCourse]);
      final finalFile = await store.saveFinalVersion(
        finalizedWorkspace,
        finalizedCourse,
        closedMeeting,
      );
      expect(finalFile.path, working.path);
      session = (jsonDecode(await finalFile.readAsString()) as Map)
          .cast<String, Object?>();
      expect(session['revision'], 1);
      expect(session['state'], 'final');

      final correctedCourse = finalizedCourse.copyWith(
        auditEvents: [
          AuditEvent(
            id: 'audit-1',
            createdAt: DateTime.utc(2026, 9, 7, 10),
            action: 'override_attendance',
            reason: 'Giảng viên xác nhận lại',
            rollNumber: 'SE000001',
            meetingId: meeting.id,
            oldValue: 'P',
            newValue: 'A',
          ),
        ],
      );
      await store.saveFinalVersion(
        finalizedWorkspace.copyWith(classes: [correctedCourse]),
        correctedCourse,
        closedMeeting,
      );
      session = (jsonDecode(await finalFile.readAsString()) as Map)
          .cast<String, Object?>();
      expect(session['revision'], 2);
      expect((session['auditEvents'] as List), hasLength(1));
      final primaryFiles = finalFile.parent
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList();
      expect(primaryFiles, hasLength(1));
    },
  );

  test('legacy versioned session files migrate to one stable file', () async {
    final root = await Directory.systemTemp.createTemp('fap-attendance-test-');
    addTearDown(() async {
      final systemTemp = Directory.systemTemp.absolute.path.toLowerCase();
      final target = root.absolute.path.toLowerCase();
      if (target.startsWith(systemTemp) &&
          target.contains('fap-attendance-test-')) {
        await root.delete(recursive: true);
      }
    });
    final meeting = Meeting(
      id: 'meeting-1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7),
      endAt: DateTime(2026, 9, 7, 9, 15),
      state: MeetingState.closed,
    );
    final course = CourseClass(
      id: 'class-1',
      courseCode: 'PRM393',
      classCode: 'SE1917',
      scheduleCode: '11',
      students: const [],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [meeting],
    );
    final workspace = TeacherWorkspace(
      id: 'workspace-1',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: [course],
    );
    final sessions = Directory(
      '${root.path}${Platform.pathSeparator}FA26${Platform.pathSeparator}classes${Platform.pathSeparator}PRM393_SE1917${Platform.pathSeparator}sessions',
    );
    await sessions.create(recursive: true);
    final legacy = File(
      '${sessions.path}${Platform.pathSeparator}M01_2026-09-07_v001_final.json',
    );
    await legacy.writeAsString(
      jsonEncode({
        'revision': 1,
        'savedAt': DateTime.utc(2026, 9, 7, 10).toIso8601String(),
      }),
    );

    final store = WorkspaceStore(root);
    expect(await store.migrateLegacySessions(workspace), 1);
    final stable = File(
      '${sessions.path}${Platform.pathSeparator}M01_2026-09-07.json',
    );
    expect(await stable.exists(), isTrue);
    expect(await legacy.exists(), isFalse);
    final session = (jsonDecode(await stable.readAsString()) as Map)
        .cast<String, Object?>();
    expect(session['revision'], 1);
    expect(session['state'], 'final');
    final recovery = Directory(
      '${root.path}${Platform.pathSeparator}.recovery${Platform.pathSeparator}FA26${Platform.pathSeparator}PRM393_SE1917${Platform.pathSeparator}sessions',
    );
    expect(
      recovery.listSync().whereType<File>().map((file) => file.path),
      anyElement(endsWith('M01_2026-09-07_v001_final.json')),
    );
  });

  test('deleting a class archives its local folder', () async {
    final root = await Directory.systemTemp.createTemp('fap-attendance-test-');
    addTearDown(() async {
      final systemTemp = Directory.systemTemp.absolute.path.toLowerCase();
      final target = root.absolute.path.toLowerCase();
      if (target.startsWith(systemTemp) &&
          target.contains('fap-attendance-test-')) {
        await root.delete(recursive: true);
      }
    });
    final course = CourseClass(
      id: 'class-1',
      courseCode: 'PRM393',
      classCode: 'SE1917',
      scheduleCode: '11',
      students: const [],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: const [],
    );
    final workspace = TeacherWorkspace(
      id: 'workspace-1',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: [course],
    );
    final store = WorkspaceStore(root);
    await store.saveWorkspace(workspace);
    final archived = await store.archiveClass(workspace, course);
    expect(archived, isNotNull);
    expect(await archived!.exists(), isTrue);
    expect(
      Directory('${root.path}/FA26/classes/PRM393_SE1917').existsSync(),
      isFalse,
    );
  });
}
