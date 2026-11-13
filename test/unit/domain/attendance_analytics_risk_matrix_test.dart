import 'dart:convert';

import 'package:fap_attendance/domain/attendance_analytics_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Student makeStudent(
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

  CourseClass buildClass({
    String id = 'cls-analytics',
    String courseCode = 'PRM393',
    String classCode = 'SE1801',
    required List<Student> students,
    required List<Meeting> meetings,
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

  List<Meeting> generateMeetings(
    int count, {
    int closedCount = 0,
    bool reverseOrder = false,
  }) {
    final base = DateTime(2026, 9, 7, 7, 30);
    final items = List<Meeting>.generate(count, (index) {
      final number = index + 1;
      final start = base.add(Duration(days: index * 3));
      final state = index < closedCount
          ? MeetingState.closed
          : (index == closedCount ? MeetingState.active : MeetingState.upcoming);
      return Meeting(
        id: 'm$number',
        number: number,
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        state: state,
      );
    });
    return reverseOrder ? items.reversed.toList() : items;
  }

  AttendanceRecord rec(
    AttendanceStatus status, {
    AttendanceSource source = AttendanceSource.manual,
    String? note,
  }) => AttendanceRecord(
    status: status,
    source: source,
    recordedAt: DateTime(2026, 9, 7, 9, 0),
    note: note,
  );

  group('AttendanceAnalyticsService risk & streak matrix', () {
    test('classifies risk thresholds accurately on 10-meeting course', () {
      const service = AttendanceAnalyticsService(
        maxAbsenceRatio: 0.20,
        warningAbsenceRatio: 0.15,
      );
      final students = [
        makeStudent('SE180001', fullName: 'Zero Absence'),
        makeStudent('SE180002', fullName: 'One Absence (10%)'),
        makeStudent('SE180003', fullName: 'Two Absences (20% warning edge)'),
        makeStudent('SE180004', fullName: 'Three Absences (30% barred)'),
      ];
      final meetings = generateMeetings(10, closedCount: 10);
      final attendance = <String, Map<String, AttendanceRecord>>{};

      for (var i = 0; i < 10; i++) {
        final mId = 'm${i + 1}';
        attendance[mId] = {
          'SE180001': rec(AttendanceStatus.present),
          'SE180002': rec(
            i == 0 ? AttendanceStatus.absent : AttendanceStatus.present,
          ),
          'SE180003': rec(
            i < 2 ? AttendanceStatus.absent : AttendanceStatus.present,
          ),
          'SE180004': rec(
            i < 3 ? AttendanceStatus.absent : AttendanceStatus.present,
          ),
        };
      }

      final course = buildClass(
        students: students,
        meetings: meetings,
        attendance: attendance,
      );
      final summary = service.summarizeClass(course);

      expect(summary.totalStudents, 4);
      expect(summary.totalMeetings, 10);
      expect(summary.closedMeetings, 10);
      expect(summary.eligibleCount, 2);
      expect(summary.warningCount, 1);
      expect(summary.barredCount, 1);

      final s1 = summary.studentAnalytics[0];
      expect(s1.riskLevel, AttendanceRiskLevel.eligible);
      expect(s1.remainingAllowedAbsences, 2);
      expect(s1.isBarred, isFalse);
      expect(s1.isAtWarning, isFalse);

      final s2 = summary.studentAnalytics[1];
      expect(s2.absenceRateTotal, closeTo(0.10, 1e-9));
      expect(s2.riskLevel, AttendanceRiskLevel.eligible);
      expect(s2.remainingAllowedAbsences, 1);

      final s3 = summary.studentAnalytics[2];
      expect(s3.absenceRateTotal, closeTo(0.20, 1e-9));
      expect(s3.maxAllowedAbsences, 2);
      expect(s3.remainingAllowedAbsences, 0);
      expect(s3.riskLevel, AttendanceRiskLevel.warning);
      expect(s3.isAtWarning, isTrue);

      final s4 = summary.studentAnalytics[3];
      expect(s4.absenceRateTotal, closeTo(0.30, 1e-9));
      expect(s4.remainingAllowedAbsences, 0);
      expect(s4.riskLevel, AttendanceRiskLevel.barred);
      expect(s4.isBarred, isTrue);
    });

    test('detects warning threshold triggered by ratio even below maxAllowedAbsences', () {
      const service = AttendanceAnalyticsService(
        maxAbsenceRatio: 0.25,
        warningAbsenceRatio: 0.15,
      );
      final students = [makeStudent('SE180010')];
      final meetings = generateMeetings(20, closedCount: 20);
      final attendance = <String, Map<String, AttendanceRecord>>{};
      for (var i = 0; i < 20; i++) {
        attendance['m${i + 1}'] = {
          'SE180010': rec(
            i < 3 ? AttendanceStatus.absent : AttendanceStatus.present,
          ),
        };
      }

      final report = service.analyzeStudent(
        buildClass(students: students, meetings: meetings, attendance: attendance),
        'se180010',
      );

      expect(report.maxAllowedAbsences, 5);
      expect(report.absentCount, 3);
      expect(report.absenceRateTotal, closeTo(0.15, 1e-9));
      expect(report.remainingAllowedAbsences, 2);
      expect(report.riskLevel, AttendanceRiskLevel.warning);
    });

    test('computes absence streaks ignoring unmarked upcoming meetings but resetting on unmarked closed meetings', () {
      const service = AttendanceAnalyticsService();
      final students = [makeStudent('SE180020')];
      final meetings = [
        Meeting(
          id: 'm4',
          number: 4,
          startAt: DateTime(2026, 9, 16, 7, 30),
          endAt: DateTime(2026, 9, 16, 9, 30),
          state: MeetingState.closed,
        ),
        Meeting(
          id: 'm2',
          number: 2,
          startAt: DateTime(2026, 9, 10, 7, 30),
          endAt: DateTime(2026, 9, 10, 9, 30),
          state: MeetingState.closed,
        ),
        Meeting(
          id: 'm6',
          number: 6,
          startAt: DateTime(2026, 9, 22, 7, 30),
          endAt: DateTime(2026, 9, 22, 9, 30),
          state: MeetingState.upcoming,
        ),
        Meeting(
          id: 'm1',
          number: 1,
          startAt: DateTime(2026, 9, 7, 7, 30),
          endAt: DateTime(2026, 9, 7, 9, 30),
          state: MeetingState.closed,
        ),
        Meeting(
          id: 'm3',
          number: 3,
          startAt: DateTime(2026, 9, 13, 7, 30),
          endAt: DateTime(2026, 9, 13, 9, 30),
          state: MeetingState.closed,
        ),
        Meeting(
          id: 'm5',
          number: 5,
          startAt: DateTime(2026, 9, 19, 7, 30),
          endAt: DateTime(2026, 9, 19, 9, 30),
          state: MeetingState.closed,
        ),
      ];
      // Sequence in order 1..6:
      // m1: Absent, m2: Absent, m3: Closed+Unmarked (resets current),
      // m4: Absent, m5: Absent, m6: Upcoming+Unmarked (preserves current = 2)
      final attendance = {
        'm1': {'SE180020': rec(AttendanceStatus.absent)},
        'm2': {'SE180020': rec(AttendanceStatus.absent)},
        'm4': {'se180020 ': rec(AttendanceStatus.absent)},
        'm5': {'SE180020': rec(AttendanceStatus.absent)},
      };

      final report = service.analyzeStudent(
        buildClass(students: students, meetings: meetings, attendance: attendance),
        '  se180020 ',
      );

      expect(report.totalMeetings, 6);
      expect(report.closedMeetings, 5);
      expect(report.absentCount, 4);
      expect(report.presentCount, 0);
      expect(report.unmarkedCount, 2);
      expect(report.longestAbsenceStreak, 2);
      expect(report.currentAbsenceStreak, 2);
      expect(report.absenceRateClosed, closeTo(1.0, 1e-9));
    });

    test('computes longest streak across 3 absences then present then 1 absence', () {
      const service = AttendanceAnalyticsService();
      final students = [makeStudent('SE180030')];
      final meetings = generateMeetings(6, closedCount: 6);
      final attendance = {
        'm1': {'SE180030': rec(AttendanceStatus.absent)},
        'm2': {'SE180030': rec(AttendanceStatus.absent)},
        'm3': {'SE180030': rec(AttendanceStatus.absent)},
        'm4': {'SE180030': rec(AttendanceStatus.present)},
        'm5': {'SE180030': rec(AttendanceStatus.absent)},
        'm6': {'SE180030': rec(AttendanceStatus.present)},
      };

      final report = service.analyzeStudent(
        buildClass(students: students, meetings: meetings, attendance: attendance),
        'SE180030',
      );

      expect(report.longestAbsenceStreak, 3);
      expect(report.currentAbsenceStreak, 0);
      expect(report.presentCount, 2);
      expect(report.absentCount, 4);
      expect(report.absenceRateTotal, closeTo(4 / 6, 1e-9));
      expect(report.absenceRateClosed, closeTo(4 / 6, 1e-9));
    });

    test('throws ArgumentError when roll number is not in roster', () {
      const service = AttendanceAnalyticsService();
      final course = buildClass(
        students: [makeStudent('SE180001')],
        meetings: generateMeetings(3, closedCount: 1),
      );

      expect(
        () => service.analyzeStudent(course, 'SE999999'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('handles empty students and empty meetings without division by zero', () {
      const service = AttendanceAnalyticsService();
      final emptyCourse = buildClass(
        students: const [],
        meetings: const [],
      );
      final summary = service.summarizeClass(emptyCourse);

      expect(summary.totalStudents, 0);
      expect(summary.totalMeetings, 0);
      expect(summary.closedMeetings, 0);
      expect(summary.eligibleCount, 0);
      expect(summary.warningCount, 0);
      expect(summary.barredCount, 0);
      expect(summary.averagePresenceRate, 0.0);
      expect(summary.studentAnalytics, isEmpty);
      expect(summary.meetingMetrics, isEmpty);

      final zeroMeetingsCourse = buildClass(
        students: [makeStudent('SE180001')],
        meetings: const [],
      );
      final report = service.analyzeStudent(zeroMeetingsCourse, 'SE180001');
      expect(report.absenceRateTotal, 0.0);
      expect(report.absenceRateClosed, 0.0);
      expect(report.maxAllowedAbsences, 0);
      expect(report.riskLevel, AttendanceRiskLevel.eligible);
    });

    test('keeps first duplicate student record on legacy duplicate roll numbers', () {
      const service = AttendanceAnalyticsService();
      final course = buildClass(
        students: [
          makeStudent('SE180001', fullName: 'First Duplicate'),
          makeStudent('se180001 ', fullName: 'Second Duplicate'),
          makeStudent('SE180002', fullName: 'Valid Student'),
        ],
        meetings: generateMeetings(4, closedCount: 2),
        attendance: {
          'm1': {
            'SE180001': rec(AttendanceStatus.present),
            'SE180002': rec(AttendanceStatus.absent),
          },
          'm2': {
            'SE180001': rec(AttendanceStatus.present),
            'SE180002': rec(AttendanceStatus.present),
          },
        },
      );

      final summary = service.summarizeClass(course);
      expect(summary.studentAnalytics, hasLength(3));
      expect(summary.studentAnalytics[0].student.fullName, 'First Duplicate');
      expect(summary.studentAnalytics[1].student.fullName, 'First Duplicate');
      expect(summary.studentAnalytics[2].student.rollNumber, 'SE180002');
      // Meeting metrics iterate over courseClass.students (3 entries).
      expect(summary.meetingMetrics.first.totalStudents, 3);
      expect(summary.meetingMetrics.first.presentCount, 2);
      expect(summary.meetingMetrics.first.absentCount, 1);
    });

    test('excludes upcoming meetings with no marks from averagePresenceRate', () {
      const service = AttendanceAnalyticsService();
      final students = [makeStudent('SE180001'), makeStudent('SE180002')];
      final meetings = [
        Meeting(
          id: 'm1',
          number: 1,
          startAt: DateTime(2026, 9, 7, 7, 30),
          endAt: DateTime(2026, 9, 7, 9, 30),
          state: MeetingState.closed,
        ),
        Meeting(
          id: 'm2',
          number: 2,
          startAt: DateTime(2026, 9, 10, 7, 30),
          endAt: DateTime(2026, 9, 10, 9, 30),
          state: MeetingState.active,
        ),
        Meeting(
          id: 'm3',
          number: 3,
          startAt: DateTime(2026, 9, 14, 7, 30),
          endAt: DateTime(2026, 9, 14, 9, 30),
          state: MeetingState.upcoming,
        ),
      ];
      final attendance = {
        'm1': {
          'SE180001': rec(AttendanceStatus.present),
          'SE180002': rec(AttendanceStatus.absent),
        },
        'm2': {
          'SE180001': rec(AttendanceStatus.present),
        },
      };

      final summary = service.summarizeClass(
        buildClass(students: students, meetings: meetings, attendance: attendance),
      );

      // m1 rate = 0.5, m2 rate = 0.5 (has present > 0), m3 ignored (0 present/absent and not closed)
      expect(summary.averagePresenceRate, closeTo(0.5, 1e-9));
      expect(summary.meetingMetrics[0].attendanceRate, closeTo(0.5, 1e-9));
      expect(summary.meetingMetrics[1].unmarkedCount, 1);
      expect(summary.meetingMetrics[2].unmarkedCount, 2);
    });

    test('sorts at-risk students by descending absence rate then ascending rollNumber', () {
      const service = AttendanceAnalyticsService();
      final students = [
        makeStudent('SE180005'),
        makeStudent('SE180003'),
        makeStudent('SE180001'),
        makeStudent('SE180002'),
      ];
      final meetings = generateMeetings(10, closedCount: 10);
      final attendance = <String, Map<String, AttendanceRecord>>{};
      for (var i = 0; i < 10; i++) {
        attendance['m${i + 1}'] = {
          'SE180005': rec(i < 2 ? AttendanceStatus.absent : AttendanceStatus.present),
          'SE180003': rec(i < 4 ? AttendanceStatus.absent : AttendanceStatus.present),
          'SE180001': rec(AttendanceStatus.present),
          'SE180002': rec(i < 2 ? AttendanceStatus.absent : AttendanceStatus.present),
        };
      }

      final atRisk = service.findAtRiskStudents(
        buildClass(students: students, meetings: meetings, attendance: attendance),
      );

      expect(
        atRisk.map((e) => e.student.rollNumber).toList(),
        ['SE180003', 'SE180002', 'SE180005'],
      );
    });

    test('exports CSV with UTF-8 BOM, spreadsheet formula protection, and proper quoting', () {
      const service = AttendanceAnalyticsService();
      final course = buildClass(
        students: [
          makeStudent(
            'SE180001',
            memberCode: '=CMD()',
            email: 'an+tag@fpt.edu.vn',
            fullName: 'Nguyen, "An"\nLine2',
          ),
          makeStudent(
            'SE180002',
            memberCode: '+SUM(A1)',
            email: '@evil',
            fullName: '-Minus Name',
          ),
        ],
        meetings: generateMeetings(5, closedCount: 5),
        attendance: {
          'm1': {
            'SE180001': rec(AttendanceStatus.present),
            'SE180002': rec(AttendanceStatus.absent),
          },
          'm2': {
            'SE180001': rec(AttendanceStatus.present),
            'SE180002': rec(AttendanceStatus.absent),
          },
          'm3': {
            'SE180001': rec(AttendanceStatus.present),
            'SE180002': rec(AttendanceStatus.present),
          },
          'm4': {
            'SE180001': rec(AttendanceStatus.present),
            'SE180002': rec(AttendanceStatus.present),
          },
          'm5': {
            'SE180001': rec(AttendanceStatus.present),
            'SE180002': rec(AttendanceStatus.present),
          },
        },
      );

      final summary = service.summarizeClass(course);
      final csv = service.exportSummaryCsv(summary);

      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(
        csv,
        contains(
          'roll_number,member_code,email,full_name,total_meetings,closed_meetings,present,absent,unmarked,absence_rate_pct,remaining_allowed_absences,longest_streak,risk_level',
        ),
      );
      expect(csv, contains("'=CMD()"));
      expect(csv, contains('"Nguyen, ""An""\nLine2"'));
      expect(csv, contains("'+SUM(A1)"));
      expect(csv, contains("'@evil"));
      expect(csv, contains("'-Minus Name"));
      expect(csv, contains(',40.0,0,2,barred'));
      expect(csv, contains(',0.0,1,0,eligible'));

      final parsedJson = jsonDecode(summary.toPrettyJson()) as Map<String, Object?>;
      expect(parsedJson['classId'], 'cls-analytics');
      expect(parsedJson['courseCode'], 'PRM393');
      expect(parsedJson['barredCount'], 1);
      expect(parsedJson['eligibleCount'], 1);
      expect((parsedJson['studentAnalytics'] as List).length, 2);
      expect((parsedJson['meetingMetrics'] as List).length, 5);
    });
  });

  group('AttendanceAnalyticsService parameterized threshold matrix', () {
    final cases = <({
      int total,
      int absent,
      double maxRatio,
      double warnRatio,
      AttendanceRiskLevel expected,
      int expectedMaxAllowed,
      int expectedRemaining,
    })>[
      (
        total: 10,
        absent: 0,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.eligible,
        expectedMaxAllowed: 2,
        expectedRemaining: 2,
      ),
      (
        total: 10,
        absent: 1,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.eligible,
        expectedMaxAllowed: 2,
        expectedRemaining: 1,
      ),
      (
        total: 10,
        absent: 2,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.warning,
        expectedMaxAllowed: 2,
        expectedRemaining: 0,
      ),
      (
        total: 10,
        absent: 3,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.barred,
        expectedMaxAllowed: 2,
        expectedRemaining: 0,
      ),
      (
        total: 15,
        absent: 2,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.eligible,
        expectedMaxAllowed: 3,
        expectedRemaining: 1,
      ),
      (
        total: 15,
        absent: 3,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.warning,
        expectedMaxAllowed: 3,
        expectedRemaining: 0,
      ),
      (
        total: 15,
        absent: 4,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.barred,
        expectedMaxAllowed: 3,
        expectedRemaining: 0,
      ),
      (
        total: 30,
        absent: 4,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.eligible,
        expectedMaxAllowed: 6,
        expectedRemaining: 2,
      ),
      (
        total: 30,
        absent: 5,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.warning,
        expectedMaxAllowed: 6,
        expectedRemaining: 1,
      ),
      (
        total: 30,
        absent: 6,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.warning,
        expectedMaxAllowed: 6,
        expectedRemaining: 0,
      ),
      (
        total: 30,
        absent: 7,
        maxRatio: 0.20,
        warnRatio: 0.15,
        expected: AttendanceRiskLevel.barred,
        expectedMaxAllowed: 6,
        expectedRemaining: 0,
      ),
      (
        total: 8,
        absent: 1,
        maxRatio: 0.25,
        warnRatio: 0.125,
        expected: AttendanceRiskLevel.warning,
        expectedMaxAllowed: 2,
        expectedRemaining: 1,
      ),
      (
        total: 8,
        absent: 2,
        maxRatio: 0.25,
        warnRatio: 0.125,
        expected: AttendanceRiskLevel.warning,
        expectedMaxAllowed: 2,
        expectedRemaining: 0,
      ),
      (
        total: 8,
        absent: 3,
        maxRatio: 0.25,
        warnRatio: 0.125,
        expected: AttendanceRiskLevel.barred,
        expectedMaxAllowed: 2,
        expectedRemaining: 0,
      ),
      (
        total: 1,
        absent: 1,
        maxRatio: 0.20,
        warnRatio: 0.10,
        expected: AttendanceRiskLevel.barred,
        expectedMaxAllowed: 0,
        expectedRemaining: 0,
      ),
    ];

    for (final c in cases) {
      test(
        'total=${c.total}, absent=${c.absent}, max=${c.maxRatio}, warn=${c.warnRatio} -> ${c.expected.name}',
        () {
          final service = AttendanceAnalyticsService(
            maxAbsenceRatio: c.maxRatio,
            warningAbsenceRatio: c.warnRatio,
          );
          final meetings = generateMeetings(c.total, closedCount: c.total);
          final attendance = <String, Map<String, AttendanceRecord>>{};
          for (var i = 0; i < c.total; i++) {
            attendance['m${i + 1}'] = {
              'SE180100': rec(
                i < c.absent
                    ? AttendanceStatus.absent
                    : AttendanceStatus.present,
              ),
            };
          }
          final report = service.analyzeStudent(
            buildClass(
              students: [makeStudent('SE180100')],
              meetings: meetings,
              attendance: attendance,
            ),
            'SE180100',
          );

          expect(report.riskLevel, c.expected);
          expect(report.maxAllowedAbsences, c.expectedMaxAllowed);
          expect(report.remainingAllowedAbsences, c.expectedRemaining);
        },
      );
    }
  });
}
