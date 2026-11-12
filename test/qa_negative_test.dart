import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/attendance_service.dart';
import 'package:fap_attendance/domain/schedule_service.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:fap_attendance/data/attendance_csv_exporter.dart';
import 'package:fap_attendance/data/roster_importer.dart';
import 'package:fap_attendance/lab3/ui/attendance_screens.dart';
import 'package:fap_attendance/lab3/ui/mobile_theme.dart';

import 'lab3/fakes.dart';

Directory _createTempDir() => Directory.systemTemp.createTempSync('fap_qa_neg_');

void _cleanupDir(Directory dir) {
  if (dir.existsSync()) {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final roboto = File('assets/fonts/Roboto.ttf');
    final arial = File('C:/Windows/Fonts/arial.ttf');
    final fontFile = roboto.existsSync() ? roboto : (arial.existsSync() ? arial : null);
    if (fontFile != null) {
      final bytes = ByteData.sublistView(fontFile.readAsBytesSync());
      for (final family in ['Roboto', 'Segoe UI']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });

  group('1. Negative Test - Empty Input & Invalid Format', () {
    testWidgets('should reject empty or whitespace reason with validation error when editing attendance', (
      WidgetTester tester,
    ) async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      await tester.binding.setSurfaceSize(const Size(412, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: h.vm,
          child: MaterialApp(
            theme: mobileTheme(),
            home: const Scaffold(
              body: EditAttendanceDialog(
                classId: 'c1',
                meetingId: 'm1',
                roll: 'S1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Act: Open the edit sheet
      await tester.tap(find.text('Mở form sửa'));
      await tester.pumpAndSettle();

      // Clear any pre-existing text in reason
      final textField = find.widgetWithText(TextFormField, 'Lý do chỉnh sửa (bắt buộc)');
      await tester.enterText(textField, '');
      await tester.pumpAndSettle();

      // Act: Try saving with empty reason
      final saveBtn = find.widgetWithText(FilledButton, 'Lưu thay đổi');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Assert: Form validation error displayed
      expect(find.text('Vui lòng nhập lý do chỉnh sửa.'), findsOneWidget);

      // Act: Enter only whitespace
      await tester.enterText(textField, '    ');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Assert: Form validation error remains
      expect(find.text('Vui lòng nhập lý do chỉnh sửa.'), findsOneWidget);
    });

    test('should throw StateError when attempting to export CSV for unclosed meeting', () {
      // Arrange
      final exporter = AttendanceCsvExporter();
      final now = DateTime(2026, 11, 13, 8, 0);
      final activeMeeting = Meeting(
        id: 'm1',
        number: 1,
        startAt: now,
        endAt: now.add(const Duration(hours: 2)),
        state: MeetingState.active, // Not closed
      );
      final course = fixtureWorkspace().classes.first.copyWith(meetings: [activeMeeting]);
      final workspace = fixtureWorkspace().copyWith(classes: [course]);

      // Act & Assert
      expect(
        () => exporter.encode(workspace, course, activeMeeting),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Chỉ được export buổi đã chốt'))),
      );
    });

    test('should throw StateError when exporting meeting that still has unmarked students', () {
      // Arrange
      final exporter = AttendanceCsvExporter();
      final now = DateTime(2026, 11, 13, 8, 0);
      final closedMeeting = Meeting(
        id: 'm1',
        number: 1,
        startAt: now,
        endAt: now.add(const Duration(hours: 2)),
        state: MeetingState.closed,
      );
      // Course has 3 students, but attendance has 0 records (blank)
      final course = fixtureWorkspace().classes.first.copyWith(
        meetings: [closedMeeting],
        attendance: {'m1': {}},
      );
      final workspace = fixtureWorkspace().copyWith(classes: [course]);

      // Act & Assert
      expect(
        () => exporter.encode(workspace, course, closedMeeting),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('vẫn còn ô trống'))),
      );
    });

    test('should throw FormatException when schedule code does not follow 2-digit slot convention', () {
      // Arrange
      final scheduler = ScheduleService();
      final invalidRule = ScheduleRule(
        scheduleCode: '99', // Invalid: Valid groups 1..3, slots 1..4
        semesterStart: DateTime(2026, 11, 2),
      );

      // Act & Assert
      expect(
        () => scheduler.generate(invalidRule, 'c1'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('11–34'))),
      );
    });

    test('should throw FormatException when decoding corrupted QR payload string', () {
      // Arrange
      const corruptedPayload = 'not-a-valid-base64-payload-###@@@';
      final incompleteJsonPayload = base64Url.encode(utf8.encode(jsonEncode({'v': 1})));

      // Act & Assert
      expect(
        () => QrPayload.decode('   '),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrPayload.decode(corruptedPayload),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => QrPayload.decode(incompleteJsonPayload),
        throwsA(isA<FormatException>()),
      );
      final blankFingerprintPayload = base64Url.encode(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'endpoint': 'https://example.com',
            'classId': 'c1',
            'meetingId': 'm1',
            'token': 'tok',
            'issuedAt': '2026-11-13T08:00:00Z',
            'expiresAt': '2026-11-13T08:01:00Z',
            'certificateFingerprint': '   ',
            'mode': 'normal',
          }),
        ),
      );
      expect(
        () => QrPayload.decode(blankFingerprintPayload),
        throwsA(isA<FormatException>()),
      );
    });

    test('should throw RosterImportException when importing dotless filename or corrupted archive bytes', () {
      // Arrange
      final importer = RosterImporter();

      // Act & Assert
      expect(
        () => importer.importBytes(
          Uint8List.fromList([1, 2, 3]),
          fileName: 'ods', // No file extension dot
          semester: 'FA26',
          semesterStart: DateTime(2026, 11, 2),
        ),
        throwsA(isA<RosterImportException>()),
      );
      expect(
        () => importer.importBytes(
          Uint8List.fromList([1, 2, 3]),
          fileName: r'C:\dir\.ods', // Hidden dotfile without basename
          semester: 'FA26',
          semesterStart: DateTime(2026, 11, 2),
        ),
        throwsA(isA<RosterImportException>()),
      );
      expect(
        () => importer.importBytes(
          Uint8List.fromList([0, 1, 2, 3, 4]),
          fileName: 'corrupted.ods',
          semester: 'FA26',
          semesterStart: DateTime(2026, 11, 2),
        ),
        throwsA(isA<RosterImportException>()),
      );
      expect(
        () => importer.importBytes(
          Uint8List.fromList([0, 1, 2, 3, 4]),
          fileName: 'corrupted.xlsx',
          semester: 'FA26',
          semesterStart: DateTime(2026, 11, 2),
        ),
        throwsA(isA<RosterImportException>()),
      );
      expect(
        () => importer.importBytes(
          Uint8List(0),
          fileName: 'empty.xlsx',
          semester: 'FA26',
          semesterStart: DateTime(2026, 11, 2),
        ),
        throwsA(isA<RosterImportException>()),
      );
    });

    test('should throw TypeError when Student json is missing mandatory fields', () {
      // Arrange: json missing rollNumber and email
      final malformedJson = <String, Object?>{
        'fullName': 'Nguyễn Văn Thiếu Dữ Liệu',
      };

      // Act & Assert
      expect(
        () => Student.fromJson(malformedJson),
        throwsA(isA<TypeError>()),
      );
    });

    test('should throw RosterImportException when importing file with invalid extension', () {
      // Arrange
      final importer = RosterImporter();

      // Act & Assert
      expect(
        () => importer.importBytes(
          Uint8List(0),
          fileName: 'students.csv', // Only .ods and .xlsx are supported
          semester: 'FA26',
          semesterStart: DateTime(2026, 11, 2),
        ),
        throwsA(isA<RosterImportException>()),
      );
    });
  });

  group('2. Negative Test - API & Storage Errors', () {
    test('should capture disk failure and set friendly error message without crashing when repository fails', () async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Simulate disk write failure
      h.repo.failSave = true;

      // Act: Attempt to mark attendance
      final success = await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present);

      // Assert
      expect(success, isFalse);
      expect(h.vm.error, isNotNull);
      expect(h.vm.error, contains('Không thể hoàn tất thao tác'));
      expect(h.telemetry.errors, contains('attendance_mark'));
    });

    test('should handle upload failure, clear progress and surface error message', () async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Export file first so there is a file to upload
      await h.vm.close('c1', 'm1');
      await h.vm.export('c1', 'm1', 'csv');
      expect(h.vm.exportedFile, isNotNull);

      // Simulate upload service failure (e.g. 403 Forbidden / Unauthorized Cloud Storage)
      h.upload.fail = true;

      // Act: Attempt cloud upload
      final success = await h.vm.upload();

      // Assert
      expect(success, isFalse);
      expect(h.vm.error, equals('Không có quyền tải lên.'));
      expect(h.telemetry.errors, contains('upload_report'));
    });

    test('should survive and keep workspace functional when config service fails', () async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Simulate remote config offline
      h.config.fail = true;

      // Act
      final success = await h.vm.refreshConfig();

      // Assert
      expect(success, isFalse);
      expect(h.vm.error, contains('Không có kết nối'));
      expect(h.vm.workspace, isNotNull, reason: 'Workspace must remain functional even when config refresh fails');
    });
  });

  group('3. Negative Test - Network Loss & Offline Failures', () {
    test('should capture SocketException and display offline guidance when link creation fails', () async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Simulate network disconnect on link creation
      h.links.fail = true;

      // Act
      final success = await h.vm.createLink('c1', 'm1');

      // Assert
      expect(success, isFalse);
      expect(h.vm.error, equals('Không có kết nối. Dữ liệu đã lưu trên máy được giữ lại.'));
      expect(h.vm.link, isNull);
    });

    test('should handle network failure during link polling and keep link receiving state intact', () async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      await h.vm.createLink('c1', 'm1');
      expect(h.vm.link, isNotNull);

      // Simulate polling failure
      h.links.fail = true;

      // Act: Refresh link
      final refreshed = await h.vm.refresh();

      // Assert: Local workspace and link session remain valid
      expect(refreshed, isTrue);
      expect(h.vm.course('c1').students.length, equals(3));
    });
  });

  group('4. Negative Test - Token Expiry, Unauthorized Access & Guardrails', () {
    test('should throw StateError when validating an expired check-in challenge token', () {
      // Arrange
      final issuer = RollingQrIssuer(secret: 'test-secret-1234');
      final store = ChallengeStore(issuer);
      final issuedAt = DateTime(2026, 11, 13, 8, 0).toUtc();
      final payload = issuer.issue(
        endpoint: 'https://example.com/api',
        classId: 'c1',
        meetingId: 'm1',
        certificateFingerprint: 'abcd',
        mode: QrMode.normal,
        now: issuedAt,
      );

      final challenge = store.create(payload, 'device-phone-1', now: issuedAt);

      // Act & Assert: Validate at 2 minutes and 1 second later (expired)
      final expiredTime = issuedAt.add(const Duration(minutes: 2, seconds: 1));
      expect(
        () => store.validate(challenge.id, deviceId: 'device-phone-1', now: expiredTime),
        throwsA(isA<StateError>().having((e) => e.message, 'message', equals('Challenge đã hết hạn.'))),
      );
    });

    test('should throw StateError when validating challenge from an unauthorized device ID', () {
      // Arrange
      final issuer = RollingQrIssuer(secret: 'test-secret-1234');
      final store = ChallengeStore(issuer);
      final now = DateTime(2026, 11, 13, 8, 0).toUtc();
      final payload = issuer.issue(
        endpoint: 'https://example.com/api',
        classId: 'c1',
        meetingId: 'm1',
        certificateFingerprint: 'abcd',
        mode: QrMode.normal,
        now: now,
      );

      final challenge = store.create(payload, 'authorized-device-01', now: now);

      // Act & Assert: Device ID mismatch (attacker/proxy)
      expect(
        () => store.validate(challenge.id, deviceId: 'unauthorized-device-99', now: now),
        throwsA(isA<StateError>().having((e) => e.message, 'message', equals('Sai thiết bị.'))),
      );
    });

    test('should throw StateError when challenge requires OTP but wrong OTP is submitted', () {
      // Arrange
      final issuer = RollingQrIssuer(secret: 'test-secret-1234');
      final store = ChallengeStore(issuer);
      final now = DateTime(2026, 11, 13, 8, 0).toUtc();
      final payload = issuer.issue(
        endpoint: 'https://example.com/api',
        classId: 'c1',
        meetingId: 'm1',
        certificateFingerprint: 'abcd',
        mode: QrMode.otp,
        now: now,
      );

      final challenge = store.create(payload, 'device-phone-1', now: now);
      expect(challenge.requiresOtp, isTrue);

      // Act & Assert: Incorrect OTP
      expect(
        () => store.validate(challenge.id, deviceId: 'device-phone-1', otp: '000000', now: now),
        throwsA(isA<StateError>().having((e) => e.message, 'message', equals('Mã bí mật không đúng.'))),
      );
    });

    test('should return false when RollingQrIssuer verifies an expired QR token payload', () {
      // Arrange
      final issuer = RollingQrIssuer(secret: 'test-secret-1234');
      final issuedAt = DateTime(2026, 11, 13, 8, 0).toUtc();
      final payload = issuer.issue(
        endpoint: 'https://example.com/api',
        classId: 'c1',
        meetingId: 'm1',
        certificateFingerprint: 'abcd',
        mode: QrMode.normal,
        now: issuedAt,
      );

      // Act: Check after payload expires (25 seconds later, lifetime is 20 seconds)
      final expiredAt = issuedAt.add(const Duration(seconds: 25));
      final isValid = issuer.verify(payload, now: expiredAt);

      // Assert
      expect(isValid, isFalse, reason: 'Expired QR token must be rejected');
    });

    test('should throw StateError when attempting to mark attendance for upcoming meeting', () {
      // Arrange
      final service = AttendanceService();
      final upcomingMeeting = Meeting(
        id: 'm_future',
        number: 2,
        startAt: DateTime(2026, 12, 1, 9, 30),
        endAt: DateTime(2026, 12, 1, 11, 45),
        state: MeetingState.upcoming, // Not started
      );
      final course = fixtureWorkspace().classes.first.copyWith(meetings: [upcomingMeeting]);

      // Act & Assert
      expect(
        () => service.markPresent(course, meetingId: 'm_future', email: 'one@example.com'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('không hoạt động'))),
      );
    });

    test('should handle user cancellation or auth error during Google Sign In', () async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      h.auth.current = null;
      await h.initialize(seed: true);
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      // Simulate Google Sign-In cancellation/failure
      h.auth.fail = true;

      // Act
      final success = await h.vm.signIn();

      // Assert
      expect(success, isFalse);
      expect(h.vm.user, isNull);
      expect(h.vm.error, equals('Đã hủy đăng nhập.'));
    });

    test('should automatically stop active attendance link when teacher signs out', () async {
      // Arrange
      final tempDir = _createTempDir();
      final h = Harness(tempDir, inMemory: true);
      await h.initialize();
      addTearDown(() async {
        await h.dispose();
        _cleanupDir(tempDir);
      });

      await h.vm.createLink('c1', 'm1');
      expect(h.vm.link, isNotNull);
      expect(h.links.receiving, isTrue);

      // Act: Sign out
      final signedOut = await h.vm.signOut();

      // Assert: Link must be stopped to prevent unauthorized submissions
      expect(signedOut, isTrue);
      expect(h.vm.user, isNull);
      expect(h.vm.link, isNull);
      expect(h.links.receiving, isFalse, reason: 'Remote link must be stopped on sign out');
    });
  });
}

// Helper Widget for testing edit sheet validation
class EditAttendanceDialog extends StatelessWidget {
  const EditAttendanceDialog({
    super.key,
    required this.classId,
    required this.meetingId,
    required this.roll,
  });
  final String classId;
  final String meetingId;
  final String roll;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => editAttendance(context, classId, meetingId, roll),
          child: const Text('Mở form sửa'),
        ),
      ),
    );
  }
}
