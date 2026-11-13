import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/lab3/services/ai_attendance_review.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeConfigService implements ConfigService {
  _FakeConfigService(this.current);

  @override
  FeatureSettings current;

  @override
  Future<void> refresh() async {}
}

class _FakeTelemetryService implements TelemetryService {
  final List<String> events = [];
  bool throwOnEvent = false;

  @override
  Future<void> identify(String? uid) async {}

  @override
  Future<void> event(String name, [Map<String, Object> parameters = const {}]) async {
    if (throwOnEvent) throw StateError('telemetry offline');
    events.add(name);
  }

  @override
  Future<void> error(Object error, StackTrace stack, String operation) async {}

  @override
  Future<void> crashForDemo() async {}
}

void main() {
  group('AiAttendanceReview.parse', () {
    test('parses valid JSON with summary and checks and formats text', () {
      final raw = jsonEncode({
        'summary': 'Có 2 sinh viên chưa điểm danh.',
        'checks': ['Kiểm tra lại danh sách vắng', 'Xác nhận slot 2'],
      });
      final review = AiAttendanceReview.parse(raw);

      expect(review.summary, 'Có 2 sinh viên chưa điểm danh.');
      expect(review.checks, hasLength(2));
      expect(
        review.text,
        'Có 2 sinh viên chưa điểm danh.\n• Kiểm tra lại danh sách vắng\n• Xác nhận slot 2',
      );
    });

    test('throws FormatException on invalid JSON, extra keys, empty summary, or invalid checks', () {
      expect(() => AiAttendanceReview.parse('not-json'), throwsFormatException);
      expect(() => AiAttendanceReview.parse('[]'), throwsFormatException);
      expect(
        () => AiAttendanceReview.parse(
          jsonEncode({'summary': 'ok', 'checks': [], 'extra': 1}),
        ),
        throwsFormatException,
      );
      expect(
        () => AiAttendanceReview.parse(
          jsonEncode({'summary': '  ', 'checks': ['a']}),
        ),
        throwsFormatException,
      );
      expect(
        () => AiAttendanceReview.parse(
          jsonEncode({'summary': 'ok', 'checks': 'not-a-list'}),
        ),
        throwsFormatException,
      );
      expect(
        () => AiAttendanceReview.parse(
          jsonEncode({'summary': 'ok', 'checks': ['valid', '  ']}),
        ),
        throwsFormatException,
      );
      expect(
        () => AiAttendanceReview.parse(
          jsonEncode({'summary': 'ok', 'checks': [123]}),
        ),
        throwsFormatException,
      );
    });
  });

  group('FirebaseAttendanceReview', () {
    late Directory tempDir;
    late _FakeConfigService config;
    late _FakeTelemetryService telemetry;
    late FirebaseAttendanceReview service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ai_rev_test_');
      config = _FakeConfigService(const FeatureSettings(enableAi: true));
      telemetry = _FakeTelemetryService();
      service = FirebaseAttendanceReview(config, telemetry, tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('review throws AppProblem immediately when enableAi is false', () async {
      config.current = const FeatureSettings(enableAi: false);
      await expectLater(
        service.review(present: 10, absent: 2, unmarked: 1),
        throwsA(isA<AppProblem>()),
      );
      expect(telemetry.events, isEmpty);
    });

    test('accept validates non-empty text, records telemetry, and writes evidence file', () async {
      await expectLater(service.accept('   '), throwsA(isA<AppProblem>()));

      await service.accept('  Đã kiểm tra đầy đủ  ');
      expect(telemetry.events, ['ai_result_accepted']);

      final files = await tempDir.list().toList();
      expect(files, hasLength(1));
      final saved = jsonDecode(await (files.single as File).readAsString()) as Map;
      expect(saved['status'], 'accepted');
      expect(saved['text'], 'Đã kiểm tra đầy đủ');
    });

    test('accept still succeeds even if telemetry throws', () async {
      telemetry.throwOnEvent = true;
      await service.accept('Confirmed');
      final files = await tempDir.list().toList();
      expect(files, hasLength(1));
    });
  });
}
