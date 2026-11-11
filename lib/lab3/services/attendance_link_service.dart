import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models.dart';
import 'contracts.dart';

/// Remote relay keeps receiving when Android goes into the background.
class HttpAttendanceLinkService implements AttendanceLinkService {
  HttpAttendanceLinkService(this.auth, {String? baseUrl, http.Client? client})
    : _base = baseUrl ?? const String.fromEnvironment('ATTENDANCE_API_URL'),
      _client = client ?? http.Client();
  final AuthService auth;
  final String _base;
  final http.Client _client;
  Future<LinkSession?> current() async {
    final json = await _request('GET', '/api/sessions/current');
    return json['session'] == null
        ? null
        : LinkSession.fromJson(json['session'] as Map<String, dynamic>);
  }

  @override
  bool get configured {
    final uri = Uri.tryParse(_base);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Object? body,
  ]) async {
    if (!configured) {
      throw const AppProblem(
        'Chưa kết nối dịch vụ link. Bạn vẫn có thể điểm danh thủ công.',
      );
    }
    final uri = Uri.parse('${_base.replaceFirst(RegExp(r'/+$'), '')}$path');
    final token = await auth.token();
    final response = await _client
        .send(
          http.Request(method, uri)
            ..headers.addAll({
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            })
            ..body = body == null ? '' : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    final text = await response.stream.bytesToString().timeout(
      const Duration(seconds: 15),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppProblem(
        response.statusCode == 401
            ? 'Phiên đăng nhập hết hạn. Hãy đăng nhập lại.'
            : 'Không thể cập nhật link (${response.statusCode}). Thử lại hoặc dùng Thủ công.',
      );
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  @override
  Future<LinkSession> create(CourseClass course, Meeting meeting) =>
      createQr(course, meeting);
  Future<LinkSession> createQr(
    CourseClass course,
    Meeting meeting, {
    bool otp = false,
  }) async {
    final json = await _request('POST', '/api/sessions', {
      'classId': course.id,
      'mode': otp ? 'otp' : 'normal',
      'meetingId': meeting.id,
      'label': '${course.courseCode} · ${course.classCode}',
      'number': meeting.number,
      'meetingDate': meeting.startAt.toIso8601String().split('T').first,
      'students': course.students
          .map((s) => {'email': s.normalizedEmail})
          .toList(),
    });
    return LinkSession.fromJson(json);
  }

  @override
  Future<LinkUpdate> poll(LinkSession session) async {
    final json = await _request(
      'GET',
      '/api/sessions/${Uri.encodeComponent(session.id)}',
    );
    return LinkUpdate(
      LinkSession.fromJson(json),
      (json['submissions'] as List).map((value) {
        final row = value as Map<String, dynamic>;
        return LinkSubmission(
          row['email'] as String,
          DateTime.parse(row['at'] as String).toLocal(),
        );
      }).toList(),
    );
  }

  @override
  Future<void> stop(LinkSession session) async {
    await _request(
      'DELETE',
      '/api/sessions/${Uri.encodeComponent(session.id)}',
    );
  }
}
