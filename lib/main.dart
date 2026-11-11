import 'dart:io';

import 'package:flutter/material.dart';

import 'application/attendance_controller.dart';
import 'ui/desktop/desktop_app.dart';
import 'lab3/mobile_bootstrap.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    runApp(const MobileBootstrap());
    return;
  }
  final controller = AttendanceController();
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
