import 'dart:io';
import 'dart:typed_data';

import 'package:fap_attendance/data/roster_importer.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports the supplied FA26 ODS fixture and ignores mark columns', () {
    final file = File('test/fixtures/FA26_Markbook.ods');
    expect(file.existsSync(), isTrue, reason: 'Missing committed ODS fixture');
    final result = RosterImporter().importBytes(
      Uint8List.fromList(file.readAsBytesSync()),
      fileName: file.path,
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
    );
    expect(result.classes.length, 10, reason: result.warnings.join('\n'));
    expect(
      result.classes.every((course) => course.students.isNotEmpty),
      isTrue,
    );
    expect(
      result.classes.every((course) => course.meetings.length == 20),
      isTrue,
    );
    expect(
      result.classes.map((course) => course.scheduleCode).toSet(),
      contains('23'),
    );
  });

  test('imports an equivalent XLSX roster', () {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', '11_PRM393_SE1917');
    final sheet = workbook['11_PRM393_SE1917'];
    sheet.appendRow([
      TextCellValue('Class'),
      TextCellValue('RollNumber'),
      TextCellValue('Email'),
      TextCellValue('MemberCode'),
      TextCellValue('FullName'),
      TextCellValue('Grade column ignored'),
    ]);
    sheet.appendRow([
      TextCellValue('SE1917'),
      TextCellValue('SE000001'),
      TextCellValue('student@example.com'),
      TextCellValue('MEM001'),
      TextCellValue('Nguyễn Văn A'),
      DoubleCellValue(9.5),
    ]);
    final bytes = workbook.save();
    expect(bytes, isNotNull);
    final result = RosterImporter().importBytes(
      Uint8List.fromList(bytes!),
      fileName: 'roster.xlsx',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
    );
    expect(result.classes.single.students.single.fullName, 'Nguyễn Văn A');
  });
}
