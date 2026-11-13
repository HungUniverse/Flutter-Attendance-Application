import 'dart:convert';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrPayload encode/decode and malformed payload guards', () {
    test('roundtrips both QrMode.normal and QrMode.otp and unpadded base64Url', () {
      for (final mode in QrMode.values) {
        final payload = QrPayload(
          version: 2,
          endpoint: 'https://192.168.1.10:8443/api/check-in',
          classId: 'cls-101',
          meetingId: 'm-12',
          token: 'deadbeefcafebabe',
          issuedAt: DateTime.utc(2026, 9, 15, 7, 30, 5),
          expiresAt: DateTime.utc(2026, 9, 15, 7, 30, 25),
          certificateFingerprint: 'AA:BB:CC:DD:EE:FF',
          mode: mode,
        );

        final encoded = payload.encode();
        final unpadded = encoded.replaceAll('=', '');
        final decoded = QrPayload.decode('  $unpadded  ');

        expect(decoded.version, 2);
        expect(decoded.endpoint, payload.endpoint);
        expect(decoded.classId, payload.classId);
        expect(decoded.meetingId, payload.meetingId);
        expect(decoded.token, payload.token);
        expect(decoded.issuedAt.toUtc(), payload.issuedAt);
        expect(decoded.expiresAt.toUtc(), payload.expiresAt);
        expect(decoded.certificateFingerprint, payload.certificateFingerprint);
        expect(decoded.mode, mode);
      }
    });

    final invalidJsonPayloads = <String, Map<String, Object?>>{
      'version zero': {
        'v': 0,
        'endpoint': 'https://localhost:8443',
        'classId': 'c1',
        'meetingId': 'm1',
        'token': 'tok',
        'issuedAt': '2026-09-15T07:30:00Z',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': 'fp',
        'mode': 'normal',
      },
      'blank endpoint': {
        'v': 1,
        'endpoint': '   ',
        'classId': 'c1',
        'meetingId': 'm1',
        'token': 'tok',
        'issuedAt': '2026-09-15T07:30:00Z',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': 'fp',
        'mode': 'normal',
      },
      'blank classId': {
        'v': 1,
        'endpoint': 'https://localhost:8443',
        'classId': '',
        'meetingId': 'm1',
        'token': 'tok',
        'issuedAt': '2026-09-15T07:30:00Z',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': 'fp',
        'mode': 'normal',
      },
      'blank meetingId': {
        'v': 1,
        'endpoint': 'https://localhost:8443',
        'classId': 'c1',
        'meetingId': '\t',
        'token': 'tok',
        'issuedAt': '2026-09-15T07:30:00Z',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': 'fp',
        'mode': 'normal',
      },
      'missing token': {
        'v': 1,
        'endpoint': 'https://localhost:8443',
        'classId': 'c1',
        'meetingId': 'm1',
        'issuedAt': '2026-09-15T07:30:00Z',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': 'fp',
        'mode': 'normal',
      },
      'missing issuedAt': {
        'v': 1,
        'endpoint': 'https://localhost:8443',
        'classId': 'c1',
        'meetingId': 'm1',
        'token': 'tok',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': 'fp',
        'mode': 'normal',
      },
      'missing expiresAt': {
        'v': 1,
        'endpoint': 'https://localhost:8443',
        'classId': 'c1',
        'meetingId': 'm1',
        'token': 'tok',
        'issuedAt': '2026-09-15T07:30:00Z',
        'certificateFingerprint': 'fp',
        'mode': 'normal',
      },
      'blank fingerprint': {
        'v': 1,
        'endpoint': 'https://localhost:8443',
        'classId': 'c1',
        'meetingId': 'm1',
        'token': 'tok',
        'issuedAt': '2026-09-15T07:30:00Z',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': '   ',
        'mode': 'normal',
      },
      'unknown mode': {
        'v': 1,
        'endpoint': 'https://localhost:8443',
        'classId': 'c1',
        'meetingId': 'm1',
        'token': 'tok',
        'issuedAt': '2026-09-15T07:30:00Z',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': 'fp',
        'mode': 'bluetoothOnly',
      },
      'invalid timestamp': {
        'v': 1,
        'endpoint': 'https://localhost:8443',
        'classId': 'c1',
        'meetingId': 'm1',
        'token': 'tok',
        'issuedAt': 'not-a-date',
        'expiresAt': '2026-09-15T07:30:20Z',
        'certificateFingerprint': 'fp',
        'mode': 'otp',
      },
    };

    test('rejects empty string, non-base64, and non-map JSON payloads', () {
      expect(() => QrPayload.decode(''), throwsFormatException);
      expect(() => QrPayload.decode('   '), throwsFormatException);
      expect(() => QrPayload.decode('!@#\$%'), throwsFormatException);

      final listEncoded = base64Url.encode(utf8.encode('[1, 2, 3]'));
      expect(() => QrPayload.decode(listEncoded), throwsFormatException);
    });

    for (final entry in invalidJsonPayloads.entries) {
      test('rejects malformed payload (${entry.key})', () {
        final raw = base64Url.encode(utf8.encode(jsonEncode(entry.value)));
        expect(() => QrPayload.decode(raw), throwsFormatException);
      });
    }
  });

  group('RollingQrIssuer HMAC window, mode activation, and OTP isolation', () {
    test('verifies token across 15s window boundary within 20s expiry then rejects after expiry', () {
      final issuer = RollingQrIssuer(secret: 'fixed-test-secret-01');
      final tIssued = DateTime.utc(2026, 9, 15, 7, 30, 10);

      final payload = issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.normal,
        now: tIssued,
      );

      expect(issuer.activeOtp, isNull);
      expect(payload.expiresAt, tIssued.add(const Duration(seconds: 20)));
      expect(issuer.verify(payload, now: tIssued), isTrue);
      // Window crosses from second 10 (window n) to second 29 (window n+1)
      expect(
        issuer.verify(
          payload,
          now: tIssued.add(const Duration(seconds: 19)),
        ),
        isTrue,
      );
      expect(
        issuer.verify(
          payload,
          now: tIssued.add(const Duration(seconds: 20)),
        ),
        isTrue,
      );
      expect(
        issuer.verify(
          payload,
          now: tIssued.add(const Duration(seconds: 21)),
        ),
        isFalse,
      );
    });

    test('switching mode rotates activationId and OTP and invalidates old tokens', () {
      final issuer = RollingQrIssuer(secret: 'fixed-test-secret-02');
      final now = DateTime.utc(2026, 9, 15, 8, 0, 0);

      final qrPayload = issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.normal,
        now: now,
      );
      expect(() => issuer.otpFor(qrPayload), throwsStateError);
      expect(issuer.verify(qrPayload, now: now), isTrue);

      final otpPayload1 = issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.otp,
        now: now,
      );
      final otp1 = issuer.otpFor(otpPayload1);
      expect(otp1, matches(RegExp(r'^\d{6}$')));
      expect(issuer.activeOtp, otp1);
      expect(issuer.verify(qrPayload, now: now), isFalse);
      expect(issuer.verify(otpPayload1, now: now), isTrue);

      // Re-issuing in OTP keeps the same OTP while mode stays active
      final otpPayload2 = issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.otp,
        now: now.add(const Duration(seconds: 1)),
      );
      expect(issuer.otpFor(otpPayload2), otp1);

      // Switching away and back generates a new non-matching activationId & new OTP
      issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.normal,
        now: now.add(const Duration(seconds: 2)),
      );
      expect(issuer.verify(otpPayload1, now: now.add(const Duration(seconds: 2))), isFalse);

      final otpPayload3 = issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.otp,
        now: now.add(const Duration(seconds: 3)),
      );
      final otp3 = issuer.otpFor(otpPayload3);
      expect(otp3, isNot(equals(otp1)));
    });

    test('rejects forged tokens or tokens from another issuer secret', () {
      final issuerA = RollingQrIssuer(secret: 'secret-a');
      final issuerB = RollingQrIssuer(secret: 'secret-b');
      final now = DateTime.utc(2026, 9, 15, 9, 0, 0);

      final payloadA = issuerA.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.normal,
        now: now,
      );
      issuerB.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.normal,
        now: now,
      );

      expect(issuerB.verify(payloadA, now: now), isFalse);

      final lastChar = payloadA.token[payloadA.token.length - 1];
      final flipped = lastChar == '0' ? '1' : '0';
      final tamperedToken = QrPayload(
        endpoint: payloadA.endpoint,
        classId: payloadA.classId,
        meetingId: payloadA.meetingId,
        token: '${payloadA.token.substring(0, payloadA.token.length - 1)}$flipped',
        issuedAt: payloadA.issuedAt,
        expiresAt: payloadA.expiresAt,
        certificateFingerprint: payloadA.certificateFingerprint,
        mode: payloadA.mode,
      );
      expect(issuerA.verify(tamperedToken, now: now), isFalse);
    });
  });

  group('ChallengeStore challenge creation, validation, and consumption', () {
    test('creates OTP challenge, trims OTP on validate, allows idempotent consume, blocks second student', () {
      final issuer = RollingQrIssuer(secret: 'challenge-secret');
      final store = ChallengeStore(issuer);
      final now = DateTime.utc(2026, 9, 15, 10, 0, 0);

      final payload = issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.otp,
        now: now,
      );
      final otp = issuer.otpFor(payload);

      final challenge = store.create(payload, 'device-abc', now: now);
      expect(challenge.requiresOtp, isTrue);
      expect(challenge.used, isFalse);
      expect(challenge.expiresAt, now.add(const Duration(minutes: 2)));

      expect(
        () => store.validate(challenge.id, deviceId: 'other-device', otp: otp, now: now),
        throwsStateError,
      );
      expect(
        () => store.validate(challenge.id, deviceId: 'device-abc', otp: '000000', now: now),
        throwsStateError,
      );
      expect(
        () => store.validate(
          challenge.id,
          deviceId: 'device-abc',
          otp: otp,
          now: now.add(const Duration(minutes: 3)),
        ),
        throwsStateError,
      );

      final validated = store.validate(
        challenge.id,
        deviceId: 'device-abc',
        otp: ' $otp ',
        now: now.add(const Duration(seconds: 30)),
      );
      expect(validated.id, challenge.id);

      final firstUse = store.consume(
        challenge.id,
        deviceId: 'device-abc',
        email: '  AnNV@FPT.EDU.VN ',
        otp: otp,
        now: now.add(const Duration(seconds: 40)),
      );
      expect(firstUse.used, isTrue);
      expect(firstUse.usedByEmail, 'annv@fpt.edu.vn');

      // Idempotent consume for same email succeeds cleanly.
      final retrySameStudent = store.consume(
        challenge.id,
        deviceId: 'device-abc',
        email: 'annv@fpt.edu.vn',
        otp: otp,
        now: now.add(const Duration(seconds: 45)),
      );
      expect(retrySameStudent.usedByEmail, 'annv@fpt.edu.vn');

      // Different student on same challenge is blocked as replay.
      expect(
        () => store.consume(
          challenge.id,
          deviceId: 'device-abc',
          email: 'binhtt@fpt.edu.vn',
          otp: otp,
          now: now.add(const Duration(seconds: 50)),
        ),
        throwsStateError,
      );
    });

    test('evicts expired challenges on create and rejects expired QR payloads', () {
      final issuer = RollingQrIssuer(secret: 'evict-secret');
      final store = ChallengeStore(issuer);
      final t0 = DateTime.utc(2026, 9, 15, 11, 0, 0);

      final firstQr = issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.normal,
        now: t0,
      );
      final c1 = store.create(firstQr, 'dev-1', now: t0);

      // Expired QR payload cannot create a challenge.
      expect(
        () => store.create(
          firstQr,
          'dev-1',
          now: t0.add(const Duration(seconds: 25)),
        ),
        throwsStateError,
      );

      // Creating a fresh challenge after 3 minutes purges expired challenge c1.
      final later = t0.add(const Duration(minutes: 3));
      final secondQr = issuer.issue(
        endpoint: 'https://192.168.1.5:8443',
        classId: 'cls-1',
        meetingId: 'm1',
        certificateFingerprint: 'FP-1',
        mode: QrMode.normal,
        now: later,
      );
      final c2 = store.create(secondQr, 'dev-2', now: later);

      expect(
        () => store.validate(c1.id, deviceId: 'dev-1', now: later),
        throwsStateError,
      );
      expect(
        store.validate(c2.id, deviceId: 'dev-2', now: later).requiresOtp,
        isFalse,
      );
    });
  });
}
