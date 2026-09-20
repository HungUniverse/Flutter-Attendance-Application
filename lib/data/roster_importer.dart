import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

import '../domain/models.dart';
import '../domain/schedule_service.dart';

class RosterImportException implements Exception {
  const RosterImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RosterImportResult {
  const RosterImportResult({required this.classes, this.warnings = const []});
  final List<CourseClass> classes;
  final List<String> warnings;
}

class RosterImporter {
  RosterImporter({ScheduleService? scheduleService})
    : _scheduleService = scheduleService ?? ScheduleService();

  final ScheduleService _scheduleService;

  RosterImportResult importBytes(
    Uint8List bytes, {
    required String fileName,
    required String semester,
    required DateTime semesterStart,
    int weeks = 10,
    int meetingsPerWeek = 2,
  }) {
    final extension = fileName.toLowerCase().split('.').last;
    final sheets = switch (extension) {
      'ods' => _readOds(bytes),
      'xlsx' => _readXlsx(bytes),
      _ => throw const RosterImportException(
        'Chỉ hỗ trợ file .ods hoặc .xlsx.',
      ),
    };
    final classes = <CourseClass>[];
    final warnings = <String>[];
    for (final entry in sheets.entries) {
      try {
        classes.add(
          _parseSheet(
            entry.key,
            entry.value,
            warnings: warnings,
            semester: semester,
            semesterStart: semesterStart,
            weeks: weeks,
            meetingsPerWeek: meetingsPerWeek,
          ),
        );
      } on RosterImportException catch (error) {
        warnings.add('${entry.key}: ${error.message}');
      }
    }
    if (classes.isEmpty) {
      throw RosterImportException(
        warnings.isEmpty
            ? 'Không tìm thấy lớp hợp lệ.'
            : 'Không có sheet hợp lệ:\n${warnings.join('\n')}',
      );
    }
    return RosterImportResult(classes: classes, warnings: warnings);
  }

  CourseClass _parseSheet(
    String sheetName,
    List<List<String>> rawRows, {
    required List<String> warnings,
    required String semester,
    required DateTime semesterStart,
    required int weeks,
    required int meetingsPerWeek,
  }) {
    final nameMatch = RegExp(r'^([1-3][1-4])_([A-Za-z0-9]+)(?:_.*)?$')
        .firstMatch(sheetName.trim());
    if (nameMatch == null) {
      throw const RosterImportException(
        'Tên sheet phải có dạng 11_PRM393_MaLop.',
      );
    }
    final scheduleCode = nameMatch.group(1)!;
    final courseCode = nameMatch.group(2)!.toUpperCase();
    final rows = rawRows
        .where((row) => row.any((v) => v.trim().isNotEmpty))
        .toList();
    if (rows.length < 2) {
      throw const RosterImportException('Sheet không có sinh viên.');
    }
    final header = <String, int>{};
    for (final cell in rows.first.indexed) {
      header[_normalizeHeader(cell.$2)] = cell.$1;
    }
    final classIndex = _findHeader(header, const ['class', 'malop']);
    final rollIndex = _findHeader(header, const [
      'rollnumber',
      'mssv',
      'studentid',
      'masinhvien',
    ]);
    final emailIndex = _findHeader(header, const ['email']);
    final nameIndex = _findHeader(header, const ['fullname', 'hoten']);
    final memberIndex = _findHeader(header, const [
      'membercode',
      'mamember',
      'mathanhvien',
    ], required: false);
    final students = <Student>[];
    final classCodes = <String>{};
    final rolls = <String>{};
    final emails = <String>{};
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      String valueAt(int index) =>
          index < 0 || index >= row.length ? '' : row[index].trim();
      final classCode = valueAt(classIndex).toUpperCase();
      final roll = valueAt(rollIndex).toUpperCase();
      final email = valueAt(emailIndex).toLowerCase();
      final name = valueAt(nameIndex);
      // Markbooks may contain footer/formula rows in grading columns. They are
      // outside the roster when all three student identity fields are blank.
      if ([roll, email, name].every((v) => v.isEmpty)) continue;
      if (classCode.isEmpty || roll.isEmpty || email.isEmpty || name.isEmpty) {
        warnings.add(
          '$sheetName: bỏ qua dòng ${rowIndex + 1} vì thiếu Class/MSSV/Email/Họ tên.',
        );
        continue;
      }
      if (!email.contains('@')) {
        warnings.add(
          '$sheetName: bỏ qua dòng ${rowIndex + 1} vì email không hợp lệ.',
        );
        continue;
      }
      if (!rolls.add(roll)) {
        warnings.add('$sheetName: bỏ qua MSSV trùng $roll.');
        continue;
      }
      if (!emails.add(email)) {
        warnings.add('$sheetName: bỏ qua email trùng $email.');
        rolls.remove(roll);
        continue;
      }
      classCodes.add(classCode);
      students.add(
        Student(
          rollNumber: roll,
          memberCode: valueAt(memberIndex),
          email: email,
          fullName: name,
        ),
      );
    }
    if (classCodes.length != 1) {
      throw RosterImportException(
        'Mỗi sheet phải chứa đúng một mã lớp; tìm thấy ${classCodes.length}.',
      );
    }
    if (students.isEmpty) {
      throw const RosterImportException('Sheet không có sinh viên hợp lệ.');
    }
    final classCode = classCodes.single;
    final classId = '${semester}_${courseCode}_$classCode';
    final rule = ScheduleRule(
      scheduleCode: scheduleCode,
      semesterStart: semesterStart,
      weeks: weeks,
      meetingsPerWeek: meetingsPerWeek,
    );
    return CourseClass(
      id: classId,
      courseCode: courseCode,
      classCode: classCode,
      scheduleCode: scheduleCode,
      students: students,
      scheduleRule: rule,
      meetings: _scheduleService.generate(rule, classId),
    );
  }

  int _findHeader(
    Map<String, int> header,
    List<String> aliases, {
    bool required = true,
  }) {
    for (final alias in aliases) {
      if (header.containsKey(alias)) return header[alias]!;
    }
    if (!required) return -1;
    throw RosterImportException('Thiếu cột ${aliases.first}.');
  }

  Map<String, List<List<String>>> _readXlsx(Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    return workbook.tables.map((name, sheet) {
      final rows = sheet.rows
          .map(
            (row) => row.map((cell) => cell?.value?.toString() ?? '').toList(),
          )
          .toList();
      return MapEntry(name, rows);
    });
  }

  Map<String, List<List<String>>> _readOds(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final content = archive.findFile('content.xml');
    if (content == null) {
      throw const RosterImportException('File ODS không có content.xml.');
    }
    final xml = XmlDocument.parse(utf8.decode(content.content as List<int>));
    final result = <String, List<List<String>>>{};
    for (final table in xml.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'table' && node.name.prefix == 'table',
    )) {
      final name = _attributeByLocalName(table, 'name');
      if (name == null || name.isEmpty) continue;
      final rows = <List<String>>[];
      for (final row in table.childElements.where(
        (node) => node.name.local == 'table-row',
      )) {
        final values = <String>[];
        for (final cell in row.childElements.where(
          (node) =>
              node.name.local == 'table-cell' ||
              node.name.local == 'covered-table-cell',
        )) {
          final repeat =
              int.tryParse(
                _attributeByLocalName(cell, 'number-columns-repeated') ?? '1',
              ) ??
              1;
          final value = cell.descendants
              .whereType<XmlElement>()
              .where((node) => node.name.local == 'p')
              .map((node) => node.innerText)
              .join(' ')
              .trim();
          for (var i = 0; i < repeat.clamp(1, 100); i++) {
            values.add(value);
          }
        }
        while (values.isNotEmpty && values.last.isEmpty) {
          values.removeLast();
        }
        rows.add(values);
      }
      result[name] = rows;
    }
    return result;
  }

  static String? _attributeByLocalName(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static String _normalizeHeader(String value) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'ả': 'a',
      'ã': 'a',
      'ạ': 'a',
      'ă': 'a',
      'ắ': 'a',
      'ằ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'ặ': 'a',
      'â': 'a',
      'ấ': 'a',
      'ầ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'ậ': 'a',
      'đ': 'd',
      'é': 'e',
      'è': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ẹ': 'e',
      'ê': 'e',
      'ế': 'e',
      'ề': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ệ': 'e',
      'í': 'i',
      'ì': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ị': 'i',
      'ó': 'o',
      'ò': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ọ': 'o',
      'ô': 'o',
      'ố': 'o',
      'ồ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ộ': 'o',
      'ơ': 'o',
      'ớ': 'o',
      'ờ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ợ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ụ': 'u',
      'ư': 'u',
      'ứ': 'u',
      'ừ': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ự': 'u',
      'ý': 'y',
      'ỳ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
      'ỵ': 'y',
    };
    final lower = value.trim().toLowerCase();
    final plain = lower.split('').map((char) => accents[char] ?? char).join();
    return plain.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
