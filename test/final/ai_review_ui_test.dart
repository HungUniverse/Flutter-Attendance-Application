import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/lab3/services/ai_attendance_review.dart';
import 'package:fap_attendance/lab3/ui/teacher_app.dart';
import 'package:fap_attendance/lab3/ui/attendance_screens.dart';

import '../lab3/fakes.dart';

class _Review implements AttendanceReviewService {
  @override
  Future<AiAttendanceReview> review({
    required int present,
    required int absent,
    required int unmarked,
  }) async => const AiAttendanceReview('Kiểm tra ba ô chưa ghi.', []);
  @override
  Future<void> accept(String edited) async {}
}

void main() {
  testWidgets('AI dialog accepts edited text and disposes with its route', (
    tester,
  ) async {
    final h = Harness(
      Directory('unused-final-ui-fixture'),
      inMemory: true,
      ai: _Review(),
    );
    await h.initialize();
    addTearDown(h.dispose);
    await tester.pumpWidget(TeacherMobileApp(model: h.vm));
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const AttendancePage(classId: 'c1', meetingId: 'm1'),
          ),
        );
    await tester.pumpAndSettle();
    final button = find.text('AI · Gợi ý kiểm tra trước khi chốt');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final editor = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, 'Đã kiểm tra và đối chiếu đủ.');
    await tester.tap(find.text('Xác nhận gợi ý'));
    await tester.pumpAndSettle();
    expect(h.vm.aiReview!.text, 'Đã kiểm tra và đối chiếu đủ.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
