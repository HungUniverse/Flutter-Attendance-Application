import 'package:fap_attendance/mobile/student_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StudentAuthService defaults to unconfigured in test environment', () async {
    final auth = StudentAuthService();
    expect(auth.configured, isFalse);

    await auth.initialize();
    expect(await auth.idToken(), isNull);

    await expectLater(
      auth.signIn('student@fpt.edu.vn', 'secret'),
      throwsStateError,
    );
    await expectLater(
      auth.register('student@fpt.edu.vn', 'secret'),
      throwsStateError,
    );
  });
}
