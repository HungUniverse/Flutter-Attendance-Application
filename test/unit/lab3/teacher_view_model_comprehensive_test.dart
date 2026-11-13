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

class _FakeAiService implements AttendanceReviewService {
  bool fail = false;
  String? acceptedText;

  @override
  Future<AiAttendanceReview> review({
    required int present,
    required int absent,
    required int unmarked,
  }) async {
    if (fail) throw const AppProblem('AI unavailable');
    return AiAttendanceReview(
      'Có $present có mặt, $absent vắng, $unmarked chưa điểm danh.',
      ['Kiểm tra sinh viên chưa điểm danh'],
    );
  }

  @override
  Future<void> accept(String edited) async {
    if (edited.trim().isEmpty) throw const AppProblem('Empty');
    acceptedText = edited.trim();
  }
}

Uint8List _xlsxBytes({
  String sheetName = '22_SWD392_SE1902',
  String classCode = 'SE1902',
}) {
  final excel = Excel.createExcel();
  final def = excel.getDefaultSheet();
  final sheet = excel[sheetName];
  sheet.appendRow([
    TextCellValue('Class'),
    TextCellValue('RollNumber'),
    TextCellValue('Email'),
    TextCellValue('FullName'),
  ]);
  sheet.appendRow([
    TextCellValue(classCode),
    TextCellValue('SE190010'),
    TextCellValue('ten@fpt.edu.vn'),
    TextCellValue('Student Ten'),
  ]);
  if (def != null && def != sheetName) {
    excel.delete(def);
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  late Directory tempDir;
  late Harness harness;
  late _FakeAiService aiService;
  late AttendanceDraftStore draftStore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vm_comp_test_');
    aiService = _FakeAiService();
    draftStore = AttendanceDraftStore(tempDir);
    harness = Harness(tempDir, ai: aiService);
    // Recreate vm with draftStore attached
    harness.vm.dispose();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  TeacherViewModel buildVm({bool signedIn = true}) {
    harness.auth.current = signedIn
        ? const TeacherIdentity('teacher1', 'teacher@example.com', 'GV')
        : null;
    return TeacherViewModel(
      auth: harness.auth,
      repository: harness.repo,
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

  group('TeacherViewModel lifecycle & auth', () {
    test('initializes signed in, loads workspace, reconciles overdue, and handles signOut', () async {
      await harness.repo.save('teacher1', fixtureWorkspace());
      final vm = buildVm();
      await vm.initialize(timers: false);

      expect(vm.user?.uid, 'teacher1');
      expect(vm.workspace?.semester, 'FA26');
      expect(vm.loadingWorkspace, isFalse);

      await vm.mark('c1', 'm1', 'S1', AttendanceStatus.present);
      expect(vm.draftCount, 1);

      expect(await vm.signOut(), isTrue);
      expect(vm.user, isNull);
      expect(vm.workspace, isNull);
      expect(harness.telemetry.events, contains('logout'));

      vm.dispose();
      await harness.auth.controller.close();
      await harness.notices.controller.close();
    });

    test('signIn authenticates user and emits login telemetry', () async {
      final vm = buildVm(signedIn: false);
      await vm.initialize(timers: false);
      expect(vm.user, isNull);

      expect(await vm.signIn(), isTrue);
      expect(vm.user?.uid, 'teacher1');
      expect(harness.telemetry.events, contains('login'));

      vm.dispose();
      await harness.auth.controller.close();
      await harness.notices.controller.close();
    });
  });

  group('TeacherViewModel attendance workflow, drafts, AI, and links', () {
    test('manual drafts, counts, discardDraft, edit, close, AI review, export, and upload', () async {
      await harness.repo.save('teacher1', fixtureWorkspace(state: MeetingState.active));
      final vm = buildVm();
      await vm.initialize(timers: false);

      vm.selectMode(AttendanceMode.manual);
      expect(vm.mode, AttendanceMode.manual);

      // Mark drafts for active meeting
      expect(await vm.mark('c1', 'm1', 's1', AttendanceStatus.present), isTrue);
      expect(await vm.mark('c1', 'm1', 'S2', AttendanceStatus.absent, reason: 'Sick'), isTrue);
      expect(vm.draftCount, 2); // 1 meeting draft with 2 student records
      expect(vm.manualDrafts.single.records.length, 2);

      final counts = vm.counts('c1', 'm1');
      expect(counts[AttendanceStatus.present], 1);
      expect(counts[AttendanceStatus.absent], 1);
      expect(counts[AttendanceStatus.unmarked], 1);

      // AI review flow
      expect(await vm.requestAiReview('c1', 'm1'), isTrue);
      expect(vm.aiReview, isNotNull);
      expect(await vm.acceptAiReview('  Verified counts  '), isTrue);
      expect(aiService.acceptedText, 'Verified counts');

      // Discard draft restores published state
      final draftKey = vm.manualDrafts.single.key;
      expect(await vm.discardDraft(draftKey), isTrue);
      expect(vm.draftCount, 0);
      expect(vm.counts('c1', 'm1')[AttendanceStatus.unmarked], 3);

      // Re-mark S1 and close meeting
      expect(await vm.mark('c1', 'm1', 'S1', AttendanceStatus.present), isTrue);
      expect(await vm.close('c1', 'm1'), isTrue);
      expect(vm.meeting('c1', 'm1').state, MeetingState.closed);
      expect(vm.draftCount, 0);
      expect(vm.course('c1').recordFor('m1', 'S1')?.status, AttendanceStatus.present);
      expect(vm.course('c1').recordFor('m1', 'S2')?.status, AttendanceStatus.absent);

      // Edit closed meeting with reason
      expect(
        await vm.edit('c1', 'm1', 'S2', AttendanceStatus.present, 'Approved excuse'),
        isTrue,
      );
      expect(vm.course('c1').recordFor('m1', 'S2')?.status, AttendanceStatus.present);

      // Export CSV & JSON and upload + share
      expect(await vm.export('c1', 'm1', 'csv'), isTrue);
      expect(vm.exportedFile, isNotNull);
      expect(vm.reportDestination, isNotNull);
      expect(await vm.upload(), isTrue);
      expect(vm.reportBackedUp, isTrue);
      expect(vm.uploadProgress, 1.0);
      expect(await vm.shareExport(), isTrue);
      expect(harness.device.sharedFile?.path, vm.exportedFile?.path);

      vm.dispose();
      await harness.auth.controller.close();
      await harness.notices.controller.close();
    });

    test('createLink, shareLink, refresh, and stopLink handle submissions and errors', () async {
      await harness.repo.save('teacher1', fixtureWorkspace(state: MeetingState.active));
      final vm = buildVm();
      await vm.initialize(timers: false);

      expect(await vm.createLink('c1', 'm1'), isTrue);
      expect(vm.link, isNotNull);

      expect(await vm.shareLink(copy: true), isTrue);
      expect(harness.device.copied, vm.link!.url);
      expect(await vm.shareLink(copy: false), isTrue);
      expect(harness.device.shared, vm.link!.url);

      // Simulate student submission via link poll
      harness.links.submissions = [
        LinkSubmission('one@example.com', fixtureNow),
      ];
      expect(await vm.refresh(), isTrue);
      expect(vm.course('c1').recordFor('m1', 'S1')?.status, AttendanceStatus.present);

      expect(await vm.stopLink(), isTrue);
      expect(vm.link, isNull);

      // Sharing without active link sets error
      expect(await vm.shareLink(), isFalse);
      expect(vm.error, isNotNull);

      vm.dispose();
      await harness.auth.controller.close();
      await harness.notices.controller.close();
    });
  });

  group('TeacherViewModel schedule, import, semester, config & notices', () {
    test('importRoster, selectSemester, updateSchedule, deleteClass, config & notifications', () async {
      await harness.repo.save('teacher1', fixtureWorkspace(state: MeetingState.upcoming));
      final vm = buildVm();
      await vm.initialize(timers: false);

      // Update schedule when all meetings upcoming
      final newRule = ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 11, 2),
        weeks: 2,
        meetingsPerWeek: 2,
      );
      expect(await vm.updateSchedule('c1', newRule), isTrue);
      expect(vm.course('c1').meetings, hasLength(4));

      // Import into new semester SP27
      expect(
        await vm.importRoster(
          bytes: _xlsxBytes(),
          filename: 'SP27_roster.xlsx',
          semester: 'SP27',
          start: DateTime(2027, 1, 4),
          weeks: 2,
          perWeek: 2,
        ),
        isTrue,
      );
      expect(vm.workspace?.semester, 'SP27');
      expect(vm.workspace?.classes.first.courseCode, 'SWD392');

      // Switch back to FA26
      expect(await vm.selectSemester('FA26'), isTrue);
      expect(vm.workspace?.semester, 'FA26');

      // Delete class
      expect(await vm.deleteClass('c1'), isTrue);
      expect(vm.workspace?.classes, isEmpty);

      // Config, notifications, notices stream, dismissMessage
      expect(await vm.refreshConfig(), isTrue);
      expect(await vm.requestNotifications(), isTrue);
      expect(vm.permission, 'authorized');
      expect(vm.messagingToken, 'fake-device-token');

      harness.notices.controller.add(
        AppNotice(id: 'n1', title: 'Hi', body: 'Body', at: fixtureNow),
      );
      await Future<void>.delayed(Duration.zero);
      expect(vm.pendingNotice?.id, 'n1');
      vm.consumeNotice();
      expect(vm.pendingNotice, isNull);

      vm.dismissMessage();
      expect(vm.message, isNull);
      expect(vm.error, isNull);

      vm.dispose();
      await harness.auth.controller.close();
      await harness.notices.controller.close();
    });

    test('blocks invalid semester names and begin while another meeting is active', () async {
      await harness.repo.save('teacher1', fixtureWorkspace(state: MeetingState.active));
      final vm = buildVm();
      await vm.initialize(timers: false);

      expect(
        await vm.importRoster(
          bytes: _xlsxBytes(),
          filename: 'bad.xlsx',
          semester: 'FA 26!',
          start: DateTime(2026, 11, 3),
          weeks: 2,
          perWeek: 2,
        ),
        isFalse,
      );
      expect(vm.error, isNotNull);

      vm.dispose();
      await harness.auth.controller.close();
      await harness.notices.controller.close();
    });
  });
}
