import 'dart:io';
import 'dart:typed_data';

import '../../domain/models.dart';
import 'report_destination.dart';

class TeacherIdentity {
  const TeacherIdentity(this.uid, this.email, this.name);
  final String uid;
  final String email;
  final String name;
}

abstract class AuthService {
  TeacherIdentity? get current;
  Stream<TeacherIdentity?> get changes;
  Future<void> signIn();
  Future<void> signOut();
  Future<String> token();
}

abstract class TelemetryService {
  Future<void> identify(String? uid);
  Future<void> event(String name, [Map<String, Object> parameters = const {}]);
  Future<void> error(Object error, StackTrace stack, String operation);
  Future<void> crashForDemo();
}

class FeatureSettings {
  const FeatureSettings({
    this.enableLink = true,
    this.exportHelp = 'Lưu PDF, JSON hoặc CSV trên thiết bị và chia sẻ tệp.',
    this.enableAi = true,
    this.aiModel = 'gemini-3.1-flash-lite',
    this.aiPrompt = 'Dựa trên số lượng tổng hợp, viết gợi ý ngắn bằng tiếng Việt để giảng viên kiểm tra trước khi chốt. Không suy đoán danh tính hoặc tự thay đổi kết quả. Trả JSON gồm summary và checks.',
  });
  final bool enableLink;
  final String exportHelp;
  final bool enableAi;
  final String aiModel;
  final String aiPrompt;
}

abstract class ConfigService {
  FeatureSettings get current;
  Future<void> refresh();
}

class AppNotice {
  const AppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    this.classId,
    this.meetingId,
  });
  final String id;
  final String title;
  final String body;
  final DateTime at;
  final String? classId;
  final String? meetingId;
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'at': at.toIso8601String(),
    'classId': classId,
    'meetingId': meetingId,
  };
  factory AppNotice.fromJson(Map<String, dynamic> json) => AppNotice(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    at: DateTime.parse(json['at'] as String),
    classId: json['classId'] as String?,
    meetingId: json['meetingId'] as String?,
  );
}

abstract class NotificationService {
  Stream<AppNotice> get opened;
  Future<void> start(String uid);
  Future<String> requestPermission();
  Future<String?> token();
  Future<List<AppNotice>> history(String uid);
  Future<void> stop();
}

abstract class UploadService {
  Future<void> upload(
    File file,
    ReportDestination destination,
    void Function(double) progress,
  );
}

abstract class DeviceService {
  Future<void> copy(String text);
  Future<void> shareText(String text);
  Future<void> shareFile(File file);
}

class LinkSession {
  const LinkSession({
    required this.id,
    required this.classId,
    required this.meetingId,
    required this.url,
    required this.expiresAt,
    this.receiving = true,
    this.code,
  });
  final String id;
  final String classId;
  final String meetingId;
  final String url;
  final DateTime expiresAt;
  final bool receiving;
  final String? code;
  Map<String, Object?> toJson() => {
    'id': id,
    'classId': classId,
    'meetingId': meetingId,
    'url': url,
    'expiresAt': expiresAt.toIso8601String(),
    'receiving': receiving,
  };
  factory LinkSession.fromJson(Map<String, dynamic> json) => LinkSession(
    id: json['id'] as String,
    classId: json['classId'] as String,
    meetingId: json['meetingId'] as String,
    url: json['url'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    receiving: json['receiving'] as bool? ?? true,
    code: json['code'] as String?,
  );
}

class LinkUpdate {
  const LinkUpdate(this.session, this.submissions);
  final LinkSession session;
  final List<LinkSubmission> submissions;
}

class LinkSubmission {
  const LinkSubmission(this.email, this.at);
  final String email;
  final DateTime at;
}

abstract class AttendanceLinkService {
  bool get configured;
  Future<LinkSession> create(CourseClass course, Meeting meeting);
  Future<LinkUpdate> poll(LinkSession session);
  Future<void> stop(LinkSession session);
}

abstract class MobileWorkspaceRepository {
  Future<List<String>> listSemesters(String uid);
  Future<TeacherWorkspace?> load(String uid, {String? semester});
  Future<void> save(String uid, TeacherWorkspace workspace);
  Future<void> saveSource(
    String uid,
    String semester,
    String name,
    Uint8List bytes,
  );
  Future<File> export(
    String uid,
    TeacherWorkspace workspace,
    CourseClass course,
    Meeting meeting,
    String format,
  );
  Future<void> archive(
    String uid,
    TeacherWorkspace workspace,
    CourseClass course,
  );
  Future<LinkSession?> loadLink(String uid);
  Future<void> saveLink(String uid, LinkSession? session);
}

class AppProblem implements Exception {
  const AppProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

class AttendanceLinkNotFound extends AppProblem {
  const AttendanceLinkNotFound() : super('Không tìm thấy phiên điểm danh.');
}
