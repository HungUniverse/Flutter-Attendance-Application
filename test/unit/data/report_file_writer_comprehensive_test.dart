import 'dart:io';

import 'package:fap_attendance/data/report_file_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('report_writer_comp_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes multi-chunk stream atomically and cleans up temp files', () async {
    final target = File(p.join(tempDir.path, 'report.csv'));
    final result = await writeReportAtomically(
      target,
      Stream.fromIterable([
        [65, 66, 67],
        [68, 69, 70],
      ]),
    );

    expect(result.path, target.path);
    expect(await target.readAsString(), 'ABCDEF');

    final files = await tempDir.list().toList();
    expect(files.where((e) => e.path.endsWith('.tmp')), isEmpty);
  });

  test('overwrites existing destination file atomically', () async {
    final target = File(p.join(tempDir.path, 'out.txt'));
    await target.writeAsString('OLD');

    await writeReportAtomically(target, Stream.value([78, 69, 87]));
    expect(await target.readAsString(), 'NEW');
  });

  test('cleans up temporary file and rethrows on stream error', () async {
    final target = File(p.join(tempDir.path, 'fail.txt'));
    await expectLater(
      writeReportAtomically(
        target,
        Stream<List<int>>.error(const FormatException('bad chunk')),
      ),
      throwsFormatException,
    );

    expect(await target.exists(), isFalse);
    final entries = await tempDir.list().toList();
    expect(entries, isEmpty);
  });
}
