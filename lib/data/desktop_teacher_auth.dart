import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../lab3/services/contracts.dart';

class DesktopTeacherAuth implements AuthService {
  DesktopTeacherAuth({String? baseUrl})
    : base = baseUrl ?? const String.fromEnvironment('ATTENDANCE_API_URL');
  final String base;
  String? _token;
  final _changes = StreamController<TeacherIdentity?>.broadcast();
  @override
  TeacherIdentity? current;
  @override
  Stream<TeacherIdentity?> get changes => _changes.stream;
  Future<Map<String, dynamic>> _post(String path, Object data) async {
    final uri = Uri.parse('$base$path');
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const AppProblem(
        'Cần cấu hình ATTENDANCE_API_URL là máy chủ HTTPS.',
      );
    }
    final r = await http
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            if (_token != null) 'authorization': 'Bearer $_token',
          },
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      throw const AppProblem(
        'Không đăng nhập được. Kiểm tra máy chủ và quyền giảng viên.',
      );
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<void> signIn() async {
    final login = await _post('/api/desktop-login', {});
    final url = Uri.parse(login['url'] as String);
    if (url.origin != Uri.parse(base).origin || url.scheme != 'https') {
      throw const AppProblem('Địa chỉ đăng nhập không hợp lệ.');
    }
    await Process.run('rundll32.exe', [
      'url.dll,FileProtocolHandler',
      url.toString(),
    ]);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final result = await _post('/api/desktop-login/poll', {
        'ticket': login['ticket'],
        'secret': login['secret'],
      });
      if (result['pending'] == true) continue;
      _token = result['token'] as String;
      current = TeacherIdentity(
        result['uid'] as String,
        result['email'] as String,
        'Giảng viên',
      );
      _changes.add(current);
      return;
    }
    throw const AppProblem('Hết thời gian đăng nhập. Hãy thử lại.');
  }

  @override
  Future<void> signOut() async {
    try {
      await _post('/api/desktop-logout', {});
    } finally {
      _token = null;
      current = null;
      _changes.add(null);
    }
  }

  @override
  Future<String> token() async =>
      _token ?? (throw const AppProblem('Vui lòng đăng nhập Google.'));
}
