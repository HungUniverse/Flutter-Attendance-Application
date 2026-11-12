import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models.dart';
import 'attendance_csv_exporter.dart';
import 'report_file_writer.dart';

class AttendancePdfExporter {
  Future<Uint8List> encode(TeacherWorkspace workspace, CourseClass course, Meeting meeting, {ByteData? fontData}) async {
    // Reuse the same completeness and finalized-state checks as CSV/JSON.
    AttendanceCsvExporter().encode(workspace, course, meeting);
    final font = pw.Font.ttf(fontData ?? await rootBundle.load('assets/fonts/Roboto.ttf'));
    final document = pw.Document(title: '${course.courseCode} ${course.classCode} - ${meeting.number}', author: 'FAP Attendance');
    final records = course.attendance[meeting.id]!;
    final present = course.students.where((s) => records[s.rollNumber]!.status == AttendanceStatus.present).length;
    final date = DateFormat('dd/MM/yyyy').format(meeting.startAt.toLocal());
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: pw.ThemeData.withFont(base: font, bold: font),
      footer: (context) => pw.Padding(padding: const pw.EdgeInsets.only(top: 12), child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text('FAP Attendance · $date', style: const pw.TextStyle(fontSize: 9)), pw.Text('${context.pageNumber} / ${context.pagesCount}', style: const pw.TextStyle(fontSize: 9))],
      )),
      build: (_) => [
        pw.Text('BÁO CÁO ĐIỂM DANH', style: const pw.TextStyle(fontSize: 20, color: PdfColors.deepOrange800)),
        pw.SizedBox(height: 12),
        pw.Text('${course.courseCode} · ${course.classCode} · ${workspace.semester}', style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(height: 8),
        pw.Text('Buổi ${meeting.number} · $date · Đã chốt'),
        pw.Text('Giảng viên · ${workspace.teacherEmail}'),
        pw.SizedBox(height: 12),
        pw.Text('Tổng ${course.students.length} sinh viên    Có mặt $present    Vắng ${course.students.length - present}'),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: ['MSSV', 'Họ và tên', 'Email', 'P/A', 'Ghi chú'],
          data: course.students.map((student) => [
            student.rollNumber, student.fullName, student.email,
            attendanceCode(records[student.rollNumber]!.status), records[student.rollNumber]!.note ?? '',
          ]).toList(),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          headerStyle: const pw.TextStyle(fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellPadding: const pw.EdgeInsets.all(6),
          columnWidths: {0: const pw.FlexColumnWidth(1), 1: const pw.FlexColumnWidth(1.7), 2: const pw.FlexColumnWidth(2), 3: const pw.FlexColumnWidth(.5), 4: const pw.FlexColumnWidth(1.8)},
        ),
      ],
    ));
    return document.save();
  }

  Future<File> export(Directory directory, TeacherWorkspace workspace, CourseClass course, Meeting meeting) async {
    final date = DateFormat('yyyy-MM-dd').format(meeting.startAt);
    final name = '${workspace.semester}_${course.courseCode}_${course.classCode}_M${meeting.number.toString().padLeft(2, '0')}_$date.pdf';
    return writeReportAtomically(File(p.join(directory.path, name)), Stream.value(await encode(workspace, course, meeting)));
  }
}
