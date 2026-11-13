import 'package:fap_attendance/network/student_join_html.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('studentJoinHtml', () {
    test('escapes HTML courseLabel and embeds JSON config safely', () {
      final html = studentJoinHtml(
        challengeId: 'ch-1',
        deviceId: 'dev-1',
        expiresAt: DateTime.utc(2026, 9, 7, 8, 0),
        requiresOtp: true,
        requiresFirebase: true,
        courseLabel: 'PRM392 <script>alert(1)</script>',
        slotNumber: 2,
      );

      expect(html, contains('<!doctype html>'));
      expect(html, contains('PRM392 &lt;script&gt;alert(1)&lt;&#47;script&gt; · Slot 2'));
      expect(html, isNot(contains('<script>alert(1)</script>')));
      expect(html, contains('"challengeId":"ch-1"'));
      expect(html, contains('"requiresOtp":true'));
      expect(html, contains('"requiresFirebase":true'));
      expect(html, contains('Email phải được xác minh trong Firebase'));
    });

    test('renders demo auth note when requiresFirebase is false', () {
      final html = studentJoinHtml(
        challengeId: 'ch-2',
        deviceId: 'dev-2',
        expiresAt: DateTime.utc(2026, 9, 7, 8, 0),
        requiresOtp: false,
        requiresFirebase: false,
        courseLabel: 'SWD392 · SE1801',
        slotNumber: 1,
      );

      expect(html, contains('Chế độ demo'));
      expect(html, contains('"requiresOtp":false'));
      expect(html, contains('"requiresFirebase":false'));
    });
  });
}
