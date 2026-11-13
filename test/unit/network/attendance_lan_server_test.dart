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

class _StubAuth implements AuthService {
  @override
  TeacherIdentity? get current => null;
  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<String> token() async => 't';
}

class _StubStudentVerifier implements StudentIdentityVerifier {
  _StubStudentVerifier({required this.email, required this.verified});

  final String email;
  final bool verified;

  @override
  Future<VerifiedStudentIdentity> verify(String idToken) async {
    if (idToken == 'bad-token') {
      throw StateError('Token không hợp lệ.');
    }
    return VerifiedStudentIdentity(email: email, verified: verified);
  }
}

void main() {
  late Directory tempDir;
  late AttendanceController controller;
  late RollingQrIssuer issuer;
  late AttendanceLanServer server;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lan_server_test_');
    controller = AttendanceController(
      teacherAuth: _StubAuth(),
      documentsDirectory: tempDir,
    );
    await controller.initialize();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 7, 30);
    controller.workspace = TeacherWorkspace(
      id: 'ws-lan',
      semester: 'FA26',
      semesterStart: start,
      classes: [
        CourseClass(
          id: 'cls-lan',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          scheduleCode: '11',
          students: const [
            Student(
              rollNumber: 'SE180001',
              email: 'student1@fpt.edu.vn',
              fullName: 'Student One',
            ),
            Student(
              rollNumber: 'SE180002',
              email: 'student2@fpt.edu.vn',
              fullName: 'Student Two',
            ),
          ],
          scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: start),
          meetings: [
            Meeting(
              id: 'cls-lan-m1',
              number: 1,
              startAt: start,
              endAt: start.add(const Duration(hours: 2)),
              state: MeetingState.active,
            ),
          ],
        ),
      ],
    );
    await controller.save();
    issuer = RollingQrIssuer(secret: 'lan-secret-123');
    server = AttendanceLanServer(controller: controller, issuer: issuer);
    await server.start(port: 0);
  });

  tearDown(() async {
    await server.stop();
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AttendanceLanServer.joinUrl', () {
    test('builds valid HTTPS /join URL and rejects invalid origins', () {
      final payload = issuer.issue(
        endpoint: server.endpoint,
        classId: 'cls-lan',
        meetingId: 'cls-lan-m1',
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.normal,
      );

      final url = server.joinUrl(payload, publicOrigin: 'https://abc.trycloudflare.com');
      final parsed = Uri.parse(url);
      expect(parsed.scheme, 'https');
      expect(parsed.path, '/join');
      expect(parsed.queryParameters['qr'], isNotEmpty);

      expect(() => server.joinUrl(payload, publicOrigin: ''), throwsStateError);
      expect(() => server.joinUrl(payload, publicOrigin: 'http://abc.com'), throwsStateError);
      expect(() => server.joinUrl(payload, publicOrigin: 'https://abc.com?x=1'), throwsStateError);
      expect(() => server.joinUrl(payload, publicOrigin: 'https://abc.com/sub'), throwsStateError);
    });
  });

  group('AttendanceLanServer HTTP & HTTPS endpoints', () {
    test('health endpoint returns healthy status', () async {
      final res = await http.get(Uri.parse('${server.localBrowserEndpoint}/api/v1/health'));
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map;
      expect(body['accepted'], isTrue);
      expect(body['code'], 'healthy');
    });

    test('/join renders HTML for active meeting and rejects missing/inactive/wrong-server QR', () async {
      final payload = issuer.issue(
        endpoint: server.endpoint,
        classId: 'cls-lan',
        meetingId: 'cls-lan-m1',
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.normal,
      );

      final okRes = await http.get(
        Uri.parse('${server.localBrowserEndpoint}/join').replace(
          queryParameters: {'qr': payload.encode()},
        ),
      );
      expect(okRes.statusCode, 200);
      expect(okRes.headers['content-type'], contains('text/html'));
      expect(okRes.body, contains('PRM392 · SE1801'));
      expect(okRes.headers['content-security-policy'], isNotNull);

      final missingRes = await http.get(Uri.parse('${server.localBrowserEndpoint}/join'));
      expect(missingRes.statusCode, 400);

      final wrongEndpoint = issuer.issue(
        endpoint: 'https://127.0.0.1:9999',
        classId: 'cls-lan',
        meetingId: 'cls-lan-m1',
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.normal,
      );
      final wrongRes = await http.get(
        Uri.parse('${server.localBrowserEndpoint}/join').replace(
          queryParameters: {'qr': wrongEndpoint.encode()},
        ),
      );
      expect(wrongRes.statusCode, 400);
    });

    test('full CheckInClient HTTPS flow in normal and OTP modes plus duplicate check-in', () async {
      final client = CheckInClient();
      final payload = issuer.issue(
        endpoint: server.endpoint,
        classId: 'cls-lan',
        meetingId: 'cls-lan-m1',
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.otp,
      );

      final challenge = await client.createChallenge(
        payload,
        payload.encode(),
        'phone-device-1',
      );
      expect(challenge.requiresOtp, isTrue);

      // Wrong OTP fails
      await expectLater(
        client.checkIn(
          payload: payload,
          challengeId: challenge.id,
          deviceId: 'phone-device-1',
          email: 'student1@fpt.edu.vn',
          otp: '000000',
        ),
        throwsStateError,
      );

      // Unknown email fails
      await expectLater(
        client.checkIn(
          payload: payload,
          challengeId: challenge.id,
          deviceId: 'phone-device-1',
          email: 'stranger@fpt.edu.vn',
          otp: issuer.activeOtp,
        ),
        throwsStateError,
      );

      // Valid check-in succeeds
      final msg = await client.checkIn(
        payload: payload,
        challengeId: challenge.id,
        deviceId: 'phone-device-1',
        email: 'student1@fpt.edu.vn',
        otp: issuer.activeOtp,
      );
      expect(msg, contains('Điểm danh thành công'));
      expect(
        controller.classById('cls-lan').recordFor('cls-lan-m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );

      // Repeat check-in with same email reports already_present
      final repeatMsg = await client.checkIn(
        payload: payload,
        challengeId: challenge.id,
        deviceId: 'phone-device-1',
        email: 'student1@fpt.edu.vn',
        otp: issuer.activeOtp,
      );
      expect(repeatMsg, contains('đã được ghi nhận'));
    });

    test('enforces Firebase bearer token verification when firebaseVerifier is configured', () async {
      await server.stop();
      final fbServer = AttendanceLanServer(
        controller: controller,
        issuer: issuer,
        firebaseVerifier: _StubStudentVerifier(
          email: 'student2@fpt.edu.vn',
          verified: true,
        ),
      );
      await fbServer.start(port: 0);
      try {
        final client = CheckInClient();
        final payload = issuer.issue(
          endpoint: fbServer.endpoint,
          classId: 'cls-lan',
          meetingId: 'cls-lan-m1',
          certificateFingerprint: fbServer.certificateFingerprint,
          mode: QrMode.normal,
        );
        final challenge = await client.createChallenge(
          payload,
          payload.encode(),
          'fb-dev-1',
        );

        // Missing bearer fails
        await expectLater(
          client.checkIn(
            payload: payload,
            challengeId: challenge.id,
            deviceId: 'fb-dev-1',
            email: 'student2@fpt.edu.vn',
          ),
          throwsStateError,
        );

        // Valid bearer succeeds
        final msg = await client.checkIn(
          payload: payload,
          challengeId: challenge.id,
          deviceId: 'fb-dev-1',
          email: 'ignored@fpt.edu.vn',
          firebaseIdToken: 'valid-id-token',
        );
        expect(msg, contains('Điểm danh thành công'));
        expect(
          controller.classById('cls-lan').recordFor('cls-lan-m1', 'SE180002')?.status,
          AttendanceStatus.present,
        );
      } finally {
        await fbServer.stop();
      }
    });
  });
}
