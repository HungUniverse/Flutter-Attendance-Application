import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/attendance_draft_store.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/report_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttendanceDraftStore persistence & concurrency serialization', () {
    late Directory tempDir;
    late AttendanceDraftStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('draft_store_test_');
      store = AttendanceDraftStore(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns empty map when draft file does not exist', () async {
      final loaded = await store.load('teacher-empty');
      expect(loaded, isEmpty);
    });

    test('rejects invalid UID path segments cleanly', () async {
      for (final badUid in ['', '../escape', 'a/b', 'u' * 129]) {
        await expectLater(
          () => store.load(badUid),
          throwsA(isA<AppProblem>()),
        );
        await expectLater(
          () => store.save(badUid, const {}),
          throwsA(isA<AppProblem>()),
        );
      }
    });

    test('roundtrips MeetingAttendanceDraft and serializes rapid sequential saves', () async {
      final t0 = DateTime(2026, 9, 14, 7, 30);
      final draft1 = MeetingAttendanceDraft(
        semester: 'FA26',
        classId: 'cls-1',
        meetingId: 'm1',
        startAt: t0,
        records: {
          'SE180001': AttendanceRecord(
            status: AttendanceStatus.present,
            source: AttendanceSource.manual,
            recordedAt: t0,
            note: 'Front row',
          ),
        },
      );
      final draft2 = MeetingAttendanceDraft(
        semester: 'FA26',
        classId: 'cls-1',
        meetingId: 'm1',
        startAt: t0,
        records: {
          'SE180001': AttendanceRecord(
            status: AttendanceStatus.present,
            source: AttendanceSource.manual,
            recordedAt: t0,
            note: 'Front row',
          ),
          'SE180002': AttendanceRecord(
            status: AttendanceStatus.absent,
            source: AttendanceSource.manual,
            recordedAt: t0.add(const Duration(minutes: 1)),
          ),
        },
      );

      // Fire back-to-back without awaiting the first -> serial queue preserves newest state.
      final f1 = store.save('teacher_1', {draft1.key: draft1});
      final f2 = store.save('teacher_1', {draft2.key: draft2});
      await Future.wait([f1, f2]);

      final loaded = await store.load('teacher_1');
      expect(loaded.keys, [draft2.key]);
      final restored = loaded[draft2.key]!;
      expect(restored.semester, 'FA26');
      expect(restored.classId, 'cls-1');
      expect(restored.meetingId, 'm1');
      expect(restored.records['SE180001']?.note, 'Front row');
      expect(
        restored.records['SE180002']?.status,
        AttendanceStatus.absent,
      );
    });
  });

  group('ReportDestination path safety, formatting, and metadata', () {
    test('builds deterministic folder paths, objectPaths, and metadata from factory', () {
      final date = DateTime(2026, 9, 7, 7, 30);
      final course = CourseClass(
        id: 'cls-1',
        courseCode: 'PRM393',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: const [],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: date),
        meetings: const [],
      );
      final meeting = Meeting(
        id: 'm1',
        number: 4,
        startAt: date,
        endAt: date.add(const Duration(hours: 2)),
        state: MeetingState.closed,
      );
      final ws = TeacherWorkspace(
        id: 'ws-1',
        semester: 'FA26',
        semesterStart: date,
        classes: [course],
      );

      final dest = ReportDestination.forExport(
        uid: 'teacher_1',
        workspace: ws,
        course: course,
        meeting: meeting,
        fileName: 'FA26_PRM393_SE1801_M04.pdf',
      );

      expect(dest.dateKey, '2026-09-07');
      expect(dest.meetingFolder, '2026-09-07_Slot-04');
      expect(
        dest.folderPath,
        'reports/teacher_1/FA26/PRM393/SE1801/2026-09-07_Slot-04',
      );
      expect(
        dest.objectPath,
        'reports/teacher_1/FA26/PRM393/SE1801/2026-09-07_Slot-04/FA26_PRM393_SE1801_M04.pdf',
      );
      expect(dest.metadata, {
        'ownerUid': 'teacher_1',
        'semester': 'FA26',
        'courseCode': 'PRM393',
        'classCode': 'SE1801',
        'meetingNumber': '4',
        'meetingDate': '2026-09-07',
        'storageLayout': 'semester-course-class-meeting-v1',
      });
    });

    test('supports csv, pdf, and json extensions while rejecting unsafe path characters and invalid meeting numbers', () {
      final d = DateTime(2026, 9, 7);
      for (final ext in ['csv', 'pdf', 'json']) {
        final dest = ReportDestination(
          ownerUid: 'u1',
          semester: 'FA26',
          courseCode: 'PRM393',
          classCode: 'SE1801',
          meetingNumber: 1,
          meetingDate: d,
          fileName: 'report_01.$ext',
        );
        expect(dest.fileName, endsWith('.$ext'));
      }

      expect(
        () => ReportDestination(
          ownerUid: '../u1',
          semester: 'FA26',
          courseCode: 'PRM393',
          classCode: 'SE1801',
          meetingNumber: 1,
          meetingDate: d,
          fileName: 'report.csv',
        ),
        throwsFormatException,
      );
      expect(
        () => ReportDestination(
          ownerUid: 'u1',
          semester: 'FA/26',
          courseCode: 'PRM393',
          classCode: 'SE1801',
          meetingNumber: 1,
          meetingDate: d,
          fileName: 'report.csv',
        ),
        throwsFormatException,
      );
      expect(
        () => ReportDestination(
          ownerUid: 'u1',
          semester: 'FA26',
          courseCode: 'PRM393',
          classCode: 'SE1801',
          meetingNumber: 0,
          meetingDate: d,
          fileName: 'report.csv',
        ),
        throwsFormatException,
      );
      expect(
        () => ReportDestination(
          ownerUid: 'u1',
          semester: 'FA26',
          courseCode: 'PRM393',
          classCode: 'SE1801',
          meetingNumber: 1,
          meetingDate: d,
          fileName: 'report.exe',
        ),
        throwsFormatException,
      );
      expect(
        () => ReportDestination(
          ownerUid: 'u1',
          semester: 'FA26',
          courseCode: 'PRM393',
          classCode: 'SE1801',
          meetingNumber: 1,
          meetingDate: d,
          fileName: '.hidden.csv',
        ),
        throwsFormatException,
      );
    });
  });
}
