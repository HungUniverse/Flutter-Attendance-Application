import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/lab3/services/ai_attendance_review.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/domain/models.dart';
import '../lab3/fakes.dart';

class _Review implements AttendanceReviewService {
  bool fail = false;
  Map<String, int>? input;
  String? accepted;
  @override
  Future<AiAttendanceReview> review({required int present, required int absent, required int unmarked}) async {
    input = {'present': present, 'absent': absent, 'unmarked': unmarked};
    if (fail) throw const AppProblem('AI unavailable');
    return const AiAttendanceReview('Kiểm tra số lượng trước khi chốt.', ['Đối chiếu các ô chưa ghi.']);
  }
  @override
  Future<void> accept(String edited) async { accepted = edited; }
}

void main() {
  test('AI parser rejects malformed output and extra fields', () {
    expect(AiAttendanceReview.parse('{"summary":"Kiểm tra","checks":["Đối chiếu"]}').checks, ['Đối chiếu']);
    for (final value in ['{}', 'null', '{"summary":"","checks":[]}', '{"summary":"Ok","checks":[2]}', '{"summary":"Ok","checks":[],"identity":"private"}']) {
      expect(() => AiAttendanceReview.parse(value), throwsFormatException);
    }
  });
  test('AI receives aggregate counts, teacher can edit acceptance, and marks stay unchanged', () async {
    final ai = _Review();
    final h = Harness(await Directory.systemTemp.createTemp('fap-final-ai-'), ai: ai);
    await h.initialize(); addTearDown(h.dispose);
    await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present);
    expect(await h.vm.requestAiReview('c1', 'm1'), true);
    expect(ai.input, {'present': 1, 'absent': 0, 'unmarked': 2});
    expect(await h.vm.acceptAiReview('Giảng viên đã kiểm tra hai ô chưa ghi.'), true);
    expect(ai.accepted, 'Giảng viên đã kiểm tra hai ô chưa ghi.');
    expect(h.vm.counts('c1', 'm1')[AttendanceStatus.unmarked], 2);
  });
  for (final disabled in [false, true]) {
    test('closing remains available when AI is ${disabled ? 'disabled' : 'failing'}', () async {
      final ai = _Review()..fail = true;
      final h = Harness(await Directory.systemTemp.createTemp('fap-final-ai-fallback-'), ai: ai);
      await h.initialize(); addTearDown(h.dispose);
      h.config.current = FeatureSettings(enableAi: !disabled);
      expect(await h.vm.requestAiReview('c1', 'm1'), false);
      expect(await h.vm.close('c1', 'm1'), true);
      expect(h.vm.meeting('c1', 'm1').state, MeetingState.closed);
      expect(h.vm.counts('c1', 'm1')[AttendanceStatus.absent], 3);
    });
  }
}
