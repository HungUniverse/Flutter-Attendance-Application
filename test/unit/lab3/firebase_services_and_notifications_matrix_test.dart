// ignore_for_file: subtype_of_sealed_class, depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fap_attendance/data/firebase_desktop_auth.dart';
import 'package:fap_attendance/data/firestore_report_metadata.dart';
import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/device_service.dart';
import 'package:fap_attendance/lab3/services/firebase_services.dart';
import 'package:fap_attendance/lab3/services/firestore_notifications.dart';
import 'package:fap_attendance/lab3/services/mobile_workspace_repository.dart';
import 'package:fap_attendance/lab3/services/report_destination.dart';
import 'package:fap_attendance/lab3/services/synced_workspace_repository.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

base class _FakeSharedPrefsAsyncPlatform
    extends SharedPreferencesAsyncPlatform {
  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {}

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async =>
      null;

  @override
  Future<double?> getDouble(
    String key,
    SharedPreferencesOptions options,
  ) async => null;

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) async =>
      null;

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => const {};

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async => const {};

  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async => null;

  @override
  Future<List<String>?> getStringList(
    String key,
    SharedPreferencesOptions options,
  ) async => null;

  @override
  Future<void> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) async {}

  @override
  Future<void> setDouble(
    String key,
    double value,
    SharedPreferencesOptions options,
  ) async {}

  @override
  Future<void> setInt(
    String key,
    int value,
    SharedPreferencesOptions options,
  ) async {}

  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {}

  @override
  Future<void> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) async {}
}

class _MockAnalytics extends Mock implements FirebaseAnalytics {}

class _MockCrashlytics extends Mock implements FirebaseCrashlytics {}

class _MockRemoteConfig extends Mock implements FirebaseRemoteConfig {}

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockReference extends Mock implements Reference {}

class _MockMessaging extends Mock implements FirebaseMessaging {}

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUserCredential extends Mock implements UserCredential {}

class _FakeUploadTask extends Fake implements UploadTask {
  _FakeUploadTask(this._controller, this._completion);

  final StreamController<TaskSnapshot> _controller;
  final Future<TaskSnapshot> Function() _completion;

  @override
  Stream<TaskSnapshot> get snapshotEvents => _controller.stream;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(TaskSnapshot value) onValue, {
    Function? onError,
  }) => _completion().then(onValue, onError: onError);
}

class _FakeTaskSnapshot extends Fake implements TaskSnapshot {
  _FakeTaskSnapshot(this._bytes, this._total);

  final int _bytes;
  final int _total;

  @override
  int get bytesTransferred => _bytes;

  @override
  int get totalBytes => _total;
}

class _FakeAuthCredential extends Fake implements AuthCredential {}

class _MemoryPrefsAsync extends Fake implements SharedPreferencesAsync {
  final Map<String, String> strings = {};

  @override
  Future<String?> getString(String key) async => strings[key];

  @override
  Future<void> setString(String key, String value) async {
    strings[key] = value;
  }

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) async =>
      strings.keys.toSet();

  @override
  Future<void> remove(String key) async {
    strings.remove(key);
  }
}

class _FakeQueryDoc extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeQueryDoc(this._id, this._data);

  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;
}

class _FakeQuerySnap extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _FakeQuerySnap(this._docs);

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;
}

class _FakeQuery extends Fake implements Query<Map<String, dynamic>> {
  _FakeQuery(this._snap);

  final QuerySnapshot<Map<String, dynamic>> _snap;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async =>
      _snap;
}

class _FakeCollection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollection(this._records);

  final List<Map<String, dynamic>> _records;
  final Map<String, Object?> appliedWhere = {};

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    appliedWhere[field.toString()] = isEqualTo;
    final matched = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < _records.length; i++) {
      final row = _records[i];
      if (row[field.toString()] == isEqualTo) {
        matched.add(_FakeQueryDoc('doc-$i', row));
      }
    }
    return _FakeQuery(_FakeQuerySnap(matched));
  }
}

class _FakeNoticeFirestore extends Fake implements FirebaseFirestore {
  _FakeNoticeFirestore(this._records);

  final List<Map<String, dynamic>> _records;
  late _FakeCollection lastCollection;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    lastCollection = _FakeCollection(_records);
    return lastCollection;
  }
}

class _FakeRemote extends Fake implements WorkspaceRemote {
  final Map<String, Map<String, dynamic>> stored = {};

  @override
  Future<Map<String, dynamic>> readWorkspace({String? semester}) async {
    if (semester == null) return {'data': null};
    return {'data': stored[semester]};
  }

  @override
  Future<Map<String, dynamic>> writeWorkspace(
    Map<String, dynamic> pending,
  ) async {
    final ws = Map<String, dynamic>.from(pending['workspace'] as Map);
    final sem = ws['semester'] as String;
    final prevRev = (stored[sem]?['revision'] as int?) ?? 0;
    final next = {'revision': prevRev + 1, 'workspace': ws};
    stored[sem] = next;
    return {'data': next};
  }
}

class _FakeReportMetadata extends Fake implements FirestoreReportMetadata {
  int calls = 0;

  @override
  Future<void> flush(String uid) async {}

  @override
  Future<void> record(
    String uid,
    TeacherWorkspace workspace,
    CourseClass course,
    Meeting meeting,
    File file,
    String format,
  ) async {
    calls++;
  }
}

class _DummyRemoteAuth implements AuthService {
  @override
  TeacherIdentity? current = const TeacherIdentity('u-owner', 'o@fpt.edu.vn', 'Owner');

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<String> token() async => 'tok';
}

class _OwnedFakeRemote extends _FakeRemote {
  _OwnedFakeRemote(this._auth);

  final AuthService _auth;

  @override
  AuthService get auth => _auth;
}

TeacherWorkspace _buildWorkspace() {
  final start = DateTime(2026, 9, 7);
  return TeacherWorkspace(
    id: 'ws-lab3',
    semester: 'FA26',
    semesterStart: start,
    teacherEmail: 'teacher@fpt.edu.vn',
    classes: [
      CourseClass(
        id: 'c1',
        courseCode: 'SWD392',
        classCode: 'SE1801',
        scheduleCode: 'M1',
        students: const [
          Student(
            rollNumber: 'SE180001',
            fullName: 'Nguyen An',
            email: 'an@fpt.edu.vn',
          ),
        ],
        scheduleRule: ScheduleRule(scheduleCode: 'M1', semesterStart: start),
        meetings: [
          Meeting(
            id: 'm1',
            number: 1,
            startAt: start,
            endAt: start.add(const Duration(minutes: 135)),
            state: MeetingState.closed,
          ),
        ],
        attendance: {
          'm1': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: start.add(const Duration(minutes: 10)),
            ),
          },
        },
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    SharedPreferencesAsyncPlatform.instance ??=
        _FakeSharedPrefsAsyncPlatform();
    registerFallbackValue(StackTrace.empty);
    registerFallbackValue(_FakeAuthCredential());
    registerFallbackValue(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero,
      ),
    );
  });

  group('FirebaseTelemetry behavior & secret protection', () {
    late _MockAnalytics analytics;
    late _MockCrashlytics crashlytics;
    late FirebaseTelemetry telemetry;

    setUp(() {
      analytics = _MockAnalytics();
      crashlytics = _MockCrashlytics();
      when(() => analytics.setUserId(id: any(named: 'id')))
          .thenAnswer((_) async {});
      when(() => analytics.logEvent(
            name: any(named: 'name'),
            parameters: any(named: 'parameters'),
          )).thenAnswer((_) async {});
      when(() => crashlytics.setUserIdentifier(any()))
          .thenAnswer((_) async {});
      when(() => crashlytics.setCustomKey(any(), any()))
          .thenAnswer((_) async {});
      when(() => crashlytics.recordError(
            any(),
            any(),
            reason: any(named: 'reason'),
          )).thenAnswer((_) async {});
      telemetry = FirebaseTelemetry(analytics, crashlytics);
    });

    test('identify synchronizes user id on both Analytics and Crashlytics', () async {
      await telemetry.identify('teacher-uid-42');
      verify(() => analytics.setUserId(id: 'teacher-uid-42')).called(1);
      verify(() => crashlytics.setUserIdentifier('teacher-uid-42')).called(1);

      await telemetry.identify(null);
      verify(() => analytics.setUserId(id: null)).called(1);
      verify(() => crashlytics.setUserIdentifier('')).called(1);
    });

    test('event converts map parameters and forwards event name', () async {
      await telemetry.event('attendance_closed', {
        'classId': 'c1',
        'count': 25,
      });
      verify(
        () => analytics.logEvent(
          name: 'attendance_closed',
          parameters: {'classId': 'c1', 'count': 25},
        ),
      ).called(1);
    });

    test('error redacts raw exception objects while recording operation context', () async {
      await telemetry.error(
        Exception('secret token leak xyz'),
        StackTrace.current,
        'sync_push',
      );
      verify(() => crashlytics.setCustomKey('operation', 'sync_push')).called(1);
      final captured = verify(
        () => crashlytics.recordError(
          captureAny(),
          any(),
          reason: 'sync_push',
        ),
      ).captured;
      expect(captured.single.toString(), isNot(contains('secret token leak')));
    });

    test('crashForDemo throws AppProblem outside LAB3_DEMO_TOOLS build', () async {
      await expectLater(
        () => telemetry.crashForDemo(),
        throwsA(isA<AppProblem>()),
      );
    });
  });

  group('FirebaseFeatureConfig remote config & resilient fallback', () {
    late _MockRemoteConfig remoteConfig;
    late FirebaseFeatureConfig featureConfig;

    setUp(() {
      remoteConfig = _MockRemoteConfig();
      when(() => remoteConfig.setConfigSettings(any())).thenAnswer((_) async {});
      when(() => remoteConfig.setDefaults(any())).thenAnswer((_) async {});
      when(() => remoteConfig.getBool('enable_link_attendance'))
          .thenReturn(true);
      when(() => remoteConfig.getString('export_help_message'))
          .thenReturn('Custom export help');
      when(() => remoteConfig.getBool('enable_attendance_ai'))
          .thenReturn(false);
      when(() => remoteConfig.getString('attendance_ai_model'))
          .thenReturn('gemini-2.5-flash');
      when(() => remoteConfig.getString('attendance_ai_prompt'))
          .thenReturn('Inspect rows carefully');
      featureConfig = FirebaseFeatureConfig(remoteConfig);
    });

    test('initialize configures defaults and reads typed FeatureSettings', () async {
      when(() => remoteConfig.fetchAndActivate()).thenAnswer((_) async => true);

      await featureConfig.initialize();

      verify(() => remoteConfig.setDefaults(any())).called(1);
      expect(featureConfig.current.enableLink, isTrue);
      expect(featureConfig.current.exportHelp, 'Custom export help');
      expect(featureConfig.current.enableAi, isFalse);
      expect(featureConfig.current.aiModel, 'gemini-2.5-flash');
    });

    test('refresh still reads cached config in finally even when fetchAndActivate throws', () async {
      when(() => remoteConfig.fetchAndActivate())
          .thenThrow(Exception('offline'));

      await expectLater(() => featureConfig.refresh(), throwsException);
      expect(featureConfig.current.exportHelp, 'Custom export help');
    });
  });

  group('FirebaseReportUpload storage streaming & error mapping', () {
    late Directory tempDir;
    late _MockStorage storage;
    late _MockReference ref;
    late FirebaseReportUpload uploadService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('upload_test_');
      storage = _MockStorage();
      ref = _MockReference();
      uploadService = FirebaseReportUpload(storage);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('rejects upload when local filename does not match destination', () async {
      final file = File('${tempDir.path}/wrong_name.csv')
        ..writeAsStringSync('a,b\n');
      final dest = ReportDestination(
        ownerUid: 'u1',
        semester: 'FA26',
        courseCode: 'SWD392',
        classCode: 'SE1801',
        meetingNumber: 1,
        meetingDate: DateTime(2026, 9, 7),
        fileName: 'SWD392_SE1801_2026-09-07_slot1.csv',
      );

      await expectLater(
        () => uploadService.upload(file, dest, (_) {}),
        throwsA(isA<AppProblem>()),
      );
      verifyNever(() => storage.ref(any()));
    });

    test('streams upload progress and resolves download URL', () async {
      const fileName = 'SWD392_SE1801_2026-09-07_slot1.csv';
      final dest = ReportDestination(
        ownerUid: 'u1',
        semester: 'FA26',
        courseCode: 'SWD392',
        classCode: 'SE1801',
        meetingNumber: 1,
        meetingDate: DateTime(2026, 9, 7),
        fileName: fileName,
      );
      final file = File('${tempDir.path}/$fileName')
        ..writeAsStringSync('Roll,Status\nSE1,P\n');
      final events = StreamController<TaskSnapshot>();
      final completer = Completer<TaskSnapshot>();

      when(() => storage.ref(dest.objectPath)).thenReturn(ref);
      when(() => ref.putFile(file, any()))
          .thenAnswer((_) => _FakeUploadTask(events, () => completer.future));

      final reported = <double>[];
      final uploadFuture = uploadService.upload(file, dest, reported.add);

      events.add(_FakeTaskSnapshot(0, 0));
      await Future<void>.delayed(Duration.zero);
      events.add(_FakeTaskSnapshot(50, 100));
      await Future<void>.delayed(Duration.zero);
      events.add(_FakeTaskSnapshot(100, 100));
      await Future<void>.delayed(Duration.zero);
      completer.complete(_FakeTaskSnapshot(100, 100));
      await events.close();

      await uploadFuture;
      expect(reported, containsAllInOrder([0.0, 0.5, 1.0]));
    });

    test('maps unauthorized FirebaseException to actionable AppProblem', () async {
      const fileName = 'SWD392_SE1801_2026-09-07_slot1.json';
      final dest = ReportDestination(
        ownerUid: 'u1',
        semester: 'FA26',
        courseCode: 'SWD392',
        classCode: 'SE1801',
        meetingNumber: 1,
        meetingDate: DateTime(2026, 9, 7),
        fileName: fileName,
      );
      final file = File('${tempDir.path}/$fileName')..writeAsStringSync('{}');
      final events = StreamController<TaskSnapshot>();
      addTearDown(events.close);

      when(() => storage.ref(dest.objectPath)).thenReturn(ref);
      when(() => ref.putFile(file, any())).thenAnswer(
        (_) => _FakeUploadTask(
          events,
          () => Future.error(
            FirebaseException(
              plugin: 'firebase_storage',
              code: 'unauthorized',
            ),
          ),
        ),
      );

      await expectLater(
        () => uploadService.upload(file, dest, (_) {}),
        throwsA(isA<AppProblem>()),
      );
    });
  });

  group('FirestoreNotifications & FirebaseNotificationService', () {
    test('FirestoreNotifications filters recipientUid and sorts descending by at', () async {
      final now = DateTime(2026, 11, 10, 12, 0);
      final fs = _FakeNoticeFirestore([
        {
          'recipientUid': 't1',
          'title': 'Older',
          'body': 'Old msg',
          'at': Timestamp.fromDate(now.subtract(const Duration(hours: 3))),
          'classId': 'remote-c1',
          'meetingId': 'm1',
        },
        {
          'recipientUid': 't2',
          'title': 'Someone else',
          'body': 'Ignore',
          'at': Timestamp.fromDate(now),
        },
        {
          'recipientUid': 't1',
          'title': 'Newest',
          'body': 'New msg',
          'at': Timestamp.fromDate(now),
        },
      ]);

      final feed = FirestoreNotifications(
        _MockMessaging(),
        fs,
        localClassId: (remoteId) => remoteId == 'remote-c1' ? 'c1' : null,
      );
      final items = await feed.history('t1');

      expect(fs.lastCollection.appliedWhere['recipientUid'], 't1');
      expect(items.length, 2);
      expect(items.first.title, 'Newest');
      expect(items.first.classId, isNull);
      expect(items.last.title, 'Older');
      expect(items.last.classId, 'c1');
      expect(items.last.meetingId, 'm1');
    });

    test('FirebaseNotificationService reads history skipping corrupt entries and sorts newest first', () async {
      final messaging = _MockMessaging();
      when(() => messaging.requestPermission()).thenAnswer(
        (_) async => const NotificationSettings(
          authorizationStatus: AuthorizationStatus.authorized,
          alert: AppleNotificationSetting.enabled,
          announcement: AppleNotificationSetting.disabled,
          badge: AppleNotificationSetting.enabled,
          carPlay: AppleNotificationSetting.disabled,
          criticalAlert: AppleNotificationSetting.disabled,
          lockScreen: AppleNotificationSetting.enabled,
          notificationCenter: AppleNotificationSetting.enabled,
          showPreviews: AppleShowPreviewSetting.always,
          sound: AppleNotificationSetting.enabled,
          timeSensitive: AppleNotificationSetting.disabled,
          providesAppNotificationSettings: AppleNotificationSetting.disabled,
        ),
      );
      when(() => messaging.getToken()).thenAnswer((_) async => 'fcm-tok-99');
      when(() => messaging.deleteToken()).thenAnswer((_) async {});

      final prefs = _MemoryPrefsAsync();
      prefs.strings['fap_notice_u1_n1'] = jsonEncode(
        AppNotice(
          id: 'n1',
          title: 'First',
          body: 'Body 1',
          at: DateTime(2026, 9, 7, 8, 0),
        ).toJson(),
      );
      prefs.strings['fap_notice_u1_bad'] = '{invalid-json';
      prefs.strings['fap_notice_u1_type'] = jsonEncode({'title': 123});
      prefs.strings['fap_notice_u2_other'] = jsonEncode(
        AppNotice(
          id: 'n2',
          title: 'Other user',
          body: 'Nope',
          at: DateTime(2026, 9, 8, 8, 0),
        ).toJson(),
      );
      prefs.strings['fap_notice_u1_n3'] = jsonEncode(
        AppNotice(
          id: 'n3',
          title: 'Latest',
          body: 'Body 3',
          at: DateTime(2026, 9, 9, 8, 0),
          classId: 'c1',
          meetingId: 'm1',
        ).toJson(),
      );

      final service = FirebaseNotificationService(messaging, preferences: prefs);

      expect(await service.requestPermission(), 'authorized');
      expect(await service.token(), 'fcm-tok-99');

      final history = await service.history('u1');
      expect(history.map((e) => e.id).toList(), ['n3', 'n1']);
      expect(history.first.classId, 'c1');

      await service.stop();
      expect(prefs.strings.containsKey('fap_notice_owner'), isFalse);
      verify(() => messaging.deleteToken()).called(1);
    });
  });

  group('FirebaseDesktopAuth loopback callback server verification', () {
    setUpAll(() {
      HttpOverrides.global = null;
    });

    test('validates origin, content-type, size, state, and completes Google sign-in', () async {
      final firebaseAuth = _MockFirebaseAuth();
      when(() => firebaseAuth.signInWithCredential(any()))
          .thenAnswer((_) async => _MockUserCredential());

      final auth = FirebaseDesktopAuth(
        firebaseAuth,
        hostingUrl: 'https://fap-attendance.web.app',
        openBrowser: (uri) async {
          final port = int.parse(uri.queryParameters['port']!);
          final state = uri.queryParameters['state']!;

          Future<int> sendPost({
            String? origin,
            ContentType? contentType,
            required String body,
          }) async {
            final single = HttpClient();
            try {
              final req = await single.post('127.0.0.1', port, '/callback');
              if (origin != null) req.headers.set('origin', origin);
              if (contentType != null) req.headers.contentType = contentType;
              final encoded = utf8.encode(body);
              req.contentLength = encoded.length;
              if (encoded.isNotEmpty) req.add(encoded);
              final res = await req.close();
              await res.drain<void>();
              return res.statusCode;
            } finally {
              single.close(force: true);
            }
          }

          expect(
            await sendPost(
              origin: 'https://evil.example',
              contentType: ContentType('application', 'x-www-form-urlencoded'),
              body: '',
            ),
            HttpStatus.forbidden,
          );

          expect(
            await sendPost(
              origin: 'https://fap-attendance.web.app',
              contentType: ContentType.json,
              body: jsonEncode({'state': state, 'idToken': 'abc'}),
            ),
            HttpStatus.badRequest,
          );

          await expectLater(
            () => sendPost(
              origin: 'https://fap-attendance.web.app',
              contentType: ContentType('application', 'x-www-form-urlencoded'),
              body: 'state=$state&idToken=${'a' * 33000}',
            ),
            anyOf(
              completion(HttpStatus.badRequest),
              throwsA(anyOf(isA<HttpException>(), isA<SocketException>())),
            ),
          );

          expect(
            await sendPost(
              origin: 'https://fap-attendance.web.app',
              contentType: ContentType('application', 'x-www-form-urlencoded'),
              body: 'state=wrong-state&idToken=abc',
            ),
            HttpStatus.badRequest,
          );

          expect(
            await sendPost(
              origin: 'https://fap-attendance.web.app',
              contentType: ContentType('application', 'x-www-form-urlencoded'),
              body: 'state=$state&idToken=google-id-token-xyz',
            ),
            HttpStatus.ok,
          );
        },
      );

      await auth.signIn();
      verify(() => firebaseAuth.signInWithCredential(any())).called(1);
    });
  });

  group('FileMobileWorkspaceRepository, SyncedMobileWorkspaceRepository & AndroidDeviceService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mobile_repo_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('enforces strict ID sanitization against path traversal', () async {
      final repo = FileMobileWorkspaceRepository(tempDir);
      final ws = _buildWorkspace();

      await expectLater(
        () => repo.save('../evil', ws),
        throwsA(isA<AppProblem>()),
      );
      await expectLater(
        () => repo.load('uid/slash', semester: 'FA26'),
        throwsA(isA<AppProblem>()),
      );
      await expectLater(
        () => repo.saveLink('u 1', null),
        throwsA(isA<AppProblem>()),
      );
    });

    test('exports csv, json, pdf reports, saves sources, & persists link', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final repo = FileMobileWorkspaceRepository(tempDir);
      final ws = _buildWorkspace();
      final c = ws.classes.first;
      final m = c.meetings.first;

      await repo.save('u1', ws);
      expect((await repo.load('u1', semester: 'FA26'))?.semester, 'FA26');

      final csvFile = await repo.export('u1', ws, c, m, 'csv');
      final jsonFile = await repo.export('u1', ws, c, m, 'json');
      final pdfFile = await repo.export('u1', ws, c, m, 'pdf');

      expect(await csvFile.exists(), isTrue);
      expect(await jsonFile.exists(), isTrue);
      expect(await pdfFile.exists(), isTrue);
      expect((await pdfFile.readAsBytes()).sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);

      await repo.saveSource('u1', 'FA26', 'FA26.xlsx', Uint8List.fromList([10, 20]));
      final link = LinkSession(
        id: 'tok123',
        url: 'https://fap.app/check/tok123',
        classId: 'c1',
        meetingId: 'm1',
        expiresAt: DateTime(2026, 9, 7, 9, 0),
        receiving: true,
        code: '654321',
      );
      await repo.saveLink('u1', link);
      expect((await repo.loadLink('u1'))?.id, 'tok123');
      // OTP secret code is intentionally never persisted to disk JSON.
      expect((await repo.loadLink('u1'))?.code, isNull);
      await repo.saveLink('u1', null);
      expect(await repo.loadLink('u1'), isNull);
    });

    test('SyncedMobileWorkspaceRepository checks owner identity and triggers metadata sink on export', () async {
      final remote = _OwnedFakeRemote(_DummyRemoteAuth());
      final sync = SharedWorkspaceSync(remote, tempDir);
      addTearDown(sync.dispose);
      final metadata = _FakeReportMetadata();
      final syncedRepo = SyncedMobileWorkspaceRepository(
        tempDir,
        sync,
        reports: metadata,
      );

      final ws = _buildWorkspace();
      await expectLater(
        () => syncedRepo.load('other-user'),
        throwsA(isA<StateError>()),
      );

      await syncedRepo.save('u-owner', ws);
      final loaded = await syncedRepo.load('u-owner', semester: 'FA26');
      expect(loaded?.semester, 'FA26');

      final exported = await syncedRepo.export(
        'u-owner',
        ws,
        ws.classes.first,
        ws.classes.first.meetings.first,
        'csv',
      );
      expect(await exported.exists(), isTrue);
      expect(metadata.calls, 1);
    });

    test('AndroidDeviceService copies text through Flutter platform clipboard', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final device = AndroidDeviceService();
      await device.copy('https://fap.app/join');
      expect(copiedText, 'https://fap.app/join');
    });
  });
}
