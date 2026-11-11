import 'package:flutter/material.dart';

import 'ui/mobile/student_app.dart';
import 'ui/theme.dart';

/// Optional legacy student scanner. The default Android app is for teachers.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'FAP Attendance - Sinh viên',
      theme: buildAppTheme(),
      home: const StudentHomePage(),
      debugShowCheckedModeBanner: false,
    ),
  );
}
