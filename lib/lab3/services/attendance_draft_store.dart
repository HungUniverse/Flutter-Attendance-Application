import 'dart:convert';
import 'dart:io';

import '../../data/report_file_writer.dart';
import '../../domain/models.dart';
import 'contracts.dart';

class MeetingAttendanceDraft {
  MeetingAttendanceDraft({
    required this.semester,
    required this.classId,
    required this.meetingId,
    required this.startAt,
    required this.records,
  });
  final String semester;
  final String classId;
  final String meetingId;
  final DateTime startAt;
  final Map<String, AttendanceRecord> records;
  String get key => '$semester/$classId/$meetingId';
  Map<String, Object?> toJson() => {
    'semester': semester,
    'classId': classId,
    'meetingId': meetingId,
    'startAt': startAt.toIso8601String(),
    'records': records.map((roll, record) => MapEntry(roll, record.toJson())),
  };
  factory MeetingAttendanceDraft.fromJson(Map<String, dynamic> value) =>
      MeetingAttendanceDraft(
        semester: value['semester'] as String,
        classId: value['classId'] as String,
        meetingId: value['meetingId'] as String,
        startAt: DateTime.parse(value['startAt'] as String),
        records: (value['records'] as Map).map(
          (roll, record) => MapEntry(
            roll as String,
            AttendanceRecord.fromJson(Map<String, Object?>.from(record as Map)),
          ),
        ),
      );
}

/// A separate, device-local journal. Workspace outbox retries must never upload it.
class AttendanceDraftStore {
  AttendanceDraftStore(this.root);
  final Directory root;
  Future<void> _tail = Future.value();
  File _file(String uid) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(uid)) {
      throw const AppProblem('Tài khoản hoặc học kỳ không hợp lệ.');
    }
    return File('${root.path}/teachers/$uid/attendance-drafts.json');
  }

  Future<Map<String, MeetingAttendanceDraft>> load(String uid) async {
    await _tail;
    final file = _file(uid);
    if (!await file.exists()) return {};
    final rows = jsonDecode(await file.readAsString()) as List;
    final drafts = rows.map(
      (value) => MeetingAttendanceDraft.fromJson(
        Map<String, dynamic>.from(value as Map),
      ),
    );
    return {for (final draft in drafts) draft.key: draft};
  }

  Future<void> save(String uid, Map<String, MeetingAttendanceDraft> drafts) {
    // Freeze the selection now; later taps cannot mutate an earlier queued write.
    final bytes = utf8.encode(
      jsonEncode(drafts.values.map((d) => d.toJson()).toList()),
    );
    final file = _file(uid);
    final next = _tail.then((_) async {
      await file.parent.create(recursive: true);
      await writeReportAtomically(file, Stream.value(bytes));
    });
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}
