import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/roster_merge_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roster update preserves attendance, schedule and missing students', () {
    final meeting = Meeting(
      id: 'm1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7),
      endAt: DateTime(2026, 9, 7, 9, 15),
      state: MeetingState.closed,
    );
    final existing = CourseClass(
      id: 'FA26_PRM393_SE1917',
      courseCode: 'PRM393',
      classCode: 'SE1917',
      scheduleCode: '11',
      students: const [
        Student(
          rollNumber: 'SE000001',
          email: 'one@example.com',
          fullName: 'Tên cũ',
        ),
        Student(
          rollNumber: 'SE000003',
          email: 'three@example.com',
          fullName: 'Sinh viên giữ lại',
        ),
      ],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
        weeks: 5,
        meetingsPerWeek: 1,
      ),
      meetings: [meeting],
      attendance: {
        'm1': {
          'SE000001': AttendanceRecord(
            status: AttendanceStatus.present,
            source: AttendanceSource.scan,
            recordedAt: DateTime(2026, 9, 7, 7, 30),
          ),
        },
      },
    );
    final imported = CourseClass(
      id: 'FA26_PRM393_SE1917',
      courseCode: 'PRM393',
      classCode: 'SE1917',
      scheduleCode: '11',
      students: const [
        Student(
          rollNumber: 'SE000001',
          email: 'one@example.com',
          fullName: 'Tên đã cập nhật',
        ),
        Student(
          rollNumber: 'SE000002',
          email: 'two@example.com',
          fullName: 'Sinh viên mới',
        ),
      ],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: const [],
    );

    final result = RosterMergeService().merge(
      existing: [existing],
      imported: [imported],
      now: DateTime(2026, 9, 17),
    );
    final merged = result.classes.single;

    expect(merged.scheduleRule.weeks, 5);
    expect(merged.scheduleRule.meetingsPerWeek, 1);
    expect(merged.meetings.single.state, MeetingState.closed);
    expect(merged.students.map((student) => student.rollNumber), [
      'SE000001',
      'SE000002',
      'SE000003',
    ]);
    expect(merged.students.first.fullName, 'Tên đã cập nhật');
    expect(
      merged.recordFor('m1', 'SE000001')?.status,
      AttendanceStatus.present,
    );
    expect(merged.recordFor('m1', 'SE000002')?.status, AttendanceStatus.absent);
    expect(merged.recordFor('m1', 'SE000003')?.status, AttendanceStatus.absent);
    expect(result.updatedClasses, 1);
    expect(result.addedStudents, 1);
    expect(result.retainedStudents, 1);
  });

  test('roster update migrates history when roll number changes', () {
    final meeting = Meeting(
      id: 'm1',
      number: 1,
      startAt: DateTime(2026, 9, 7, 7),
      endAt: DateTime(2026, 9, 7, 9, 15),
      state: MeetingState.closed,
    );
    CourseClass course(Student student, {bool withAttendance = false}) =>
        CourseClass(
          id: 'FA26_PRM393_SE1917',
          courseCode: 'PRM393',
          classCode: 'SE1917',
          scheduleCode: '11',
          students: [student],
          scheduleRule: ScheduleRule(
            scheduleCode: '11',
            semesterStart: DateTime(2026, 9, 7),
          ),
          meetings: [meeting],
          attendance: withAttendance
              ? {
                  'm1': {
                    student.rollNumber: AttendanceRecord(
                      status: AttendanceStatus.present,
                      source: AttendanceSource.scan,
                      recordedAt: DateTime(2026, 9, 7, 7, 30),
                    ),
                  },
                }
              : const {},
        );

    final result = RosterMergeService().merge(
      existing: [
        course(
          const Student(
            rollNumber: 'SE000001',
            email: 'same@example.com',
            fullName: 'Student',
          ),
          withAttendance: true,
        ),
      ],
      imported: [
        course(
          const Student(
            rollNumber: 'SE000099',
            email: 'same@example.com',
            fullName: 'Student',
          ),
        ),
      ],
    );

    expect(
      result.classes.single.recordFor('m1', 'SE000099')?.status,
      AttendanceStatus.present,
    );
    expect(result.classes.single.recordFor('m1', 'SE000001'), isNull);
  });
}
