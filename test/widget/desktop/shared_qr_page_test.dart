import 'dart:async';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/attendance_link_service.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/ui/desktop/shared_qr_page.dart';
import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _StubAuth implements AuthService {
  @override
  TeacherIdentity? current = const TeacherIdentity(
    'teacher-1',
    'gv@fpt.edu.vn',
    'Giảng viên',
  );

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<String> token() async => 'stub-token';
}

class _FakeAttendanceLinkService extends HttpAttendanceLinkService {
  _FakeAttendanceLinkService(super.auth)
    : super(baseUrl: 'https://relay.example.com');

  LinkSession nextSession = LinkSession(
    id: 'link-1',
    classId: 'cls-1',
    meetingId: 'm1',
    url: 'https://fap-attendance.test/join/tok-1',
    expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    receiving: true,
    code: '482913',
  );

  List<LinkSubmission> submissions = const [];
  Object? createError;
  int createCalls = 0;
  int stopCalls = 0;

  @override
  bool get configured => true;

  @override
  Future<LinkSession> create(CourseClass courseClass, Meeting meeting) async =>
      createQr(courseClass, meeting);

  @override
  Future<LinkSession> createQr(
    CourseClass courseClass,
    Meeting meeting, {
    bool otp = false,
  }) async {
    createCalls++;
    if (createError != null) throw createError!;
    return nextSession;
  }

  @override
  Future<LinkSession?> current() async => nextSession;

  @override
  Future<LinkUpdate> poll(LinkSession session) async =>
      LinkUpdate(session, submissions);

  @override
  Future<void> stop(LinkSession session) async {
    stopCalls++;
  }
}

void main() {
  late AttendanceController controller;
  late _FakeAttendanceLinkService linkService;

  setUp(() async {
    final auth = _StubAuth();
    controller = AttendanceController(teacherAuth: auth);
    linkService = _FakeAttendanceLinkService(auth);
    controller.sharedLinks = linkService;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
    controller.workspace = TeacherWorkspace(
      id: 'ws-shared-qr',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      teacherEmail: 'gv@fpt.edu.vn',
      classes: [
        CourseClass(
          id: 'cls-1',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          scheduleCode: '11',
          students: const [
            Student(
              rollNumber: 'SE180001',
              email: 'an@fpt.edu.vn',
              fullName: 'Nguyen Van An',
            ),
            Student(
              rollNumber: 'SE180002',
              email: 'binh@fpt.edu.vn',
              fullName: 'Tran Thi Binh',
            ),
          ],
          scheduleRule: ScheduleRule(
            scheduleCode: '11',
            semesterStart: DateTime(2026, 9, 7),
          ),
          meetings: [
            Meeting(
              id: 'm1',
              number: 1,
              startAt: todayStart,
              endAt: todayStart.add(const Duration(hours: 2)),
              state: MeetingState.active,
            ),
          ],
        ),
      ],
    );
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpSharedQr(
    WidgetTester tester, {
    QrMode mode = QrMode.normal,
    Size size = const Size(1000, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: SharedQrPage(
          controller: controller,
          classId: 'cls-1',
          meetingId: 'm1',
          mode: mode,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SharedQrPage', () {
    testWidgets(
      'renders QR code, count, OTP code, and Copy link on desktop width',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpSharedQr(tester, size: const Size(1000, 800));

        expect(find.text('PRM392 · SE1801 · Buổi 1'), findsOneWidget);
        expect(find.text('Đang nhận điểm danh'), findsOneWidget);
        expect(find.text('0 / 2'), findsOneWidget);
        expect(find.text('Sinh viên có mặt'), findsOneWidget);
        expect(find.text('Mã xác nhận'), findsOneWidget);
        expect(find.text('482913'), findsOneWidget);
        expect(find.text('Sao chép link'), findsOneWidget);
        expect(find.text('Chốt danh sách'), findsOneWidget);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(linkService.createCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('switches to stacked Column layout on narrow width (< 570px)', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpSharedQr(tester, size: const Size(520, 900));

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Sao chép link'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('copies link and shows confirmation SnackBar', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await pumpSharedQr(tester);

      await tester.tap(find.text('Sao chép link'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Đã sao chép link điểm danh.'), findsOneWidget);
    });

    testWidgets('shows stopped state and lets teacher regenerate QR', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      linkService.nextSession = LinkSession(
        id: 'link-stopped',
        classId: 'cls-1',
        meetingId: 'm1',
        url: 'https://fap-attendance.test/join/tok-stopped',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        receiving: false,
      );

      await pumpSharedQr(tester);
      expect(find.text('Đã dừng nhận'), findsOneWidget);
      expect(find.text('Tạo lại QR'), findsOneWidget);

      linkService.nextSession = LinkSession(
        id: 'link-new',
        classId: 'cls-1',
        meetingId: 'm1',
        url: 'https://fap-attendance.test/join/tok-new',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        receiving: true,
        code: '991122',
      );
      await tester.tap(find.text('Tạo lại QR'));
      await tester.pumpAndSettle();

      expect(find.text('Đang nhận điểm danh'), findsOneWidget);
      expect(find.text('991122'), findsOneWidget);
      expect(linkService.createCalls, 2);
    });

    testWidgets('displays error notice when link creation fails', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      linkService.createError = const AppProblem('Không thể kết nối máy chủ.');

      await pumpSharedQr(tester);

      expect(find.text('Chưa mở mã QR'), findsOneWidget);
      expect(find.textContaining('Không thể kết nối máy chủ.'), findsOneWidget);
      expect(find.text('Tạo lại QR'), findsOneWidget);
    });

    testWidgets('closes meeting and pops page when Chốt danh sách tapped', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.binding.setSurfaceSize(const Size(1000, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => SharedQrPage(
                          controller: controller,
                          classId: 'cls-1',
                          meetingId: 'm1',
                        ),
                      ),
                    );
                  },
                  child: const Text('Push SharedQr'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Push SharedQr'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedQrPage), findsOneWidget);

      await tester.ensureVisible(find.text('Chốt danh sách'));
      await tester.tap(find.text('Chốt danh sách'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pumpAndSettle();
        if (find.byType(SharedQrPage).evaluate().isEmpty) break;
      }

      expect(controller.meetingById('cls-1', 'm1').state, MeetingState.closed);
      expect(linkService.stopCalls, 1);
      expect(find.byType(SharedQrPage), findsNothing);
    });
  });
}
