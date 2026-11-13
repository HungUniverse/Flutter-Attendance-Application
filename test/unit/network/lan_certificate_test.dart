import 'package:fap_attendance/network/lan_certificate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LanCertificate.create generates SecurityContext and non-empty SHA-1 fingerprint', () {
    final cert = LanCertificate.create('127.0.0.1');
    expect(cert.context, isNotNull);
    expect(cert.fingerprint, isNotEmpty);
    expect(
      cert.fingerprint.replaceAll(RegExp('[^a-fA-F0-9]'), '').length,
      40,
    );
  });
}
