import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contracts.dart';
import 'report_destination.dart';

Future<void> initializeMobileFirebase() async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
}

@pragma('vm:entry-point')
Future<void> attendanceMessagingBackgroundHandler(RemoteMessage message) async {
  await initializeMobileFirebase();
  await FirebaseNotificationService.persist(message);
}

class FirebaseTeacherAuth implements AuthService {
  FirebaseTeacherAuth(this.auth);
  final FirebaseAuth auth;
  Future<void>? _initializing;
  Future<void> _googleReady() =>
      _initializing ??= GoogleSignIn.instance.initialize();
  TeacherIdentity? _identity(User? user) => user == null
      ? null
      : TeacherIdentity(
          user.uid,
          user.email ?? '',
          user.displayName ?? 'Giảng viên',
        );
  @override
  TeacherIdentity? get current => _identity(auth.currentUser);
  @override
  Stream<TeacherIdentity?> get changes =>
      auth.authStateChanges().map(_identity);
  @override
  Future<void> signIn() async {
    try {
      await _googleReady();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AppProblem('Google không trả về thông tin đăng nhập.');
      }
      await auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AppProblem('Đã hủy đăng nhập. Bạn có thể thử lại.');
      }
      throw const AppProblem(
        'Không đăng nhập được với Google. Kiểm tra kết nối và cấu hình tài khoản.',
      );
    } on FirebaseAuthException catch (error) {
      throw AppProblem(
        error.code == 'network-request-failed'
            ? 'Không có kết nối. Hãy kiểm tra mạng và thử lại.'
            : 'Không xác thực được tài khoản. Hãy thử lại hoặc kiểm tra cấu hình đăng nhập.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    await _googleReady();
    await GoogleSignIn.instance.signOut();
    await auth.signOut();
  }

  @override
  Future<String> token() async {
    final value = await auth.currentUser?.getIdToken();
    if (value == null) throw const AppProblem('Vui lòng đăng nhập lại.');
    return value;
  }
}

class FirebaseTelemetry implements TelemetryService {
  FirebaseTelemetry(this.analytics, this.crashlytics);
  final FirebaseAnalytics analytics;
  final FirebaseCrashlytics crashlytics;
  @override
  Future<void> identify(String? uid) async {
    await analytics.setUserId(id: uid);
    await crashlytics.setUserIdentifier(uid ?? '');
  }

  @override
  Future<void> event(
    String name, [
    Map<String, Object> parameters = const {},
  ]) => analytics.logEvent(
    name: name,
    parameters: parameters.isEmpty ? null : parameters,
  );
  @override
  Future<void> error(Object error, StackTrace stack, String operation) async {
    await crashlytics.setCustomKey('operation', operation);
    // Free-text errors may contain imported student data, paths or tokens.
    await crashlytics.recordError(
      Exception('$operation: ${error.runtimeType}'),
      stack,
      reason: operation,
      fatal: false,
    );
  }

  @override
  Future<void> crashForDemo() async {
    if (!const bool.fromEnvironment('LAB3_DEMO_TOOLS')) {
      throw const AppProblem(
        'Khu vực kiểm thử crash chưa được bật cho bản này.',
      );
    }
    await crashlytics.setCustomKey('operation', 'lab3_demo_crash');
    crashlytics.crash();
  }
}

class FirebaseFeatureConfig implements ConfigService {
  FirebaseFeatureConfig(this.config);
  final FirebaseRemoteConfig config;
  FeatureSettings _current = const FeatureSettings();
  @override
  FeatureSettings get current => _current;
  Future<void> initialize() async {
    await config.setDefaults({
      'enable_link_attendance': true,
      'export_help_message': const FeatureSettings().exportHelp,
    });
    await config.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? const Duration(minutes: 1)
            : const Duration(hours: 1),
      ),
    );
    _read();
  }

  void _read() => _current = FeatureSettings(
    enableLink: config.getBool('enable_link_attendance'),
    exportHelp: config.getString('export_help_message'),
  );
  @override
  Future<void> refresh() async {
    try {
      await config.fetchAndActivate();
    } finally {
      _read();
    }
  }
}

class FirebaseReportUpload implements UploadService {
  FirebaseReportUpload(this.storage);
  final FirebaseStorage storage;
  @override
  Future<String> upload(
    File file,
    ReportDestination destination,
    void Function(double) progress,
  ) async {
    final name = file.uri.pathSegments.last;
    if (name != destination.fileName) {
      throw const AppProblem(
        'Tệp báo cáo không khớp thông tin sao lưu. Hãy xuất lại tệp.',
      );
    }
    final ref = storage.ref(destination.objectPath);
    final task = ref.putFile(
      file,
      SettableMetadata(
        contentType: name.endsWith('.json') ? 'application/json' : 'text/csv',
        customMetadata: destination.metadata,
      ),
    );
    final subscription = task.snapshotEvents.listen((snapshot) {
      progress(
        snapshot.totalBytes == 0
            ? 0
            : snapshot.bytesTransferred / snapshot.totalBytes,
      );
    });
    try {
      await task;
      return await ref.getDownloadURL();
    } on FirebaseException catch (error) {
      if (error.code == 'unauthorized' || error.code == 'unauthenticated') {
        throw const AppProblem(
          'Không có quyền sao lưu. Kiểm tra đăng nhập và Storage Rules mới rồi thử lại.',
        );
      }
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }
}

class FirebaseNotificationService implements NotificationService {
  FirebaseNotificationService(this.messaging);
  final FirebaseMessaging messaging;
  final _opened = StreamController<AppNotice>.broadcast();
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _tap;
  String? _uid;
  @override
  Stream<AppNotice> get opened => _opened.stream;
  static AppNotice _notice(RemoteMessage m) => AppNotice(
    id:
        m.messageId ??
        '${m.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}',
    title: m.notification?.title ?? m.data['title'] ?? 'Thông báo điểm danh',
    body: m.notification?.body ?? m.data['body'] ?? '',
    at: m.sentTime ?? DateTime.now(),
    classId: m.data['classId'],
    meetingId: m.data['meetingId'],
  );
  static Future<void> persist(RemoteMessage message) async {
    final prefs = SharedPreferencesAsync();
    final uid = await prefs.getString('fap_notice_owner');
    if (uid == null ||
        (message.data['uid'] != null && message.data['uid'] != uid)) {
      return;
    }
    final notice = _notice(message);
    await prefs.setString(
      'fap_notice_${uid}_${notice.id}',
      jsonEncode(notice.toJson()),
    );
  }

  @override
  Future<void> start(String uid) async {
    await _foreground?.cancel();
    await _tap?.cancel();
    _uid = uid;
    await SharedPreferencesAsync().setString('fap_notice_owner', uid);
    _foreground = FirebaseMessaging.onMessage.listen((m) async {
      try {
        await persist(m);
      } on Object {
        /* retry through next history read */
      }
    });
    _tap = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initial = await messaging.getInitialMessage();
    if (initial != null) await _handleTap(initial);
  }

  Future<void> _handleTap(RemoteMessage message) async {
    if (_uid == null ||
        (message.data['uid'] != null && message.data['uid'] != _uid)) {
      return;
    }
    await persist(message);
    _opened.add(_notice(message));
  }

  @override
  Future<String> requestPermission() async =>
      (await messaging.requestPermission()).authorizationStatus.name;
  @override
  Future<String?> token() => messaging.getToken();
  @override
  Future<List<AppNotice>> history(String uid) async {
    final prefs = SharedPreferencesAsync();
    final keys = (await prefs.getKeys()).where(
      (key) => key.startsWith('fap_notice_${uid}_'),
    );
    final entries = <AppNotice>[];
    for (final key in keys) {
      final value = await prefs.getString(key);
      if (value != null) {
        entries.add(
          AppNotice.fromJson(jsonDecode(value) as Map<String, dynamic>),
        );
      }
    }
    return entries..sort((a, b) => b.at.compareTo(a.at));
  }

  @override
  Future<void> stop() async {
    _uid = null;
    await _foreground?.cancel();
    await _tap?.cancel();
    await SharedPreferencesAsync().remove('fap_notice_owner');
    await messaging.deleteToken();
  }
}
