import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/lab3/services/report_destination.dart';

import 'fakes.dart';

void main() {
  ReportDestination destination({
    String uid = 'teacher1',
    String semester = 'FA26',
    String course = 'PRM393',
    String classCode = 'SE1913',
    int meeting = 1,
    String file = 'attendance.json',
  }) => ReportDestination(
    ownerUid: uid,
    semester: semester,
    courseCode: course,
    classCode: classCode,
    meetingNumber: meeting,
    meetingDate: DateTime(2026, 11, 4, 9, 30),
    fileName: file,
  );

  test('folders use report data, including codes with underscores', () {
    final workspace = fixtureWorkspace(
      semester: 'FA_26',
      courseCode: 'PRM_393',
    );
    final report = ReportDestination.forExport(
      uid: 'teacher1',
      workspace: workspace,
      course: workspace.classes.first,
      meeting: workspace.classes.first.meetings.first,
      fileName: 'arbitrary_name.csv',
    );
    expect(
      report.objectPath,
      'reports/teacher1/FA_26/PRM_393/SE1901/2026-11-03_Slot-01/arbitrary_name.csv',
    );
    expect(report.metadata, containsPair('ownerUid', 'teacher1'));
    expect(report.metadata, containsPair('meetingDate', '2026-11-03'));
    expect(report.metadata, containsPair('meetingNumber', '1'));
  });

  test('different owners, classes and meetings never share a report path', () {
    final paths = {
      destination().objectPath,
      destination(uid: 'teacher2').objectPath,
      destination(classCode: 'SE1914').objectPath,
      destination(meeting: 2).objectPath,
      destination(file: 'attendance.csv').objectPath,
    };
    expect(paths.length, 5);
    expect(
      paths.first,
      'reports/teacher1/FA26/PRM393/SE1913/2026-11-04_Slot-01/attendance.json',
    );
    expect(destination(meeting: 100).meetingFolder, '2026-11-04_Slot-100');
  });

  test(
    'unsafe folder names and filenames cannot escape the report hierarchy',
    () {
      for (final invalid in [
        '',
        '..',
        '../FA26',
        'FA26/class',
        r'FA26\class',
      ]) {
        expect(() => destination(semester: invalid), throwsFormatException);
      }
      for (final invalid in [
        '../attendance.json',
        'a/b.csv',
        'a.exe',
        '.json',
      ]) {
        expect(() => destination(file: invalid), throwsFormatException);
      }
      expect(() => destination(meeting: 0), throwsFormatException);
    },
  );
}
