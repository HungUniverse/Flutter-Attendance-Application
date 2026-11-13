import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:fap_attendance/data/roster_importer.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _buildXlsx(Map<String, List<List<String>>> sheets) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet();
  for (final entry in sheets.entries) {
    final sheet = excel[entry.key];
    for (final row in entry.value) {
      sheet.appendRow(row.map((v) => TextCellValue(v)).toList());
    }
  }
  if (defaultSheet != null && !sheets.containsKey(defaultSheet)) {
    excel.delete(defaultSheet);
  }
  return Uint8List.fromList(excel.encode()!);
}

Uint8List _buildOds(Map<String, List<List<String>>> sheets) {
  final buffer = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8"?>')
    ..write('<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">')
    ..write('<office:body><office:spreadsheet>');
  for (final entry in sheets.entries) {
    buffer.write('<table:table table:name="${entry.key}">');
    for (final row in entry.value) {
      buffer.write('<table:table-row>');
      for (final cell in row) {
        buffer.write('<table:table-cell><text:p>$cell</text:p></table:table-cell>');
      }
      buffer.write('</table:table-row>');
    }
    buffer.write('</table:table>');
  }
  buffer.write('</office:spreadsheet></office:body></office:document-content>');

  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'content.xml',
        utf8.encode(buffer.toString()).length,
        utf8.encode(buffer.toString()),
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  late RosterImporter importer;

  setUp(() {
    importer = RosterImporter();
  });

  group('RosterImporter.semesterFromFileName', () {
    test('extracts semester prefix case-insensitively across path separators', () {
      expect(RosterImporter.semesterFromFileName('FA26_roster.xlsx'), 'FA26');
      expect(RosterImporter.semesterFromFileName('C:\\docs\\sp26-classes.ods'), 'SP26');
      expect(RosterImporter.semesterFromFileName('/tmp/su25 roster.xlsx'), 'SU25');
      expect(RosterImporter.semesterFromFileName('FA26'), 'FA26');
      expect(RosterImporter.semesterFromFileName('invalid_roster.xlsx'), isNull);
    });
  });

  group('RosterImporter.importBytes XLSX', () {
    test('parses Vietnamese accented headers, deduplicates warnings, and generates meetings', () {
      final bytes = _buildXlsx({
        '11_PRM392_SE1801': [
          ['Mã Lớp', 'MSSV', 'Email', 'Họ Tên', 'Mã Thành Viên'],
          ['SE1801', 'SE180001', 'AnNV@fpt.edu.vn', 'Nguyễn Văn An', 'AnNV'],
          ['SE1801', 'SE180001', 'an2@fpt.edu.vn', 'Duplicate Roll', 'DupR'],
          ['SE1801', 'SE180002', 'annv@fpt.edu.vn', 'Duplicate Email', 'DupE'],
          ['SE1801', 'SE180003', 'bad-email', 'Invalid Email', 'BadE'],
          ['SE1801', '', 'missing@fpt.edu.vn', 'Missing Roll', 'MissR'],
          ['', '', '', '', ''], // footer / blank identity row ignored silently
          ['SE1801', 'SE180004', 'binhtt@fpt.edu.vn', 'Trần Thị Bình', 'BinhTT'],
        ],
        'InvalidSheetName': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1802', 'SE180010', 'c@fpt.edu.vn', 'Cuong'],
        ],
      });

      final result = importer.importBytes(
        bytes,
        fileName: 'FA26_classes.xlsx',
        semester: 'FA26',
        semesterStart: DateTime(2026, 9, 7),
        weeks: 2,
        meetingsPerWeek: 2,
      );

      expect(result.classes, hasLength(1));
      final cls = result.classes.single;
      expect(cls.id, 'FA26_PRM392_SE1801');
      expect(cls.courseCode, 'PRM392');
      expect(cls.classCode, 'SE1801');
      expect(cls.scheduleCode, '11');
      expect(cls.students.map((s) => s.rollNumber), ['SE180001', 'SE180004']);
      expect(cls.meetings, hasLength(4));
      expect(result.warnings.length, greaterThanOrEqualTo(5));
    });

    test('rejects mismatched class code between sheet name and Class column', () {
      final bytes = _buildXlsx({
        '11_PRM392_SE1801': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1899', 'SE180001', 'a@fpt.edu.vn', 'An'],
        ],
      });

      expect(
        () => importer.importBytes(
          bytes,
          fileName: 'FA26.xlsx',
          semester: 'FA26',
          semesterStart: DateTime(2026, 9, 7),
        ),
        throwsA(isA<RosterImportException>()),
      );
    });

    test('rejects sheet containing multiple class codes or missing required headers', () {
      final multiClass = _buildXlsx({
        '11_PRM392': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1801', 'SE1', 'a@fpt.edu.vn', 'A'],
          ['SE1802', 'SE2', 'b@fpt.edu.vn', 'B'],
        ],
      });
      expect(
        () => importer.importBytes(
          multiClass,
          fileName: 'a.xlsx',
          semester: 'FA26',
          semesterStart: DateTime(2026, 9, 7),
        ),
        throwsA(isA<RosterImportException>()),
      );

      final missingCol = _buildXlsx({
        '11_PRM392_SE1801': [
          ['Class', 'RollNumber', 'FullName'],
          ['SE1801', 'SE1', 'A'],
        ],
      });
      expect(
        () => importer.importBytes(
          missingCol,
          fileName: 'a.xlsx',
          semester: 'FA26',
          semesterStart: DateTime(2026, 9, 7),
        ),
        throwsA(isA<RosterImportException>()),
      );
    });
  });

  group('RosterImporter.importBytes ODS & error cases', () {
    test('parses valid ODS archive', () {
      final bytes = _buildOds({
        '22_SWD392_SE1802': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1802', 'SE180100', 'stud@fpt.edu.vn', 'Student ODS'],
        ],
      });

      final result = importer.importBytes(
        bytes,
        fileName: 'FA26.ods',
        semester: 'FA26',
        semesterStart: DateTime(2026, 9, 7),
      );
      expect(result.classes, hasLength(1));
      expect(result.classes.first.classCode, 'SE1802');
      expect(result.classes.first.students.first.fullName, 'Student ODS');
    });

    test('throws RosterImportException for unsupported extensions and corrupted bytes', () {
      expect(
        () => importer.importBytes(
          Uint8List(0),
          fileName: 'roster.csv',
          semester: 'FA26',
          semesterStart: DateTime(2026, 9, 7),
        ),
        throwsA(isA<RosterImportException>()),
      );
      expect(
        () => importer.importBytes(
          Uint8List.fromList([1, 2, 3]),
          fileName: 'roster.xlsx',
          semester: 'FA26',
          semesterStart: DateTime(2026, 9, 7),
        ),
        throwsA(isA<RosterImportException>()),
      );
      expect(
        () => importer.importBytes(
          Uint8List.fromList([1, 2, 3]),
          fileName: 'roster.ods',
          semester: 'FA26',
          semesterStart: DateTime(2026, 9, 7),
        ),
        throwsA(isA<RosterImportException>()),
      );
    });
  });
}
