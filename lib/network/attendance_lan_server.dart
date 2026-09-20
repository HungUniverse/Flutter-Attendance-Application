import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../application/attendance_controller.dart';
import '../domain/models.dart';
import '../domain/qr_protocol.dart';
import 'firebase_identity_verifier.dart';
import 'lan_certificate.dart';
import 'student_join_html.dart';

class AttendanceLanServer {
  AttendanceLanServer({
    required this.controller,
    required this.issuer,
    this.firebaseVerifier,
    this.allowLanAccess = false,
  }) : challenges = ChallengeStore(issuer);

  final AttendanceController controller;
  final RollingQrIssuer issuer;
  final StudentIdentityVerifier? firebaseVerifier;
  final bool allowLanAccess;
  final ChallengeStore challenges;

  HttpServer? _server;
  HttpServer? _browserServer;
  late LanCertificate _certificate;
  String? _host;

  String get endpoint => 'https://${_host!}:${_server!.port}';
  String get localBrowserEndpoint => 'http://${_host!}:${_browserServer!.port}';
  String get tunnelOrigin => 'http://127.0.0.1:${_browserServer!.port}';
  String get certificateFingerprint => _certificate.fingerprint;

  String joinUrl(QrPayload payload, {String? publicOrigin}) {
    final raw = publicOrigin?.trim() ?? '';
    if (raw.isEmpty) {
      throw StateError(
        'Đang chờ URL HTTPS công khai. Hãy bật tunnel để điện thoại quét QR.',
      );
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw StateError(
        'URL công khai phải là HTTPS origin, ví dụ https://abc.trycloudflare.com',
      );
    }
    return uri
        .replace(path: '/join', queryParameters: {'qr': payload.encode()})
        .toString();
  }

  Future<void> start({int port = 8787}) async {
    if (_server != null) return;
    _host = allowLanAccess
        ? await _findLanAddress()
        : InternetAddress.loopbackIPv4.address;
    _certificate = LanCertificate.create(_host!);
    final router = Router()
      ..get('/join', _join)
      ..get('/api/v1/health', _health)
      ..post('/api/v1/student-sign-in', _studentSignIn)
      ..post('/api/v1/challenges', _createChallenge)
      ..post('/api/v1/check-ins', _checkIn);
    final handler = router.call;
    _server = await shelf_io.serve(
      handler,
      allowLanAccess ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
      port,
      securityContext: _certificate.context,
    );
    try {
      _browserServer = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        port + 1,
      );
    } on Object {
      await _server?.close(force: true);
      _server = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    await _browserServer?.close(force: true);
    _server = null;
    _browserServer = null;
  }

  Response _join(Request request) {
    try {
      final encoded = request.url.queryParameters['qr'];
      if (encoded == null) {
        throw StateError('Link QR thiếu dữ liệu.');
      }
      final payload = QrPayload.decode(encoded);
      if (payload.endpoint != endpoint) {
        throw StateError('QR không thuộc máy chủ này.');
      }
      final meeting = controller.meetingById(
        payload.classId,
        payload.meetingId,
      );
      if (meeting.state != MeetingState.active) {
        throw StateError('Slot đã chốt.');
      }
      final course = controller.classById(payload.classId);
      final deviceId = const Uuid().v4();
      final challenge = challenges.create(payload, deviceId);
      return Response.ok(
        studentJoinHtml(
          challengeId: challenge.id,
          deviceId: deviceId,
          expiresAt: challenge.expiresAt,
          requiresOtp: challenge.requiresOtp,
          requiresFirebase: firebaseVerifier != null,
          courseLabel: '${course.courseCode} · ${course.classCode}',
          slotNumber: meeting.number,
        ),
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-store',
          'referrer-policy': 'no-referrer',
          'x-content-type-options': 'nosniff',
          'content-security-policy': "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; base-uri 'none'",
        },
      );
    } on Object catch (error) {
      return Response(
        400,
        body: error.toString().replaceFirst('Bad state: ', ''),
      );
    }
  }

  Future<Response> _studentSignIn(Request request) async {
    try {
      final verifier = firebaseVerifier;
      if (verifier is! FirebaseIdentityVerifier) {
        throw StateError('Đăng nhập Firebase chưa được cấu hình.');
      }
      final body = await _body(request);
      final email = (body['email'] as String? ?? '').trim();
      final password = body['password'] as String? ?? '';
      if (email.isEmpty || password.isEmpty) {
        throw StateError('Thiếu email hoặc mật khẩu.');
      }
      final response = await http.post(
        Uri.https(
          'identitytoolkit.googleapis.com',
          '/v1/accounts:signInWithPassword',
          {'key': verifier.apiKey},
        ),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );
      if (response.statusCode != 200) {
        throw StateError('Email hoặc mật khẩu không đúng.');
      }
      final data = (jsonDecode(response.body) as Map).cast<String, Object?>();
      return _json(200, {
        'accepted': true,
        'idToken': data['idToken'],
        'message': 'Đăng nhập thành công.',
      });
    } on Object catch (error) {
      return _error(error);
    }
  }

  Response _health(Request request) => _json(200, {
    'accepted': true,
    'code': 'healthy',
    'message': 'FAP Attendance desktop is ready.',
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
  });

  Future<Response> _createChallenge(Request request) async {
    try {
      final body = await _body(request);
      final payload = QrPayload.decode(body['qr']! as String);
      if (payload.endpoint != endpoint) {
        throw StateError('QR không thuộc máy chủ này.');
      }
      final meeting = controller.meetingById(
        payload.classId,
        payload.meetingId,
      );
      if (meeting.state != MeetingState.active) {
        throw StateError('Buổi điểm danh đã đóng.');
      }
      final challenge = challenges.create(payload, body['deviceId']! as String);
      return _json(200, {
        'accepted': true,
        'code': 'challenge_created',
        'message': 'QR hợp lệ.',
        'challengeId': challenge.id,
        'expiresAt': challenge.expiresAt.toIso8601String(),
        'requiresOtp': challenge.requiresOtp,
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object catch (error) {
      return _error(error);
    }
  }

  Future<Response> _checkIn(Request request) async {
    try {
      final body = await _body(request);
      final deviceId = body['deviceId']! as String;
      final pendingChallenge = challenges.validate(
        body['challengeId']! as String,
        deviceId: deviceId,
        otp: body['otp'] as String?,
      );
      String email;
      if (firebaseVerifier != null) {
        final authorization = request.headers['authorization'] ?? '';
        if (!authorization.startsWith('Bearer ')) {
          throw StateError('Thiếu Firebase ID token.');
        }
        final identity = await firebaseVerifier!.verify(
          authorization.substring(7),
        );
        if (!identity.verified) throw StateError('Email chưa được xác minh.');
        email = identity.email;
      } else {
        email = (body['email'] as String? ?? '').trim().toLowerCase();
      }
      final courseClass = controller.classById(pendingChallenge.classId);
      final student = courseClass.students
          .where((candidate) => candidate.normalizedEmail == email)
          .firstOrNull;
      if (student == null) throw StateError('Email không thuộc danh sách lớp.');
      final challenge = challenges.consume(
        body['challengeId']! as String,
        deviceId: deviceId,
        email: email,
        otp: body['otp'] as String?,
      );
      if (courseClass
              .recordFor(challenge.meetingId, student.rollNumber)
              ?.status ==
          AttendanceStatus.present) {
        return _json(200, {
          'accepted': true,
          'code': 'already_present',
          'message': 'Bạn đã được ghi nhận có mặt trước đó.',
          'recordedAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
      await controller.markPresent(
        challenge.classId,
        challenge.meetingId,
        email,
        source: AttendanceSource.scan,
      );
      return _json(200, {
        'accepted': true,
        'code': 'present_recorded',
        'message': 'Điểm danh thành công.',
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object catch (error) {
      return _error(error);
    }
  }

  Future<Map<String, Object?>> _body(Request request) async {
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > 16 * 1024) {
        throw StateError('Yêu cầu quá lớn.');
      }
    }
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
  }

  Response _error(Object error) => _json(400, {
    'accepted': false,
    'code': 'check_in_rejected',
    'message': error.toString().replaceFirst('Bad state: ', ''),
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
  });

  Response _json(int status, Map<String, Object?> body) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  static Future<String> _findLanAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final candidates = <(int, String)>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback || address.address.startsWith('169.254.')) {
          continue;
        }
        final name = interface.name.toLowerCase();
        var score = 0;
        if (name.contains('wi-fi') ||
            name.contains('wlan') ||
            name.contains('ethernet')) {
          score += 100;
        }
        if (name.contains('virtual') ||
            name.contains('wsl') ||
            name.contains('hyper-v') ||
            name.contains('vpn')) {
          score -= 100;
        }
        if (address.address.startsWith('192.168.')) score += 30;
        if (address.address.startsWith('10.')) score += 20;
        candidates.add((score, address.address));
      }
    }
    candidates.sort((a, b) => b.$1.compareTo(a.$1));
    return candidates.isEmpty
        ? InternetAddress.loopbackIPv4.address
        : candidates.first.$2;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
