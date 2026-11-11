import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fap_attendance/data/roster_importer.dart';

Future<void> main(List<String> args) async {
  final fromStdin = args.length == 2 && args.first == '--stdin';
  if (args.length != 1 && !fromStdin) {
    stderr.writeln(
      'Usage: dart run demo-fap/markbook_rosters.dart [--stdin] <file.ods|file.xlsx>',
    );
    exitCode = 2;
    return;
  }

  final fileName = args.last;
  final bytes = fromStdin
      ? await stdin
            .fold(BytesBuilder(copy: false), (buffer, chunk) {
              buffer.add(chunk);
              return buffer;
            })
            .then((buffer) => buffer.takeBytes())
      : await File(fileName).readAsBytes();
  final result = RosterImporter().importBytes(
    bytes,
    fileName: fileName,
    semester: 'FA26',
    semesterStart: DateTime(2026, 9, 7),
  );

  stdout.write(
    jsonEncode({
      'semester': 'FA26',
      'classes': result.classes
          .map(
            (course) => {
              'courseCode': course.courseCode,
              'classCode': course.classCode,
              'scheduleCode': course.scheduleCode,
              'students': course.students
                  .map(
                    (student) => {
                      'rollNumber': student.rollNumber,
                      'fullName': student.fullName,
                    },
                  )
                  .toList(),
              'meetings': course.meetings
                  .map(
                    (meeting) => {
                      'number': meeting.number,
                      'startAt': meeting.startAt.toIso8601String(),
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    }),
  );
}
