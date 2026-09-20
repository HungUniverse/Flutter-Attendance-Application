import 'dart:convert';

enum MeetingState { upcoming, active, closed }

enum AttendanceStatus { unmarked, present, absent }

enum AttendanceSource { scan, manual, finalize, simulator }

enum QrMode { normal, otp }

enum SyncState { localOnly, pendingSync, synced, conflict }

String attendanceCode(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => 'P',
  AttendanceStatus.absent => 'A',
  AttendanceStatus.unmarked => '',
};

AttendanceStatus attendanceStatusFromCode(String value) => switch (value) {
  'P' => AttendanceStatus.present,
  'A' => AttendanceStatus.absent,
  _ => AttendanceStatus.unmarked,
};

class Student {
  const Student({
    required this.rollNumber,
    required this.email,
    required this.fullName,
    this.memberCode = '',
  });

  final String rollNumber;
  final String memberCode;
  final String email;
  final String fullName;

  String get normalizedEmail => email.trim().toLowerCase();

  Map<String, Object?> toJson() => {
    'rollNumber': rollNumber,
    'memberCode': memberCode,
    'email': email,
    'fullName': fullName,
  };

  factory Student.fromJson(Map<String, Object?> json) => Student(
    rollNumber: json['rollNumber']! as String,
    memberCode: (json['memberCode'] as String?) ?? '',
    email: json['email']! as String,
    fullName: json['fullName']! as String,
  );
}

class ScheduleRule {
  const ScheduleRule({
    required this.scheduleCode,
    required this.semesterStart,
    this.weeks = 10,
    this.meetingsPerWeek = 2,
    this.weekdays = const [],
    this.excludedDates = const [],
    this.additionalStarts = const [],
  });

  final String scheduleCode;
  final DateTime semesterStart;
  final int weeks;
  final int meetingsPerWeek;
  final List<int> weekdays;
  final List<DateTime> excludedDates;
  final List<DateTime> additionalStarts;

  int get dayGroup => int.tryParse(scheduleCode.substring(0, 1)) ?? 0;
  int get dailySlot => int.tryParse(scheduleCode.substring(1, 2)) ?? 0;

  Map<String, Object?> toJson() => {
    'scheduleCode': scheduleCode,
    'semesterStart': semesterStart.toIso8601String(),
    'weeks': weeks,
    'meetingsPerWeek': meetingsPerWeek,
    'weekdays': weekdays,
    'excludedDates': excludedDates.map((e) => e.toIso8601String()).toList(),
    'additionalStarts': additionalStarts
        .map((e) => e.toIso8601String())
        .toList(),
  };

  factory ScheduleRule.fromJson(Map<String, Object?> json) => ScheduleRule(
    scheduleCode: json['scheduleCode']! as String,
    semesterStart: DateTime.parse(json['semesterStart']! as String),
    weeks: (json['weeks'] as num?)?.toInt() ?? 10,
    meetingsPerWeek: (json['meetingsPerWeek'] as num?)?.toInt() ?? 2,
    weekdays: ((json['weekdays'] as List?) ?? const [])
        .map((value) => (value as num).toInt())
        .toList(),
    excludedDates: ((json['excludedDates'] as List?) ?? const [])
        .map((e) => DateTime.parse(e as String))
        .toList(),
    additionalStarts: ((json['additionalStarts'] as List?) ?? const [])
        .map((e) => DateTime.parse(e as String))
        .toList(),
  );
}

class Meeting {
  const Meeting({
    required this.id,
    required this.number,
    required this.startAt,
    required this.endAt,
    this.state = MeetingState.upcoming,
  });

  final String id;
  final int number;
  final DateTime startAt;
  final DateTime endAt;
  final MeetingState state;

  Meeting copyWith({MeetingState? state}) => Meeting(
    id: id,
    number: number,
    startAt: startAt,
    endAt: endAt,
    state: state ?? this.state,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'number': number,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'state': state.name,
  };

  factory Meeting.fromJson(Map<String, Object?> json) => Meeting(
    id: json['id']! as String,
    number: (json['number']! as num).toInt(),
    startAt: DateTime.parse(json['startAt']! as String),
    endAt: DateTime.parse(json['endAt']! as String),
    state: MeetingState.values.byName(json['state']! as String),
  );

  bool isOnDate(DateTime value) {
    final localStart = startAt.toLocal();
    final localValue = value.toLocal();
    return localStart.year == localValue.year &&
        localStart.month == localValue.month &&
        localStart.day == localValue.day;
  }

  bool isBeforeDate(DateTime value) {
    final localStart = startAt.toLocal();
    final localValue = value.toLocal();
    final meetingDate = DateTime(
      localStart.year,
      localStart.month,
      localStart.day,
    );
    final comparedDate = DateTime(
      localValue.year,
      localValue.month,
      localValue.day,
    );
    return meetingDate.isBefore(comparedDate);
  }

  bool isAfterDate(DateTime value) => !isOnDate(value) && !isBeforeDate(value);
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.status,
    required this.source,
    required this.recordedAt,
    this.note,
  });

  final AttendanceStatus status;
  final AttendanceSource source;
  final DateTime recordedAt;
  final String? note;

  Map<String, Object?> toJson() => {
    'status': attendanceCode(status),
    'source': source.name,
    'recordedAt': recordedAt.toIso8601String(),
    if (note != null) 'note': note,
  };

  factory AttendanceRecord.fromJson(Map<String, Object?> json) =>
      AttendanceRecord(
        status: attendanceStatusFromCode((json['status'] as String?) ?? ''),
        source: AttendanceSource.values.byName(json['source']! as String),
        recordedAt: DateTime.parse(json['recordedAt']! as String),
        note: json['note'] as String?,
      );
}

class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.createdAt,
    required this.action,
    required this.reason,
    this.rollNumber,
    this.meetingId,
    this.oldValue,
    this.newValue,
  });

  final String id;
  final DateTime createdAt;
  final String action;
  final String reason;
  final String? rollNumber;
  final String? meetingId;
  final String? oldValue;
  final String? newValue;

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'action': action,
    'reason': reason,
    'rollNumber': rollNumber,
    'meetingId': meetingId,
    'oldValue': oldValue,
    'newValue': newValue,
  };

  factory AuditEvent.fromJson(Map<String, Object?> json) => AuditEvent(
    id: json['id']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    action: json['action']! as String,
    reason: json['reason']! as String,
    rollNumber: json['rollNumber'] as String?,
    meetingId: json['meetingId'] as String?,
    oldValue: json['oldValue'] as String?,
    newValue: json['newValue'] as String?,
  );
}

class CourseClass {
  const CourseClass({
    required this.id,
    required this.courseCode,
    required this.classCode,
    required this.scheduleCode,
    required this.students,
    required this.scheduleRule,
    required this.meetings,
    this.attendance = const {},
    this.auditEvents = const [],
  });

  final String id;
  final String courseCode;
  final String classCode;
  final String scheduleCode;
  final List<Student> students;
  final ScheduleRule scheduleRule;
  final List<Meeting> meetings;
  final Map<String, Map<String, AttendanceRecord>> attendance;
  final List<AuditEvent> auditEvents;

  CourseClass copyWith({
    List<Student>? students,
    ScheduleRule? scheduleRule,
    List<Meeting>? meetings,
    Map<String, Map<String, AttendanceRecord>>? attendance,
    List<AuditEvent>? auditEvents,
  }) => CourseClass(
    id: id,
    courseCode: courseCode,
    classCode: classCode,
    scheduleCode: scheduleCode,
    students: students ?? this.students,
    scheduleRule: scheduleRule ?? this.scheduleRule,
    meetings: meetings ?? this.meetings,
    attendance: attendance ?? this.attendance,
    auditEvents: auditEvents ?? this.auditEvents,
  );

  AttendanceRecord? recordFor(String meetingId, String rollNumber) =>
      attendance[meetingId]?[rollNumber];

  Map<String, Object?> toJson() => {
    'id': id,
    'courseCode': courseCode,
    'classCode': classCode,
    'scheduleCode': scheduleCode,
    'students': students.map((e) => e.toJson()).toList(),
    'scheduleRule': scheduleRule.toJson(),
    'meetings': meetings.map((e) => e.toJson()).toList(),
    'attendance': attendance.map(
      (meetingId, records) => MapEntry(
        meetingId,
        records.map((roll, record) => MapEntry(roll, record.toJson())),
      ),
    ),
    'auditEvents': auditEvents.map((e) => e.toJson()).toList(),
  };

  factory CourseClass.fromJson(Map<String, Object?> json) => CourseClass(
    id: json['id']! as String,
    courseCode: json['courseCode']! as String,
    classCode: json['classCode']! as String,
    scheduleCode: json['scheduleCode']! as String,
    students: (json['students']! as List)
        .map((e) => Student.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    scheduleRule: ScheduleRule.fromJson(
      (json['scheduleRule']! as Map).cast<String, Object?>(),
    ),
    meetings: (json['meetings']! as List)
        .map((e) => Meeting.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
    attendance: ((json['attendance'] as Map?) ?? const {}).map(
      (meetingId, records) => MapEntry(
        meetingId as String,
        (records as Map).map(
          (roll, record) => MapEntry(
            roll as String,
            AttendanceRecord.fromJson((record as Map).cast<String, Object?>()),
          ),
        ),
      ),
    ),
    auditEvents: ((json['auditEvents'] as List?) ?? const [])
        .map((e) => AuditEvent.fromJson((e as Map).cast<String, Object?>()))
        .toList(),
  );
}

class TeacherWorkspace {
  const TeacherWorkspace({
    required this.id,
    required this.semester,
    required this.semesterStart,
    required this.classes,
    this.schemaVersion = 1,
    this.teacherEmail = '',
    this.syncState = SyncState.localOnly,
    this.updatedAt,
  });

  final int schemaVersion;
  final String id;
  final String semester;
  final DateTime semesterStart;
  final String teacherEmail;
  final List<CourseClass> classes;
  final SyncState syncState;
  final DateTime? updatedAt;

  TeacherWorkspace copyWith({
    List<CourseClass>? classes,
    String? teacherEmail,
    SyncState? syncState,
    DateTime? updatedAt,
  }) => TeacherWorkspace(
    schemaVersion: schemaVersion,
    id: id,
    semester: semester,
    semesterStart: semesterStart,
    teacherEmail: teacherEmail ?? this.teacherEmail,
    classes: classes ?? this.classes,
    syncState: syncState ?? this.syncState,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'semester': semester,
    'semesterStart': semesterStart.toIso8601String(),
    'teacherEmail': teacherEmail,
    'classes': classes.map((e) => e.toJson()).toList(),
    'syncState': syncState.name,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory TeacherWorkspace.fromJson(Map<String, Object?> json) =>
      TeacherWorkspace(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        id: json['id']! as String,
        semester: json['semester']! as String,
        semesterStart: DateTime.parse(json['semesterStart']! as String),
        teacherEmail: (json['teacherEmail'] as String?) ?? '',
        classes: (json['classes']! as List)
            .map(
              (e) => CourseClass.fromJson((e as Map).cast<String, Object?>()),
            )
            .toList(),
        syncState: SyncState.values.byName(
          (json['syncState'] as String?) ?? SyncState.localOnly.name,
        ),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt']! as String),
      );

  factory TeacherWorkspace.decode(String source) => TeacherWorkspace.fromJson(
    (jsonDecode(source) as Map).cast<String, Object?>(),
  );
}
