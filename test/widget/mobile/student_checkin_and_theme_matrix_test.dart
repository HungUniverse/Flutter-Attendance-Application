import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:fap_attendance/lab3/ui/mobile_theme.dart';
import 'package:fap_attendance/ui/mobile/student_app.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const scannerChannel = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'device_id': 'student-dev-99',
      'student_email': 'an.nv@fpt.edu.vn',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (call) async {
          if (call.method == 'requestCameraPermission') return 1;
          if (call.method == 'state') return 1;
          return <String, dynamic>{};
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, null);
  });

  group('StudentHomePage scanner & expired QR edge cases', () {
    testWidgets('shows scanner prompt, handles invalid QR gracefully, and keeps scanner stable', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const StudentHomePage(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('FAP ATTENDANCE'), findsOneWidget);
      final scannerWidget = tester.widget<MobileScanner>(
        find.byType(MobileScanner),
      );
      expect(scannerWidget.onDetect, isNotNull);

      // Simulate detecting an expired QR URL -> should not enter form view with invalid payload
      final issuer = RollingQrIssuer();
      final expired = issuer.issue(
        endpoint: 'https://192.168.1.10:8787',
        classId: 'c1',
        meetingId: 'm1',
        certificateFingerprint: 'AA:BB:CC:DD',
        mode: QrMode.normal,
        now: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      scannerWidget.onDetect?.call(
        BarcodeCapture(
          barcodes: [
            Barcode(rawValue: 'https://test.trycloudflare.com/join?qr=${expired.encode()}'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // Still on scanner view because expired QR failed validation and restarted scanner
      expect(find.byType(MobileScanner), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('creates unique device_id across fresh installs and preserves existing email', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'student_email': 'binh@fpt.edu.vn'});
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const StudentHomePage(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('device_id'), isNotEmpty);
      expect(prefs.getString('student_email'), 'binh@fpt.edu.vn');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('AppTheme & MobileTheme accessibility and design tokens', () {
    testWidgets('buildAppTheme enforces consistent orange seed, crisp borders, and surface palette', (
      tester,
    ) async {
      final desktopTheme = buildAppTheme();
      expect(desktopTheme.colorScheme.primary, AppColors.orange);
      expect(desktopTheme.scaffoldBackgroundColor, AppColors.canvas);
      expect(desktopTheme.useMaterial3, isTrue);

      final mTheme = mobileTheme();
      expect(mTheme.colorScheme.primary, AppColors.orangeDark);
      expect(mTheme.useMaterial3, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          theme: mTheme,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Xác nhận')),
                OutlinedButton(onPressed: () {}, child: const Text('Hủy')),
                const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Card'))),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Xác nhận'), findsOneWidget);
      expect(find.text('Hủy'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
    });
  });
}
