import 'package:fap_attendance/ui/mobile/student_app.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'device_id': 'test-device-1',
      'student_email': 'sv@fpt.edu.vn',
    });
    const scannerChannel = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/method',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (call) async {
          if (call.method == 'requestCameraPermission') return 1;
          if (call.method == 'state') return 1;
          return <String, dynamic>{};
        });
  });

  tearDown(() {
    const scannerChannel = MethodChannel(
      'dev.steenbakker.mobile_scanner/scanner/method',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, null);
  });

  group('StudentHomePage', () {
    testWidgets('renders FAP ATTENDANCE header and QR scan prompt initially', (
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
      expect(
        find.text(
          'Quét mã QR đang hiển thị trên máy giảng viên. Điện thoại và máy tính phải cùng mạng Wi-Fi.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SafeArea), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('persists generated device_id when preferences initially empty', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
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
      final savedId = prefs.getString('device_id');
      expect(savedId, isNotNull);
      expect(savedId, isNotEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('renders cleanly across narrow and tablet mobile viewports', (
      tester,
    ) async {
      for (final size in const [
        Size(360, 720),
        Size(480, 960),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: const StudentHomePage(),
          ),
        );
        await tester.pump();
        expect(find.text('FAP ATTENDANCE'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
      await tester.binding.setSurfaceSize(null);
    });
  });
}
