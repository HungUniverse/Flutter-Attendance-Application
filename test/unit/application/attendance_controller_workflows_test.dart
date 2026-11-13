import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/data/workspace_store.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineAuth implements AuthService {
  @override
  TeacherIdentity? current;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<String> token() async => '';
}

Uint8List _buildXlsxRoster(Map<String, List<List<String>>> sheets) {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;
  late AttendanceController controller;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('att_ctrl_workflows_');
    controller = AttendanceController(
      teacherAuth: _OfflineAuth(),
      documentsDirectory: docsDir,
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    if (await docsDir.exists()) {
      await docsDir.delete(recursive: true);
    }
  });

  group('AttendanceController import, merge, and semester switching', () {
    test('imports XLSX roster, re-imports with merge retaining attendance, and switches semesters', () async {
      final today = DateTime.now();
      final faBytes = _buildXlsxRoster({
        '11_PRM393_SE1801': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1801', 'SE180001', 'an@fpt.edu.vn', 'Nguyen Van An'],
          ['SE1801', 'SE180002', 'binh@fpt.edu.vn', 'Tran Thi Binh'],
        ],
      });

      final warnings = await controller.importRoster(
        bytes: faBytes,
        fileName: 'FA26_PRM393.xlsx',
        semester: 'FA26',
        semesterStart: DateTime(today.year, today.month, today.day),
        teacherEmail: '  GV@FPT.EDU.VN  ',
        weeks: 2,
        meetingsPerWeek: 2,
      );

      expect(warnings, isEmpty);
      expect(controller.workspace, isNotNull);
      expect(controller.workspace!.semester, 'FA26');
      expect(controller.workspace!.teacherEmail, 'gv@fpt.edu.vn');
      expect(controller.workspace!.classes, hasLength(1));
      expect(controller.lastMessage, contains('Đã import 1 lớp'));

      // Re-import into same semester with an added student -> updates/merges cleanly
      final faUpdateBytes = _buildXlsxRoster({
        '11_PRM393_SE1801': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1801', 'SE180001', 'an@fpt.edu.vn', 'Nguyen Van An'],
          ['SE1801', 'SE180002', 'binh@fpt.edu.vn', 'Tran Thi Binh'],
          ['SE1801', 'SE180003', 'chi@fpt.edu.vn', 'Le Hoang Chi'],
        ],
      });
      await controller.importRoster(
        bytes: faUpdateBytes,
        fileName: 'FA26_PRM393_v2.xlsx',
        semester: 'FA26',
        semesterStart: DateTime(today.year, today.month, today.day),
        weeks: 2,
      );

      expect(controller.workspace!.classes.single.students, hasLength(3));
      expect(controller.lastMessage, contains('Đã cập nhật'));

      // Import a second semester SP27
      final spBytes = _buildXlsxRoster({
        '22_SWP391_SE1805': [
          ['Class', 'RollNumber', 'Email', 'FullName'],
          ['SE1805', 'SE180010', 'dung@fpt.edu.vn', 'Pham Dung'],
        ],
      });
      await controller.importRoster(
        bytes: spBytes,
        fileName: 'SP27_SWP391.xlsx',
        semester: 'SP27',
        semesterStart: DateTime(today.year, today.month, today.day),
        weeks: 1,
      );

      expect(controller.workspace!.semester, 'SP27');
      final store = WorkspaceStore(Directory('${docsDir.path}/FAP Attendance'));
      final semesters = await store.listSemesters();
      expect(semesters, containsAll(['FA26', 'SP27']));

      await controller.loadSemester('FA26');
      expect(controller.workspace!.semester, 'FA26');
      expect(controller.workspace!.classes.single.students, hasLength(3));
    });
  });

  group('AttendanceController attendance lifecycle, export, schedule update & class deletion', () {
    Future<CourseClass> seedTodayClass() async {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day, 7, 30);
      final course = CourseClass(
        id: 'cls-today',
        courseCode: 'PRM393',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE180001',
            email: 'an@fpt.edu.vn',
            fullName: 'Nguyen Van An',
          ),
          Student(
            rollNumber: 'SE180002',
            email: 'binh@fpt.edu.vn',
            fullName: 'Tran Thi Binh',
          ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: todayStart,
          weeks: 2,
        ),
        meetings: [
          Meeting(
            id: 'm-today',
            number: 1,
            startAt: todayStart,
            endAt: todayStart.add(const Duration(hours: 2)),
            state: MeetingState.upcoming,
          ),
          Meeting(
            id: 'm-future',
            number: 2,
            startAt: todayStart.add(const Duration(days: 7)),
            endAt: todayStart.add(const Duration(days: 7, hours: 2)),
            state: MeetingState.upcoming,
          ),
        ],
      );
      controller.workspace = TeacherWorkspace(
        id: 'ws-today',
        semester: 'FA26',
        semesterStart: todayStart,
        teacherEmail: 'gv@fpt.edu.vn',
        classes: [course],
      );
      await controller.save();
      return course;
    }

    test('executes full session flow: start -> markPresent -> close -> override -> export CSV & PDF', () async {
      await seedTodayClass();

      await controller.startMeeting('cls-today', 'm-today');
      expect(
        controller.meetingById('cls-today', 'm-today').state,
        MeetingState.active,
      );

      await controller.markPresent(
        'cls-today',
        'm-today',
        'AN@FPT.EDU.VN',
        source: AttendanceSource.scan,
      );
      expect(
        controller.classById('cls-today').recordFor('m-today', 'SE180001')?.status,
        AttendanceStatus.present,
      );

      await controller.closeMeeting('cls-today', 'm-today');
      expect(
        controller.meetingById('cls-today', 'm-today').state,
        MeetingState.closed,
      );
      expect(
        controller.classById('cls-today').recordFor('m-today', 'SE180002')?.status,
        AttendanceStatus.absent,
      );

      await controller.overrideStatus(
        classId: 'cls-today',
        meetingId: 'm-today',
        rollNumber: 'SE180002',
        status: AttendanceStatus.present,
        reason: 'Hospital discharge note',
      );
      final updatedClass = controller.classById('cls-today');
      expect(
        updatedClass.recordFor('m-today', 'SE180002')?.status,
        AttendanceStatus.present,
      );
      expect(updatedClass.auditEvents.single.reason, 'Hospital discharge note');

      final csvFile = await controller.exportMeeting(
        'cls-today',
        'm-today',
        format: 'csv',
      );
      expect(await csvFile.exists(), isTrue);
      expect(await csvFile.readAsString(), contains('SE180001'));

      final pdfFile = await controller.exportMeeting(
        'cls-today',
        'm-today',
        format: 'pdf',
      );
      expect(await pdfFile.exists(), isTrue);
      expect((await pdfFile.readAsBytes()).length, greaterThan(1000));
    });

    test('finalizeOverdueMeetings closes past meetings automatically on initialize', () async {
      final past = DateTime.now().subtract(const Duration(days: 3));
      final overdueClass = CourseClass(
        id: 'cls-overdue',
        courseCode: 'PRN221',
        classCode: 'SE1803',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE180001',
            email: 'an@fpt.edu.vn',
            fullName: 'An',
          ),
        ],
        scheduleRule: ScheduleRule(scheduleCode: '11', semesterStart: past),
        meetings: [
          Meeting(
            id: 'm-overdue',
            number: 1,
            startAt: past,
            endAt: past.add(const Duration(hours: 2)),
            state: MeetingState.active,
          ),
        ],
      );
      final store = WorkspaceStore(Directory('${docsDir.path}/FAP Attendance'));
      await store.saveWorkspace(
        TeacherWorkspace(
          id: 'ws-ov',
          semester: 'FA26',
          semesterStart: past,
          classes: [overdueClass],
        ),
      );

      final freshController = AttendanceController(
        teacherAuth: _OfflineAuth(),
        documentsDirectory: docsDir,
      );
      addTearDown(freshController.dispose);
      await freshController.initialize();

      expect(
        freshController.meetingById('cls-overdue', 'm-overdue').state,
        MeetingState.closed,
      );
      expect(
        freshController.classById('cls-overdue').recordFor('m-overdue', 'SE180001')?.status,
        AttendanceStatus.absent,
      );
    });

    test('updateSchedule regenerates meetings and deleteClass archives & removes target class', () async {
      await seedTodayClass();
      final baseRule = controller.classById('cls-today').scheduleRule;

      await controller.updateSchedule(
        'cls-today',
        ScheduleRule(
          scheduleCode: baseRule.scheduleCode,
          semesterStart: baseRule.semesterStart,
          weeks: 4,
        ),
      );
      expect(controller.classById('cls-today').meetings, hasLength(8));

      await controller.deleteClass('cls-today');
      expect(controller.workspace!.classes, isEmpty);
      expect(controller.lastMessage, contains('Đã xóa'));
    });
  });
}
