import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';

import '../lab3/services/contracts.dart';
import '../lab3/services/firebase_services.dart';

/// Google OAuth runs in the system browser. A short-lived loopback listener
/// receives the Google credential, then the native Firebase SDK validates it.
class FirebaseDesktopAuth extends FirebaseTeacherAuth {
  FirebaseDesktopAuth(super.auth, {required this.hostingUrl});
  final String hostingUrl;

  @override
  Future<void> signIn() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final state = base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    final result = Completer<String>();
    final subscription = server.listen((request) async {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.headers.set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8');
      if (request.method != 'POST' || request.uri.path != '/callback'
          || request.headers.value('origin') != Uri.parse(hostingUrl).origin) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      try {
        final bytes = <int>[];
        await for (final chunk in request) {
          bytes.addAll(chunk);
          if (bytes.length > 32768) throw const FormatException('Oversized credential');
        }
        final values = Uri.splitQueryString(utf8.decode(bytes));
        if (values['state'] != state || (values['idToken'] ?? '').isEmpty || result.isCompleted) {
          throw const FormatException('Invalid login callback');
        }
        result.complete(values['idToken']);
        request.response.write('<!doctype html><html lang="vi"><meta charset="utf-8"><title>FAP Attendance</title><p>Đã nhận xác thực. Bạn có thể trở lại ứng dụng FAP Attendance.</p></html>');
      } on Object {
        request.response.statusCode = HttpStatus.badRequest;
      } finally {
        await request.response.close();
      }
    }, onError: (Object error) {
      if (!result.isCompleted) result.completeError(error);
    });
    try {
      final url = Uri.parse('$hostingUrl/desktop-login').replace(queryParameters: {'port': '${server.port}', 'state': state});
      final launch = await Process.run('rundll32.exe', ['url.dll,FileProtocolHandler', url.toString()]);
      if (launch.exitCode != 0) throw const AppProblem('Không mở được trình duyệt đăng nhập.');
      final token = await result.future.timeout(const Duration(minutes: 2), onTimeout: () => throw const AppProblem('Hết thời gian đăng nhập Google. Hãy thử lại.'));
      await auth.signInWithCredential(GoogleAuthProvider.credential(idToken: token));
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }
}
