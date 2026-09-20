import 'dart:async';
import 'dart:io';

import 'package:fap_attendance/network/quick_tunnel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'quick tunnel registers a public HTTPS URL for a loopback server',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final tunnel = QuickTunnel();
      final serving = server.listen((request) {
        request.response
          ..statusCode = 200
          ..write('healthy');
        unawaited(request.response.close());
      });
      try {
        final origin = await tunnel.start('http://127.0.0.1:${server.port}');
        expect(origin, startsWith('https://'));
        expect(tunnel.url, origin);
      } finally {
        await tunnel.stop();
        await serving.cancel();
        await server.close(force: true);
      }
    },
    skip: Platform.environment['RUN_PUBLIC_TUNNEL_TEST'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
