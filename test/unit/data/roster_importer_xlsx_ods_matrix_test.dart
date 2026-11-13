import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:fap_attendance/data/roster_importer.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final importer = RosterImporter();
  final mondayStart = DateTime(2026, 9, 7);

  Uint8List buildXlsx(Map<String, List<List<String>>> sheets) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    for (final entry in sheets.entries) {
      final sheet = excel[entry.key];
      for (final row in entry.value) {
        sheet.appendRow(row.map((cell) => TextCellValue(cell)).toList());
      }
    }
    if (defaultSheet != null && !sheets.containsKey(defaultSheet)) {
      excel.delete(defaultSheet);
    }
    return Uint8List.fromList(excel.encode()!);
  }

  Uint8List buildOds(Map<String, List<List<String>>> sheets) {
    String xmlEscape(String v) => v
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');

    final tablesBuffer = StringBuffer();
    for (final entry in sheets.entries) {
      tablesBuffer.write('<table:table table:name="${xmlEscape(entry.key)}">');
      for (final row in entry.value) {
        tablesBuffer.write('<table:table-row>');
        for (final cell in row) {
          tablesBuffer.write(
            '<table:table-cell office:value-type="string"><text:p>${xmlEscape(cell)}</text:p></table:table-cell>',
          );
        }
        tablesBuffer.write('</table:table-row>');
      }
      tablesBuffer.write('</table:table>');
    }

    final contentXml =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<office:document-content '
        'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
        'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
        'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">'
        '<office:body><office:spreadsheet>$tablesBuffer</office:spreadsheet></office:body>'
        '</office:document-content>';

    final archive = Archive();
    final xmlBytes = utf8.encode(contentXml);
    archive.addFile(ArchiveFile('content.xml', xmlBytes.length, xmlBytes));
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  group('RosterImporter semester detection & extension checks', () {
    test('detects FA/SP/SU semester codes from filenames across Windows and POSIX paths', () {
      expect(RosterImporter.semesterFromFileName('FA26_PRM393.xlsx'), 'FA26');
      expect(RosterImporter.semesterFromFileName('/tmp/sp25-classes.ods'), 'SP25');
      expect(RosterImporter.semesterFromFileName(r'C:\Users\gv\SU24.xlsx'), 'SU24');
      expect(RosterImporter.semesterFromFileName('su27 roster.ods'), 'SU27');
      expect(RosterImporter.semesterFromFileName('WI26_PRM393.xlsx'), isNull);
      expect(RosterImporter.semesterFromFileName('2026_FA_PRM393.xlsx'), isNull);
    });

    test('rejects unsupported file extensions such as csv, txt, or missing extension', () {
      for (final fileName in ['roster.csv', 'roster.txt', 'roster', '.xlsx']) {
        expect(
          () => importer.importBytes(
            Uint8List.fromList([1, 2, 3]),
            fileName: fileName,
            semester: 'FA26',
            semesterStart: mondayStart,
          ),
          throwsA(isA<RosterImportException>()),
        );
      }
    });
  });

  group('RosterImporter XLSX multi-sheet parsing & warnings', () {
    test('parses XLSX with Vietnamese headers, optional MemberCode, formula footer skip, and warnings', () {
      final bytes = buildXlsx({
        '11_PRM393_SE1801': [
          ['MaLop', 'MSSV', 'Email', 'HoTen', 'MaThanhVien'],
          ['se1801', 'se180001', 'AnNV@fpt.edu.vn', 'Nguyễn Văn An', 'AnNVSE180001'],
          ['se1801', 'SE180002', 'BinhTT@fpt.edu.vn', 'Trần Thị Bình', ''],
          // Missing identity fields completely -> silently skipped footer row
          ['se1801', '', '', '', ''],
          // Invalid email -> warning + skipped
          ['se1801', 'SE180003', 'not-an-email', 'Invalid Email Student', ''],
          // Duplicate roll -> warning + skipped
          ['se1801', 'se180001', 'other@fpt.edu.vn', 'Dup Roll Student', ''],
          // Duplicate email -> warning + skipped
          ['se1801', 'SE180004', 'annv@fpt.edu.vn', 'Dup Email Student', ''],
          // Missing name -> warning + skipped
          ['se1801', 'SE180005', 'chi@fpt.edu.vn', '', ''],
        ],
        '22_SWP391': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1802', 'SE180010', 'dung@fpt.edu.vn', 'Phạm Tiến Dũng'],
        ],
        'InvalidSheetName': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1899', 'SE180099', 'bad@fpt.edu.vn', 'Ignored'],
        ],
      });

      final result = importer.importBytes(
        bytes,
        fileName: 'FA26_classes.XLSX',
        semester: 'FA26',
        semesterStart: mondayStart,
        weeks: 3,
        meetingsPerWeek: 2,
      );

      expect(result.classes, hasLength(2));
      final prm = result.classes[0];
      expect(prm.courseCode, 'PRM393');
      expect(prm.classCode, 'SE1801');
      expect(prm.scheduleCode, '11');
      expect(prm.meetings, hasLength(6));
      expect(prm.meetings.first.state, MeetingState.upcoming);
      expect(
        prm.students.map((s) => (s.rollNumber, s.email, s.memberCode)).toList(),
        [
          ('SE180001', 'annv@fpt.edu.vn', 'AnNVSE180001'),
          ('SE180002', 'binhtt@fpt.edu.vn', ''),
        ],
      );

      final swp = result.classes[1];
      expect(swp.courseCode, 'SWP391');
      expect(swp.classCode, 'SE1802');
      expect(swp.scheduleCode, '22');

      expect(
        result.warnings.join('\n'),
        allOf([
          contains('email không hợp lệ'),
          contains('MSSV trùng SE180001'),
          contains('email trùng annv@fpt.edu.vn'),
          contains('thiếu Class/MSSV/Email/Họ tên'),
          contains('InvalidSheetName'),
        ]),
      );
    });

    test('throws RosterImportException when all sheets mix class codes or fail validation', () {
      final bytes = buildXlsx({
        '11_PRM393_SE1801': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1801', 'SE180001', 'a@fpt.edu.vn', 'An'],
          ['SE1802', 'SE180002', 'b@fpt.edu.vn', 'Binh'],
        ],
      });

      expect(
        () => importer.importBytes(
          bytes,
          fileName: 'FA26_mixed.xlsx',
          semester: 'FA26',
          semesterStart: mondayStart,
        ),
        throwsA(
          isA<RosterImportException>().having(
            (e) => e.message,
            'message',
            contains('đúng một mã lớp'),
          ),
        ),
      );
    });
  });

  group('RosterImporter ODS archive parsing', () {
    test('parses valid ODS content.xml into CourseClass with full schedule generation', () {
      final bytes = buildOds({
        '34_PRN231_SE1807': [
          ['Class', 'StudentId', 'Email', 'FullName', 'MemberCode'],
          ['SE1807', 'HE180001', 'linh@fpt.edu.vn', 'Đỗ Khánh Linh', 'LinhDKHE180001'],
          ['SE1807', 'HE180002', 'nam@fpt.edu.vn', 'Vũ Hải Nam', 'NamVHHE180002'],
        ],
      });

      final result = importer.importBytes(
        bytes,
        fileName: 'FA26_PRN231.ods',
        semester: 'FA26',
        semesterStart: mondayStart,
        weeks: 2,
        meetingsPerWeek: 2,
      );

      expect(result.warnings, isEmpty);
      expect(result.classes, hasLength(1));
      final cls = result.classes.single;
      expect(cls.scheduleCode, '34');
      expect(cls.courseCode, 'PRN231');
      expect(cls.classCode, 'SE1807');
      expect(cls.students, hasLength(2));
      expect(cls.meetings, hasLength(4));
      expect(cls.meetings.every((m) => m.startAt.hour == 15), isTrue);
    });

    test('rejects ODS archive missing content.xml', () {
      final archive = Archive()
        ..addFile(ArchiveFile('mimetype', 4, utf8.encode('test')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

      expect(
        () => importer.importBytes(
          bytes,
          fileName: 'bad.ods',
          semester: 'FA26',
          semesterStart: mondayStart,
        ),
        throwsA(isA<RosterImportException>()),
      );
    });
  });
}
