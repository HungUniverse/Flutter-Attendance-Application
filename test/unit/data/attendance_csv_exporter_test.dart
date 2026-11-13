import 'dart:io';

import 'package:csv/csv.dart';
import 'package:fap_attendance/data/attendance_csv_exporter.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AttendanceCsvExporter exporter;

  setUp(() {
    exporter = AttendanceCsvExporter();
  });

  TeacherWorkspace makeWorkspace({
    required MeetingState meetingState,
    bool includeAllRecords = true,
  }) {
    final meeting = Meeting(
      id: 'cls-1-m1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7, 30),
      endAt: DateTime(2026, 9, 7, 9, 15),
      state: meetingState,
    );
    final course = CourseClass(
      id: 'cls-1',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      scheduleCode: '11',
      students: const [
        Student(
          rollNumber: 'SE180001',
          memberCode: 'AnNV',
          email: 'annv@fpt.edu.vn',
          fullName: '=HYPERLINK("http://bad")',
        ),
        Student(
          rollNumber: 'SE180002',
          memberCode: 'BinhTT',
          email: 'binhtt@fpt.edu.vn',
          fullName: 'Tran, Thi Binh',
        ),
      ],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [meeting],
      attendance: includeAllRecords
          ? {
              'cls-1-m1': {
                'SE180001': AttendanceRecord(
                  status: AttendanceStatus.present,
                  source: AttendanceSource.scan,
                  recordedAt: DateTime.utc(2026, 9, 7, 7, 45),
                ),
                'SE180002': AttendanceRecord(
                  status: AttendanceStatus.absent,
                  source: AttendanceSource.finalize,
                  recordedAt: DateTime.utc(2026, 9, 7, 9, 15),
                ),
              },
            }
          : const {},
    );
    return TeacherWorkspace(
      id: 'ws-1',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      teacherEmail: 'gv@fpt.edu.vn',
      classes: [course],
    );
  }

  test('encode generates UTF-8 BOM CSV with formula neutralization and exact columns', () {
    final ws = makeWorkspace(meetingState: MeetingState.closed);
    final cls = ws.classes.first;
    final meeting = cls.meetings.first;

    final csv = exporter.encode(ws, cls, meeting);
    expect(csv.startsWith('\uFEFF'), isTrue);

    final parsed = const CsvToListConverter().convert(csv.substring(1));
    expect(parsed, hasLength(3));
    expect(parsed.first, [
      'schema_version',
      'semester',
      'course_code',
      'class_code',
      'schedule_code',
      'meeting_id',
      'meeting_number',
      'meeting_date',
      'start_time',
      'end_time',
      'roll_number',
      'member_code',
      'email',
      'full_name',
      'status',
      'recorded_at',
      'source',
    ]);
    expect(parsed[1][10], 'SE180001');
    expect(parsed[1][13], "'=HYPERLINK(\"http://bad\")");
    expect(parsed[1][14], 'P');
    expect(parsed[1][16], 'scan');
    expect(parsed[2][10], 'SE180002');
    expect(parsed[2][13], 'Tran, Thi Binh');
    expect(parsed[2][14], 'A');
    expect(parsed[2][16], 'finalize');
  });

  test('encode rejects non-closed meetings or meetings with unmarked students', () {
    final activeWs = makeWorkspace(meetingState: MeetingState.active);
    expect(
      () => exporter.encode(
        activeWs,
        activeWs.classes.first,
        activeWs.classes.first.meetings.first,
      ),
      throwsStateError,
    );

    final incompleteWs = makeWorkspace(
      meetingState: MeetingState.closed,
      includeAllRecords: false,
    );
    expect(
      () => exporter.encode(
        incompleteWs,
        incompleteWs.classes.first,
        incompleteWs.classes.first.meetings.first,
      ),
      throwsStateError,
    );
  });

  test('export writes CSV file with expected naming convention atomically', () async {
    final tempDir = await Directory.systemTemp.createTemp('csv_exp_test_');
    try {
      final ws = makeWorkspace(meetingState: MeetingState.closed);
      final cls = ws.classes.first;
      final meeting = cls.meetings.first;

      final file = await exporter.export(tempDir, ws, cls, meeting);
      expect(await file.exists(), isTrue);
      expect(file.path, endsWith('FA26_PRM392_SE1801_M01_2026-09-07.csv'));
      final content = await file.readAsString();
      expect(content, contains('SE180001'));
      expect(content, contains('SE180002'));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
