import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:fap_attendance/lab3/viewmodels/teacher_view_model.dart';

import 'fakes.dart';

void main() {
  late Harness h;
  setUp(() async {
    h = Harness(await Directory.systemTemp.createTemp('fap-lab3-test-'));
    await h.initialize();
  });
  tearDown(() async {
    await h.dispose();
  });
  test(
    'legacy workspace metadata does not prevent restoring attendance',
    () async {
      await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present);
      final json = h.vm.workspace!.toJson()..['syncState'] = 'conflict';
      final restored = TeacherWorkspace.fromJson(json);
      expect(restored.classes.first.students.length, 3);
      expect(
        restored.classes.first.recordFor('m1', 'S1')!.status,
        AttendanceStatus.present,
      );
      expect(restored.toJson().containsKey('syncState'), false);
    },
  );
  test('manual is local-first; switching mode and duplicate link never overwrite teacher choice', () async {
    expect(await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.absent), true);
    h.vm.selectMode(AttendanceMode.manual);
    h.vm.selectMode(AttendanceMode.link);
    expect(await h.vm.createLink('c1', 'm1'), true);
    h.links.submissions = [
      LinkSubmission('one@example.com', fixtureNow),
      LinkSubmission('two@example.com', fixtureNow),
    ];
    expect(await h.vm.refresh(), true);
    expect(await h.vm.refresh(), true);
    final counts = h.vm.counts('c1', 'm1');
    expect(counts[AttendanceStatus.absent], 1);
    expect(counts[AttendanceStatus.present], 1);
    expect(counts[AttendanceStatus.unmarked], 1);
    expect(
      h.vm.course('c1').recordFor('m1', 'S1')!.source,
      AttendanceSource.manual,
    );
    expect(
      (await h.repo.load('teacher1'))!.classes.first
          .recordFor('m1', 'S1')!
          .status,
      AttendanceStatus.absent,
    );
  });
  test('close freezes link, imports final submissions and fills only missing Absent', () async {
    await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present);
    await h.vm.createLink('c1', 'm1');
    h.links.submissions = [LinkSubmission('two@example.com', fixtureNow)];
    expect(await h.vm.close('c1', 'm1'), true);
    expect(h.links.receiving, false);
    expect(h.vm.meeting('c1', 'm1').state, MeetingState.closed);
    expect(h.vm.counts('c1', 'm1')[AttendanceStatus.present], 2);
    expect(h.vm.counts('c1', 'm1')[AttendanceStatus.absent], 1);
    expect(await h.vm.mark('c1', 'm1', 'S3', AttendanceStatus.present), false);
  });
  test('offline close cannot discard unresolved link results', () async {
    await h.vm.createLink('c1', 'm1');
    h.links.fail = true;
    expect(await h.vm.close('c1', 'm1'), false);
    expect(h.vm.meeting('c1', 'm1').state, MeetingState.active);
    expect(h.vm.link, isNotNull);
    expect(h.vm.counts('c1', 'm1')[AttendanceStatus.unmarked], 3);
  });
  test(
    'edit requires a new nonblank reason and keeps audit before/after',
    () async {
      await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.absent);
      expect(
        await h.vm.edit('c1', 'm1', 'S1', AttendanceStatus.present, '  '),
        false,
      );
      expect(
        h.vm.course('c1').recordFor('m1', 'S1')!.status,
        AttendanceStatus.absent,
      );
      expect(
        await h.vm.edit(
          'c1',
          'm1',
          'S1',
          AttendanceStatus.present,
          'Kiểm tra lại danh sách',
        ),
        true,
      );
      final audit = h.vm.course('c1').auditEvents.single;
      expect(audit.oldValue, 'A');
      expect(audit.newValue, 'P');
      expect(audit.reason, 'Kiểm tra lại danh sách');
    },
  );
  test('failed local write never publishes a false success', () async {
    h.repo.failSave = true;
    expect(await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present), false);
    expect(h.vm.course('c1').recordFor('m1', 'S1'), isNull);
    expect(h.vm.message, isNull);
    expect(h.vm.error, isNotNull);
    expect(h.telemetry.errors, contains('attendance_mark'));
  });
  test('tracking failure never breaks attendance', () async {
    h.telemetry.fail = true;
    expect(await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present), true);
    expect(h.vm.counts('c1', 'm1')[AttendanceStatus.present], 1);
  });
  test('Storage permission failure retains real local JSON; retry shares same file', () async {
    await h.vm.close('c1', 'm1');
    expect(await h.vm.export('c1', 'm1', 'json'), true);
    final file = h.vm.exportedFile!;
    expect(await file.exists(), true);
    final destination = h.vm.reportDestination!;
    expect(
      destination.objectPath,
      'reports/teacher1/FA26/PRM393/SE1901/2026-11-03_Slot-01/${file.uri.pathSegments.last}',
    );
    h.upload.fail = true;
    expect(await h.vm.upload(), false);
    expect(h.upload.lastDestination, same(destination));
    expect(await file.exists(), true);
    expect(h.vm.cloudUrl, isNull);
    h.upload.fail = false;
    expect(await h.vm.upload(), true);
    expect(h.upload.lastDestination, same(destination));
    expect(h.vm.uploadProgress, 1);
    expect(h.vm.cloudUrl, isNotNull);
    expect(await h.vm.shareExport(), true);
    expect(h.device.sharedFile!.path, file.path);
  });
  test(
    'upload stays tied to exported report after switching workspace',
    () async {
      await h.vm.close('c1', 'm1');
      expect(await h.vm.export('c1', 'm1', 'csv'), true);
      final destination = h.vm.reportDestination!;
      final file = h.vm.exportedFile!;
      h.vm.workspace = fixtureWorkspace(semester: 'SP27');
      expect(await h.vm.upload(), true);
      expect(h.upload.lastDestination, same(destination));
      expect(h.upload.lastDestination!.semester, 'FA26');
      expect(h.upload.lastDestination!.fileName, file.uri.pathSegments.last);
      expect(h.upload.lastDestination!.objectPath, endsWith('.csv'));
    },
  );
  test(
    'notification denial and Remote Config offline keep data/defaults',
    () async {
      h.notices.fail = true;
      expect(await h.vm.requestNotifications(), false);
      h.config.fail = true;
      expect(await h.vm.refreshConfig(), false);
      expect(h.vm.settings.enableLink, true);
      expect(h.vm.workspace!.classes.length, 1);
    },
  );
  test('config can disable new links while manual remains available', () async {
    h.config.current = const FeatureSettings(
      enableLink: false,
      exportHelp: 'New guidance',
    );
    expect(await h.vm.createLink('c1', 'm1'), false);
    expect(await h.vm.mark('c1', 'm1', 'S1', AttendanceStatus.present), true);
    expect(h.vm.settings.exportHelp, 'New guidance');
  });
  test('separate accounts cannot open each other local workspace', () async {
    expect(await h.repo.load('teacher2'), isNull);
    await h.vm.close('c1', 'm1');
    await h.vm.export('c1', 'm1', 'json');
    expect(h.vm.reportDestination, isNotNull);
    expect(await h.vm.signOut(), true);
    await Future<void>.delayed(Duration.zero);
    expect(h.vm.user, isNull);
    expect(h.vm.workspace, isNull);
    expect(h.vm.exportedFile, isNull);
    expect(h.vm.reportDestination, isNull);
    expect(await h.vm.upload(), false);
  });
  test('past-day restoration imports accepted server timestamps before auto-finalization', () async {
    await h.vm.createLink('c1', 'm1');
    h.links.submissions = [LinkSubmission('one@example.com', fixtureNow)];
    h.clock = fixtureNow.add(const Duration(days: 1));
    expect(await h.vm.refresh(), true);
    expect(h.vm.meeting('c1', 'm1').state, MeetingState.closed);
    expect(h.vm.counts('c1', 'm1')[AttendanceStatus.present], 1);
    expect(h.vm.counts('c1', 'm1')[AttendanceStatus.absent], 2);
  });
  test(
    'invalid import reports a nonfatal without replacing existing workspace',
    () async {
      final file = File('test/fixtures/FA26_Markbook.ods');
      final bytes = await file.readAsBytes();
      expect(
        await h.vm.importRoster(
          bytes: bytes,
          filename: 'bad.txt',
          semester: 'FA26',
          start: fixtureNow,
          weeks: 10,
          perWeek: 2,
        ),
        false,
      );
      expect(h.telemetry.errors, contains('markbook_import'));
      expect(h.vm.course('c1').students.length, 3);
    },
  );
}
