import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/data/roster_importer.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run demo-fap/markbook_rosters.dart <markbook.ods>');
    exitCode = 2;
    return;
  }

  final file = File(args.single);
  final result = RosterImporter().importBytes(
    Uint8List.fromList(await file.readAsBytes()),
    fileName: file.path,
    semester: 'FA26',
    semesterStart: DateTime(2026, 9, 7),
  );

  stdout.write(jsonEncode({
    'semester': 'FA26',
    'classes': result.classes.map((course) => {
      'courseCode': course.courseCode,
      'classCode': course.classCode,
      'scheduleCode': course.scheduleCode,
      'students': course.students.map((student) => {
        'rollNumber': student.rollNumber,
        'fullName': student.fullName,
      }).toList(),
      'meetings': course.meetings.map((meeting) => {
        'number': meeting.number,
        'startAt': meeting.startAt.toIso8601String(),
      }).toList(),
    }).toList(),
  }));
}
