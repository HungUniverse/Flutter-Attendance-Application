import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../domain/models.dart';

class AttendanceCsvExporter {
  String encode(
    TeacherWorkspace workspace,
    CourseClass courseClass,
    Meeting meeting,
  ) {
    if (meeting.state != MeetingState.closed) {
      throw StateError('Chỉ được export buổi đã chốt.');
    }
    final records = courseClass.attendance[meeting.id] ?? const {};
    if (courseClass.students.any(
      (student) =>
          records[student.rollNumber]?.status == null ||
          records[student.rollNumber]!.status == AttendanceStatus.unmarked,
    )) {
      throw StateError('Buổi điểm danh vẫn còn ô trống.');
    }
    final rows = <List<Object?>>[
      const [
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
      ],
    ];
    final date = DateFormat('yyyy-MM-dd');
    final time = DateFormat('HH:mm');
    for (final student in courseClass.students) {
      final record = records[student.rollNumber]!;
      rows.add([
        1,
        workspace.semester,
        courseClass.courseCode,
        courseClass.classCode,
        courseClass.scheduleCode,
        meeting.id,
        meeting.number,
        date.format(meeting.startAt),
        time.format(meeting.startAt),
        time.format(meeting.endAt),
        student.rollNumber,
        student.memberCode,
        student.email,
        student.fullName,
        attendanceCode(record.status),
        record.recordedAt.toUtc().toIso8601String(),
        record.source.name,
      ]);
    }
    return '\uFEFF${const ListToCsvConverter().convert(rows)}';
  }

  Future<File> export(
    Directory directory,
    TeacherWorkspace workspace,
    CourseClass courseClass,
    Meeting meeting,
  ) async {
    await directory.create(recursive: true);
    final date = DateFormat('yyyy-MM-dd').format(meeting.startAt);
    final name =
        '${workspace.semester}_${courseClass.courseCode}_${courseClass.classCode}_M${meeting.number.toString().padLeft(2, '0')}_$date.csv';
    final file = File(p.join(directory.path, name));
    await file.writeAsString(
      encode(workspace, courseClass, meeting),
      flush: true,
    );
    return file;
  }
}
