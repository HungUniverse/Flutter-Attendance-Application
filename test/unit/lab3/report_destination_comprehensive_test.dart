import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/report_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReportDestination', () {
    test('builds canonical folderPath, objectPath, dateKey, and metadata', () {
      final dest = ReportDestination(
        ownerUid: 'teacher-1',
        semester: 'FA26',
        courseCode: 'PRM392',
        classCode: 'SE1801',
        meetingNumber: 4,
        meetingDate: DateTime(2026, 9, 17, 7, 30),
        fileName: 'report_04.pdf',
      );

      expect(dest.dateKey, '2026-09-17');
      expect(dest.meetingFolder, '2026-09-17_Slot-04');
      expect(
        dest.folderPath,
        'reports/teacher-1/FA26/PRM392/SE1801/2026-09-17_Slot-04',
      );
      expect(
        dest.objectPath,
        'reports/teacher-1/FA26/PRM392/SE1801/2026-09-17_Slot-04/report_04.pdf',
      );
      expect(dest.metadata['meetingNumber'], '4');
      expect(dest.metadata['storageLayout'], 'semester-course-class-meeting-v1');
    });

    test('forExport factory captures workspace, course, and meeting fields', () {
      final ws = TeacherWorkspace(
        id: 'ws',
        semester: 'SP26',
        semesterStart: DateTime(2026, 1, 5),
        classes: const [],
      );
      final course = CourseClass(
        id: 'c1',
        courseCode: 'SWD392',
        classCode: 'SE1802',
        scheduleCode: '21',
        students: const [],
        scheduleRule: ScheduleRule(
          scheduleCode: '21',
          semesterStart: DateTime(2026, 1, 5),
        ),
        meetings: const [],
      );
      final meeting = Meeting(
        id: 'm12',
        number: 12,
        startAt: DateTime(2026, 2, 14, 9, 30),
        endAt: DateTime(2026, 2, 14, 11, 45),
      );

      final dest = ReportDestination.forExport(
        uid: 'uid_9',
        workspace: ws,
        course: course,
        meeting: meeting,
        fileName: 'export.csv',
      );
      expect(dest.meetingFolder, '2026-02-14_Slot-12');
      expect(dest.objectPath, endsWith('/export.csv'));
    });

    test('validates segments, meetingNumber, and allowed extensions', () {
      expect(
        () => ReportDestination(
          ownerUid: '../bad',
          semester: 'FA26',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          meetingNumber: 1,
          meetingDate: DateTime(2026, 9, 7),
          fileName: 'a.csv',
        ),
        throwsFormatException,
      );
      expect(
        () => ReportDestination(
          ownerUid: 'u1',
          semester: 'FA26',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          meetingNumber: 0,
          meetingDate: DateTime(2026, 9, 7),
          fileName: 'a.csv',
        ),
        throwsFormatException,
      );
      expect(
        () => ReportDestination(
          ownerUid: 'u1',
          semester: 'FA26',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          meetingNumber: 1,
          meetingDate: DateTime(2026, 9, 7),
          fileName: 'a.exe',
        ),
        throwsFormatException,
      );
    });
  });
}
