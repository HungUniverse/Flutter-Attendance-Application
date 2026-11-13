import 'dart:async';
import 'dart:io';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/attendance_link_service.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/ui/desktop/qr_session_page.dart';
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
    'teacher@fpt.edu.vn',
    'Teacher One',
  );

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<String> token() async => 'fake-token';
}

class _FakeSync extends SharedWorkspaceSync {
  _FakeSync(super.api, super.root) {
    conflict = false;
    status = 'Đã đồng bộ';
  }
}

class _DummyRemote implements WorkspaceRemote {
  @override
  AuthService get auth => _StubAuth();

  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) async => {
    'data': null,
  };

  @override
  Future<Map<String, dynamic>> writeWorkspace(
    Map<String, dynamic> pending,
  ) async => {'data': null};
}

class _FakeAttendanceLinkService extends HttpAttendanceLinkService {
  _FakeAttendanceLinkService(super.auth)
    : super(baseUrl: 'https://relay.example.com');

  bool failNextCreate = false;
  int createCalls = 0;
  int stopCalls = 0;
  LinkSession? activeSession;
  List<LinkSubmission> nextSubmissions = const [];

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
    if (failNextCreate) {
      failNextCreate = false;
      throw const AppProblem('Không thể tạo mã QR lúc này.');
    }
    final session = LinkSession(
      id: 'sess-$createCalls',
      classId: courseClass.id,
      meetingId: meeting.id,
      url: 'https://relay.example.com/attend/sess-$createCalls',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      receiving: true,
      code: otp ? '842915' : null,
    );
    activeSession = session;
    return session;
  }

  @override
  Future<LinkSession?> current() async => activeSession;

  @override
  Future<LinkUpdate> poll(LinkSession session) async =>
      LinkUpdate(session, nextSubmissions);

  @override
  Future<void> stop(LinkSession session) async {
    stopCalls++;
    activeSession = LinkSession(
      id: session.id,
      classId: session.classId,
      meetingId: session.meetingId,
      url: session.url,
      expiresAt: session.expiresAt,
      receiving: false,
      code: session.code,
    );
  }
}

TeacherWorkspace _buildTodayWorkspace({
  MeetingState todayState = MeetingState.active,
  int studentCount = 3,
}) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
  final futureStart = todayStart.add(const Duration(days: 2));
  return TeacherWorkspace(
    id: 'ws-qr',
    semester: 'FA26',
    semesterStart: DateTime(now.year, now.month, 1),
    teacherEmail: 'teacher@fpt.edu.vn',
    classes: [
      CourseClass(
        id: 'c1',
        courseCode: 'SWD392',
        classCode: 'SE1801',
        scheduleCode: 'M1',
        students: [
          for (var i = 1; i <= studentCount; i++)
            Student(
              rollNumber: 'SE18000$i',
              fullName: 'Sinh vien $i',
              email: 'sv$i@fpt.edu.vn',
            ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: 'M1',
          semesterStart: DateTime(now.year, now.month, 1),
        ),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: todayStart,
            endAt: todayStart.add(const Duration(minutes: 135)),
            state: todayState,
          ),
          Meeting(
            id: 'm2',
            number: 2,
            startAt: futureStart,
            endAt: futureStart.add(const Duration(minutes: 135)),
            state: MeetingState.upcoming,
          ),
        ],
      ),
    ],
  );
}

void main() {
  late Directory tempDir;
  late _StubAuth auth;
  late _FakeAttendanceLinkService linkService;
  late AttendanceController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('qr_widget_matrix_');
    auth = _StubAuth();
    linkService = _FakeAttendanceLinkService(auth);
    controller = AttendanceController(
      teacherAuth: auth,
      documentsDirectory: tempDir,
    );
    controller.sharedLinks = linkService;
    controller.workspace = _buildTodayWorkspace();
    await controller.save();
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) => MaterialApp(
    theme: buildAppTheme(),
    home: child,
  );

  group('SharedQrPage responsive layout, OTP, copy, error retry & conflict', () {
    testWidgets('uses Row on >=570px viewport and Column on <570px viewport', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          SharedQrPage(
            controller: controller,
            classId: 'c1',
            meetingId: 'm1',
            mode: QrMode.normal,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Đang nhận điểm danh'), findsOneWidget);
      expect(find.text('Sinh viên có mặt'), findsOneWidget);
      expect(find.text('0 / 3'), findsOneWidget);
      expect(find.byType(Row), findsWidgets);

      await tester.binding.setSurfaceSize(const Size(480, 900));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Sao chép link'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('renders OTP verification code in QrMode.otp and copies link to clipboard', (
      tester,
    ) async {
      String? copiedUrl;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedUrl = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.binding.setSurfaceSize(const Size(920, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          SharedQrPage(
            controller: controller,
            classId: 'c1',
            meetingId: 'm1',
            mode: QrMode.otp,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mã xác nhận'), findsOneWidget);
      expect(find.text('842915'), findsOneWidget);

      await tester.tap(find.text('Sao chép link'));
      await tester.pumpAndSettle();

      expect(copiedUrl, contains('https://relay.example.com/attend/sess-'));
      expect(find.text('Đã sao chép link điểm danh.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('displays error notice and retries link creation via Tạo lại QR', (
      tester,
    ) async {
      linkService.failNextCreate = true;
      await tester.binding.setSurfaceSize(const Size(920, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          SharedQrPage(
            controller: controller,
            classId: 'c1',
            meetingId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Tạo lại QR'), findsOneWidget);

      await tester.tap(find.text('Tạo lại QR'));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Đang nhận điểm danh'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('displays sync conflict banner when sync.conflict is true', (
      tester,
    ) async {
      final fakeSync = _FakeSync(_DummyRemote(), tempDir)..conflict = true;
      controller.sync = fakeSync;

      await tester.binding.setSurfaceSize(const Size(920, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          SharedQrPage(
            controller: controller,
            classId: 'c1',
            meetingId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Xung đột đồng bộ. Về danh sách lớp để đối chiếu.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows Đã chốt status on closed meeting and hides live QR', (
      tester,
    ) async {
      await tester.runAsync(() async {
        controller.workspace = _buildTodayWorkspace(
          todayState: MeetingState.closed,
        );
        await controller.save();
      });

      await tester.binding.setSurfaceSize(const Size(920, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          SharedQrPage(
            controller: controller,
            classId: 'c1',
            meetingId: 'm1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đã chốt'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Chốt danh sách button closes meeting, marks absences, and pops page', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(920, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SharedQrPage(
                        controller: controller,
                        classId: 'c1',
                        meetingId: 'm1',
                      ),
                    ),
                  ),
                  child: const Text('Mở QR'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở QR'));
      await tester.pumpAndSettle();
      expect(find.text('Chốt danh sách'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Chốt danh sách'));
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();

      expect(
        controller.meetingById('c1', 'm1').state,
        MeetingState.closed,
      );
      expect(find.text('Mở QR'), findsOneWidget);
    });
  });

  group('QrSessionPage LAN/Tunnel mode switching, list & close workflow', () {
    testWidgets('starts server, switches between normal & OTP modes, and lists checked-in students', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          wrap(
            QrSessionPage(
              controller: controller,
              classId: 'c1',
              meetingId: 'm1',
              initialMode: QrMode.normal,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pump();

      expect(find.text('SWD392 · Slot 1'), findsOneWidget);
      expect(find.text('QR thường'), findsOneWidget);
      expect(find.text('QR + mã bí mật'), findsOneWidget);
      expect(find.text('Sinh viên đã điểm danh'), findsOneWidget);
      expect(find.text('Chưa có sinh viên điểm danh.'), findsOneWidget);

      await tester.tap(find.text('QR + mã bí mật'));
      await tester.pump();
      expect(
        find.text('Mã bí mật giữ nguyên cho đến khi bật lại chế độ này'),
        findsOneWidget,
      );

      await tester.runAsync(() async {
        await controller.markPresent(
          'c1',
          'm1',
          'sv1@fpt.edu.vn',
          source: AttendanceSource.scan,
        );
      });
      await tester.tap(find.text('QR thường'));
      await tester.pump();

      expect(find.text('Sinh vien 1'), findsOneWidget);
      expect(find.text('SE180001'), findsOneWidget);
      expect(find.text('1/3 có mặt'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
    });

    testWidgets('closes active LAN QR session and pops back to host route', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          wrap(
            Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => QrSessionPage(
                          controller: controller,
                          classId: 'c1',
                          meetingId: 'm1',
                          initialMode: QrMode.normal,
                        ),
                      ),
                    ),
                    child: const Text('Start LAN'),
                  ),
                ),
              ),
            ),
          ),
        );
      });
      await tester.runAsync(() async {
        await tester.tap(find.text('Start LAN'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();

      expect(find.text('Chốt danh sách'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Chốt danh sách'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();

      expect(controller.meetingById('c1', 'm1').state, MeetingState.closed);
      expect(find.text('Start LAN'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
    });
  });
}
