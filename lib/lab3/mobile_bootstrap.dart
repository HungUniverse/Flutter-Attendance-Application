import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'services/firestore_attendance_links.dart';
import 'services/firestore_notifications.dart';
import 'services/ai_attendance_review.dart';
import 'services/device_service.dart';
import 'services/firebase_services.dart';
import '../data/shared_workspace_sync.dart';
import '../data/firestore_workspace_remote.dart';
import '../data/firestore_report_metadata.dart';
import 'services/synced_workspace_repository.dart';
import 'ui/mobile_theme.dart';
import 'ui/teacher_app.dart';
import 'viewmodels/teacher_view_model.dart';

class MobileBootstrapService {
  Future<TeacherViewModel> create() async {
    await initializeMobileFirebase();
    FirebaseMessaging.onBackgroundMessage(attendanceMessagingBackgroundHandler);
    final telemetry = FirebaseTelemetry(
      FirebaseAnalytics.instance,
      FirebaseCrashlytics.instance,
    );
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(
        telemetry
            .error(
              details.exception,
              details.stack ?? StackTrace.current,
              'flutter_error',
            )
            .catchError((Object _) {}),
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        telemetry.error(error, stack, 'async_error').catchError((Object _) {}),
      );
      return true;
    };
    final auth = FirebaseTeacherAuth(FirebaseAuth.instance);
    final config = FirebaseFeatureConfig(FirebaseRemoteConfig.instance);
    await config.initialize();
    final directory = await getApplicationDocumentsDirectory();
    final root = Directory('${directory.path}/FAP Attendance Mobile');
    final db = FirebaseFirestore.instance;
    final sync = SharedWorkspaceSync(FirestoreWorkspaceRemote(db, auth), root);
    late TeacherViewModel model;
    model = TeacherViewModel(
      auth: auth,
      repository: SyncedMobileWorkspaceRepository(root, sync, reports: FirestoreReportMetadata(db, root)),
      sync: sync,
      telemetry: telemetry,
      config: config,
      notifications: FirestoreNotifications(FirebaseMessaging.instance, db),
      device: AndroidDeviceService(),
      ai: FirebaseAttendanceReview(config, telemetry, Directory('${root.path}/ai-evidence')),
      links: FirestoreAttendanceLinks(db, auth, () => model.workspace?.semester,
        hostingUrl: 'https://${db.app.options.projectId}.web.app'),
    );
    await model.initialize();
    return model;
  }
}

class MobileBootstrap extends StatefulWidget {
  const MobileBootstrap({super.key});
  @override
  State<MobileBootstrap> createState() => _MobileBootstrapState();
}

class _MobileBootstrapState extends State<MobileBootstrap> {
  late Future<TeacherViewModel> _model;
  TeacherViewModel? _created;
  @override
  void initState() {
    super.initState();
    _model = _create();
  }

  Future<TeacherViewModel> _create() async =>
      _created = await MobileBootstrapService().create();
  @override
  void dispose() {
    _created?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TeacherViewModel>(
    future: _model,
    builder: (context, snapshot) {
      if (snapshot.hasData) return TeacherMobileApp(model: snapshot.data!);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: mobileTheme(),
        home: Scaffold(
          appBar: AppBar(title: const Text('FAP Attendance')),
          body: SafeArea(
            child: snapshot.hasError
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Icon(Icons.settings_outlined, size: 64),
                      const SizedBox(height: 24),
                      const Text(
                        'Cần hoàn tất cấu hình Firebase',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Thêm google-services.json của ứng dụng Android vào android/app, bật Google Sign-In và bổ sung SHA. Sau đó build và cài lại app. Hướng dẫn chi tiết nằm trong docs/FIREBASE_ANDROID_SETUP.md.',
                      ),
                      if (kDebugMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            'Loại lỗi: ${snapshot.error.runtimeType}',
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => setState(() => _model = _create()),
                        child: const Text('Thử khởi tạo lại'),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    },
  );
}
