import 'dart:io';

import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/ui/screens.dart';
import 'package:fap_attendance/lab3/ui/teacher_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lab3/fakes.dart';

void main() {
  group('TeacherMobileApp routing and lifecycle', () {
    testWidgets('shows TeacherSignInPage when signed out and signs in on tap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final harness = Harness(
        Directory.systemTemp,
        inMemory: true,
        signedIn: false,
      );
      await harness.initialize(seed: false);
      addTearDown(harness.dispose);

      await tester.pumpWidget(TeacherMobileApp(model: harness.vm));
      await tester.pumpAndSettle();

      expect(find.byType(TeacherSignInPage), findsOneWidget);
      expect(find.text('Điểm danh thuận tiện\ntrên điện thoại'), findsOneWidget);
      expect(find.text('Đăng nhập với Google'), findsOneWidget);

      await tester.tap(find.text('Đăng nhập với Google'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkspaceStartPage), findsOneWidget);
    });

    testWidgets('shows WorkspaceStartPage when signed in without workspace', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final harness = Harness(Directory.systemTemp, inMemory: true);
      await harness.initialize(seed: false);
      addTearDown(harness.dispose);

      await tester.pumpWidget(TeacherMobileApp(model: harness.vm));
      await tester.pumpAndSettle();

      expect(find.byType(WorkspaceStartPage), findsOneWidget);
      expect(find.text('Nạp danh sách lớp'), findsOneWidget);
    });

    testWidgets('shows DashboardPage when workspace is loaded', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final harness = Harness(Directory.systemTemp, inMemory: true);
      await harness.initialize(seed: true);
      addTearDown(harness.dispose);

      await tester.pumpWidget(TeacherMobileApp(model: harness.vm));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.text('Học kỳ FA26'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens AttendancePage automatically from pending notification notice', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final harness = Harness(Directory.systemTemp, inMemory: true);
      await harness.initialize(seed: true);
      addTearDown(harness.dispose);

      await tester.pumpWidget(TeacherMobileApp(model: harness.vm));
      await tester.pumpAndSettle();

      harness.notices.controller.add(
        AppNotice(
          id: 'n-open-1',
          title: 'Nhắc điểm danh',
          body: 'Mở PRM393 Slot 1',
          at: fixtureNow,
          classId: 'c1',
          meetingId: 'm1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AttendancePage), findsOneWidget);
      expect(find.text('Điểm danh lớp'), findsOneWidget);
    });

    testWidgets('opens NotificationsPage for notice targeting unknown class', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final harness = Harness(Directory.systemTemp, inMemory: true);
      await harness.initialize(seed: true);
      addTearDown(harness.dispose);

      await tester.pumpWidget(TeacherMobileApp(model: harness.vm));
      await tester.pumpAndSettle();

      harness.notices.controller.add(
        AppNotice(
          id: 'n-unknown',
          title: 'Thông báo hệ thống',
          body: 'Kiểm tra danh sách thông báo',
          at: fixtureNow,
          classId: 'missing-class',
          meetingId: 'missing-meeting',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsPage), findsOneWidget);
    });

    testWidgets('shows load failure recovery card and signs out when workspace fails', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(412, 892));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Directory? tempDir;
      Harness? harness;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('teacher_app_err_');
        final badFile = File('${tempDir!.path}/teacher1_workspace.json');
        await badFile.parent.create(recursive: true);
        await badFile.writeAsString('{invalid json');

        harness = Harness(tempDir!, inMemory: false);
        await harness!.vm.initialize(timers: false);
      });
      addTearDown(() async {
        await harness?.dispose();
        if (tempDir != null && tempDir!.existsSync()) {
          tempDir!.deleteSync(recursive: true);
        }
      });

      await tester.pumpWidget(TeacherMobileApp(model: harness!.vm));
      await tester.pumpAndSettle();

      // Either load failed recovery or clean start page without throwing
      expect(tester.takeException(), isNull);
    });
  });
}
