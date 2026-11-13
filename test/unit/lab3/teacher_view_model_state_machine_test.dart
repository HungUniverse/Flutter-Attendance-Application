import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/ai_attendance_review.dart';
import 'package:fap_attendance/lab3/services/attendance_draft_store.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lab3/fakes.dart';

class _FailLoadRepo extends FailingRepository {
  _FailLoadRepo(super.root);

  @override
  Future<TeacherWorkspace?> load(String uid, {String? semester}) async {
    throw const FileSystemException('corrupt storage');
  }
}

class _ScriptedAiService implements AttendanceReviewService {
  bool shouldFail = false;
  String? lastAccepted;

  @override
  Future<AiAttendanceReview> review({
    required int present,
    required int absent,
    required int unmarked,
  }) async {
    if (shouldFail) throw const AppProblem('AI service temporary error');
    return AiAttendanceReview(
      'P=$present A=$absent U=$unmarked',
      [if (unmarked > 0) 'Con $unmarked sinh vien chua diem danh'],
    );
  }

  @override
  Future<void> accept(String edited) async {
    if (edited.trim().isEmpty) throw const AppProblem('Empty review text');
    lastAccepted = edited.trim();
  }
}

Uint8List _xlsxBytes({
  String sheetName = '12_PRN221_SE1810',
  String classCode = 'SE1810',
}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  final sheet = excel[sheetName];
  sheet.appendRow([
    TextCellValue('Class'),
    TextCellValue('RollNumber'),
    TextCellValue('Email'),
    TextCellValue('FullName'),
  ]);
  sheet.appendRow([
    TextCellValue(classCode),
    TextCellValue('SE180101'),
    TextCellValue('student1@fpt.edu.vn'),
    TextCellValue('Nguyen Minh Anh'),
  ]);
  if (defaultSheet != null && defaultSheet != sheetName) {
    excel.delete(defaultSheet);
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  late Directory tempDir;
  late Harness harness;
  late _ScriptedAiService aiService;
  late AttendanceDraftStore draftStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vm_sm_test_');
    aiService = _ScriptedAiService();
    draftStore = AttendanceDraftStore(tempDir);
    harness = Harness(tempDir, ai: aiService);
    harness.vm.dispose();
  });

  tearDown(() async {
    await harness.auth.controller.close();
    await harness.notices.controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  TeacherViewModel buildVm({
    bool signedIn = true,
    MobileWorkspaceRepository? repoOverride,
  }) {
    harness.auth.current = signedIn
        ? const TeacherIdentity('teacher1', 'teacher@example.com', 'GV')
        : null;
    return TeacherViewModel(
      auth: harness.auth,
      repository: repoOverride ?? harness.repo,
      telemetry: harness.telemetry,
      config: harness.config,
      notifications: harness.notices,
      uploads: harness.upload,
      device: harness.device,
      links: harness.links,
      ai: aiService,
      drafts: draftStore,
      clock: () => harness.clock,
    );
  }

  group('TeacherViewModel auth rebinding, error recovery & drafts', () {
    test('rebinds cleanly when auth identity changes and clears previous state', () async {
      final ws1 = fixtureWorkspace(semester: 'FA26');
      final ws2 = TeacherWorkspace(
        id: 'ws-teacher2',
        semester: 'SP27',
        semesterStart: harness.clock,
        teacherEmail: 'teacher2@fpt.edu.vn',
        classes: const [],
      );
      await harness.repo.save('teacher1', ws1);
      await harness.repo.save('teacher2', ws2);

      final vm = buildVm();
      addTearDown(vm.dispose);
      await vm.initialize(timers: false);

      expect(vm.user?.uid, 'teacher1');
      expect(vm.workspace?.semester, 'FA26');

      harness.auth.current = const TeacherIdentity(
        'teacher2',
        'teacher2@fpt.edu.vn',
        'Teacher Two',
      );
      harness.auth.controller.add(harness.auth.current);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(vm.user?.uid, 'teacher2');
      expect(vm.workspace?.semester, 'SP27');
      expect(vm.link, isNull);
      expect(vm.manualDrafts, isEmpty);
    });

    test('sets workspaceLoadFailed when repository throws on load', () async {
      final vm = buildVm(repoOverride: _FailLoadRepo(tempDir));
      addTearDown(vm.dispose);
      await vm.initialize(timers: false);

      expect(vm.workspaceLoadFailed, isTrue);
      expect(vm.workspace, isNull);
      expect(vm.error, isNotNull);
    });

    test('persists local drafts without uploading, restores on reload, and discardDraft reverts to saved workspace', () async {
      final activeToday = fixtureWorkspace();
      await harness.repo.save('teacher1', activeToday);

      final vm1 = buildVm();
      addTearDown(vm1.dispose);
      await vm1.initialize(timers: false);

      // Start m1 on c1 so we can take manual draft marks.
      expect(await vm1.begin('c1', 'm1'), isTrue);
      expect(vm1.meeting('c1', 'm1').state, MeetingState.active);

      final marked = await vm1.mark(
        'c1',
        'm1',
        's1',
        AttendanceStatus.present,
        reason: 'Checked in person',
      );
      expect(marked, isTrue);
      expect(vm1.draftCount, 1);
      expect(
        vm1.course('c1').recordFor('m1', 's1')?.status,
        AttendanceStatus.present,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Reload fresh ViewModel -> draft re-applied from AttendanceDraftStore
      final vm2 = buildVm();
      addTearDown(vm2.dispose);
      await vm2.initialize(timers: false);
      expect(vm2.draftCount, 1);
      expect(
        vm2.course('c1').recordFor('m1', 's1')?.status,
        AttendanceStatus.present,
      );

      final key = vm2.manualDrafts.single.key;
      expect(await vm2.discardDraft(key), isTrue);
      expect(vm2.draftCount, 0);
      expect(vm2.course('c1').recordFor('m1', 's1'), isNull);
      expect(vm2.message, contains('Firebase'));
    });

    test('rejects mark with unmarked status or on non-today upcoming meeting', () async {
      await harness.repo.save('teacher1', fixtureWorkspace());
      final vm = buildVm();
      addTearDown(vm.dispose);
      await vm.initialize(timers: false);

      // Meeting m2 is upcoming -> mark fails
      expect(
        await vm.mark('c1', 'm2', 's1', AttendanceStatus.present),
        isFalse,
      );
      expect(vm.error, isNotNull);

      await vm.begin('c1', 'm1');
      expect(
        await vm.mark('c1', 'm1', 's1', AttendanceStatus.unmarked),
        isFalse,
      );
      expect(vm.error, contains('không hợp lệ'));
    });
  });

  group('TeacherViewModel link lifecycle, close, edit, AI review & semester switch', () {
    test('creates link, enforces single active link, polls/closes meeting, and cleans up drafts', () async {
      await harness.repo.save('teacher1', fixtureWorkspace());
      final vm = buildVm();
      addTearDown(vm.dispose);
      await vm.initialize(timers: false);

      expect(await vm.begin('c1', 'm1'), isTrue);
      expect(await vm.mark('c1', 'm1', 's1', AttendanceStatus.present), isTrue);

      // Creating link succeeds and persists handle
      expect(await vm.createLink('c1', 'm1'), isTrue);
      expect(vm.link, isNotNull);
      expect(vm.link!.classId, 'c1');

      // Cannot open another meeting while another is active or link open
      expect(await vm.createLink('c1', 'm2'), isFalse);
      expect(vm.error, contains('buổi học khác'));

      // Blocking import and semester change while link is active
      expect(
        await vm.importRoster(
          bytes: _xlsxBytes(),
          filename: 'SP27_PRN221.xlsx',
          semester: 'SP27',
          start: harness.clock,
          weeks: 2,
          perWeek: 2,
        ),
        isFalse,
      );
      expect(vm.error, contains('dừng nhận link'));

      expect(await vm.selectSemester('SP27'), isFalse);
      expect(vm.error, contains('dừng nhận link'));

      // Close active meeting -> stops link, clears link, closes m1, clears draft
      expect(await vm.close('c1', 'm1'), isTrue);
      expect(vm.link, isNull);
      expect(vm.meeting('c1', 'm1').state, MeetingState.closed);
      expect(vm.draftCount, 0);
      expect(
        vm.course('c1').recordFor('m1', 's1')?.status,
        AttendanceStatus.present,
      );
      expect(
        vm.course('c1').recordFor('m1', 's2')?.status,
        AttendanceStatus.absent,
      );

      // Edit closed meeting writes audit event
      expect(
        await vm.edit(
          'c1',
          'm1',
          's2',
          AttendanceStatus.present,
          'Late arrival approved',
        ),
        isTrue,
      );
      expect(
        vm.course('c1').recordFor('m1', 's2')?.status,
        AttendanceStatus.present,
      );
      expect(vm.course('c1').auditEvents.single.reason, 'Late arrival approved');
    });

    test('requestAiReview and acceptAiReview honor feature flags and handle errors', () async {
      await harness.repo.save('teacher1', fixtureWorkspace());
      final vm = buildVm();
      addTearDown(vm.dispose);
      await vm.initialize(timers: false);

      await vm.begin('c1', 'm1');
      await vm.mark('c1', 'm1', 's1', AttendanceStatus.present);

      // Accept without review fails
      expect(await vm.acceptAiReview('looks good'), isFalse);
      expect(vm.error, contains('gợi ý AI'));

      expect(await vm.requestAiReview('c1', 'm1'), isTrue);
      expect(vm.aiReview, isNotNull);
      expect(vm.aiReview!.summary, contains('P=1'));

      expect(await vm.acceptAiReview('  Verified count  '), isTrue);
      expect(aiService.lastAccepted, 'Verified count');
      expect(vm.aiReview!.summary, 'Verified count');

      // Disable AI via config
      harness.config.current = const FeatureSettings(
        enableAi: false,
        enableLink: false,
      );
      expect(await vm.requestAiReview('c1', 'm1'), isFalse);
      expect(vm.error, contains('AI đang tắt'));
      expect(await vm.createLink('c1', 'm1'), isFalse);
      expect(vm.error, contains('Tạo link đang tạm tắt'));
    });

    test('imports XLSX into new semester and switches between FA26 and SP27', () async {
      await harness.repo.save('teacher1', fixtureWorkspace(semester: 'FA26'));
      final vm = buildVm();
      addTearDown(vm.dispose);
      await vm.initialize(timers: false);

      expect(vm.workspace!.semester, 'FA26');

      final imported = await vm.importRoster(
        bytes: _xlsxBytes(),
        filename: 'SP27_PRN221.xlsx',
        semester: 'SP27',
        start: harness.clock,
        weeks: 2,
        perWeek: 2,
      );
      expect(imported, isTrue);
      expect(vm.workspace!.semester, 'SP27');
      expect(vm.workspace!.classes.single.courseCode, 'PRN221');

      expect(await vm.selectSemester('FA26'), isTrue);
      expect(vm.workspace!.semester, 'FA26');
      expect(await vm.selectSemester('UNKNOWN'), isFalse);
      expect(vm.error, contains('Không tìm thấy'));
    });
  });
}
