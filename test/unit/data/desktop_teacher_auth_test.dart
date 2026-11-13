import 'package:fap_attendance/data/desktop_teacher_auth.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopTeacherAuth', () {
    test('starts signed out and throws AppProblem when requesting token', () async {
      final auth = DesktopTeacherAuth(baseUrl: 'https://auth.example.com');
      expect(auth.current, isNull);
      await expectLater(auth.token(), throwsA(isA<AppProblem>()));
    });

    test('signIn rejects non-HTTPS or empty baseUrl before launching browser', () async {
      final emptyAuth = DesktopTeacherAuth(baseUrl: '');
      await expectLater(emptyAuth.signIn(), throwsA(isA<AppProblem>()));

      final httpAuth = DesktopTeacherAuth(baseUrl: 'http://insecure.local');
      await expectLater(httpAuth.signIn(), throwsA(isA<AppProblem>()));
    });

    test('signOut clears state and emits null on changes stream even if server call fails', () async {
      final auth = DesktopTeacherAuth(baseUrl: 'http://invalid');
      auth.current = const TeacherIdentity('uid-1', 'gv@fpt.edu.vn', 'GV');

      final events = <TeacherIdentity?>[];
      final sub = auth.changes.listen(events.add);

      await expectLater(auth.signOut(), throwsA(isA<AppProblem>()));
      await Future<void>.delayed(Duration.zero);

      expect(auth.current, isNull);
      expect(events, [null]);
      await sub.cancel();
    });
  });
}
