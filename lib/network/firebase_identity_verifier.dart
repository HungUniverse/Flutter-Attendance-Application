import 'dart:convert';

import 'package:http/http.dart' as http;

class VerifiedStudentIdentity {
  const VerifiedStudentIdentity({required this.email, required this.verified});

  final String email;
  final bool verified;
}

abstract interface class StudentIdentityVerifier {
  Future<VerifiedStudentIdentity> verify(String idToken);
}

class FirebaseIdentityVerifier implements StudentIdentityVerifier {
  FirebaseIdentityVerifier({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<VerifiedStudentIdentity> verify(String idToken) async {
    final response = await _client.post(
      Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:lookup', {
        'key': apiKey,
      }),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
    if (response.statusCode != 200) {
      throw StateError('Firebase token không hợp lệ hoặc đã hết hạn.');
    }
    final body = (jsonDecode(response.body) as Map).cast<String, Object?>();
    final users = (body['users'] as List?) ?? const [];
    if (users.isEmpty) throw StateError('Không tìm thấy tài khoản Firebase.');
    final user = (users.first as Map).cast<String, Object?>();
    return VerifiedStudentIdentity(
      email: (user['email'] as String?)?.trim().toLowerCase() ?? '',
      verified: user['emailVerified'] == true,
    );
  }
}

class Lab2IdentityVerifier implements StudentIdentityVerifier {
  const Lab2IdentityVerifier(this.email);

  final String email;

  @override
  Future<VerifiedStudentIdentity> verify(String idToken) async =>
      VerifiedStudentIdentity(
        email: email.trim().toLowerCase(),
        verified: true,
      );
}
