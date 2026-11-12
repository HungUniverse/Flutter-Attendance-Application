import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/data/firebase_desktop_auth.dart';

class _CredentialResult extends Fake implements UserCredential {}

class _Auth extends Fake implements FirebaseAuth {
  final tokens = <String?>[];
  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    tokens.add((credential as OAuthCredential).idToken);
    return _CredentialResult();
  }
}

Future<int> callbackRequest(
  Uri login, {
  String? origin,
  String? state,
  String token = 'synthetic-google-token',
  String method = 'POST',
  String path = '/callback',
  String contentType = 'application/x-www-form-urlencoded',
}) async {
  final client = HttpClient();
  try {
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: int.parse(login.queryParameters['port']!),
      path: path,
    );
    final request = await client.openUrl(method, uri);
    request.headers.contentType = ContentType.parse(contentType);
    if (origin != null) request.headers.set('origin', origin);
    if (method == 'POST') {
      request.write(
        Uri(
          queryParameters: {
            'state': state ?? login.queryParameters['state']!,
            'idToken': token,
          },
        ).query,
      );
    }
    final response = await request.close();
    await response.transform(utf8.decoder).join();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  for (final origin in ['https://attendance.example', 'null', null]) {
    test(
      'Windows login accepts a valid state with ${origin == null ? 'no Origin header' : 'Origin $origin'}',
      () async {
        final auth = _Auth();
        final login = FirebaseDesktopAuth(
          auth,
          hostingUrl: 'https://attendance.example',
          openBrowser: (uri) async {
            final status = await callbackRequest(uri, origin: origin);
            expect(status, HttpStatus.ok);
          },
        );
        await login.signIn();
        expect(auth.tokens, ['synthetic-google-token']);
      },
    );
  }

  test(
    'opaque-origin callbacks still reject wrong state and empty credentials',
    () async {
      final auth = _Auth();
      final login = FirebaseDesktopAuth(
        auth,
        hostingUrl: 'https://attendance.example',
        openBrowser: (uri) async {
          expect(
            await callbackRequest(uri, origin: 'null', state: 'wrong-state'),
            HttpStatus.badRequest,
          );
          expect(
            await callbackRequest(uri, origin: 'null', token: ''),
            HttpStatus.badRequest,
          );
          expect(auth.tokens, isEmpty);
          expect(await callbackRequest(uri, origin: 'null'), HttpStatus.ok);
        },
      );
      await login.signIn();
      expect(auth.tokens, ['synthetic-google-token']);
    },
  );

  test(
    'untrusted origins and unexpected requests cannot consume the login',
    () async {
      final auth = _Auth();
      final login = FirebaseDesktopAuth(
        auth,
        hostingUrl: 'https://attendance.example',
        openBrowser: (uri) async {
          expect(
            await callbackRequest(uri, origin: 'https://other.example'),
            HttpStatus.forbidden,
          );
          expect(
            await callbackRequest(uri, method: 'GET'),
            HttpStatus.forbidden,
          );
          expect(
            await callbackRequest(uri, path: '/other'),
            HttpStatus.forbidden,
          );
          expect(
            await callbackRequest(uri, contentType: 'application/json'),
            HttpStatus.badRequest,
          );
          expect(auth.tokens, isEmpty);
          expect(await callbackRequest(uri), HttpStatus.ok);
        },
      );
      await login.signIn();
      expect(auth.tokens, ['synthetic-google-token']);
    },
  );

  test('oversized credentials are rejected before a valid retry', () async {
    final auth = _Auth();
    final login = FirebaseDesktopAuth(
      auth,
      hostingUrl: 'https://attendance.example',
      openBrowser: (uri) async {
        try {
          expect(
            await callbackRequest(uri, token: 'x' * 32769),
            HttpStatus.badRequest,
          );
        } on HttpException {
          // Dart may reject an oversized streamed body by closing its socket.
          expect(auth.tokens, isEmpty);
        }
        expect(await callbackRequest(uri), HttpStatus.ok);
      },
    );
    await login.signIn();
    expect(auth.tokens, ['synthetic-google-token']);
  });

  test('concurrent valid callbacks exchange the credential once', () async {
    final auth = _Auth();
    final login = FirebaseDesktopAuth(
      auth,
      hostingUrl: 'https://attendance.example',
      openBrowser: (uri) async {
        final statuses = await Future.wait([
          callbackRequest(uri, origin: 'null'),
          callbackRequest(uri, origin: 'null'),
        ]);
        expect(
          statuses,
          unorderedEquals([HttpStatus.ok, HttpStatus.badRequest]),
        );
      },
    );
    await login.signIn();
    expect(auth.tokens, ['synthetic-google-token']);
  });
}
