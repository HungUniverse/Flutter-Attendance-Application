import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_attendance/data/attendance_pdf_exporter.dart';
import 'package:fap_attendance/domain/attendance_service.dart';
import 'package:fap_attendance/domain/models.dart';

import '../lab3/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'normal export flow creates, backs up, and shares a corrected Vietnamese PDF',
    () async {
      final harness = Harness(
        await Directory.systemTemp.createTemp('fap-final-pdf-'),
      );
      await harness.initialize();
      addTearDown(harness.dispose);
      await harness.vm.close('c1', 'm1');
      await harness.vm.edit(
        'c1',
        'm1',
        'S1',
        AttendanceStatus.present,
        'Đã đối chiếu minh chứng có mặt.',
      );
      expect(await harness.vm.export('c1', 'm1', 'pdf'), true);
      final file = harness.vm.exportedFile!;
      expect(file.path, endsWith('.pdf'));
      expect(ascii.decode((await file.readAsBytes()).take(4).toList()), '%PDF');
      expect(await harness.vm.upload(), true);
      expect(harness.upload.lastDestination!.objectPath, endsWith('.pdf'));
      expect(harness.vm.reportBackedUp, isTrue);
      expect(await file.exists(), isTrue);
      expect(await harness.vm.shareExport(), true);
      final preview = Directory('build/final-previews');
      await preview.create(recursive: true);
      await file.copy('${preview.path}/attendance-corrected.pdf');
    },
  );

  test(
    'large roster spans pages and an active meeting cannot export',
    () async {
      final workspace = fixtureWorkspace();
      final original = workspace.classes.single;
      final font = ByteData.sublistView(
        await File('assets/fonts/Roboto.ttf').readAsBytes(),
      );
      final exporter = AttendancePdfExporter();
      await expectLater(
        exporter.encode(
          workspace,
          original,
          original.meetings.single,
          fontData: font,
        ),
        throwsStateError,
      );
      final course = AttendanceService().closeMeeting(
        original.copyWith(
          students: [
            for (var i = 0; i < 120; i++)
              Student(
                rollNumber: 'SE${i.toString().padLeft(6, '0')}',
                email: 'student$i@example.com',
                fullName: 'Nguyễn Thị Minh Anh $i',
              ),
          ],
        ),
        'm1',
        now: fixtureNow,
      );
      final bytes = await exporter.encode(
        workspace.copyWith(classes: [course]),
        course,
        course.meetings.single,
        fontData: font,
      );
      final directory = await Directory('build/final-previews')
          .create(recursive: true);
      await File('${directory.path}/attendance-120-students.pdf')
          .writeAsBytes(bytes);
      expect(bytes.length, greaterThan(10000));
    },
  );
}
