import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class StudentAuthService {
  bool _initialized = false;

  bool get configured =>
      const String.fromEnvironment('FIREBASE_API_KEY').isNotEmpty;

  Future<void> initialize() async {
    if (_initialized || !configured) return;
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
        appId: String.fromEnvironment('FIREBASE_APP_ID'),
        messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
      ),
    );
    _initialized = true;
  }

  Future<User> signIn(String email, String password) async {
    await initialize();
    if (!_initialized) {
      throw StateError('Firebase chưa được cấu hình; đang ở chế độ Lab 2.');
    }
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw StateError('Không đăng nhập được Firebase.');
    await user.reload();
    return FirebaseAuth.instance.currentUser!;
  }

  Future<User> register(String email, String password) async {
    await initialize();
    if (!_initialized) {
      throw StateError('Firebase chưa được cấu hình; đang ở chế độ Lab 2.');
    }
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
    final user = credential.user;
    if (user == null) throw StateError('Không tạo được tài khoản Firebase.');
    await user.sendEmailVerification();
    return user;
  }

  Future<String?> idToken() async {
    if (!_initialized) return null;
    return FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  Future<void> sendVerification() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }
}
