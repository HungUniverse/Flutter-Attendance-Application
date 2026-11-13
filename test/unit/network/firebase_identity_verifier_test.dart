import 'dart:convert';

import 'package:fap_attendance/network/firebase_identity_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('FirebaseIdentityVerifier', () {
    test('verifies valid Firebase lookup response and normalizes email', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'identitytoolkit.googleapis.com');
        expect(req.url.queryParameters['key'], 'api-key-1');
        return http.Response(
          jsonEncode({
            'users': [
              {'email': '  Student@FPT.EDU.VN ', 'emailVerified': true},
            ],
          }),
          200,
        );
      });

      final verifier = FirebaseIdentityVerifier(apiKey: 'api-key-1', client: client);
      final identity = await verifier.verify('tok-123');
      expect(identity.email, 'student@fpt.edu.vn');
      expect(identity.verified, isTrue);
    });

    test('throws StateError when status != 200 or users list is empty', () async {
      final errorClient = MockClient((_) async => http.Response('err', 400));
      final v1 = FirebaseIdentityVerifier(apiKey: 'k', client: errorClient);
      await expectLater(v1.verify('bad'), throwsStateError);

      final emptyClient = MockClient(
        (_) async => http.Response(jsonEncode({'users': []}), 200),
      );
      final v2 = FirebaseIdentityVerifier(apiKey: 'k', client: emptyClient);
      await expectLater(v2.verify('empty'), throwsStateError);
    });
  });

  group('Lab2IdentityVerifier', () {
    test('returns trimmed lowercase email as verified', () async {
      const verifier = Lab2IdentityVerifier('  Demo@FPT.EDU.VN ');
      final id = await verifier.verify('anything');
      expect(id.email, 'demo@fpt.edu.vn');
      expect(id.verified, isTrue);
    });
  });
}
