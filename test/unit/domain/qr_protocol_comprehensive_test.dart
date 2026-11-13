import 'dart:convert';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrPayload encode & decode', () {
    test('roundtrips normal and otp payloads accurately', () {
      final issued = DateTime.utc(2026, 9, 7, 7, 30, 0);
      final expires = issued.add(const Duration(seconds: 20));
      final payload = QrPayload(
        version: 1,
        endpoint: 'https://192.168.1.10:8443',
        classId: 'cls-1',
        meetingId: 'cls-1-m1',
        token: 'abc-token-123',
        issuedAt: issued,
        expiresAt: expires,
        certificateFingerprint: 'AA:BB:CC',
        mode: QrMode.otp,
      );

      final encoded = payload.encode();
      final decoded = QrPayload.decode(encoded);

      expect(decoded.version, 1);
      expect(decoded.endpoint, payload.endpoint);
      expect(decoded.classId, payload.classId);
      expect(decoded.meetingId, payload.meetingId);
      expect(decoded.token, payload.token);
      expect(decoded.issuedAt.toUtc(), issued);
      expect(decoded.expiresAt.toUtc(), expires);
      expect(decoded.certificateFingerprint, 'AA:BB:CC');
      expect(decoded.mode, QrMode.otp);
    });

    test('decode throws FormatException for empty, non-JSON, non-Map, or missing fields', () {
      expect(() => QrPayload.decode(''), throwsFormatException);
      expect(() => QrPayload.decode('   '), throwsFormatException);
      expect(() => QrPayload.decode('not-valid-base64!!!'), throwsFormatException);

      final listEncoded = base64Url.encode(utf8.encode(jsonEncode([1, 2, 3])));
      expect(() => QrPayload.decode(listEncoded), throwsFormatException);

      final missingField = base64Url.encode(
        utf8.encode(jsonEncode({'v': 1, 'endpoint': 'https://x'})),
      );
      expect(() => QrPayload.decode(missingField), throwsFormatException);

      final badVersion = base64Url.encode(
        utf8.encode(
          jsonEncode({
            'v': 0,
            'endpoint': 'https://x',
            'classId': 'c',
            'meetingId': 'm',
            'token': 't',
            'issuedAt': DateTime.utc(2026, 9, 7).toIso8601String(),
            'expiresAt': DateTime.utc(2026, 9, 7).toIso8601String(),
            'certificateFingerprint': 'fp',
            'mode': 'normal',
          }),
        ),
      );
      expect(() => QrPayload.decode(badVersion), throwsFormatException);
    });
  });

  group('RollingQrIssuer', () {
    test('issues valid normal payload and verifies within window', () {
      final issuer = RollingQrIssuer(secret: 'test-secret-key');
      final now = DateTime.utc(2026, 9, 7, 7, 30, 0);

      final payload = issuer.issue(
        endpoint: 'https://127.0.0.1:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP1',
        mode: QrMode.normal,
        now: now,
      );

      expect(issuer.activeOtp, isNull);
      expect(() => issuer.otpFor(payload), throwsStateError);
      expect(issuer.verify(payload, now: now), isTrue);
      expect(issuer.verify(payload, now: now.add(const Duration(seconds: 19))),
          isTrue);
      expect(issuer.verify(payload, now: now.add(const Duration(seconds: 21))),
          isFalse);
    });

    test('otp mode generates 6-digit OTP and invalidates normal payloads', () {
      final issuer = RollingQrIssuer(secret: 'secret-2');
      final now = DateTime.utc(2026, 9, 7, 7, 30, 0);

      final normalPayload = issuer.issue(
        endpoint: 'https://127.0.0.1:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP1',
        mode: QrMode.normal,
        now: now,
      );

      final otpPayload = issuer.issue(
        endpoint: 'https://127.0.0.1:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP1',
        mode: QrMode.otp,
        now: now,
      );

      expect(issuer.activeOtp, isNotNull);
      expect(issuer.activeOtp!.length, 6);
      expect(int.tryParse(issuer.activeOtp!), isNotNull);
      expect(issuer.otpFor(otpPayload), issuer.activeOtp);

      expect(issuer.verify(otpPayload, now: now), isTrue);
      expect(issuer.verify(normalPayload, now: now), isFalse);
    });

    test('rejects tampered token', () {
      final issuer = RollingQrIssuer(secret: 'secret-3');
      final now = DateTime.utc(2026, 9, 7, 7, 30, 0);
      final payload = issuer.issue(
        endpoint: 'https://127.0.0.1:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP1',
        mode: QrMode.normal,
        now: now,
      );

      final tampered = QrPayload(
        endpoint: payload.endpoint,
        classId: payload.classId,
        meetingId: payload.meetingId,
        token: '${payload.token.substring(0, payload.token.length - 1)}x',
        issuedAt: payload.issuedAt,
        expiresAt: payload.expiresAt,
        certificateFingerprint: payload.certificateFingerprint,
        mode: payload.mode,
      );
      expect(issuer.verify(tampered, now: now), isFalse);
    });
  });

  group('ChallengeStore', () {
    test('creates, validates, and consumes normal challenge idempotently for same email', () {
      final issuer = RollingQrIssuer(secret: 'challenge-secret');
      final store = ChallengeStore(issuer);
      final now = DateTime.utc(2026, 9, 7, 7, 30, 0);

      final payload = issuer.issue(
        endpoint: 'https://127.0.0.1:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP',
        mode: QrMode.normal,
        now: now,
      );

      final challenge = store.create(payload, 'device-abc', now: now);
      expect(challenge.requiresOtp, isFalse);
      expect(challenge.used, isFalse);

      final validated = store.validate(
        challenge.id,
        deviceId: 'device-abc',
        now: now.add(const Duration(seconds: 30)),
      );
      expect(validated.id, challenge.id);

      final consumed = store.consume(
        challenge.id,
        deviceId: 'device-abc',
        email: '  Student@FPT.EDU.VN ',
        now: now.add(const Duration(seconds: 45)),
      );
      expect(consumed.used, isTrue);
      expect(consumed.usedByEmail, 'student@fpt.edu.vn');

      // Same email re-consuming succeeds idempotently
      final reConsumed = store.consume(
        challenge.id,
        deviceId: 'device-abc',
        email: 'student@fpt.edu.vn',
        now: now.add(const Duration(seconds: 50)),
      );
      expect(reConsumed.used, isTrue);

      // Different email cannot reuse consumed challenge
      expect(
        () => store.consume(
          challenge.id,
          deviceId: 'device-abc',
          email: 'other@fpt.edu.vn',
          now: now.add(const Duration(seconds: 55)),
        ),
        throwsStateError,
      );
    });

    test('enforces OTP, deviceId, expiration, and purges expired challenges', () {
      final issuer = RollingQrIssuer(secret: 'otp-secret');
      final store = ChallengeStore(issuer);
      final t0 = DateTime.utc(2026, 9, 7, 7, 30, 0);

      final otpPayload = issuer.issue(
        endpoint: 'https://127.0.0.1:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP',
        mode: QrMode.otp,
        now: t0,
      );

      final challenge = store.create(otpPayload, 'dev-1', now: t0);
      expect(challenge.requiresOtp, isTrue);
      final otp = issuer.activeOtp!;

      expect(
        () => store.validate(challenge.id, deviceId: 'dev-wrong', otp: otp, now: t0),
        throwsStateError,
      );
      expect(
        () => store.validate(challenge.id, deviceId: 'dev-1', otp: '000000', now: t0),
        throwsStateError,
      );
      expect(
        store.validate(challenge.id, deviceId: 'dev-1', otp: ' $otp ', now: t0).id,
        challenge.id,
      );

      // Expired challenge (> 2 minutes)
      final tExpired = t0.add(const Duration(minutes: 2, seconds: 1));
      expect(
        () => store.validate(challenge.id, deviceId: 'dev-1', otp: otp, now: tExpired),
        throwsStateError,
      );

      // Creating a new challenge later purges expired ones
      final freshPayload = issuer.issue(
        endpoint: 'https://127.0.0.1:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP',
        mode: QrMode.otp,
        now: tExpired,
      );
      store.create(freshPayload, 'dev-2', now: tExpired);
      expect(
        () => store.validate(challenge.id, deviceId: 'dev-1', otp: otp, now: t0),
        throwsStateError,
      );
    });

    test('create rejects expired QR payload', () {
      final issuer = RollingQrIssuer(secret: 'exp-secret');
      final store = ChallengeStore(issuer);
      final t0 = DateTime.utc(2026, 9, 7, 7, 30, 0);
      final payload = issuer.issue(
        endpoint: 'https://127.0.0.1:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP',
        mode: QrMode.normal,
        now: t0,
      );

      expect(
        () => store.create(
          payload,
          'dev-1',
          now: t0.add(const Duration(seconds: 25)),
        ),
        throwsStateError,
      );
    });
  });
}
