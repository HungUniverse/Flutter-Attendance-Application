import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:uuid/uuid.dart';

import '../../data/report_file_writer.dart';
import 'contracts.dart';

class AiAttendanceReview {
  const AiAttendanceReview(this.summary, this.checks);
  final String summary;
  final List<String> checks;
  String get text => [summary, ...checks.map((check) => '• $check')].join('\n');

  factory AiAttendanceReview.parse(String text) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic> || value.length != 2 || value['summary'] is! String || (value['summary'] as String).trim().isEmpty
        || value['checks'] is! List || (value['checks'] as List).any((check) => check is! String || check.trim().isEmpty)) {
      throw const FormatException('AI trả dữ liệu không đúng định dạng.');
    }
    return AiAttendanceReview(value['summary'] as String, (value['checks'] as List).cast<String>());
  }
}

abstract class AttendanceReviewService {
  Future<AiAttendanceReview> review({required int present, required int absent, required int unmarked});
  Future<void> accept(String edited);
}

class FirebaseAttendanceReview implements AttendanceReviewService {
  FirebaseAttendanceReview(this.config, this.telemetry, this.evidenceDirectory);
  final ConfigService config;
  final TelemetryService telemetry;
  final Directory evidenceDirectory;

  Future<void> _event(String name) async {
    try { await telemetry.event(name); } on Object { /* Attendance remains usable when telemetry is offline. */ }
  }
  Future<void> _evidence(Map<String, Object?> data) async {
    try {
      await evidenceDirectory.create(recursive: true);
      await writeReportAtomically(File('${evidenceDirectory.path}/${const Uuid().v4()}.json'), Stream.value(utf8.encode(jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(), ...data,
      }))));
    } on Object { /* Evidence failures do not block closing attendance. */ }
  }

  @override
  Future<AiAttendanceReview> review({required int present, required int absent, required int unmarked}) async {
    final settings = config.current;
    if (!settings.enableAi) throw const AppProblem('Gợi ý AI đang tắt. Bạn có thể tiếp tục chốt.');
    final counts = {'present': present, 'absent': absent, 'unmarked': unmarked};
    await _event('ai_request');
    try {
      final model = FirebaseAI.googleAI().generativeModel(
        model: settings.aiModel,
        systemInstruction: Content.system(settings.aiPrompt),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: Schema.object(properties: {
            'summary': Schema.string(), 'checks': Schema.array(items: Schema.string()),
          }),
        ),
      );
      final response = await model.generateContent([Content.text(jsonEncode(counts))]).timeout(const Duration(seconds: 20));
      final text = response.text ?? '';
      final review = AiAttendanceReview.parse(text);
      await _evidence({'input': counts, 'model': settings.aiModel, 'output': jsonDecode(text), 'status': 'success'});
      return review;
    } on Object catch (error) {
      await _event('ai_error');
      await _evidence({'input': counts, 'model': settings.aiModel, 'status': 'error', 'failureType': error.runtimeType.toString()});
      throw const AppProblem('Chưa lấy được gợi ý AI. Bạn có thể kiểm tra số đếm và chốt như bình thường.');
    }
  }

  @override
  Future<void> accept(String edited) async {
    if (edited.trim().isEmpty) throw const AppProblem('Vui lòng nhập nội dung xác nhận.');
    await _event('ai_result_accepted');
    // Only aggregate model inputs/outputs are retained in evidence.
    await _evidence({'status': 'accepted', 'edited': true});
  }
}
