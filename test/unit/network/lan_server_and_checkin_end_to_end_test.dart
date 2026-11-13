import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/mobile/check_in_client.dart';
import 'package:fap_attendance/network/attendance_lan_server.dart';
import 'package:fap_attendance/network/firebase_identity_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _OfflineAuth implements AuthService {
  @override
  TeacherIdentity? current;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<String> token() async => '';
}

class _UnverifiedVerifier implements StudentIdentityVerifier {
  const _UnverifiedVerifier({required this.email, required this.verified});
  final String email;
  final bool verified;

  @override
  Future<VerifiedStudentIdentity> verify(String idToken) async {
    if (idToken == 'invalid') throw StateError('Invalid token');
    return VerifiedStudentIdentity(email: email, verified: verified);
  }
}

class _MockHttpClient extends http.BaseClient {
  _MockHttpClient(this.handler);

  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bytes;
    final res = await handler(copy);
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
      request: request,
    );
  }
}

Future<int> _findFreePortPair() async {
  for (var candidate = 19100; candidate < 19300; candidate += 2) {
    try {
      final s1 = await ServerSocket.bind(InternetAddress.loopbackIPv4, candidate);
      await s1.close();
      final s2 = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        candidate + 1,
      );
      await s2.close();
      return candidate;
    } on SocketException {
      continue;
    }
  }
  throw StateError('No free consecutive port pair available for test');
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late Directory docsDir;
  late AttendanceController controller;
  late RollingQrIssuer issuer;
  late AttendanceLanServer server;
  final client = CheckInClient();

  CourseClass buildTodayClass({MeetingState state = MeetingState.active}) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
    return CourseClass(
      id: 'cls-lan',
      courseCode: 'PRM393',
      classCode: 'SE1801',
      scheduleCode: '11',
      students: const [
        Student(
          rollNumber: 'SE180001',
          email: 'an@fpt.edu.vn',
          fullName: 'Nguyen Van An',
        ),
        Student(
          rollNumber: 'SE180002',
          email: 'binh@fpt.edu.vn',
          fullName: 'Tran Thi Binh',
        ),
      ],
      scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: todayStart),
      meetings: [
        Meeting(
          id: 'm1',
          number: 1,
          startAt: todayStart,
          endAt: todayStart.add(const Duration(hours: 2)),
          state: state,
        ),
      ],
    );
  }

  Future<void> startServer({StudentIdentityVerifier? verifier}) async {
    issuer = RollingQrIssuer(secret: 'lan-test-secret');
    server = AttendanceLanServer(
      controller: controller,
      issuer: issuer,
      firebaseVerifier: verifier,
      allowLanAccess: false,
    );
    final port = await _findFreePortPair();
    await server.start(port: port);
  }

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('lan_e2e_test_');
    controller = AttendanceController(
      teacherAuth: _OfflineAuth(),
      documentsDirectory: docsDir,
    );
    await controller.initialize();
    controller.workspace = TeacherWorkspace(
      id: 'ws-lan',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: [buildTodayClass()],
    );
  });

  tearDown(() async {
    await server.stop();
    controller.dispose();
    if (await docsDir.exists()) {
      await docsDir.delete(recursive: true);
    }
  });

  group('AttendanceLanServer & CheckInClient pinned-TLS end-to-end flows', () {
    test('validates joinUrl HTTPS public origins cleanly', () async {
      await startServer();
      final payload = issuer.issue(
        endpoint: server.endpoint,
        classId: 'cls-lan',
        meetingId: 'm1',
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.normal,
      );

      expect(
        () => server.joinUrl(payload, publicOrigin: null),
        throwsStateError,
      );
      expect(
        () => server.joinUrl(payload, publicOrigin: 'http://bad.example.com'),
        throwsStateError,
      );
      expect(
        () => server.joinUrl(
          payload,
          publicOrigin: 'https://abc.trycloudflare.com/extra',
        ),
        throwsStateError,
      );

      final url = server.joinUrl(
        payload,
        publicOrigin: 'https://demo.trycloudflare.com/',
      );
      expect(url, startsWith('https://demo.trycloudflare.com/join?qr='));
    });

    test('serves health, HTML join page with strict CSP headers, and completes pinned TLS OTP check-in', () async {
      await startServer();

      final healthRes = await http.get(
        Uri.parse('${server.tunnelOrigin}/api/v1/health'),
      );
      expect(healthRes.statusCode, 200);
      expect(jsonDecode(healthRes.body)['code'], 'healthy');

      final payload = issuer.issue(
        endpoint: server.endpoint,
        classId: 'cls-lan',
        meetingId: 'm1',
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.otp,
      );
      final encoded = payload.encode();
      final otp = issuer.otpFor(payload);

      // Verify browser /join HTML endpoint and security headers
      final joinRes = await http.get(
        Uri.parse('${server.tunnelOrigin}/join?qr=$encoded'),
      );
      expect(joinRes.statusCode, 200);
      expect(joinRes.headers['cache-control'], 'no-store');
      expect(joinRes.headers['referrer-policy'], 'no-referrer');
      expect(joinRes.headers['x-content-type-options'], 'nosniff');
      expect(joinRes.headers['content-security-policy'], contains("default-src 'none'"));
      expect(joinRes.body, contains('PRM393 · SE1801 · Slot 1'));

      // Execute TLS-pinned mobile CheckInClient challenge + check-in
      final challenge = await client.createChallenge(
        payload,
        encoded,
        'pixel-8-pro',
      );
      expect(challenge.requiresOtp, isTrue);

      // Wrong OTP is rejected by server
      await expectLater(
        () => client.checkIn(
          payload: payload,
          challengeId: challenge.id,
          deviceId: 'pixel-8-pro',
          email: 'an@fpt.edu.vn',
          otp: '000000',
        ),
        throwsStateError,
      );

      // Valid OTP succeeds and marks student present
      final okMsg = await client.checkIn(
        payload: payload,
        challengeId: challenge.id,
        deviceId: 'pixel-8-pro',
        email: 'AN@FPT.EDU.VN',
        otp: otp,
      );
      expect(okMsg, contains('thành công'));
      expect(
        controller.classById('cls-lan').recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );

      // Duplicate check-in from same student returns already_present gracefully
      final repeatMsg = await client.checkIn(
        payload: payload,
        challengeId: challenge.id,
        deviceId: 'pixel-8-pro',
        email: 'an@fpt.edu.vn',
        otp: otp,
      );
      expect(repeatMsg, contains('trước đó'));

      // Unknown student email is rejected
      final unknownChallenge = await client.createChallenge(
        payload,
        encoded,
        'pixel-9',
      );
      await expectLater(
        () => client.checkIn(
          payload: payload,
          challengeId: unknownChallenge.id,
          deviceId: 'pixel-9',
          email: 'outsider@fpt.edu.vn',
          otp: otp,
        ),
        throwsStateError,
      );
    });

    test('rejects pinned TLS client when certificate fingerprint mismatches server cert', () async {
      await startServer();
      final badPayload = issuer.issue(
        endpoint: server.endpoint,
        classId: 'cls-lan',
        meetingId: 'm1',
        certificateFingerprint: '00:00:00:00:00:00:00:00:00:00',
        mode: QrMode.normal,
      );

      await expectLater(
        () => client.createChallenge(
          badPayload,
          badPayload.encode(),
          'device-bad-pin',
        ),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('enforces Firebase bearer token & emailVerified when verifier is attached', () async {
      await startServer(
        verifier: const _UnverifiedVerifier(
          email: 'binh@fpt.edu.vn',
          verified: false,
        ),
      );
      final payload = issuer.issue(
        endpoint: server.endpoint,
        classId: 'cls-lan',
        meetingId: 'm1',
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.normal,
      );
      final challenge = await client.createChallenge(
        payload,
        payload.encode(),
        'dev-fb',
      );

      // Missing bearer header rejected
      await expectLater(
        () => client.checkIn(
          payload: payload,
          challengeId: challenge.id,
          deviceId: 'dev-fb',
          email: 'binh@fpt.edu.vn',
        ),
        throwsStateError,
      );

      // Unverified email rejected
      await expectLater(
        () => client.checkIn(
          payload: payload,
          challengeId: challenge.id,
          deviceId: 'dev-fb',
          email: 'binh@fpt.edu.vn',
          firebaseIdToken: 'valid-token',
        ),
        throwsStateError,
      );
    });

    test('rejects oversized body (>16KB) and closed meetings on join/challenge endpoints', () async {
      await startServer();
      final payload = issuer.issue(
        endpoint: server.endpoint,
        classId: 'cls-lan',
        meetingId: 'm1',
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.normal,
      );

      // Oversized payload (>16KB) is rejected by server body limit (400 or stream abort)
      try {
        final bigRes = await http.post(
          Uri.parse('${server.tunnelOrigin}/api/v1/challenges'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'pad': 'A' * 20000}),
        );
        expect(bigRes.statusCode, 400);
        expect(jsonDecode(bigRes.body)['message'], contains('quá lớn'));
      } on http.ClientException catch (err) {
        // On Windows loopback, shelf_io closing unread >16KB body stream resets socket
        expect(err.message, isNotEmpty);
      }

      // Close meeting -> /join and /challenges reject requests
      await controller.closeMeeting('cls-lan', 'm1');
      final closedJoin = await http.get(
        Uri.parse('${server.tunnelOrigin}/join?qr=${payload.encode()}'),
      );
      expect(closedJoin.statusCode, 400);
      expect(closedJoin.body, contains('đã chốt'));
      final closedChallenge = await http.post(
        Uri.parse('${server.tunnelOrigin}/api/v1/challenges'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'qr': payload.encode(), 'deviceId': 'dev-closed'}),
      );
      expect(closedChallenge.statusCode, 400);
      expect(jsonDecode(closedChallenge.body)['message'], contains('đã đóng'));
    });
  });

  group('FirebaseIdentityVerifier & Lab2IdentityVerifier', () {
    test('verifies valid lookup response and rejects non-200 or empty users', () async {
      var mode = 'ok';
      final verifier = FirebaseIdentityVerifier(
        apiKey: 'fake-api-key',
        client: _MockHttpClient((req) async {
          expect(req.url.queryParameters['key'], 'fake-api-key');
          if (mode == 'err') return http.Response('denied', 403);
          if (mode == 'empty') return http.Response(jsonEncode({'users': []}), 200);
          return http.Response(
            jsonEncode({
              'users': [
                {'email': '  Student@FPT.EDU.VN ', 'emailVerified': true},
              ],
            }),
            200,
          );
        }),
      );

      final ok = await verifier.verify('tok-1');
      expect(ok.email, 'student@fpt.edu.vn');
      expect(ok.verified, isTrue);

      mode = 'empty';
      await expectLater(() => verifier.verify('tok-2'), throwsStateError);

      mode = 'err';
      await expectLater(() => verifier.verify('tok-3'), throwsStateError);

      const lab2 = Lab2IdentityVerifier('  An@FPT.edu.vn ');
      final l2Res = await lab2.verify('anything');
      expect(l2Res.email, 'an@fpt.edu.vn');
      expect(l2Res.verified, isTrue);
    });
  });
}
