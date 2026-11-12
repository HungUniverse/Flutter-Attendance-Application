import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'application/attendance_controller.dart';
import 'ui/desktop/desktop_app.dart';
import 'lab3/mobile_bootstrap.dart';
import 'lab3/services/firebase_services.dart';
import 'data/firebase_desktop_auth.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    runApp(const MobileBootstrap());
    return;
  }
  const legacy = bool.fromEnvironment('LAB3_LEGACY');
  if (!legacy) await initializeMobileFirebase();
  final controller = AttendanceController(
    finalFirebase: !legacy,
    teacherAuth: legacy ? null : FirebaseDesktopAuth(FirebaseAuth.instance,
      hostingUrl: 'https://${FirebaseAuth.instance.app.options.projectId}.web.app'),
  );
  await controller.initialize();
  runApp(FapAttendanceApp(controller: controller));
}

class FapAttendanceApp extends StatelessWidget {
  const FapAttendanceApp({super.key, required this.controller});

  final AttendanceController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FAP Attendance',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: DesktopHomePage(controller: controller),
    );
  }
}
