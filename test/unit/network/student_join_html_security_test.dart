import 'dart:convert';

import 'package:fap_attendance/network/student_join_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('studentJoinHtml rendering & XSS sanitization', () {
    final expires = DateTime.utc(2026, 9, 15, 7, 32, 0);

    test('escapes HTML meta-characters in courseLabel and escapes script breakout in embedded JSON config', () {
      final html = studentJoinHtml(
        challengeId: 'ch-</script><img onerror=alert(1)>',
        deviceId: 'dev-1',
        expiresAt: expires,
        requiresOtp: true,
        requiresFirebase: true,
        courseLabel: 'PRM393 <script>alert("xss")</script> & SE1801',
        slotNumber: 3,
      );

      expect(
        html,
        contains(
          'PRM393 &lt;script&gt;alert(&quot;xss&quot;)&lt;&#47;script&gt; &amp; SE1801 · Slot 3',
        ),
      );
      expect(
        html,
        isNot(contains('ch-</script>')),
      );
      expect(
        html,
        contains(r'ch-\u003c/script>'),
      );
      expect(html, contains('<meta name="referrer" content="no-referrer">'));
      expect(
        html,
        contains('Email phải được xác minh trong Firebase.'),
      );
    });

    test('renders demo mode notice and serialized flags when OTP and Firebase are disabled', () {
      final html = studentJoinHtml(
        challengeId: 'ch-demo-99',
        deviceId: 'dev-demo',
        expiresAt: expires,
        requiresOtp: false,
        requiresFirebase: false,
        courseLabel: 'SWD392 · SE1802',
        slotNumber: 5,
      );

      expect(html, contains('SWD392 · SE1802 · Slot 5'));
      expect(html, contains('Chế độ demo:'));

      final match = RegExp(r'const config=(\{.*?\});').firstMatch(html);
      expect(match, isNotNull);
      final parsed = jsonDecode(match!.group(1)!) as Map<String, Object?>;
      expect(parsed['challengeId'], 'ch-demo-99');
      expect(parsed['deviceId'], 'dev-demo');
      expect(parsed['expiresAt'], '2026-09-15T07:32:00.000Z');
      expect(parsed['requiresOtp'], isFalse);
      expect(parsed['requiresFirebase'], isFalse);
    });
  });
}
