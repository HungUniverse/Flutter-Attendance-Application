import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class QrPayload {
  const QrPayload({
    required this.endpoint,
    required this.classId,
    required this.meetingId,
    required this.token,
    required this.issuedAt,
    required this.expiresAt,
    required this.certificateFingerprint,
    required this.mode,
    this.version = 1,
  });

  final int version;
  final String endpoint;
  final String classId;
  final String meetingId;
  final String token;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String certificateFingerprint;
  final QrMode mode;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'v': version,
        'endpoint': endpoint,
        'classId': classId,
        'meetingId': meetingId,
        'token': token,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'certificateFingerprint': certificateFingerprint,
        'mode': mode.name,
      }),
    ),
  );

  factory QrPayload.decode(String source) {
    final normalized = base64Url.normalize(source.trim());
    final json = (jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map)
        .cast<String, Object?>();
    return QrPayload(
      version: (json['v'] as num).toInt(),
      endpoint: json['endpoint']! as String,
      classId: json['classId']! as String,
      meetingId: json['meetingId']! as String,
      token: json['token']! as String,
      issuedAt: DateTime.parse(json['issuedAt']! as String),
      expiresAt: DateTime.parse(json['expiresAt']! as String),
      certificateFingerprint: json['certificateFingerprint']! as String,
      mode: QrMode.values.byName(json['mode']! as String),
    );
  }
}

class RollingQrIssuer {
  RollingQrIssuer({String? secret}) : _secret = secret ?? _randomToken(32);

  final String _secret;

  QrPayload issue({
    required String endpoint,
    required String classId,
    required String meetingId,
    required String certificateFingerprint,
    required QrMode mode,
    DateTime? now,
  }) {
    final at = (now ?? DateTime.now()).toUtc();
    final window =
        at.millisecondsSinceEpoch ~/ const Duration(seconds: 15).inMilliseconds;
    final token = _hmac('$classId|$meetingId|$window');
    return QrPayload(
      endpoint: endpoint,
      classId: classId,
      meetingId: meetingId,
      token: token,
      issuedAt: at,
      expiresAt: at.add(const Duration(seconds: 20)),
      certificateFingerprint: certificateFingerprint,
      mode: mode,
    );
  }

  String otpFor(QrPayload payload) {
    final value = int.parse(
      _hmac('otp|${payload.token}').substring(0, 8),
      radix: 16,
    );
    return (value % 1000000).toString().padLeft(6, '0');
  }

  bool verify(QrPayload payload, {DateTime? now}) {
    final at = (now ?? DateTime.now()).toUtc();
    if (at.isAfter(payload.expiresAt.toUtc())) return false;
    final windows = [
      payload.issuedAt.toUtc().millisecondsSinceEpoch ~/ 15000,
      at.millisecondsSinceEpoch ~/ 15000,
      at.millisecondsSinceEpoch ~/ 15000 - 1,
    ];
    return windows.any(
      (window) => _constantTimeEquals(
        payload.token,
        _hmac('${payload.classId}|${payload.meetingId}|$window'),
      ),
    );
  }

  String _hmac(String value) =>
      Hmac(sha256, utf8.encode(_secret)).convert(utf8.encode(value)).toString();

  static String _randomToken(int bytes) {
    final random = Random.secure();
    return base64UrlEncode(
      List<int>.generate(bytes, (_) => random.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var result = 0;
    for (var i = 0; i < left.length; i++) {
      result |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return result == 0;
  }
}

class CheckInChallenge {
  const CheckInChallenge({
    required this.id,
    required this.deviceId,
    required this.classId,
    required this.meetingId,
    required this.expiresAt,
    required this.requiresOtp,
    this.otp,
    this.used = false,
    this.usedByEmail,
  });

  final String id;
  final String deviceId;
  final String classId;
  final String meetingId;
  final DateTime expiresAt;
  final bool requiresOtp;
  final String? otp;
  final bool used;
  final String? usedByEmail;

  CheckInChallenge markUsed(String email) => CheckInChallenge(
    id: id,
    deviceId: deviceId,
    classId: classId,
    meetingId: meetingId,
    expiresAt: expiresAt,
    requiresOtp: requiresOtp,
    otp: otp,
    used: true,
    usedByEmail: email.trim().toLowerCase(),
  );
}

class ChallengeStore {
  ChallengeStore(this.issuer);
  final RollingQrIssuer issuer;
  final Map<String, CheckInChallenge> _challenges = {};

  CheckInChallenge create(QrPayload payload, String deviceId, {DateTime? now}) {
    final at = (now ?? DateTime.now()).toUtc();
    _challenges.removeWhere((_, challenge) => at.isAfter(challenge.expiresAt));
    if (!issuer.verify(payload, now: at)) throw StateError('QR đã hết hạn.');
    final challenge = CheckInChallenge(
      id: const Uuid().v4(),
      deviceId: deviceId,
      classId: payload.classId,
      meetingId: payload.meetingId,
      expiresAt: at.add(const Duration(minutes: 2)),
      requiresOtp: payload.mode == QrMode.otp,
      otp: payload.mode == QrMode.otp ? issuer.otpFor(payload) : null,
    );
    _challenges[challenge.id] = challenge;
    return challenge;
  }

  CheckInChallenge validate(
    String challengeId, {
    required String deviceId,
    String? otp,
    DateTime? now,
  }) {
    final challenge = _challenges[challengeId];
    if (challenge == null) throw StateError('Challenge không tồn tại.');
    if (challenge.deviceId != deviceId) throw StateError('Sai thiết bị.');
    if ((now ?? DateTime.now()).toUtc().isAfter(challenge.expiresAt)) {
      throw StateError('Challenge đã hết hạn.');
    }
    if (challenge.requiresOtp && challenge.otp != otp?.trim()) {
      throw StateError('Mã bí mật không đúng.');
    }
    return challenge;
  }

  CheckInChallenge consume(
    String challengeId, {
    required String deviceId,
    required String email,
    String? otp,
    DateTime? now,
  }) {
    final challenge = validate(
      challengeId,
      deviceId: deviceId,
      otp: otp,
      now: now,
    );
    final normalizedEmail = email.trim().toLowerCase();
    if (challenge.used) {
      if (challenge.usedByEmail == normalizedEmail) return challenge;
      throw StateError('Challenge đã được sử dụng.');
    }
    final used = challenge.markUsed(normalizedEmail);
    _challenges[challengeId] = used;
    return used;
  }
}
