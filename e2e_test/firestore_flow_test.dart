import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:fap_attendance/data/firestore_workspace_remote.dart';
import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/data/firestore_report_metadata.dart';
import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/firebase_services.dart';
import 'package:fap_attendance/lab3/services/firestore_attendance_links.dart';
import 'package:fap_attendance/lab3/services/synced_workspace_repository.dart';
import 'package:fap_attendance/lab3/services/ai_attendance_review.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';

import '../test/lab3/fakes.dart';

String fakeGoogleToken(String email) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'none', 'typ': 'JWT'})}.${encode({'sub': email, 'email': email, 'email_verified': true, 'iss': 'https://accounts.google.com', 'aud': 'fake', 'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.';
}

Future<Map<String, dynamic>> studentCheckIn(
  String session,
  String email,
) async {
  final result = await Process.run('node', [
    'e2e_test/student-check-in.mjs',
    session,
    email,
  ], workingDirectory: const String.fromEnvironment('FAP_PROJECT_DIR'));
  expect(result.exitCode, 0, reason: result.stderr.toString());
  final line = const LineSplitter()
      .convert(result.stdout.toString())
      .lastWhere((line) => line.startsWith('{'));
  return jsonDecode(line) as Map<String, dynamic>;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Firebase and web SDK complete three isolated attendance flows',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await initializeMobileFirebase();
        expect(
          await FirebaseAppCheck.instance.getToken(),
          isNotEmpty,
          reason:
              'Live project App Check debug token must exchange successfully.',
        );
        final results = <Map<String, Object?>>[];
        for (var round = 1; round <= 3; round++) {
          final app = await Firebase.initializeApp(
            name: 'FinalEmulator$round',
            options: const FirebaseOptions(
              apiKey: 'fake-api-key',
              appId: '1:123:web:emulator',
              messagingSenderId: '123',
              projectId: 'demo-fap-final',
            ),
          );
          final auth = FirebaseAuth.instanceFor(app: app);
          await auth.useAuthEmulator('127.0.0.1', 9099);
          await auth.signInWithCredential(
            GoogleAuthProvider.credential(
              idToken: fakeGoogleToken('teacher@example.com'),
            ),
          );
          final uid = auth.currentUser!.uid;
          final provision = await http.patch(
            Uri.parse(
              'http://127.0.0.1:8080/v1/projects/demo-fap-final/databases/(default)/documents/users/$uid',
            ),
            headers: {
              'authorization': 'Bearer owner',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'fields': {
                'role': {'stringValue': 'teacher'},
              },
            }),
          );
          expect(provision.statusCode, 200);
          final db = FirebaseFirestore.instanceFor(app: app);
          db.useFirestoreEmulator('127.0.0.1', 8080);
          final root = await Directory.systemTemp.createTemp(
            'fap-native-final-',
          );
          final identity = FirebaseTeacherAuth(auth);
          final sync = SharedWorkspaceSync(
            FirestoreWorkspaceRemote(db, identity),
            root,
          );
          final reports = FirestoreReportMetadata(db, root);
          final repository = SyncedMobileWorkspaceRepository(
            root,
            sync,
            reports: reports,
          );
          final now = DateTime.now();
          final source = fixtureWorkspace(
            state: MeetingState.upcoming,
            semester: 'DEMO$round',
          );
          final course = source.classes.single.copyWith(
            meetings: [
              Meeting(
                id: 'm1',
                number: 1,
                startAt: DateTime(now.year, now.month, now.day, 8),
                endAt: DateTime(now.year, now.month, now.day, 23, 59),
              ),
            ],
          );
          await repository.save(
            uid,
            source.copyWith(
              classes: [course],
              teacherEmail: 'teacher@example.com',
              updatedAt: now.toUtc(),
            ),
          );
          expect(sync.status, 'Đã đồng bộ');
          final notices = FakeNotices();
          late TeacherViewModel model;
          model = TeacherViewModel(
            auth: identity,
            repository: repository,
            sync: sync,
            telemetry: FakeTelemetry(),
            config: FakeConfig(),
            notifications: notices,
            device: FakeDevice(),
            links: FirestoreAttendanceLinks(
              db,
              identity,
              () => model.workspace?.semester,
              hostingUrl: 'https://fap-attendance-71655.web.app',
            ),
          );
          try {
            await model.initialize(timers: false);
            expect(await model.begin('c1', 'm1'), true, reason: model.error);
            expect(
              await model.mark('c1', 'm1', 'S1', AttendanceStatus.absent),
              true,
            );
            expect(
              await model.createLink('c1', 'm1'),
              true,
              reason: model.error,
            );
            final session = model.link!.id;
            expect(
              (await studentCheckIn(session, 'one@example.com'))['accepted'],
              true,
            );
            final timer = Stopwatch()..start();
            expect(
              (await studentCheckIn(session, 'two@example.com'))['accepted'],
              true,
            );
            final deadline = DateTime.now().add(const Duration(seconds: 15));
            while (model.counts('c1', 'm1')[AttendanceStatus.present] != 1 &&
                DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            timer.stop();
            expect(
              model.counts('c1', 'm1')[AttendanceStatus.present],
              1,
              reason: model.linkError,
            );
            expect(
              model.course('c1').recordFor('m1', 'S1')!.status,
              AttendanceStatus.absent,
            );
            expect(
              (await studentCheckIn(session, 'two@example.com'))['alreadySent'],
              true,
            );
            expect(
              (await studentCheckIn(
                session,
                'outsider@example.com',
              ))['accepted'],
              false,
            );
            expect(await model.close('c1', 'm1'), true, reason: model.error);
            expect(
              (await studentCheckIn(session, 'three@example.com'))['accepted'],
              false,
            );
            expect(model.counts('c1', 'm1')[AttendanceStatus.absent], 2);
            expect(
              await model.edit(
                'c1',
                'm1',
                'S1',
                AttendanceStatus.present,
                'Đối chiếu minh chứng',
              ),
              true,
              reason: model.error,
            );
            expect(
              await model.export('c1', 'm1', 'pdf'),
              true,
              reason: model.error,
            );
            expect(reports.warning, isNull);
            final restored = await repository.load(uid, semester: 'DEMO$round');
            expect(
              restored!.classes.single.recordFor('m1', 'S1')!.status,
              AttendanceStatus.present,
            );
            expect(
              restored.classes.single.auditEvents.single.reason,
              'Đối chiếu minh chứng',
            );
            final desktopRoot = await Directory.systemTemp.createTemp(
              'fap-windows-reopen-',
            );
            final desktop = AttendanceController(
              finalFirebase: true,
              teacherAuth: identity,
              firestore: db,
              documentsDirectory: desktopRoot,
            );
            try {
              await desktop.initialize();
              expect(
                desktop.workspace!.classes.single.recordFor('m1', 'S1')!.status,
                AttendanceStatus.present,
              );
              expect(desktop.sync, isNotNull);
              expect(desktop.sharedLinks, isA<FirestoreAttendanceLinks>());
            } finally {
              desktop.dispose();
              await desktopRoot.delete(recursive: true);
            }
            results.add({
              'round': round,
              'webSdkToNativeMs': timer.elapsedMilliseconds,
              'status': 'passed',
            });
          } finally {
            model.dispose();
            await notices.controller.close();
            await db.terminate();
            await auth.signOut();
            await app.delete();
            await root.delete(recursive: true);
          }
        }
        final output = Directory(
          '${const String.fromEnvironment('FAP_PROJECT_DIR')}/build/final-previews',
        );
        await output.create(recursive: true);
        await File('${output.path}/native-web-emulator-results.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(results));
        if (const bool.fromEnvironment('RUN_LIVE_AI')) {
          final service = FirebaseAttendanceReview(
            FakeConfig(),
            FakeTelemetry(),
            Directory('${output.path}/ai-live-evidence'),
          );
          for (final counts in [(20, 3, 2), (30, 0, 0), (10, 5, 15)]) {
            try {
              final review = await service.review(
                present: counts.$1,
                absent: counts.$2,
                unmarked: counts.$3,
              );
              expect(review.summary, isNotEmpty);
            } on AppProblem catch (error) {
              expect(error.message, contains('chốt'));
            }
          }
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
