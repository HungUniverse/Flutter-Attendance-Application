import 'package:flutter_test/flutter_test.dart';

import 'package:fap_attendance/domain/attendance_analytics_service.dart';
import 'package:fap_attendance/domain/models.dart';

CourseClass _buildTestCourse({
  int meetingCount = 20,
  int closedCount = 10,
  List<Student>? students,
  Map<String, Map<String, AttendanceRecord>>? attendance,
}) {
  final start = DateTime(2026, 11, 2, 7, 0);
  final roster =
      students ??
      const [
        Student(
          rollNumber: 'SE194673',
          memberCode: 'DuyTT',
          email: 'duongthanhduy@fpt.edu.vn',
          fullName: 'Dương Thành Thanh Duy',
        ),
        Student(
          rollNumber: 'SE190002',
          memberCode: 'AnhNTM',
          email: 'anhntm@fpt.edu.vn',
          fullName: 'Nguyễn Thị Minh Anh',
        ),
        Student(
          rollNumber: 'SE190003',
          memberCode: 'BaoLQ',
          email: 'baolq@fpt.edu.vn',
          fullName: 'Lê Quốc Bảo',
        ),
      ];

  final meetings = List.generate(meetingCount, (index) {
    final day = start.add(Duration(days: index * 3));
    return Meeting(
      id: 'm${index + 1}',
      number: index + 1,
      startAt: day,
      endAt: day.add(const Duration(hours: 2, minutes: 15)),
      state: index < closedCount ? MeetingState.closed : MeetingState.upcoming,
    );
  });

  return CourseClass(
    id: 'FA26_PRM393_SE1901',
    courseCode: 'PRM393',
    classCode: 'SE1901',
    scheduleCode: '11',
    students: roster,
    scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
    meetings: meetings,
    attendance: attendance ?? const {},
  );
}

AttendanceRecord _rec(AttendanceStatus status) => AttendanceRecord(
  status: status,
  source: AttendanceSource.manual,
  recordedAt: DateTime(2026, 11, 13, 9, 0),
);

void main() {
  group('AttendanceAnalyticsService - Student Risk & Thresholds', () {
    const service = AttendanceAnalyticsService();

    test('should classify student as eligible when absences are below warning threshold', () {
      // Arrange: 20 meetings, 2 absences (10% < 15% warning threshold)
      final attendance = <String, Map<String, AttendanceRecord>>{
        'm1': {'SE194673': _rec(AttendanceStatus.absent)},
        'm2': {'SE194673': _rec(AttendanceStatus.present)},
        'm3': {'SE194673': _rec(AttendanceStatus.absent)},
        for (var i = 4; i <= 10; i++)
          'm$i': {'SE194673': _rec(AttendanceStatus.present)},
      };
      final course = _buildTestCourse(attendance: attendance);

      // Act
      final analytics = service.analyzeStudent(course, 'SE194673');

      // Assert
      expect(analytics.totalMeetings, equals(20));
      expect(analytics.closedMeetings, equals(10));
      expect(analytics.presentCount, equals(8));
      expect(analytics.absentCount, equals(2));
      expect(analytics.unmarkedCount, equals(10));
      expect(analytics.absenceRateTotal, closeTo(0.10, 1e-6));
      expect(analytics.absenceRateClosed, closeTo(0.20, 1e-6));
      expect(analytics.maxAllowedAbsences, equals(4));
      expect(analytics.remainingAllowedAbsences, equals(2));
      expect(analytics.riskLevel, equals(AttendanceRiskLevel.eligible));
      expect(analytics.isBarred, isFalse);
      expect(analytics.isAtWarning, isFalse);
    });

    test('should classify student as warning when reaching 15%-20% absence boundary', () {
      // Arrange: 20 meetings, 4 absences (exact 20% limit = 4 allowed absences)
      final attendance = <String, Map<String, AttendanceRecord>>{
        for (var i = 1; i <= 4; i++)
          'm$i': {'SE194673': _rec(AttendanceStatus.absent)},
        for (var i = 5; i <= 10; i++)
          'm$i': {'SE194673': _rec(AttendanceStatus.present)},
      };
      final course = _buildTestCourse(attendance: attendance);

      // Act
      final analytics = service.analyzeStudent(course, 'se194673');

      // Assert
      expect(analytics.absentCount, equals(4));
      expect(analytics.absenceRateTotal, closeTo(0.20, 1e-6));
      expect(analytics.remainingAllowedAbsences, equals(0));
      expect(analytics.riskLevel, equals(AttendanceRiskLevel.warning));
      expect(analytics.isAtWarning, isTrue);
      expect(analytics.isBarred, isFalse);
    });

    test('should classify student as barred when exceeding 20% absence threshold', () {
      // Arrange: 20 meetings, 5 absences (25% > 20% limit)
      final attendance = <String, Map<String, AttendanceRecord>>{
        for (var i = 1; i <= 5; i++)
          'm$i': {'SE194673': _rec(AttendanceStatus.absent)},
        for (var i = 6; i <= 10; i++)
          'm$i': {'SE194673': _rec(AttendanceStatus.present)},
      };
      final course = _buildTestCourse(attendance: attendance);

      // Act
      final analytics = service.analyzeStudent(course, 'SE194673');

      // Assert
      expect(analytics.absentCount, equals(5));
      expect(analytics.absenceRateTotal, closeTo(0.25, 1e-6));
      expect(analytics.remainingAllowedAbsences, equals(0));
      expect(analytics.riskLevel, equals(AttendanceRiskLevel.barred));
      expect(analytics.isBarred, isTrue);
    });

    test('should track longest and current consecutive absence streaks accurately', () {
      // Arrange: A, A, A, P, A, A (longest = 3, current = 2)
      final attendance = <String, Map<String, AttendanceRecord>>{
        'm1': {'SE194673': _rec(AttendanceStatus.absent)},
        'm2': {'SE194673': _rec(AttendanceStatus.absent)},
        'm3': {'SE194673': _rec(AttendanceStatus.absent)},
        'm4': {'SE194673': _rec(AttendanceStatus.present)},
        'm5': {'SE194673': _rec(AttendanceStatus.absent)},
        'm6': {'SE194673': _rec(AttendanceStatus.absent)},
      };
      final course = _buildTestCourse(closedCount: 6, attendance: attendance);

      // Act
      final analytics = service.analyzeStudent(course, 'SE194673');

      // Assert
      expect(analytics.longestAbsenceStreak, equals(3));
      expect(analytics.currentAbsenceStreak, equals(2));
    });

    test('should handle empty meeting schedule gracefully without division by zero', () {
      // Arrange
      final course = _buildTestCourse(meetingCount: 0, closedCount: 0);

      // Act
      final analytics = service.analyzeStudent(course, 'SE194673');

      // Assert
      expect(analytics.totalMeetings, equals(0));
      expect(analytics.absenceRateTotal, equals(0.0));
      expect(analytics.absenceRateClosed, equals(0.0));
      expect(analytics.riskLevel, equals(AttendanceRiskLevel.eligible));
    });

    test('should throw ArgumentError when analyzing unknown student roll number', () {
      // Arrange
      final course = _buildTestCourse();

      // Act & Assert
      expect(
        () => service.analyzeStudent(course, 'SE999999'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('AttendanceAnalyticsService - Class Summary & Export', () {
    const service = AttendanceAnalyticsService();

    test('class summary matches individual reports for an unsorted schedule', () {
      final course = _buildTestCourse(
        meetingCount: 3,
        closedCount: 2,
        attendance: {
          'm1': {'SE194673': _rec(AttendanceStatus.present)},
          'm2': {'se194673': _rec(AttendanceStatus.absent)},
          'm3': {'SE194673': _rec(AttendanceStatus.absent)},
        },
      );
      final unsorted = course.copyWith(meetings: course.meetings.reversed.toList());

      final summary = service.summarizeClass(unsorted);
      expect(summary.meetingMetrics.map((m) => m.meetingNumber), [1, 2, 3]);
      expect(summary.closedMeetings, 2);
      expect(summary.studentAnalytics.first.currentAbsenceStreak, 2);
      expect(
        summary.studentAnalytics.map((report) => report.toJson()),
        unsorted.students.map(
          (student) => service.analyzeStudent(unsorted, student.rollNumber).toJson(),
        ),
      );
    });

    test('should aggregate class summary, risk counts, and meeting participation rates', () {
      // Arrange:
      // SE194673: 0 absences (eligible)
      // SE190002: 3 absences out of 20 = 15% (warning)
      // SE190003: 5 absences out of 20 = 25% (barred)
      final attendance = <String, Map<String, AttendanceRecord>>{};
      for (var i = 1; i <= 5; i++) {
        attendance['m$i'] = {
          'SE194673': _rec(AttendanceStatus.present),
          'SE190002': _rec(
            i <= 3 ? AttendanceStatus.absent : AttendanceStatus.present,
          ),
          'SE190003': _rec(AttendanceStatus.absent),
        };
      }
      final course = _buildTestCourse(closedCount: 5, attendance: attendance);

      // Act
      final summary = service.summarizeClass(course);
      final atRisk = service.findAtRiskStudents(course);

      // Assert
      expect(summary.totalStudents, equals(3));
      expect(summary.eligibleCount, equals(1));
      expect(summary.warningCount, equals(1));
      expect(summary.barredCount, equals(1));
      expect(summary.meetingMetrics, hasLength(20));
      expect(summary.meetingMetrics.first.presentCount, equals(1));
      expect(summary.meetingMetrics.first.absentCount, equals(2));
      expect(atRisk.map((s) => s.student.rollNumber), equals(['SE190003', 'SE190002']));
    });

    test('should export summary to CSV with UTF-8 BOM and sanitize formula injection', () {
      // Arrange
      final dangerousStudents = const [
        Student(
          rollNumber: 'SE194673',
          memberCode: 'DuyTT',
          email: 'duongthanhduy@fpt.edu.vn',
          fullName: '=CMD|" /C calc"!A0',
        ),
      ];
      final course = _buildTestCourse(
        meetingCount: 5,
        closedCount: 1,
        students: dangerousStudents,
        attendance: {
          'm1': {'SE194673': _rec(AttendanceStatus.present)},
        },
      );

      // Act
      final summary = service.summarizeClass(course);
      final csv = service.exportSummaryCsv(summary);
      final json = summary.toJson();

      // Assert
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains("'=CMD|\"\" /C calc\"\"!A0"));
      expect(json['courseCode'], equals('PRM393'));
      expect(summary.toPrettyJson(), contains('"classCode": "SE1901"'));
    });

    test('should resolve case-mismatched attendance roll keys and quote carriage-return CSV values', () {
      // Arrange
      final course = _buildTestCourse(
        meetingCount: 5,
        closedCount: 1,
        students: const [
          Student(
            rollNumber: 'SE194673',
            memberCode: 'DuyTT\rLine2',
            email: 'duongthanhduy@fpt.edu.vn',
            fullName: '  =SUM(A1:A2)',
          ),
        ],
        attendance: {
          'm1': {'se194673': _rec(AttendanceStatus.present)},
        },
      );

      // Act
      final summary = service.summarizeClass(course);
      final csv = service.exportSummaryCsv(summary);

      // Assert
      expect(summary.studentAnalytics.single.presentCount, equals(1));
      expect(summary.meetingMetrics.first.presentCount, equals(1));
      expect(csv, contains('"DuyTT\rLine2"'));
      expect(csv, contains("'  =SUM(A1:A2)"));
    });
  });
}
