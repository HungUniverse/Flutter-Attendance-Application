import 'dart:convert';

import 'package:fap_attendance/domain/attendance_analytics_service.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AttendanceAnalyticsService analytics;

  setUp(() {
    analytics = const AttendanceAnalyticsService();
  });

  CourseClass makeClass({
    required List<Student> students,
    required List<Meeting> meetings,
    Map<String, Map<String, AttendanceRecord>> attendance = const {},
  }) {
    return CourseClass(
      id: 'cls-ana',
      courseCode: 'SWP391',
      classCode: 'SE1805',
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

  List<Meeting> makeMeetings(int count, {int closedCount = 0}) {
    return List.generate(count, (i) {
      final num = i + 1;
      final start = DateTime(2026, 9, 7 + i * 3, 7, 30);
      return Meeting(
        id: 'm$num',
        number: num,
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        state: i < closedCount ? MeetingState.closed : MeetingState.upcoming,
      );
    });
  }

  group('AttendanceAnalyticsService.analyzeStudent', () {
    test('calculates streaks, rates, remaining allowed absences, and risk levels', () {
      const s1 = Student(
        rollNumber: 'SE180001',
        memberCode: 'An',
        email: 'an@fpt.edu.vn',
        fullName: 'An Nguyen',
      );
      // 10 meetings -> maxAllowedAbsences = floor(10 * 0.20) = 2
      final meetings = makeMeetings(10, closedCount: 7);
      final recorded = DateTime(2026, 9, 10);

      // Pattern across m1..m7: A, A, P, A, A, A (barred! 5 absences, longest streak 3, current streak 3)
      final cls = makeClass(
        students: [s1],
        meetings: meetings,
        attendance: {
          'm1': {'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: recorded)},
          'm2': {'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: recorded)},
          'm3': {'SE180001': AttendanceRecord(status: AttendanceStatus.present, source: AttendanceSource.scan, recordedAt: recorded)},
          'm4': {'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: recorded)},
          'm5': {'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: recorded)},
          'm6': {'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: recorded)},
          // m7 is closed & unmarked -> resets currentStreak
        },
      );

      final report = analytics.analyzeStudent(cls, 'se180001');
      expect(report.totalMeetings, 10);
      expect(report.closedMeetings, 7);
      expect(report.presentCount, 1);
      expect(report.absentCount, 5);
      expect(report.unmarkedCount, 4);
      expect(report.absenceRateTotal, closeTo(0.5, 1e-9));
      expect(report.absenceRateClosed, closeTo(5 / 6, 1e-9));
      expect(report.maxAllowedAbsences, 2);
      expect(report.remainingAllowedAbsences, 0);
      expect(report.longestAbsenceStreak, 3);
      expect(report.currentAbsenceStreak, 0);
      expect(report.riskLevel, AttendanceRiskLevel.barred);
      expect(report.isBarred, isTrue);
      expect(report.isAtWarning, isFalse);

      final json = report.toJson();
      expect(json['riskLevel'], 'barred');
      expect(json['rollNumber'], 'SE180001');
    });

    test('classifies warning when absentCount equals maxAllowedAbsences or >= warningAbsenceRatio', () {
      const s1 = Student(
        rollNumber: 'SE180001',
        email: 'an@fpt.edu.vn',
        fullName: 'An',
      );
      final meetings = makeMeetings(10, closedCount: 5);
      final rec = DateTime(2026, 9, 10);
      final cls = makeClass(
        students: [s1],
        meetings: meetings,
        attendance: {
          'm1': {'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: rec)},
          'm2': {'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: rec)},
        },
      );

      final report = analytics.analyzeStudent(cls, 'SE180001');
      expect(report.riskLevel, AttendanceRiskLevel.warning);
      expect(report.isAtWarning, isTrue);
      expect(report.remainingAllowedAbsences, 0);
      expect(report.currentAbsenceStreak, 0);
      expect(report.longestAbsenceStreak, 2);
    });

    test('throws ArgumentError for rollNumber not in class', () {
      final cls = makeClass(students: const [], meetings: makeMeetings(2));
      expect(() => analytics.analyzeStudent(cls, 'SE999999'), throwsArgumentError);
    });

    test('handles zero meetings gracefully', () {
      const s1 = Student(rollNumber: 'SE1', email: 's1@fpt.edu.vn', fullName: 'S1');
      final cls = makeClass(students: [s1], meetings: const []);
      final report = analytics.analyzeStudent(cls, 'SE1');
      expect(report.absenceRateTotal, 0.0);
      expect(report.absenceRateClosed, 0.0);
      expect(report.riskLevel, AttendanceRiskLevel.eligible);
    });
  });

  group('AttendanceAnalyticsService.summarizeClass & findAtRiskStudents & CSV', () {
    test('summarizes class counts, meeting metrics, deduplicates duplicate roll numbers, and exports CSV safely', () {
      const s1 = Student(rollNumber: 'SE180001', memberCode: 'M1', email: 's1@fpt.edu.vn', fullName: '=FormulaName');
      const s2 = Student(rollNumber: 'SE180002', memberCode: 'M2', email: 's2@fpt.edu.vn', fullName: 'Binh, Tran');
      const s3 = Student(rollNumber: 'SE180003', memberCode: 'M3', email: 's3@fpt.edu.vn', fullName: 'Cuong "Nick"');
      const s1Dup = Student(rollNumber: 'se180001', memberCode: 'M1D', email: 'dup@fpt.edu.vn', fullName: 'Dup');

      final meetings = makeMeetings(10, closedCount: 3);
      final rec = DateTime(2026, 9, 10);
      final cls = makeClass(
        students: [s1, s2, s3, s1Dup],
        meetings: meetings,
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: rec),
            'SE180002': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: rec),
            'SE180003': AttendanceRecord(status: AttendanceStatus.present, source: AttendanceSource.scan, recordedAt: rec),
          },
          'm2': {
            'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: rec),
            'SE180002': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: rec),
            'SE180003': AttendanceRecord(status: AttendanceStatus.present, source: AttendanceSource.scan, recordedAt: rec),
          },
          'm3': {
            'SE180001': AttendanceRecord(status: AttendanceStatus.absent, source: AttendanceSource.finalize, recordedAt: rec),
            'SE180002': AttendanceRecord(status: AttendanceStatus.present, source: AttendanceSource.scan, recordedAt: rec),
            'SE180003': AttendanceRecord(status: AttendanceStatus.present, source: AttendanceSource.scan, recordedAt: rec),
          },
        },
      );

      final summary = analytics.summarizeClass(cls);
      expect(summary.studentAnalytics, hasLength(4));
      expect(summary.studentAnalytics[3].absentCount, 3);
      expect(summary.barredCount, 2); // s1 and duplicate se180001 share barred analytics
      expect(summary.warningCount, 1); // s2: 2 absences
      expect(summary.eligibleCount, 1); // s3: 0 absences
      expect(summary.meetingMetrics, hasLength(10));
      expect(summary.averagePresenceRate, closeTo((1 / 4 + 1 / 4 + 2 / 4) / 3, 1e-9));

      expect(() => jsonDecode(summary.toPrettyJson()), returnsNormally);

      final atRisk = analytics.findAtRiskStudents(cls);
      expect(atRisk.map((e) => e.student.rollNumber).toList(), ['SE180001', 'SE180001', 'SE180002']);

      final csv = analytics.exportSummaryCsv(summary);
      expect(csv.startsWith('\uFEFFroll_number,'), isTrue);
      expect(csv, contains("'=FormulaName"));
      expect(csv, contains('"Binh, Tran"'));
      expect(csv, contains('"Cuong ""Nick"""'));
    });
  });
}
