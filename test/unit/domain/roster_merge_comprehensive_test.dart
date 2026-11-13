import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/roster_merge_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RosterMergeService mergeService;
  late DateTime now;

  setUp(() {
    mergeService = RosterMergeService();
    now = DateTime(2026, 9, 10, 9, 0);
  });

  CourseClass makeClass({
    required String id,
    required String courseCode,
    required String classCode,
    required List<Student> students,
    List<Meeting> meetings = const [],
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
  }) {
    return CourseClass(
      id: id,
      courseCode: courseCode,
      classCode: classCode,
      scheduleCode: '11',
      students: students,
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: meetings,
      attendance: attendance,
    );
  }

  test('adds brand new classes, updates matched classes, and keeps unimported existing classes', () {
    final existingClass1 = makeClass(
      id: 'c1',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      students: const [
        Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'Old Name'),
        Student(rollNumber: 'SE180002', email: 's2@fpt.edu.vn', fullName: 'Retained'),
      ],
      meetings: [
        Meeting(
          id: 'm1',
          number: 1,
          startAt: DateTime(2026, 9, 7, 7, 30),
          endAt: DateTime(2026, 9, 7, 9, 15),
          state: MeetingState.closed,
        ),
      ],
      attendance: {
        'm1': {
          'se180001': AttendanceRecord(
            status: AttendanceStatus.present,
            source: AttendanceSource.scan,
            recordedAt: DateTime(2026, 9, 7, 7, 35),
          ),
        },
      },
    );

    final existingUnimported = makeClass(
      id: 'c-old',
      courseCode: 'SWP391',
      classCode: 'SE1809',
      students: const [
        Student(rollNumber: 'SE180099', email: 's99@fpt.edu.vn', fullName: 'Ninety Nine'),
      ],
    );

    final importedUpdate1 = makeClass(
      id: 'c1-import',
      courseCode: ' prm392 ',
      classCode: ' se1801 ',
      students: const [
        Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'Updated Name'),
        Student(rollNumber: 'SE180001', email: 's1@fpt.edu.vn', fullName: 'Duplicate Ignored'),
        Student(rollNumber: 'SE180003', email: 's3@fpt.edu.vn', fullName: 'Brand New'),
      ],
    );

    final importedNewClass = makeClass(
      id: 'c2',
      courseCode: 'MLN122',
      classCode: 'SE1802',
      students: const [
        Student(rollNumber: 'SE180010', email: 's10@fpt.edu.vn', fullName: 'Ten'),
        Student(rollNumber: 'SE180011', email: 's11@fpt.edu.vn', fullName: 'Eleven'),
      ],
    );

    final result = mergeService.merge(
      existing: [existingClass1, existingUnimported],
      imported: [importedUpdate1, importedNewClass],
      now: now,
    );

    expect(result.addedClasses, 1);
    expect(result.updatedClasses, 1);
    expect(result.addedStudents, 3); // SE180003 + 2 in c2
    expect(result.retainedStudents, 1); // SE180002
    expect(result.classes, hasLength(3));

    final mergedC1 = result.classes.firstWhere((c) => c.id == 'c1');
    expect(mergedC1.students.map((s) => s.rollNumber), ['SE180001', 'SE180003', 'SE180002']);
    expect(mergedC1.students.first.fullName, 'Updated Name');
    // Case-variant 'se180001' migrated to canonical 'SE180001'
    expect(mergedC1.attendance['m1']!.containsKey('SE180001'), isTrue);
    expect(mergedC1.attendance['m1']!.containsKey('se180001'), isFalse);
    expect(mergedC1.recordFor('m1', 'SE180001')?.status, AttendanceStatus.present);
    // Closed meeting auto-fills absent for newly added SE180003 and existing unmarked SE180002
    expect(mergedC1.recordFor('m1', 'SE180003')?.status, AttendanceStatus.absent);
    expect(mergedC1.recordFor('m1', 'SE180002')?.status, AttendanceStatus.absent);
  });

  test('migrates attendance records when matched student email has renamed rollNumber', () {
    final existing = makeClass(
      id: 'c1',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      students: const [
        Student(rollNumber: 'OLD001', email: 'rename@fpt.edu.vn', fullName: 'Renamed'),
      ],
      meetings: [
        Meeting(
          id: 'm1',
          number: 1,
          startAt: DateTime(2026, 9, 7, 7, 30),
          endAt: DateTime(2026, 9, 7, 9, 15),
          state: MeetingState.closed,
        ),
      ],
      attendance: {
        'm1': {
          'OLD001': AttendanceRecord(
            status: AttendanceStatus.present,
            source: AttendanceSource.scan,
            recordedAt: DateTime(2026, 9, 7, 7, 40),
          ),
        },
      },
    );

    final imported = makeClass(
      id: 'c1-new',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      students: const [
        Student(rollNumber: 'NEW001', email: 'RENAME@fpt.edu.vn', fullName: 'Renamed'),
      ],
    );

    final result = mergeService.merge(existing: [existing], imported: [imported], now: now);
    final merged = result.classes.single;
    expect(merged.recordFor('m1', 'NEW001')?.status, AttendanceStatus.present);
    expect(merged.attendance['m1']!.containsKey('OLD001'), isFalse);
  });
}
