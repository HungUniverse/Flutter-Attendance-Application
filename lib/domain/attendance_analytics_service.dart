import 'dart:convert';

import 'models.dart';

enum AttendanceRiskLevel { eligible, warning, barred }

class StudentAttendanceAnalytics {
  const StudentAttendanceAnalytics({
    required this.student,
    required this.totalMeetings,
    required this.closedMeetings,
    required this.presentCount,
    required this.absentCount,
    required this.unmarkedCount,
    required this.absenceRateTotal,
    required this.absenceRateClosed,
    required this.maxAllowedAbsences,
    required this.remainingAllowedAbsences,
    required this.currentAbsenceStreak,
    required this.longestAbsenceStreak,
    required this.riskLevel,
  });

  final Student student;
  final int totalMeetings;
  final int closedMeetings;
  final int presentCount;
  final int absentCount;
  final int unmarkedCount;
  final double absenceRateTotal;
  final double absenceRateClosed;
  final int maxAllowedAbsences;
  final int remainingAllowedAbsences;
  final int currentAbsenceStreak;
  final int longestAbsenceStreak;
  final AttendanceRiskLevel riskLevel;

  bool get isBarred => riskLevel == AttendanceRiskLevel.barred;
  bool get isAtWarning => riskLevel == AttendanceRiskLevel.warning;

  Map<String, Object?> toJson() => {
    'rollNumber': student.rollNumber,
    'memberCode': student.memberCode,
    'email': student.email,
    'fullName': student.fullName,
    'totalMeetings': totalMeetings,
    'closedMeetings': closedMeetings,
    'presentCount': presentCount,
    'absentCount': absentCount,
    'unmarkedCount': unmarkedCount,
    'absenceRateTotal': absenceRateTotal,
    'absenceRateClosed': absenceRateClosed,
    'maxAllowedAbsences': maxAllowedAbsences,
    'remainingAllowedAbsences': remainingAllowedAbsences,
    'currentAbsenceStreak': currentAbsenceStreak,
    'longestAbsenceStreak': longestAbsenceStreak,
    'riskLevel': riskLevel.name,
  };
}

class MeetingParticipationMetric {
  const MeetingParticipationMetric({
    required this.meetingId,
    required this.meetingNumber,
    required this.state,
    required this.totalStudents,
    required this.presentCount,
    required this.absentCount,
    required this.unmarkedCount,
    required this.attendanceRate,
  });

  final String meetingId;
  final int meetingNumber;
  final MeetingState state;
  final int totalStudents;
  final int presentCount;
  final int absentCount;
  final int unmarkedCount;
  final double attendanceRate;

  Map<String, Object?> toJson() => {
    'meetingId': meetingId,
    'meetingNumber': meetingNumber,
    'state': state.name,
    'totalStudents': totalStudents,
    'presentCount': presentCount,
    'absentCount': absentCount,
    'unmarkedCount': unmarkedCount,
    'attendanceRate': attendanceRate,
  };
}

class ClassAttendanceSummary {
  const ClassAttendanceSummary({
    required this.classId,
    required this.courseCode,
    required this.classCode,
    required this.totalStudents,
    required this.totalMeetings,
    required this.closedMeetings,
    required this.eligibleCount,
    required this.warningCount,
    required this.barredCount,
    required this.averagePresenceRate,
    required this.studentAnalytics,
    required this.meetingMetrics,
  });

  final String classId;
  final String courseCode;
  final String classCode;
  final int totalStudents;
  final int totalMeetings;
  final int closedMeetings;
  final int eligibleCount;
  final int warningCount;
  final int barredCount;
  final double averagePresenceRate;
  final List<StudentAttendanceAnalytics> studentAnalytics;
  final List<MeetingParticipationMetric> meetingMetrics;

  Map<String, Object?> toJson() => {
    'classId': classId,
    'courseCode': courseCode,
    'classCode': classCode,
    'totalStudents': totalStudents,
    'totalMeetings': totalMeetings,
    'closedMeetings': closedMeetings,
    'eligibleCount': eligibleCount,
    'warningCount': warningCount,
    'barredCount': barredCount,
    'averagePresenceRate': averagePresenceRate,
    'studentAnalytics': studentAnalytics.map((e) => e.toJson()).toList(),
    'meetingMetrics': meetingMetrics.map((e) => e.toJson()).toList(),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class AttendanceAnalyticsService {
  const AttendanceAnalyticsService({
    this.maxAbsenceRatio = 0.20,
    this.warningAbsenceRatio = 0.15,
  }) : assert(maxAbsenceRatio > 0 && maxAbsenceRatio <= 1.0),
       assert(warningAbsenceRatio > 0 && warningAbsenceRatio <= maxAbsenceRatio);

  final double maxAbsenceRatio;
  final double warningAbsenceRatio;

  StudentAttendanceAnalytics analyzeStudent(
    CourseClass courseClass,
    String rollNumber,
  ) {
    final normalizedRoll = rollNumber.trim().toUpperCase();
    final student = courseClass.students
        .where((s) => s.rollNumber.trim().toUpperCase() == normalizedRoll)
        .firstOrNull;
    if (student == null) {
      throw ArgumentError.value(
        rollNumber,
        'rollNumber',
        'Sinh viên không thuộc danh sách lớp.',
      );
    }

    final sortedMeetings = [...courseClass.meetings]
      ..sort((a, b) => a.number.compareTo(b.number));
    final totalMeetings = sortedMeetings.length;
    final closedMeetings = sortedMeetings
        .where((m) => m.state == MeetingState.closed)
        .length;

    var presentCount = 0;
    var absentCount = 0;
    var unmarkedCount = 0;
    var currentStreak = 0;
    var longestStreak = 0;

    for (final meeting in sortedMeetings) {
      final status =
          _recordFor(courseClass, meeting.id, student.rollNumber)?.status ??
          AttendanceStatus.unmarked;
      switch (status) {
        case AttendanceStatus.present:
          presentCount++;
          currentStreak = 0;
        case AttendanceStatus.absent:
          absentCount++;
          currentStreak++;
          if (currentStreak > longestStreak) {
            longestStreak = currentStreak;
          }
        case AttendanceStatus.unmarked:
          unmarkedCount++;
          if (meeting.state == MeetingState.closed) {
            currentStreak = 0;
          }
      }
    }

    final absenceRateTotal = totalMeetings == 0
        ? 0.0
        : absentCount / totalMeetings;
    final recordedTotal = presentCount + absentCount;
    final absenceRateClosed = recordedTotal == 0
        ? 0.0
        : absentCount / recordedTotal;

    final maxAllowedAbsences = (totalMeetings * maxAbsenceRatio).floor();
    final remaining = maxAllowedAbsences - absentCount;
    final remainingAllowedAbsences = remaining < 0 ? 0 : remaining;

    final riskLevel = _classifyRisk(
      totalMeetings: totalMeetings,
      absentCount: absentCount,
      absenceRateTotal: absenceRateTotal,
      maxAllowedAbsences: maxAllowedAbsences,
    );

    return StudentAttendanceAnalytics(
      student: student,
      totalMeetings: totalMeetings,
      closedMeetings: closedMeetings,
      presentCount: presentCount,
      absentCount: absentCount,
      unmarkedCount: unmarkedCount,
      absenceRateTotal: absenceRateTotal,
      absenceRateClosed: absenceRateClosed,
      maxAllowedAbsences: maxAllowedAbsences,
      remainingAllowedAbsences: remainingAllowedAbsences,
      currentAbsenceStreak: currentStreak,
      longestAbsenceStreak: longestStreak,
      riskLevel: riskLevel,
    );
  }

  ClassAttendanceSummary summarizeClass(CourseClass courseClass) {
    final sortedMeetings = [...courseClass.meetings]
      ..sort((a, b) => a.number.compareTo(b.number));

    final studentReports = courseClass.students
        .map((student) => analyzeStudent(courseClass, student.rollNumber))
        .toList();

    var eligibleCount = 0;
    var warningCount = 0;
    var barredCount = 0;

    for (final report in studentReports) {
      switch (report.riskLevel) {
        case AttendanceRiskLevel.eligible:
          eligibleCount++;
        case AttendanceRiskLevel.warning:
          warningCount++;
        case AttendanceRiskLevel.barred:
          barredCount++;
      }
    }

    final meetingMetrics = <MeetingParticipationMetric>[];
    var totalPresenceSum = 0.0;
    var countedMeetings = 0;

    for (final meeting in sortedMeetings) {
      var present = 0;
      var absent = 0;
      var unmarked = 0;

      for (final student in courseClass.students) {
        final status =
            _recordFor(courseClass, meeting.id, student.rollNumber)?.status ??
            AttendanceStatus.unmarked;
        switch (status) {
          case AttendanceStatus.present:
            present++;
          case AttendanceStatus.absent:
            absent++;
          case AttendanceStatus.unmarked:
            unmarked++;
        }
      }

      final studentTotal = courseClass.students.length;
      final rate = studentTotal == 0 ? 0.0 : present / studentTotal;
      if (meeting.state == MeetingState.closed || present > 0 || absent > 0) {
        totalPresenceSum += rate;
        countedMeetings++;
      }

      meetingMetrics.add(
        MeetingParticipationMetric(
          meetingId: meeting.id,
          meetingNumber: meeting.number,
          state: meeting.state,
          totalStudents: studentTotal,
          presentCount: present,
          absentCount: absent,
          unmarkedCount: unmarked,
          attendanceRate: rate,
        ),
      );
    }

    final averagePresenceRate = countedMeetings == 0
        ? 0.0
        : totalPresenceSum / countedMeetings;

    return ClassAttendanceSummary(
      classId: courseClass.id,
      courseCode: courseClass.courseCode,
      classCode: courseClass.classCode,
      totalStudents: courseClass.students.length,
      totalMeetings: sortedMeetings.length,
      closedMeetings: sortedMeetings
          .where((m) => m.state == MeetingState.closed)
          .length,
      eligibleCount: eligibleCount,
      warningCount: warningCount,
      barredCount: barredCount,
      averagePresenceRate: averagePresenceRate,
      studentAnalytics: studentReports,
      meetingMetrics: meetingMetrics,
    );
  }

  List<StudentAttendanceAnalytics> findAtRiskStudents(CourseClass courseClass) {
    final summary = summarizeClass(courseClass);
    return summary.studentAnalytics
        .where((s) => s.riskLevel != AttendanceRiskLevel.eligible)
        .toList()
      ..sort((a, b) {
        final rateCompare = b.absenceRateTotal.compareTo(a.absenceRateTotal);
        if (rateCompare != 0) return rateCompare;
        return a.student.rollNumber.compareTo(b.student.rollNumber);
      });
  }

  String exportSummaryCsv(ClassAttendanceSummary summary) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      'roll_number,member_code,email,full_name,total_meetings,closed_meetings,present,absent,unmarked,absence_rate_pct,remaining_allowed_absences,longest_streak,risk_level',
    );
    for (final item in summary.studentAnalytics) {
      final ratePct = (item.absenceRateTotal * 100).toStringAsFixed(1);
      buffer.writeln(
        [
          _escapeCsv(item.student.rollNumber),
          _escapeCsv(item.student.memberCode),
          _escapeCsv(item.student.email),
          _escapeCsv(item.student.fullName),
          item.totalMeetings,
          item.closedMeetings,
          item.presentCount,
          item.absentCount,
          item.unmarkedCount,
          ratePct,
          item.remainingAllowedAbsences,
          item.longestAbsenceStreak,
          item.riskLevel.name,
        ].join(','),
      );
    }
    return buffer.toString();
  }

  AttendanceRiskLevel _classifyRisk({
    required int totalMeetings,
    required int absentCount,
    required double absenceRateTotal,
    required int maxAllowedAbsences,
  }) {
    if (totalMeetings == 0 || absentCount == 0) {
      return AttendanceRiskLevel.eligible;
    }
    if (absentCount > maxAllowedAbsences ||
        absenceRateTotal > maxAbsenceRatio + 1e-9) {
      return AttendanceRiskLevel.barred;
    }
    if (absentCount == maxAllowedAbsences ||
        absenceRateTotal >= warningAbsenceRatio - 1e-9) {
      return AttendanceRiskLevel.warning;
    }
    return AttendanceRiskLevel.eligible;
  }

  static AttendanceRecord? _recordFor(
    CourseClass courseClass,
    String meetingId,
    String rollNumber,
  ) {
    final records = courseClass.attendance[meetingId];
    if (records == null) return null;
    final direct = records[rollNumber];
    if (direct != null) return direct;
    final normalized = rollNumber.trim().toUpperCase();
    for (final entry in records.entries) {
      if (entry.key.trim().toUpperCase() == normalized) {
        return entry.value;
      }
    }
    return null;
  }

  static String _escapeCsv(String value) {
    final trimmedLeft = value.trimLeft();
    final sanitized =
        value.startsWith('=') ||
            value.startsWith('+') ||
            value.startsWith('-') ||
            value.startsWith('@') ||
            value.startsWith('\t') ||
            value.startsWith('\r') ||
            trimmedLeft.startsWith('=') ||
            trimmedLeft.startsWith('+') ||
            trimmedLeft.startsWith('-') ||
            trimmedLeft.startsWith('@')
        ? "'$value"
        : value;
    if (sanitized.contains(',') ||
        sanitized.contains('"') ||
        sanitized.contains('\n') ||
        sanitized.contains('\r')) {
      return '"${sanitized.replaceAll('"', '""')}"';
    }
    return sanitized;
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
