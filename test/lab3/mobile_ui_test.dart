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
    await tester.tap(find.byKey(const ValueKey('timetable-nav-1')));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('timetable-nav-0')));
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
      'weekly timetable keeps calendar fixed and opens the right session at $width',
      (tester) async {
        final h = Harness(Directory('unused-ui-fixture'), inMemory: true);
        final base = fixtureWorkspace();
        final course = base.classes.single;
        final start = DateTime(2026, 11, 2);
        await h.repo.save('teacher1', fixtureWorkspace(semester: 'SP26'));
        await h.repo.save('teacher1', fixtureWorkspace(semester: 'SU26'));
        await h.repo.save(
          'teacher1',
          base.copyWith(
            classes: [
              course.copyWith(
                meetings: [
                  ...course.meetings,
                  Meeting(
                    id: 'm2',
                    number: 2,
                    startAt: DateTime(2026, 11, 6, 9, 30),
                    endAt: DateTime(2026, 11, 6, 11, 45),
                  ),
                ],
              ),
              CourseClass(
                id: 'monday',
                courseCode: 'MLN122',
                classCode: 'SE1915',
                scheduleCode: '13',
                students: const [],
                scheduleRule: ScheduleRule(
                  scheduleCode: '13',
                  semesterStart: start,
                ),
                meetings: [
                  for (final (number, hour, minute) in [
                    (1, 12, 30),
                    (2, 15, 0),
                  ])
                    Meeting(
                      id: 'monday-$number',
                      number: number,
                      startAt: DateTime(2026, 11, 2, hour, minute),
                      endAt: DateTime(2026, 11, 2, hour + 2, minute + 15),
                      state: MeetingState.closed,
                    ),
                ],
              ),
            ],
          ),
        );
        await h.initialize(seed: false);
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
        expect(find.text('Weekly timetable'), findsOneWidget);
        expect(
          find.text('Current week: 02/11/2026 – 08/11/2026'),
          findsOneWidget,
        );
        expect(find.text('FALL2026'), findsOneWidget);
        expect(find.text('Slot 3'), findsOneWidget);
        const meetChannel = MethodChannel('vn.edu.fpt.fap_attendance/meet');
        MethodCall? openedMeeting;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(meetChannel, (call) async {
          openedMeeting = call;
          return null;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(meetChannel, null),
        );
        await tester.tap(find.text('Meet URL').hitTestable().first);
        await tester.pumpAndSettle();
        expect(openedMeeting?.method, 'open');
        expect(
          openedMeeting?.arguments,
          'https://meet.google.com/meet/ptq-remp-zui',
        );
        expect(find.byType(AttendancePage), findsNothing);
        final month = find.text('November 2026');
        final monthPosition = tester.getTopLeft(month);
        await tester.runAsync(() async {
          final boundary =
              repaint.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'build/lab3-previews/timetable-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(
          find.bySemanticsLabel('Friday, 6 November 2026, có lịch dạy'),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(month), monthPosition);
        await tester.tap(find.text('NOT YET').hitTestable());
        await tester.pumpAndSettle();
        final attendance = tester.widget<AttendancePage>(
          find.byType(AttendancePage),
        );
        expect((attendance.classId, attendance.meetingId), ('c1', 'm2'));
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Tuần sau'));
        await tester.pumpAndSettle();
        expect(find.text('Chưa có lịch dạy trong tuần này.'), findsOneWidget);
        await tester.tap(find.text('Week: 09/11/2026 – 15/11/2026'));
        await tester.pumpAndSettle();
        expect(
          find.text('Current week: 02/11/2026 – 08/11/2026'),
          findsOneWidget,
        );
        await tester.tap(find.text('SUMMER2026'));
        await tester.pumpAndSettle();
        expect(h.vm.workspace!.semester, 'SU26');
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        expect(find.text('Danh sách lớp'), findsOneWidget);
        expect(find.text('Nạp danh sách lớp'), findsOneWidget);
        expect(tester.takeException(), isNull);
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
