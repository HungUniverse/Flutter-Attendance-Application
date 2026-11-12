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
  FirebaseDesktopAuth(
    super.auth, {
    required this.hostingUrl,
    Future<void> Function(Uri)? openBrowser,
  }) : _openBrowser = openBrowser ?? _launchBrowser;
  final String hostingUrl;
  final Future<void> Function(Uri) _openBrowser;

  static Future<void> _launchBrowser(Uri url) async {
    final launch = await Process.run('rundll32.exe', [
      'url.dll,FileProtocolHandler',
      url.toString(),
    ]);
    if (launch.exitCode != 0) {
      throw const AppProblem('Không mở được trình duyệt đăng nhập.');
    }
  }

  @override
  Future<void> signIn() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    final state = base64Url.encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final result = Completer<String>();
    var callbackReceived = false;
    final subscription = server.listen(
      (request) async {
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/html; charset=utf-8',
        );
        final origins = request.headers['origin'] ?? const <String>[];
        final origin = origins.isEmpty ? null : origins.first;
        // HTTPS-to-loopback form navigation may redact Origin to "null".
        // The per-login random state binds these callbacks to this app.
        final untrustedOrigin =
            origin != null &&
            origin != 'null' &&
            origin != Uri.parse(hostingUrl).origin;
        if (origins.length > 1 ||
            request.method != 'POST' ||
            request.uri.path != '/callback' ||
            untrustedOrigin) {
          request.response.statusCode = HttpStatus.forbidden;
          await request.response.close();
          return;
        }
        String? receivedToken;
        try {
          if (request.headers.contentType?.mimeType !=
              'application/x-www-form-urlencoded') {
            throw const FormatException('Invalid callback content type');
          }
          final bytes = <int>[];
          await for (final chunk in request) {
            bytes.addAll(chunk);
            if (bytes.length > 32768) {
              throw const FormatException('Oversized credential');
            }
          }
          final values = Uri.splitQueryString(utf8.decode(bytes));
          if (values['state'] != state ||
              (values['idToken'] ?? '').isEmpty ||
              callbackReceived) {
            throw const FormatException('Invalid login callback');
          }
          callbackReceived = true;
          receivedToken = values['idToken'];
          request.response.write(
            '<!doctype html><html lang="vi"><meta charset="utf-8"><title>FAP Attendance</title><p>Đã nhận xác thực. Bạn có thể trở lại ứng dụng FAP Attendance.</p></html>',
          );
        } on Object {
          request.response.statusCode = HttpStatus.badRequest;
        } finally {
          // Flush the browser acknowledgement before Firebase sign-in can
          // finish and close this short-lived loopback server.
          await request.response.close().catchError((Object _) {});
          if (receivedToken != null && !result.isCompleted) {
            result.complete(receivedToken);
          }
        }
      },
      onError: (Object error) {
        if (!result.isCompleted) result.completeError(error);
      },
    );
    try {
      final url = Uri.parse('$hostingUrl/desktop-login')
          .replace(queryParameters: {'port': '${server.port}', 'state': state});
      await _openBrowser(url);
      final token = await result.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw const AppProblem(
          'Hết thời gian đăng nhập Google. Hãy thử lại.',
        ),
      );
      await auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: token),
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }
}
