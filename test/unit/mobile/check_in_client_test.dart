import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:fap_attendance/mobile/check_in_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CheckInChallengeResponse stores id and requiresOtp', () {
    const resp = CheckInChallengeResponse(id: 'ch-123', requiresOtp: true);
    expect(resp.id, 'ch-123');
    expect(resp.requiresOtp, isTrue);
  });

  test('CheckInClient fails cleanly when server fingerprint mismatches or endpoint unreachable', () async {
    final client = CheckInClient();
    final payload = QrPayload(
      endpoint: 'https://127.0.0.1:1',
      classId: 'c1',
      meetingId: 'm1',
      token: 'tok',
      issuedAt: DateTime.utc(2026, 9, 7),
      expiresAt: DateTime.utc(2026, 9, 7, 1),
      certificateFingerprint: '00:11:22',
      mode: QrMode.normal,
    );

    await expectLater(
      client.createChallenge(payload, payload.encode(), 'dev-1'),
      throwsA(anything),
    );
  });
}
