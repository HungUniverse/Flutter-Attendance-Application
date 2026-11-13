import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TeacherIdentity and FeatureSettings store defaults and values', () {
    const id = TeacherIdentity('u1', 'gv@fpt.edu.vn', 'Lecturer');
    expect(id.uid, 'u1');
    expect(id.email, 'gv@fpt.edu.vn');
    expect(id.name, 'Lecturer');

    const settings = FeatureSettings();
    expect(settings.enableLink, isTrue);
    expect(settings.enableAi, isTrue);
    expect(settings.aiModel, isNotEmpty);
    expect(settings.aiPrompt, isNotEmpty);
  });

  test('AppNotice roundtrips through toJson and fromJson', () {
    final now = DateTime.utc(2026, 9, 7, 8, 0);
    final notice = AppNotice(
      id: 'n1',
      title: 'Slot Reminder',
      body: 'Slot 1 starts soon',
      at: now,
      classId: 'cls-1',
      meetingId: 'm1',
    );
    final decoded = AppNotice.fromJson(notice.toJson());
    expect(decoded.id, 'n1');
    expect(decoded.title, 'Slot Reminder');
    expect(decoded.body, 'Slot 1 starts soon');
    expect(decoded.at, now);
    expect(decoded.classId, 'cls-1');
    expect(decoded.meetingId, 'm1');
  });

  test('LinkSession roundtrips through toJson and fromJson', () {
    final exp = DateTime.utc(2026, 9, 7, 8, 15);
    final session = LinkSession(
      id: 's1',
      classId: 'cls-1',
      meetingId: 'm1',
      url: 'https://fap.web.app/s1',
      expiresAt: exp,
      receiving: false,
      code: '654321',
    );
    final json = session.toJson();
    final decoded = LinkSession.fromJson({...json, 'code': '654321'});
    expect(decoded.id, 's1');
    expect(decoded.receiving, isFalse);
    expect(decoded.code, '654321');
    expect(decoded.expiresAt, exp);
  });

  test('AppProblem toString returns message', () {
    const problem = AppProblem('Custom error message');
    expect(problem.toString(), 'Custom error message');
  });
}
