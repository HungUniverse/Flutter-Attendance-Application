import 'models.dart';

class AttendanceService {
  CourseClass startMeeting(
    CourseClass courseClass,
    String meetingId, {
    DateTime? now,
  }) {
    if (courseClass.meetings.any((m) => m.state == MeetingState.active)) {
      throw StateError('Lớp đã có một slot điểm danh đang hoạt động.');
    }
    final meeting = courseClass.meetings.singleWhere((m) => m.id == meetingId);
    if (meeting.state != MeetingState.upcoming) {
      throw StateError('Chỉ có thể bắt đầu một slot chưa điểm danh.');
    }
    final current = now ?? DateTime.now();
    if (meeting.isBeforeDate(current)) {
      throw StateError('Slot đã qua ngày và đã bị khóa.');
    }
    if (meeting.isAfterDate(current)) {
      throw StateError('Chưa đến ngày học của slot này.');
    }
    return courseClass.copyWith(
      meetings: courseClass.meetings
          .map(
            (m) =>
                m.id == meetingId ? m.copyWith(state: MeetingState.active) : m,
          )
          .toList(),
    );
  }

  CourseClass markPresent(
    CourseClass courseClass, {
    required String meetingId,
    required String email,
    AttendanceSource source = AttendanceSource.scan,
    DateTime? now,
  }) {
    final meeting = courseClass.meetings.singleWhere((m) => m.id == meetingId);
    if (meeting.state != MeetingState.active) {
      throw StateError('Slot điểm danh không hoạt động.');
    }
    final recordedAt = now ?? DateTime.now();
    if (!meeting.isOnDate(recordedAt)) {
      throw StateError('Slot không thuộc ngày hôm nay và đã bị khóa.');
    }
    final normalized = email.trim().toLowerCase();
    final student = courseClass.students
        .where((s) => s.normalizedEmail == normalized)
        .firstOrNull;
    if (student == null) throw StateError('Email không thuộc danh sách lớp.');
    final attendance = _deepCopy(courseClass.attendance);
    attendance.putIfAbsent(meetingId, () => {});
    attendance[meetingId]![student.rollNumber] = AttendanceRecord(
      status: AttendanceStatus.present,
      source: source,
      recordedAt: recordedAt,
    );
    return courseClass.copyWith(attendance: attendance);
  }

  CourseClass closeMeeting(
    CourseClass courseClass,
    String meetingId, {
    DateTime? now,
  }) {
    final attendance = _deepCopy(courseClass.attendance);
    final records = attendance.putIfAbsent(meetingId, () => {});
    final recordedAt = now ?? DateTime.now();
    for (final student in courseClass.students) {
      records.putIfAbsent(
        student.rollNumber,
        () => AttendanceRecord(
          status: AttendanceStatus.absent,
          source: AttendanceSource.finalize,
          recordedAt: recordedAt,
        ),
      );
    }
    return courseClass.copyWith(
      attendance: attendance,
      meetings: courseClass.meetings
          .map(
            (m) =>
                m.id == meetingId ? m.copyWith(state: MeetingState.closed) : m,
          )
          .toList(),
    );
  }

  CourseClass finalizeOverdueMeetings(
    CourseClass courseClass, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    var updated = courseClass;
    for (final meeting in courseClass.meetings) {
      if (meeting.state != MeetingState.closed &&
          meeting.isBeforeDate(current)) {
        updated = closeMeeting(updated, meeting.id, now: current);
      }
    }
    return updated;
  }

  CourseClass overrideStatus(
    CourseClass courseClass, {
    required String meetingId,
    required String rollNumber,
    required AttendanceStatus status,
    required String reason,
    required String auditId,
    DateTime? now,
  }) {
    if (reason.trim().isEmpty) throw ArgumentError('Cần nhập lý do chỉnh sửa.');
    final meeting = courseClass.meetings.singleWhere((m) => m.id == meetingId);
    if (meeting.state == MeetingState.upcoming) {
      throw StateError('Không thể sửa slot chưa bắt đầu hoặc đã quá hạn.');
    }
    final at = now ?? DateTime.now();
    final attendance = _deepCopy(courseClass.attendance);
    final records = attendance.putIfAbsent(meetingId, () => {});
    final old = records[rollNumber];
    records[rollNumber] = AttendanceRecord(
      status: status,
      source: AttendanceSource.manual,
      recordedAt: at,
      note: reason.trim(),
    );
    final audit = [
      ...courseClass.auditEvents,
      AuditEvent(
        id: auditId,
        createdAt: at,
        action: 'attendance_override',
        reason: reason.trim(),
        rollNumber: rollNumber,
        meetingId: meetingId,
        oldValue: old == null ? '' : attendanceCode(old.status),
        newValue: attendanceCode(status),
      ),
    ];
    return courseClass.copyWith(attendance: attendance, auditEvents: audit);
  }

  double absenceRate(CourseClass courseClass, String rollNumber) {
    if (courseClass.meetings.isEmpty) return 0;
    var absent = 0;
    for (final meeting in courseClass.meetings) {
      if (courseClass.recordFor(meeting.id, rollNumber)?.status ==
          AttendanceStatus.absent) {
        absent++;
      }
    }
    return absent / courseClass.meetings.length;
  }

  static Map<String, Map<String, AttendanceRecord>> _deepCopy(
    Map<String, Map<String, AttendanceRecord>> source,
  ) => source.map((key, value) => MapEntry(key, Map.of(value)));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
