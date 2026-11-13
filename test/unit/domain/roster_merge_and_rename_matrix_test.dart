import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/roster_merge_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = RosterMergeService();
  final t0 = DateTime(2026, 9, 15, 8, 30);

  Student s(String roll, {String? email, String? name, String memberCode = ''}) =>
      Student(
        rollNumber: roll,
        memberCode: memberCode,
        email: email ?? '${roll.toLowerCase()}@fpt.edu.vn',
        fullName: name ?? 'Student $roll',
      );

  Meeting m(String id, int number, MeetingState state) {
    final start = DateTime(2026, 9, 7 + number * 2, 7, 30);
    return Meeting(
      id: id,
      number: number,
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      state: state,
    );
  }

  CourseClass buildClass({
    required String id,
    required String courseCode,
    required String classCode,
    required List<Student> students,
    List<Meeting> meetings = const [],
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
  }) => CourseClass(
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

  group('RosterMergeService class matching and student migration', () {
    test('merges matching classes case-insensitively, keeps added/unmatched classes, and computes counts', () {
      final existingClass = buildClass(
        id: 'existing-1',
        courseCode: 'PRM393',
        classCode: 'SE1801',
        students: [
          s('SE180001', email: 'an@fpt.edu.vn'),
          s('SE180002', email: 'binh@fpt.edu.vn'),
        ],
        meetings: [
          m('m1', 1, MeetingState.closed),
          m('m2', 2, MeetingState.upcoming),
        ],
        attendance: {
          'm1': {
            'se180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.finalize,
              recordedAt: t0,
            ),
          },
        },
      );
      final untouchedClass = buildClass(
        id: 'existing-untouched',
        courseCode: 'SWD392',
        classCode: 'SE1805',
        students: [s('SE180099')],
      );

      final importedMatching = buildClass(
        id: 'new-temp-id',
        courseCode: ' prm393 ',
        classCode: ' se1801 ',
        students: [
          s('SE180001', email: 'an@fpt.edu.vn', name: 'Updated Name An'),
          s('SE180003', email: 'chi@fpt.edu.vn'),
          s('se180003', email: 'dup@fpt.edu.vn'), // duplicate roll skipped
        ],
      );
      final brandNewClass = buildClass(
        id: 'new-cls-2',
        courseCode: 'SWR302',
        classCode: 'SE1809',
        students: [s('SE180010'), s('SE180011')],
      );

      final result = service.merge(
        existing: [existingClass, untouchedClass],
        imported: [importedMatching, brandNewClass],
        now: t0,
      );

      expect(result.addedClasses, 1);
      expect(result.updatedClasses, 1);
      // SE180003 (1 in merged class) + SE180010, SE180011 (2 in brand new class)
      expect(result.addedStudents, 3);
      // SE180002 was not in importedMatching -> retained
      expect(result.retainedStudents, 1);
      expect(result.classes, hasLength(3));

      final mergedPrm = result.classes.firstWhere(
        (c) => c.courseCode == 'PRM393',
      );
      expect(mergedPrm.id, 'existing-1');
      expect(
        mergedPrm.students.map((e) => e.rollNumber).toList(),
        ['SE180001', 'SE180003', 'SE180002'],
      );
      expect(mergedPrm.students.first.fullName, 'Updated Name An');

      // Canonicalized SE180001 kept its 'present' mark on closed m1
      expect(mergedPrm.attendance['m1']!.containsKey('se180001'), isFalse);
      expect(
        mergedPrm.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      // Retained SE180002 kept its record
      expect(
        mergedPrm.recordFor('m1', 'SE180002')?.status,
        AttendanceStatus.absent,
      );
      // Newly added SE180003 was backfilled absent on already closed m1, left empty on upcoming m2
      final addedClosed = mergedPrm.recordFor('m1', 'SE180003');
      expect(addedClosed?.status, AttendanceStatus.absent);
      expect(addedClosed?.source, AttendanceSource.finalize);
      expect(addedClosed?.note, contains('cập nhật danh sách lớp'));
      expect(mergedPrm.recordFor('m2', 'SE180003'), isNull);
    });

    test('migrates attendance keys when an existing student changes rollNumber matched by email', () {
      final existing = buildClass(
        id: 'cls-rename',
        courseCode: 'PRN221',
        classCode: 'SE1701',
        students: [
          s('DE170001', email: 'AnTran@FPT.EDU.VN', name: 'Tran An'),
        ],
        meetings: [
          m('m1', 1, MeetingState.closed),
          m('m2', 2, MeetingState.active),
        ],
        attendance: {
          'm1': {
            'de170001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
          'm2': {
            'DE170001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: t0,
              note: 'Verified',
            ),
          },
        },
      );

      final imported = buildClass(
        id: 'imp-rename',
        courseCode: 'PRN221',
        classCode: 'SE1701',
        students: [
          s('SE180555', email: 'antran@fpt.edu.vn', name: 'Tran An'),
        ],
      );

      final result = service.merge(
        existing: [existing],
        imported: [imported],
        now: t0,
      );

      expect(result.updatedClasses, 1);
      expect(result.addedStudents, 0);
      expect(result.retainedStudents, 0);

      final merged = result.classes.single;
      expect(merged.students.single.rollNumber, 'SE180555');
      expect(merged.attendance['m1']!.containsKey('de170001'), isFalse);
      expect(merged.attendance['m2']!.containsKey('DE170001'), isFalse);
      expect(
        merged.recordFor('m1', 'SE180555')?.status,
        AttendanceStatus.present,
      );
      expect(
        merged.recordFor('m2', 'SE180555')?.note,
        'Verified',
      );
    });

    test('preserves original existing attendance map without external mutation', () {
      final existing = buildClass(
        id: 'cls-immut',
        courseCode: 'PRJ301',
        classCode: 'SE1803',
        students: [s('SE180001', email: 'a@fpt.edu.vn')],
        meetings: [m('m1', 1, MeetingState.closed)],
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.scan,
              recordedAt: t0,
            ),
          },
        },
      );
      final imported = buildClass(
        id: 'cls-immut-2',
        courseCode: 'PRJ301',
        classCode: 'SE1803',
        students: [
          s('SE180001', email: 'a@fpt.edu.vn'),
          s('SE180002', email: 'b@fpt.edu.vn'),
        ],
      );

      final result = service.merge(
        existing: [existing],
        imported: [imported],
        now: t0,
      );

      expect(existing.students, hasLength(1));
      expect(existing.attendance['m1']?.containsKey('SE180002'), isFalse);
      expect(result.classes.single.students, hasLength(2));
      expect(
        result.classes.single.recordFor('m1', 'SE180002')?.status,
        AttendanceStatus.absent,
      );
    });
  });
}
