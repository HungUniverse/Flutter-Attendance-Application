import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:fap_attendance/mobile/check_in_client.dart';
import 'package:fap_attendance/network/lan_certificate.dart';
import 'package:fap_attendance/network/quick_tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

String _formatSha1(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join();

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
  });

  group('LanCertificate self-signed TLS generation & pinning', () {
    test('creates 2048-bit TLS context with formatted SHA-1 fingerprint', () {
      final cert = LanCertificate.create('127.0.0.1');

      expect(cert.fingerprint, isNotEmpty);
      expect(
        RegExp(r'^[0-9A-F]{40}$', caseSensitive: false)
            .hasMatch(cert.fingerprint),
        isTrue,
      );
      expect(cert.context, isA<SecurityContext>());
    });

    test('generates distinct keypairs and fingerprints on each invocation', () {
      final first = LanCertificate.create('127.0.0.1');
      final second = LanCertificate.create('localhost');

      expect(first.fingerprint, isNot(equals(second.fingerprint)));
    });

    test('serves valid TLS handshake verified via pinned SHA-1 certificate', () async {
      final cert = LanCertificate.create('127.0.0.1');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        cert.context,
      );
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.write('tls-ok');
        await req.response.close();
      });

      final client = HttpClient()
        ..badCertificateCallback = (peerCert, host, port) =>
            _formatSha1(peerCert.sha1) == cert.fingerprint.toUpperCase();
      addTearDown(() => client.close(force: true));

      final request = await client.getUrl(
        Uri.parse('https://127.0.0.1:${server.port}/ping'),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, HttpStatus.ok);
      expect(body, 'tls-ok');
    });

    test('rejects TLS handshake when pinned fingerprint differs', () async {
      final cert = LanCertificate.create('127.0.0.1');
      final other = LanCertificate.create('127.0.0.1');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        cert.context,
      );
      addTearDown(() => server.close(force: true));
      server.listen((req) async => req.response.close());

      final client = HttpClient()
        ..badCertificateCallback = (peerCert, host, port) =>
            _formatSha1(peerCert.sha1) == other.fingerprint.toUpperCase();
      addTearDown(() => client.close(force: true));

      await expectLater(
        () => client.getUrl(Uri.parse('https://127.0.0.1:${server.port}/ping')),
        throwsA(isA<HandshakeException>()),
      );
    });
  });

  group('QuickTunnel lifecycle & error guards', () {
    test('starts with null url and allows idempotent stop() calls', () async {
      final tunnel = QuickTunnel();
      expect(tunnel.url, isNull);
      await expectLater(tunnel.stop(), completes);
      await expectLater(tunnel.stop(), completes);
      expect(tunnel.url, isNull);
    });
  });

  group('CheckInClient certificate-pinned TLS requests & error mapping', () {
    final issuer = RollingQrIssuer();

    QrPayload makePayload(
      int port,
      String fingerprint, {
      QrMode mode = QrMode.normal,
    }) => issuer.issue(
      endpoint: 'https://127.0.0.1:$port',
      classId: 'c1',
      meetingId: 'm1',
      certificateFingerprint: fingerprint,
      mode: mode,
    );

    test('createChallenge & checkIn complete end-to-end over pinned HTTPS', () async {
      final cert = LanCertificate.create('127.0.0.1');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        cert.context,
      );
      addTearDown(() => server.close(force: true));

      final seenAuthHeaders = <String?>[];
      final seenBodies = <Map<String, Object?>>[];

      server.listen((req) async {
        seenAuthHeaders.add(req.headers.value(HttpHeaders.authorizationHeader));
        final text = await utf8.decodeStream(req);
        final jsonBody = Map<String, Object?>.from(jsonDecode(text) as Map);
        seenBodies.add(jsonBody);
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/api/v1/challenges') {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(
            jsonEncode({'challengeId': 'ch-99', 'requiresOtp': true}),
          );
        } else {
          req.response.statusCode = HttpStatus.ok;
          req.response.write(
            jsonEncode({'message': 'Điểm danh thành công!'}),
          );
        }
        await req.response.close();
      });

      final client = CheckInClient();
      final payload = makePayload(server.port, cert.fingerprint, mode: QrMode.otp);
      final encoded = payload.encode();

      final challenge = await client.createChallenge(payload, encoded, 'dev-1');
      expect(challenge.id, 'ch-99');
      expect(challenge.requiresOtp, isTrue);

      final msg = await client.checkIn(
        payload: payload,
        challengeId: challenge.id,
        deviceId: 'dev-1',
        email: 'sv1@fpt.edu.vn',
        otp: '123456',
        firebaseIdToken: 'fb-tok-77',
      );
      expect(msg, 'Điểm danh thành công!');
      expect(seenAuthHeaders, [null, 'Bearer fb-tok-77']);
      expect(seenBodies.last['otp'], '123456');
      expect(seenBodies.last['email'], 'sv1@fpt.edu.vn');
    });

    test('surfaces structured server error messages for 4xx/5xx responses', () async {
      final cert = LanCertificate.create('127.0.0.1');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        cert.context,
      );
      addTearDown(() => server.close(force: true));

      var mode = 'custom';
      server.listen((req) async {
        await utf8.decodeStream(req);
        req.response.headers.contentType = ContentType.json;
        req.response.statusCode = HttpStatus.badRequest;
        if (mode == 'custom') {
          req.response.write(jsonEncode({'message': 'Sai mã OTP.'}));
        } else {
          req.response.write(jsonEncode({'ok': false}));
        }
        await req.response.close();
      });

      final client = CheckInClient();
      final payload = makePayload(server.port, cert.fingerprint);

      await expectLater(
        () => client.checkIn(
          payload: payload,
          challengeId: 'ch-1',
          deviceId: 'dev-1',
          email: 'sv1@fpt.edu.vn',
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'Sai mã OTP.'),
        ),
      );

      mode = 'fallback';
      await expectLater(
        () => client.checkIn(
          payload: payload,
          challengeId: 'ch-1',
          deviceId: 'dev-1',
          email: 'sv1@fpt.edu.vn',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Điểm danh thất bại.',
          ),
        ),
      );
    });

    test('rejects server with mismatched TLS fingerprint', () async {
      final realCert = LanCertificate.create('127.0.0.1');
      final wrongCert = LanCertificate.create('127.0.0.1');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        realCert.context,
      );
      addTearDown(() => server.close(force: true));
      server.listen((req) async => req.response.close());

      final client = CheckInClient();
      final payload = makePayload(server.port, wrongCert.fingerprint);

      await expectLater(
        () => client.createChallenge(payload, payload.encode(), 'dev-1'),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('rejects non-JSON response payload from server', () async {
      final cert = LanCertificate.create('127.0.0.1');
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        cert.context,
      );
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        await utf8.decodeStream(req);
        req.response.statusCode = HttpStatus.ok;
        req.response.write('<html>not-json</html>');
        await req.response.close();
      });

      final client = CheckInClient();
      final payload = makePayload(server.port, cert.fingerprint);

      await expectLater(
        () => client.createChallenge(payload, payload.encode(), 'dev-1'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
