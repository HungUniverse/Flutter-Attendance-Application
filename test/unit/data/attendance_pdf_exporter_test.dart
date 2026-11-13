import 'dart:io';

import 'package:fap_attendance/data/attendance_pdf_exporter.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AttendancePdfExporter exporter;

  setUp(() {
    exporter = AttendancePdfExporter();
  });

  TeacherWorkspace makeWorkspace({MeetingState state = MeetingState.closed}) {
    final meeting = Meeting(
      id: 'cls-pdf-m1',
      number: 3,
      startAt: DateTime(2026, 9, 14, 7, 30),
      endAt: DateTime(2026, 9, 14, 9, 15),
      state: state,
    );
    final cls = CourseClass(
      id: 'cls-pdf',
      courseCode: 'SWD392',
      classCode: 'SE1803',
      scheduleCode: '11',
      students: const [
        Student(
          rollNumber: 'SE180001',
          email: 'annv@fpt.edu.vn',
          fullName: 'Nguyễn Văn An',
        ),
        Student(
          rollNumber: 'SE180002',
          email: 'binhtt@fpt.edu.vn',
          fullName: 'Trần Thị Bình',
        ),
      ],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [meeting],
      attendance: state == MeetingState.closed
          ? {
              'cls-pdf-m1': {
                'SE180001': AttendanceRecord(
                  status: AttendanceStatus.present,
                  source: AttendanceSource.scan,
                  recordedAt: DateTime(2026, 9, 14, 7, 35),
                ),
                'SE180002': AttendanceRecord(
                  status: AttendanceStatus.absent,
                  source: AttendanceSource.manual,
                  recordedAt: DateTime(2026, 9, 14, 8, 0),
                  note: 'Nghỉ có phép',
                ),
              },
            }
          : const {},
    );

    return TeacherWorkspace(
      id: 'ws-pdf',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      teacherEmail: 'teacher@fpt.edu.vn',
      classes: [cls],
    );
  }

  test('encode produces valid PDF bytes starting with %PDF header', () async {
    final fontBytes = await File('assets/fonts/Roboto.ttf').readAsBytes();
    final fontData = ByteData.sublistView(fontBytes);
    final ws = makeWorkspace();
    final bytes = await exporter.encode(
      ws,
      ws.classes.first,
      ws.classes.first.meetings.first,
      fontData: fontData,
    );

    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('encode throws StateError if meeting is not closed', () async {
    final fontBytes = await File('assets/fonts/Roboto.ttf').readAsBytes();
    final fontData = ByteData.sublistView(fontBytes);
    final ws = makeWorkspace(state: MeetingState.upcoming);

    expect(
      () => exporter.encode(
        ws,
        ws.classes.first,
        ws.classes.first.meetings.first,
        fontData: fontData,
      ),
      throwsStateError,
    );
  });

  test('export writes PDF file to disk using bundled asset font', () async {
    final tempDir = await Directory.systemTemp.createTemp('pdf_exp_test_');
    try {
      final ws = makeWorkspace();
      final cls = ws.classes.first;
      final meeting = cls.meetings.first;
      final file = await exporter.export(tempDir, ws, cls, meeting);
      expect(await file.exists(), isTrue);
      expect(file.path, endsWith('FA26_SWD392_SE1803_M03_2026-09-14.pdf'));
      final content = await file.readAsBytes();
      expect(String.fromCharCodes(content.take(4)), '%PDF');
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
