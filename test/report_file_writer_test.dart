import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/data/report_file_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'failed report write preserves the prior report and permits retry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fap-report-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final report = File(p.join(directory.path, 'report.csv'));
      await report.writeAsString('previous report');

      Stream<List<int>> interruptedWrite() async* {
        yield utf8.encode('partial replacement');
        throw const FileSystemException('Report source read was interrupted');
      }

      await expectLater(
        writeReportAtomically(report, interruptedWrite()),
        throwsA(isA<FileSystemException>()),
      );
      expect(await report.readAsString(), 'previous report');
      expect(
        await directory.list().map((entry) => p.basename(entry.path)).toList(),
        ['report.csv'],
      );

      await writeReportAtomically(
        report,
        Stream.value(utf8.encode('new report')),
      );
      expect(await report.readAsString(), 'new report');
    },
  );
}
