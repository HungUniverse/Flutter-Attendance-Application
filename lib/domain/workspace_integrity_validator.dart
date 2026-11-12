import 'models.dart';

enum IntegritySeverity { info, warning, error }

class IntegrityIssue {
  const IntegrityIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.classId,
    this.meetingId,
    this.rollNumber,
  });

  final String code;
  final IntegritySeverity severity;
  final String message;
  final String? classId;
  final String? meetingId;
  final String? rollNumber;

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': severity.name,
    'message': message,
    if (classId != null) 'classId': classId,
    if (meetingId != null) 'meetingId': meetingId,
    if (rollNumber != null) 'rollNumber': rollNumber,
  };
}

class WorkspaceIntegrityReport {
  const WorkspaceIntegrityReport({
    required this.workspaceId,
    required this.semester,
    required this.issues,
  });

  final String workspaceId;
  final String semester;
  final List<IntegrityIssue> issues;

  bool get isValid =>
      !issues.any((issue) => issue.severity == IntegritySeverity.error);

  int get errorCount =>
      issues.where((i) => i.severity == IntegritySeverity.error).length;

  int get warningCount =>
      issues.where((i) => i.severity == IntegritySeverity.warning).length;

  int get infoCount =>
      issues.where((i) => i.severity == IntegritySeverity.info).length;

  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'semester': semester,
    'isValid': isValid,
    'errorCount': errorCount,
    'warningCount': warningCount,
    'infoCount': infoCount,
    'issues': issues.map((e) => e.toJson()).toList(),
  };
}

class WorkspaceIntegrityValidator {
  const WorkspaceIntegrityValidator();

  WorkspaceIntegrityReport validateWorkspace(TeacherWorkspace workspace) {
    final issues = <IntegrityIssue>[];

    if (workspace.id.trim().isEmpty) {
      issues.add(
        const IntegrityIssue(
          code: 'WORKSPACE_EMPTY_ID',
          severity: IntegritySeverity.error,
          message: 'Workspace ID không được để trống.',
        ),
      );
    }

    if (workspace.semester.trim().isEmpty) {
      issues.add(
        const IntegrityIssue(
          code: 'WORKSPACE_EMPTY_SEMESTER',
          severity: IntegritySeverity.error,
          message: 'Kỳ học (semester) không được để trống.',
        ),
      );
    }

    final seenClassIds = <String>{};
    for (final courseClass in workspace.classes) {
      final normalizedClassId = courseClass.id.trim();
      if (!seenClassIds.add(normalizedClassId)) {
        issues.add(
          IntegrityIssue(
            code: 'DUPLICATE_CLASS_ID',
            severity: IntegritySeverity.error,
            message: 'Mã định danh lớp bị trùng lặp: ${courseClass.id}.',
            classId: courseClass.id,
          ),
        );
      }
      issues.addAll(validateClass(courseClass));
    }

    return WorkspaceIntegrityReport(
      workspaceId: workspace.id,
      semester: workspace.semester,
      issues: issues,
    );
  }

  List<IntegrityIssue> validateClass(CourseClass courseClass) {
    final issues = <IntegrityIssue>[];
    final classId = courseClass.id;

    if (!RegExp(r'^[1-3][1-4]$').hasMatch(courseClass.scheduleCode.trim())) {
      issues.add(
        IntegrityIssue(
          code: 'INVALID_SCHEDULE_CODE',
          severity: IntegritySeverity.error,
          message:
              'Mã lịch học "${courseClass.scheduleCode}" không nằm trong khoảng 11–34.',
          classId: classId,
        ),
      );
    }

    final seenRolls = <String>{};
    final seenEmails = <String>{};
    final validRolls = <String>{};

    for (final student in courseClass.students) {
      final roll = student.rollNumber.trim();
      final upperRoll = roll.toUpperCase();
      final email = student.normalizedEmail;

      if (roll.isEmpty || student.fullName.trim().isEmpty) {
        issues.add(
          IntegrityIssue(
            code: 'STUDENT_MISSING_IDENTITY',
            severity: IntegritySeverity.error,
            message: 'Sinh viên thiếu MSSV hoặc họ tên.',
            classId: classId,
            rollNumber: student.rollNumber,
          ),
        );
      } else {
        validRolls.add(student.rollNumber);
      }

      if (upperRoll.isNotEmpty && !seenRolls.add(upperRoll)) {
        issues.add(
          IntegrityIssue(
            code: 'DUPLICATE_STUDENT_ROLL',
            severity: IntegritySeverity.error,
            message: 'MSSV bị trùng lặp trong cùng lớp: ${student.rollNumber}.',
            classId: classId,
            rollNumber: student.rollNumber,
          ),
        );
      }

      if (email.isEmpty || !email.contains('@')) {
        issues.add(
          IntegrityIssue(
            code: 'INVALID_STUDENT_EMAIL',
            severity: IntegritySeverity.error,
            message: 'Email sinh viên không hợp lệ: "${student.email}".',
            classId: classId,
            rollNumber: student.rollNumber,
          ),
        );
      } else if (!seenEmails.add(email)) {
        issues.add(
          IntegrityIssue(
            code: 'DUPLICATE_STUDENT_EMAIL',
            severity: IntegritySeverity.error,
            message: 'Email sinh viên bị trùng lặp: $email.',
            classId: classId,
            rollNumber: student.rollNumber,
          ),
        );
      }
    }

    final seenMeetingIds = <String>{};
    final seenMeetingNumbers = <int>{};
    var activeMeetingCount = 0;

    for (final meeting in courseClass.meetings) {
      if (!seenMeetingIds.add(meeting.id)) {
        issues.add(
          IntegrityIssue(
            code: 'DUPLICATE_MEETING_ID',
            severity: IntegritySeverity.error,
            message: 'Mã buổi học bị trùng lặp: ${meeting.id}.',
            classId: classId,
            meetingId: meeting.id,
          ),
        );
      }

      if (!seenMeetingNumbers.add(meeting.number)) {
        issues.add(
          IntegrityIssue(
            code: 'DUPLICATE_MEETING_NUMBER',
            severity: IntegritySeverity.warning,
            message: 'Số thứ tự buổi học bị trùng: buổi ${meeting.number}.',
            classId: classId,
            meetingId: meeting.id,
          ),
        );
      }

      if (!meeting.endAt.isAfter(meeting.startAt)) {
        issues.add(
          IntegrityIssue(
            code: 'INVALID_MEETING_TIME_RANGE',
            severity: IntegritySeverity.error,
            message:
                'Thời gian kết thúc buổi học phải sau thời gian bắt đầu (${meeting.id}).',
            classId: classId,
            meetingId: meeting.id,
          ),
        );
      }

      if (meeting.state == MeetingState.active) {
        activeMeetingCount++;
      }

      if (meeting.state == MeetingState.closed) {
        final records = courseClass.attendance[meeting.id] ?? const {};
        for (final student in courseClass.students) {
          final status = records[student.rollNumber]?.status;
          if (status == null || status == AttendanceStatus.unmarked) {
            issues.add(
              IntegrityIssue(
                code: 'CLOSED_MEETING_UNMARKED_STUDENT',
                severity: IntegritySeverity.error,
                message:
                    'Buổi đã chốt (${meeting.id}) vẫn còn sinh viên chưa điểm danh (${student.rollNumber}).',
                classId: classId,
                meetingId: meeting.id,
                rollNumber: student.rollNumber,
              ),
            );
          }
        }
      }
    }

    if (activeMeetingCount > 1) {
      issues.add(
        IntegrityIssue(
          code: 'MULTIPLE_ACTIVE_MEETINGS',
          severity: IntegritySeverity.error,
          message:
              'Lớp có $activeMeetingCount buổi đang mở cùng lúc (chỉ cho phép tối đa 1).',
          classId: classId,
        ),
      );
    }

    for (final entry in courseClass.attendance.entries) {
      final meetingId = entry.key;
      if (!seenMeetingIds.contains(meetingId)) {
        issues.add(
          IntegrityIssue(
            code: 'ORPHANED_MEETING_ATTENDANCE',
            severity: IntegritySeverity.warning,
            message:
                'Dữ liệu điểm danh tham chiếu tới buổi học không tồn tại: $meetingId.',
            classId: classId,
            meetingId: meetingId,
          ),
        );
      }

      for (final roll in entry.value.keys) {
        if (!validRolls.contains(roll)) {
          issues.add(
            IntegrityIssue(
              code: 'ORPHANED_STUDENT_ATTENDANCE',
              severity: IntegritySeverity.warning,
              message:
                  'Dữ liệu điểm danh tham chiếu tới MSSV ngoài danh sách lớp: $roll.',
              classId: classId,
              meetingId: meetingId,
              rollNumber: roll,
            ),
          );
        }
      }
    }

    for (final audit in courseClass.auditEvents) {
      if (audit.reason.trim().isEmpty) {
        issues.add(
          IntegrityIssue(
            code: 'AUDIT_EMPTY_REASON',
            severity: IntegritySeverity.error,
            message: 'Bản ghi audit (${audit.id}) thiếu lý do chỉnh sửa.',
            classId: classId,
            meetingId: audit.meetingId,
            rollNumber: audit.rollNumber,
          ),
        );
      }
    }

    return issues;
  }

  CourseClass repairCourseClass(
    CourseClass courseClass, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();

    final deduplicatedStudents = <Student>[];
    final seenUpperRolls = <String>{};
    final seenEmails = <String>{};
    final canonicalRollByUpper = <String, String>{};

    for (final student in courseClass.students) {
      final roll = student.rollNumber.trim();
      final upperRoll = roll.toUpperCase();
      final email = student.normalizedEmail;
      if (roll.isEmpty || student.fullName.trim().isEmpty) continue;
      if (!seenUpperRolls.add(upperRoll)) continue;
      if (email.isNotEmpty && email.contains('@') && !seenEmails.add(email)) {
        seenUpperRolls.remove(upperRoll);
        continue;
      }
      deduplicatedStudents.add(student);
      canonicalRollByUpper[upperRoll] = student.rollNumber;
    }

    var seenActive = false;
    final repairedMeetings = <Meeting>[];
    final validMeetingIds = <String>{};
    for (final meeting in courseClass.meetings) {
      if (!validMeetingIds.add(meeting.id)) continue;
      if (meeting.state == MeetingState.active) {
        if (!seenActive) {
          seenActive = true;
          repairedMeetings.add(meeting);
        } else {
          repairedMeetings.add(meeting.copyWith(state: MeetingState.upcoming));
        }
      } else {
        repairedMeetings.add(meeting);
      }
    }

    final cleanedAttendance = <String, Map<String, AttendanceRecord>>{};
    for (final entry in courseClass.attendance.entries) {
      if (!validMeetingIds.contains(entry.key)) continue;
      final validRecords = <String, AttendanceRecord>{};
      for (final recordEntry in entry.value.entries) {
        final canonicalRoll =
            canonicalRollByUpper[recordEntry.key.trim().toUpperCase()];
        if (canonicalRoll != null) {
          validRecords[canonicalRoll] = recordEntry.value;
        }
      }
      cleanedAttendance[entry.key] = validRecords;
    }

    for (final meeting in repairedMeetings) {
      if (meeting.state != MeetingState.closed) continue;
      final records = cleanedAttendance.putIfAbsent(meeting.id, () => {});
      for (final student in deduplicatedStudents) {
        final existing = records[student.rollNumber];
        if (existing == null || existing.status == AttendanceStatus.unmarked) {
          records[student.rollNumber] = AttendanceRecord(
            status: AttendanceStatus.absent,
            source: AttendanceSource.finalize,
            recordedAt: timestamp,
            note: 'Tự động điền vắng khi đồng bộ toàn vẹn dữ liệu.',
          );
        }
      }
    }

    final repairedAudit = <AuditEvent>[
      for (final audit in courseClass.auditEvents)
        audit.reason.trim().isEmpty
            ? AuditEvent(
                id: audit.id,
                createdAt: audit.createdAt,
                action: audit.action,
                reason: 'Bổ sung lý do kiểm toán mặc định khi đồng bộ dữ liệu.',
                rollNumber: audit.rollNumber,
                meetingId: audit.meetingId,
                oldValue: audit.oldValue,
                newValue: audit.newValue,
              )
            : audit,
    ];

    return courseClass.copyWith(
      students: deduplicatedStudents,
      meetings: repairedMeetings,
      attendance: cleanedAttendance,
      auditEvents: repairedAudit,
    );
  }
}
