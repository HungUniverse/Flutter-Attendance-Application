import 'package:fap_attendance/network/quick_tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QuickTunnel initializes with null url and stop is safe when idle', () async {
    final tunnel = QuickTunnel();
    expect(tunnel.url, isNull);
    await tunnel.stop();
    expect(tunnel.url, isNull);
  });
}
