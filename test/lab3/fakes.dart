import 'dart:async';
import 'dart:io';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/services/report_destination.dart';
import 'package:fap_attendance/lab3/services/mobile_workspace_repository.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';

final fixtureNow = DateTime(2026, 11, 3, 10);
TeacherWorkspace fixtureWorkspace({
  MeetingState state = MeetingState.active,
  String semester = 'FA26',
  String courseCode = 'PRM393',
}) => TeacherWorkspace(
  id: 'w1',
  semester: semester,
  semesterStart: DateTime(2026, 11, 3),
  classes: [
    CourseClass(
      id: 'c1',
      courseCode: courseCode,
      classCode: 'SE1901',
      scheduleCode: '22',
      students: const [
        Student(
          rollNumber: 'S1',
          email: 'one@example.com',
          fullName: 'Nguyễn Thị Minh Anh',
        ),
        Student(
          rollNumber: 'S2',
          email: 'two@example.com',
          fullName: 'Trần Nguyễn Hoàng Phương Thảo',
        ),
        Student(
          rollNumber: 'S3',
          email: 'three@example.com',
          fullName: 'Lê Quốc Bảo',
        ),
      ],
      scheduleRule: ScheduleRule(
        scheduleCode: '22',
        semesterStart: DateTime(2026, 11, 3),
      ),
      meetings: [
        Meeting(
          id: 'm1',
          number: 1,
          startAt: DateTime(2026, 11, 3, 9, 30),
          endAt: DateTime(2026, 11, 3, 11, 45),
          state: state,
        ),
      ],
    ),
  ],
);

class FakeAuth implements AuthService {
  FakeAuth({bool signedIn = true}) {
    if (signedIn) {
      current = const TeacherIdentity(
        'teacher1',
        'teacher@example.com',
        'Giảng viên',
      );
    }
  }
  @override
  TeacherIdentity? current;
  final controller = StreamController<TeacherIdentity?>.broadcast(sync: true);
  bool fail = false;
  @override
  Stream<TeacherIdentity?> get changes => controller.stream;
  @override
  Future<void> signIn() async {
    if (fail) {
      throw const AppProblem('Đã hủy đăng nhập.');
    }
    current = const TeacherIdentity(
      'teacher1',
      'teacher@example.com',
      'Giảng viên',
    );
    controller.add(current);
  }

  @override
  Future<void> signOut() async {
    current = null;
    controller.add(null);
  }

  @override
  Future<String> token() async => 'test-token';
}

class FakeTelemetry implements TelemetryService {
  bool fail = false;
  final events = <String>[];
  final errors = <String>[];
  @override
  Future<void> identify(String? uid) async {}
  @override
  Future<void> event(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {
    if (fail) throw StateError('tracking offline');
    events.add(name);
  }

  @override
  Future<void> error(Object e, StackTrace s, String operation) async {
    errors.add(operation);
  }

  @override
  Future<void> crashForDemo() async {}
}

class FakeConfig implements ConfigService {
  @override
  FeatureSettings current = const FeatureSettings();
  bool fail = false;
  @override
  Future<void> refresh() async {
    if (fail) throw const SocketException('offline');
  }
}

class FakeNotices implements NotificationService {
  final controller = StreamController<AppNotice>.broadcast();
  bool fail = false;
  bool failHistory = false;
  @override
  Stream<AppNotice> get opened => controller.stream;
  @override
  Future<void> start(String uid) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<String> requestPermission() async {
    if (fail) throw const AppProblem('Quyền thông báo bị từ chối.');
    return 'authorized';
  }

  @override
  Future<String?> token() async => 'fake-device-token';
  @override
  Future<List<AppNotice>> history(String uid) async {
    if (failHistory) {
      throw const FormatException('Invalid notification history');
    }
    return [];
  }
}

class FakeUpload implements UploadService {
  bool fail = false;
  ReportDestination? lastDestination;
  @override
  Future<String> upload(
    File file,
    ReportDestination destination,
    void Function(double) progress,
  ) async {
    lastDestination = destination;
    progress(.5);
    if (fail) throw const AppProblem('Không có quyền tải lên.');
    progress(1);
    return 'https://example.test/report';
  }
}

class FakeDevice implements DeviceService {
  String? copied;
  String? shared;
  File? sharedFile;
  @override
  Future<void> copy(String text) async {
    copied = text;
  }

  @override
  Future<void> shareText(String text) async {
    shared = text;
  }

  @override
  Future<void> shareFile(File file) async {
    sharedFile = file;
  }
}

class FakeLinks implements AttendanceLinkService {
  @override
  bool configured = true;
  bool fail = false;
  bool receiving = true;
  Completer<LinkUpdate>? pendingPoll;
  List<LinkSubmission> submissions = [];
  LinkSession get session => LinkSession(
    id: 'session1',
    classId: 'c1',
    meetingId: 'm1',
    url: 'https://attendance.example/join/test',
    expiresAt: fixtureNow.add(const Duration(hours: 12)),
    receiving: receiving,
  );
  @override
  Future<LinkSession> create(CourseClass c, Meeting m) async {
    if (fail) throw const SocketException('offline');
    receiving = true;
    return session;
  }

  @override
  Future<LinkUpdate> poll(LinkSession s) async {
    if (fail) throw const SocketException('offline');
    final pending = pendingPoll;
    if (pending != null) return pending.future;
    return LinkUpdate(session, submissions);
  }

  @override
  Future<void> stop(LinkSession s) async {
    if (fail) throw const SocketException('offline');
    receiving = false;
  }
}

class FailingRepository extends FileMobileWorkspaceRepository {
  FailingRepository(super.root);
  bool failSave = false;
  bool failClearLink = false;
  @override
  Future<void> save(String uid, TeacherWorkspace workspace) async {
    if (failSave) throw const FileSystemException('disk full');
    await super.save(uid, workspace);
  }

  @override
  Future<void> saveLink(String uid, LinkSession? session) async {
    if (session == null && failClearLink) {
      throw const FileSystemException('Cannot remove the link cache');
    }
    await super.saveLink(uid, session);
  }
}

class Harness {
  Harness(this.directory, {bool signedIn = true, this.inMemory = false})
    : auth = FakeAuth(signedIn: signedIn) {
    repo = inMemory
        ? MemoryRepository(directory)
        : FailingRepository(directory);
    vm = TeacherViewModel(
      auth: auth,
      repository: repo,
      telemetry: telemetry,
      config: config,
      notifications: notices,
      uploads: upload,
      device: device,
      links: links,
      clock: () => clock,
    );
  }
  final Directory directory;
  final FakeAuth auth;
  final bool inMemory;
  late final FailingRepository repo;
  late final TeacherViewModel vm;
  final telemetry = FakeTelemetry();
  final config = FakeConfig();
  final notices = FakeNotices();
  final upload = FakeUpload();
  final device = FakeDevice();
  final links = FakeLinks();
  DateTime clock = fixtureNow;
  Future<void> initialize({bool seed = true}) async {
    if (seed) await repo.save('teacher1', fixtureWorkspace());
    await vm.initialize(timers: false);
  }

  Future<void> dispose() async {
    vm.dispose();
    await auth.controller.close();
    await notices.controller.close();
    if (!inMemory) await directory.delete(recursive: true);
  }
}

class MemoryRepository extends FailingRepository {
  MemoryRepository(super.root);
  final values = <String, TeacherWorkspace>{};
  final sessions = <String, LinkSession?>{};
  @override
  Future<TeacherWorkspace?> load(String uid, {String? semester}) async =>
      values[uid];
  @override
  Future<void> save(String uid, TeacherWorkspace workspace) async {
    if (failSave) throw const FileSystemException('disk full');
    values[uid] = workspace;
  }

  @override
  Future<LinkSession?> loadLink(String uid) async => sessions[uid];
  @override
  Future<void> saveLink(String uid, LinkSession? session) async {
    sessions[uid] = session;
  }
}
