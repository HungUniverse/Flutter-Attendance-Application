import 'dart:convert';
import 'dart:io';

import '../domain/qr_protocol.dart';

class CheckInChallengeResponse {
  const CheckInChallengeResponse({required this.id, required this.requiresOtp});

  final String id;
  final bool requiresOtp;
}

class CheckInClient {
  Future<CheckInChallengeResponse> createChallenge(
    QrPayload payload,
    String encodedQr,
    String deviceId,
  ) async {
    final body = await _post(payload, '/api/v1/challenges', {
      'qr': encodedQr,
      'deviceId': deviceId,
    });
    return CheckInChallengeResponse(
      id: body['challengeId']! as String,
      requiresOtp: body['requiresOtp'] == true,
    );
  }

  Future<String> checkIn({
    required QrPayload payload,
    required String challengeId,
    required String deviceId,
    required String email,
    String? otp,
    String? firebaseIdToken,
  }) async {
    final data = <String, Object?>{
      'challengeId': challengeId,
      'deviceId': deviceId,
      'email': email,
    };
    if (otp != null) data['otp'] = otp;
    final body = await _post(
      payload,
      '/api/v1/check-ins',
      data,
      bearer: firebaseIdToken,
    );
    return body['message']! as String;
  }

  Future<Map<String, Object?>> _post(
    QrPayload payload,
    String path,
    Map<String, Object?> data, {
    String? bearer,
  }) async {
    final expected = _normalize(payload.certificateFingerprint);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..badCertificateCallback = (certificate, host, port) =>
          _normalizeFingerprint(certificate.sha1) == expected;
    try {
      final request = await client.postUrl(
        Uri.parse('${payload.endpoint}$path'),
      );
      request.headers.contentType = ContentType.json;
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      request.write(jsonEncode(data));
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final decoded = (jsonDecode(utf8.decode(bytes)) as Map)
          .cast<String, Object?>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          (decoded['message'] as String?) ?? 'Điểm danh thất bại.',
        );
      }
      return decoded;
    } finally {
      client.close(force: true);
    }
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp('[^a-fA-F0-9]'), '').toLowerCase();

  static String _normalizeFingerprint(List<int> value) =>
      value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
