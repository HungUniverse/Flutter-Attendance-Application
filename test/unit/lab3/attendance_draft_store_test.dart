import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/attendance_draft_store.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('MeetingAttendanceDraft serializes and deserializes with composite key', () {
    final start = DateTime.utc(2026, 9, 7, 7, 30);
    final draft = MeetingAttendanceDraft(
      semester: 'FA26',
      classId: 'cls-1',
      meetingId: 'm1',
      startAt: start,
      records: {
        'SE180001': AttendanceRecord(
          status: AttendanceStatus.present,
          source: AttendanceSource.manual,
          recordedAt: start,
          note: 'On time',
        ),
      },
    );

    expect(draft.key, 'FA26/cls-1/m1/${start.toIso8601String()}');
    final decoded = MeetingAttendanceDraft.fromJson(draft.toJson());
    expect(decoded.semester, 'FA26');
    expect(decoded.classId, 'cls-1');
    expect(decoded.meetingId, 'm1');
    expect(decoded.startAt, start);
    expect(decoded.records['SE180001']?.status, AttendanceStatus.present);
    expect(decoded.records['SE180001']?.note, 'On time');
  });

  test('AttendanceDraftStore returns empty map when missing and persists drafts atomically', () async {
    expect(await store.load('teacher-1'), isEmpty);

    final start = DateTime.utc(2026, 9, 7, 7, 30);
    final d1 = MeetingAttendanceDraft(
      semester: 'FA26',
      classId: 'cls-1',
      meetingId: 'm1',
      startAt: start,
      records: {
        'SE180001': AttendanceRecord(
          status: AttendanceStatus.present,
          source: AttendanceSource.manual,
          recordedAt: start,
        ),
      },
    );
    final d2 = MeetingAttendanceDraft(
      semester: 'FA26',
      classId: 'cls-1',
      meetingId: 'm2',
      startAt: start.add(const Duration(days: 3)),
      records: {
        'SE180002': AttendanceRecord(
          status: AttendanceStatus.absent,
          source: AttendanceSource.manual,
          recordedAt: start,
        ),
      },
    );

    // Concurrent serialized saves preserve latest snapshot
    await Future.wait([
      store.save('teacher-1', {d1.key: d1}),
      store.save('teacher-1', {d1.key: d1, d2.key: d2}),
    ]);

    final loaded = await store.load('teacher-1');
    expect(loaded.keys, containsAll([d1.key, d2.key]));
    expect(loaded[d2.key]?.records['SE180002']?.status, AttendanceStatus.absent);
  });

  test('AttendanceDraftStore rejects invalid uids', () async {
    await expectLater(store.load('../bad'), throwsA(isA<AppProblem>()));
    expect(() => store.save('bad/uid', {}), throwsA(isA<AppProblem>()));
  });
}
