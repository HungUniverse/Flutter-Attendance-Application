import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/ui/teacher_app.dart';
import 'package:fap_attendance/lab3/ui/screens.dart';
import 'package:fap_attendance/lab3/ui/mobile_theme.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Local preview font, not distributed with the application.
    final file = File('C:/Windows/Fonts/arial.ttf');
    if (file.existsSync()) {
      final bytes = ByteData.sublistView(file.readAsBytesSync());
      for (final family in ['Roboto', 'Segoe UI']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('notification destination returns to the existing workspace', (
    tester,
  ) async {
    final h = Harness(Directory('unused-ui-fixture'), inMemory: true);
    await h.initialize();
    addTearDown(h.dispose);
    await tester.pumpWidget(TeacherMobileApp(model: h.vm));
    await tester.pumpAndSettle();
    final nav = find.byType(NavigationBar);
    await tester.tap(
      find.descendant(of: nav, matching: find.text('Thông báo')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsPage), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Lịch & lớp'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(h.vm.course('c1').students.length, 3);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [360.0, 412.0]) {
    testWidgets('all business screens render at $width', (tester) async {
      final h = Harness(Directory('unused-ui-fixture'), inMemory: true);
      await h.initialize();
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        await h.dispose();
      });
      final screens = <Widget>[
        const WorkspaceStartPage(),
        const ImportPage(),
        const SchedulePage(classId: 'c1'),
        const LinkPage(classId: 'c1', meetingId: 'm1'),
        const StudentPage(classId: 'c1', roll: 'S1'),
        const HistoryPage(classId: 'c1'),
        const ExportPage(classId: 'c1', meetingId: 'm1'),
        const NotificationsPage(),
        const AccountPage(),
      ];
      for (final page in screens) {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: h.vm,
            child: MaterialApp(
              key: ValueKey(page.runtimeType),
              theme: mobileTheme(),
              home: page,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Drive'), findsNothing);
        if (page is ExportPage) {
          final backup = find.widgetWithText(
            CheckboxListTile,
            'Sao lưu Firebase Storage',
          );
          await tester.scrollUntilVisible(backup, 180);
          expect(tester.widget<CheckboxListTile>(backup).value, isFalse);
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.runtimeType} at $width',
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('manual layout and actual widget preview at $width', (
      tester,
    ) async {
      final h = Harness(Directory('unused-ui-fixture'), inMemory: true);
      await h.initialize();
      h.vm.selectMode(AttendanceMode.manual);
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        await h.dispose();
      });
      final repaint = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: repaint,
          child: TeacherMobileApp(model: h.vm),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const AttendancePage(classId: 'c1', meetingId: 'm1'),
            ),
          );
      await tester.pumpAndSettle();
      expect(find.text('Qua link'), findsOneWidget);
      expect(find.text('Thủ công'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            repaint.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/lab3-previews/manual-${width.toInt()}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      final present = find.text('P · Có mặt');
      await tester.scrollUntilVisible(
        present,
        150,
        scrollable: find
            .descendant(
              of: find.byType(AttendancePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(present.first);
      await tester.pumpAndSettle();
      expect(h.vm.course('c1').recordFor('m1', 'S1'), isNotNull);
      expect(find.byType(AttendancePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            repaint.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/lab3-previews/manual-controls-${width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
      'weekly schedule scrolls by date and opens the selected meeting at $width',
      (tester) async {
        final h = Harness(Directory('unused-ui-fixture'), inMemory: true);
        await h.initialize();
        final workspace = h.vm.workspace!;
        final course = workspace.classes.single;
        h.vm.workspace = workspace.copyWith(
          classes: [
            course.copyWith(
              meetings: [
                course.meetings.single,
                Meeting(
                  id: 'm2',
                  number: 2,
                  startAt: DateTime(2026, 11, 3, 7),
                  endAt: DateTime(2026, 11, 3, 9, 15),
                  state: MeetingState.upcoming,
                ),
              ],
            ),
          ],
        );
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() async {
          await tester.binding.setSurfaceSize(null);
          await h.dispose();
        });
        await tester.pumpWidget(TeacherMobileApp(model: h.vm));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lịch tuần'));
        await tester.pumpAndSettle();
        expect(find.text('02/11 – 08/11/2026'), findsOneWidget);
        expect(find.text('03/11'), findsOneWidget);
        expect(find.text('Ca 1'), findsOneWidget);
        expect(find.text('07:00'), findsOneWidget);
        expect(find.text('Ca 2'), findsOneWidget);
        expect(find.text('09:30'), findsOneWidget);
        final first = find.text('SE1901 · Slot 1');
        final second = find.text('SE1901 · Slot 2');
        expect(
          tester.getTopLeft(second).dy,
          lessThan(tester.getTopLeft(first).dy),
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                (widget.axisDirection == AxisDirection.left ||
                    widget.axisDirection == AxisDirection.right),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(first);
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(
          tester.widget<AttendancePage>(find.byType(AttendancePage)).meetingId,
          'm1',
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        final next = find.byTooltip('Tuần sau');
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('09/11 – 15/11/2026'), findsOneWidget);
        expect(
          find.text('Chưa có lịch dạy trong tuần này. Chọn tuần khác.'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('editing validates a new reason and cancellation keeps record', (
    tester,
  ) async {
    final h = Harness(Directory('unused-ui-fixture'), inMemory: true);
    await h.initialize();
    addTearDown(h.dispose);
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(TeacherMobileApp(model: h.vm));
    await tester.pumpAndSettle();
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const StudentPage(classId: 'c1', roll: 'S1'),
          ),
        );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sửa P/A'));
    await tester.tap(find.text('Sửa P/A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng nhập lý do chỉnh sửa.'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(h.vm.course('c1').recordFor('m1', 'S1'), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'sign-out clears protected routes and canceled Google login stays guarded',
    (tester) async {
      final h = Harness(Directory('unused-ui-fixture'), inMemory: true);
      await h.initialize();
      addTearDown(h.dispose);
      await tester.pumpWidget(TeacherMobileApp(model: h.vm));
      await tester.pumpAndSettle();
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute<void>(builder: (_) => const AccountPage()));
      await tester.pumpAndSettle();
      await h.vm.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập với Google'), findsOneWidget);
      expect(find.text('Tài khoản & cài đặt'), findsNothing);
      h.auth.fail = true;
      await tester.tap(find.text('Đăng nhập với Google'));
      await tester.pumpAndSettle();
      expect(find.text('Đã hủy đăng nhập.'), findsOneWidget);
      expect(h.vm.user, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
