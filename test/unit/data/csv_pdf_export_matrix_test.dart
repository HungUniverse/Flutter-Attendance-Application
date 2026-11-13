import 'dart:io';

import 'package:fap_attendance/data/attendance_csv_exporter.dart';
import 'package:fap_attendance/data/attendance_pdf_exporter.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final csvExporter = AttendanceCsvExporter();
  final pdfExporter = AttendancePdfExporter();
  final baseStart = DateTime(2026, 9, 14, 7, 30);

  Student s(
    String roll, {
    String memberCode = '',
    String email = '',
    String fullName = '',
  }) => Student(
    rollNumber: roll,
    memberCode: memberCode,
    email: email.isEmpty ? '${roll.toLowerCase()}@fpt.edu.vn' : email,
    fullName: fullName.isEmpty ? 'Student $roll' : fullName,
  );

  Meeting m(
    String id,
    int number, {
    MeetingState state = MeetingState.closed,
  }) => Meeting(
    id: id,
    number: number,
    startAt: baseStart.add(Duration(days: (number - 1) * 3)),
    endAt: baseStart.add(Duration(days: (number - 1) * 3, hours: 2)),
    state: state,
  );

  ({
    TeacherWorkspace workspace,
    CourseClass course,
    Meeting meeting,
  }) buildSample({
    MeetingState meetingState = MeetingState.closed,
    List<Student>? students,
    Map<String, Map<String, AttendanceRecord>>? attendance,
    String semester = 'FA26',
  }) {
    final roster =
        students ??
        [
          s(
            'SE180001',
            memberCode: 'AnNVSE180001',
            email: 'annv@fpt.edu.vn',
            fullName: 'Nguyễn Văn An',
          ),
          s(
            'SE180002',
            memberCode: '=CMD("calc")',
            email: '+evil@fpt.edu.vn',
            fullName: 'Trần, "Bình"',
          ),
        ];
    final meeting = m('m1', 1, state: meetingState);
    final course = CourseClass(
      id: 'cls-exp',
      courseCode: 'PRM393',
      classCode: 'SE1801',
      scheduleCode: '11',
      students: roster,
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: baseStart,
      ),
      meetings: [meeting],
      attendance:
          attendance ??
          {
            'm1': {
              'se180001': AttendanceRecord(
                status: AttendanceStatus.present,
                source: AttendanceSource.scan,
                recordedAt: DateTime.utc(2026, 9, 14, 0, 35, 10),
              ),
              'SE180002': AttendanceRecord(
                status: AttendanceStatus.absent,
                source: AttendanceSource.manual,
                recordedAt: DateTime.utc(2026, 9, 14, 1, 0, 0),
                note: 'Nghỉ không phép',
              ),
            },
          },
    );
    final workspace = TeacherWorkspace(
      id: 'ws-exp',
      semester: semester,
      semesterStart: baseStart,
      teacherEmail: 'gv@fpt.edu.vn',
      classes: [course],
    );
    return (workspace: workspace, course: course, meeting: meeting);
  }

  group('AttendanceCsvExporter encoding & atomic disk export', () {
    test('rejects upcoming, active, missing, or unmarked attendance cells', () {
      final active = buildSample(meetingState: MeetingState.active);
      expect(
        () => csvExporter.encode(
          active.workspace,
          active.course,
          active.meeting,
        ),
        throwsStateError,
      );

      final upcoming = buildSample(meetingState: MeetingState.upcoming);
      expect(
        () => csvExporter.encode(
          upcoming.workspace,
          upcoming.course,
          upcoming.meeting,
        ),
        throwsStateError,
      );

      final incomplete = buildSample(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: baseStart,
            ),
          },
        },
      );
      expect(
        () => csvExporter.encode(
          incomplete.workspace,
          incomplete.course,
          incomplete.meeting,
        ),
        throwsStateError,
      );

      final unmarkedCell = buildSample(
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: baseStart,
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.unmarked,
              source: AttendanceSource.manual,
              recordedAt: baseStart,
            ),
          },
        },
      );
      expect(
        () => csvExporter.encode(
          unmarkedCell.workspace,
          unmarkedCell.course,
          unmarkedCell.meeting,
        ),
        throwsStateError,
      );
    });

    test('encodes UTF-8 BOM, headers, UTC timestamps, P/A codes, and spreadsheet formula sanitization', () {
      final sample = buildSample();
      final csv = csvExporter.encode(
        sample.workspace,
        sample.course,
        sample.meeting,
      );

      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(
        csv,
        contains(
          'schema_version,semester,course_code,class_code,schedule_code,meeting_id,meeting_number,meeting_date,start_time,end_time,roll_number,member_code,email,full_name,status,recorded_at,source',
        ),
      );
      expect(
        csv,
        contains('1,FA26,PRM393,SE1801,11,m1,1,2026-09-14,07:30,09:30'),
      );
      expect(csv, contains('SE180001,AnNVSE180001,annv@fpt.edu.vn,Nguyễn Văn An,P,'));
      expect(csv, contains('2026-09-14T00:35:10.000Z,scan'));
      expect(csv, contains("'=CMD"));
      expect(csv, contains("'+evil@fpt.edu.vn"));
      expect(csv, contains('"Trần, ""Bình"""'));
      expect(csv, contains(',A,2026-09-14T01:00:00.000Z,manual'));
    });

    test('writes atomic CSV file with zero-padded meeting number and removes staging temp file', () async {
      final tempDir = await Directory.systemTemp.createTemp('csv_export_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final nestedDir = Directory(p.join(tempDir.path, 'nested', 'exports'));
      final sample = buildSample();
      final outFile = await csvExporter.export(
        nestedDir,
        sample.workspace,
        sample.course,
        sample.meeting,
      );

      expect(await outFile.exists(), isTrue);
      expect(
        p.basename(outFile.path),
        'FA26_PRM393_SE1801_M01_2026-09-14.csv',
      );
      final rawBytes = await outFile.readAsBytes();
      expect(rawBytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
      final contents = await outFile.readAsString();
      expect(contents, contains('SE180001'));

      final leftovers = nestedDir.listSync().where(
        (entity) => p.basename(entity.path).contains('.tmp'),
      );
      expect(leftovers, isEmpty);
    });
  });

  group('AttendancePdfExporter multi-page rendering & atomic disk export', () {
    Future<ByteData> loadRoboto() => rootBundle.load('assets/fonts/Roboto.ttf');

    test('delegates closed and completeness guards before generating PDF', () async {
      final fontData = await loadRoboto();
      final active = buildSample(meetingState: MeetingState.active);

      await expectLater(
        () => pdfExporter.encode(
          active.workspace,
          active.course,
          active.meeting,
          fontData: fontData,
        ),
        throwsStateError,
      );
    });

    test('renders valid PDF bytes across large multi-page student rosters and writes atomically to disk', () async {
      final fontData = await loadRoboto();
      final students = List<Student>.generate(
        45,
        (i) => s(
          'SE18${(i + 1).toString().padLeft(4, '0')}',
          fullName: 'Sinh Viên Thứ ${i + 1} Đặng Hoàng Minh',
        ),
      );
      final attendance = {
        'm1': {
          for (var i = 0; i < students.length; i++)
            students[i].rollNumber: AttendanceRecord(
              status: i % 5 == 0
                  ? AttendanceStatus.absent
                  : AttendanceStatus.present,
              source: i % 5 == 0
                  ? AttendanceSource.manual
                  : AttendanceSource.scan,
              recordedAt: baseStart,
              note: i % 5 == 0 ? 'Vắng có lý do #${i + 1}' : null,
            ),
        },
      };
      final sample = buildSample(students: students, attendance: attendance);

      final bytes = await pdfExporter.encode(
        sample.workspace,
        sample.course,
        sample.meeting,
        fontData: fontData,
      );

      expect(bytes.length, greaterThan(1500));
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');

      final tempDir = await Directory.systemTemp.createTemp('pdf_export_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = await pdfExporter.export(
        tempDir,
        sample.workspace,
        sample.course,
        sample.meeting,
      );
      expect(await file.exists(), isTrue);
      expect(
        p.basename(file.path),
        'FA26_PRM393_SE1801_M01_2026-09-14.pdf',
      );
      expect(await file.length(), greaterThan(1500));
    });
  });
}
