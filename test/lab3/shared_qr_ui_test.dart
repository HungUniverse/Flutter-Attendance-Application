import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/attendance_link_service.dart';
import 'package:fap_attendance/ui/desktop/shared_qr_page.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'shared desktop QR preserves OTP mode; leaving does not stop remote reception',
    (tester) async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'id': 'remote1',
            'classId': 'c1',
            'meetingId': 'm1',
            'url': 'https://attendance.test/join/token',
            'expiresAt': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
            'receiving': true,
            'code': '123456',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final controller = AttendanceController()
        ..workspace = fixtureWorkspace()
        ..sharedLinks = HttpAttendanceLinkService(
          FakeAuth(),
          baseUrl: 'https://attendance.test',
          client: client,
        );
      addTearDown(() => controller.dispose());
      addTearDown(client.close);
      String? copiedLink;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedLink = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: SharedQrPage(
            controller: controller,
            classId: 'c1',
            meetingId: 'm1',
            mode: QrMode.otp,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Mã xác nhận'), findsOneWidget);
      expect(find.text('123456'), findsOneWidget);
      expect(find.text('https://attendance.test/join/token'), findsNothing);
      await tester.tap(find.text('Sao chép link'));
      await tester.pump();
      expect(copiedLink, 'https://attendance.test/join/token');
      expect(jsonDecode(requests.single.body)['mode'], 'otp');
      await tester.binding.setSurfaceSize(const Size(420, 760));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
    },
  );
}
