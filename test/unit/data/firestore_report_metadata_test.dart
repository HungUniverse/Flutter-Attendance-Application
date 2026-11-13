// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:fap_attendance/data/firestore_report_metadata.dart';
import 'package:fap_attendance/data/firestore_workspace_remote.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

class _MockFirestore extends Mock implements FirebaseFirestore {
  Future<T> Function<T>(Future<T> Function(Transaction))? onRunTransaction;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    if (onRunTransaction != null) {
      return onRunTransaction!<T>(transactionHandler);
    }
    throw UnimplementedError('onRunTransaction not configured');
  }
}

class _MockTransaction extends Mock implements Transaction {}

class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocSnap extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _FakeDocRef extends Fake
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDocRef());
  });

  late Directory tempDir;
  late _MockFirestore db;
  late _MockTransaction tx;
  late FirestoreReportMetadata service;
  late TeacherWorkspace workspace;
  late CourseClass course;
  late Meeting meeting;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('firestore_report_meta_');
    db = _MockFirestore();
    tx = _MockTransaction();
    service = FirestoreReportMetadata(db, tempDir);

    meeting = Meeting(
      id: 'm1',
      number: 1,
      startAt: DateTime(2026, 11, 3, 7, 30),
      endAt: DateTime(2026, 11, 3, 9, 45),
      state: MeetingState.closed,
    );
    course = CourseClass(
      id: 'cls-1',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      scheduleCode: '11',
      students: const [
        Student(
          rollNumber: 'SE180001',
          email: 'an@fpt.edu.vn',
          fullName: 'Nguyen Van An',
        ),
      ],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
      ),
      meetings: [meeting],
    );
    workspace = TeacherWorkspace(
      id: 'ws-1',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: [course],
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Directory queueDir(String uid) =>
      Directory(p.join(tempDir.path, 'teachers', uid, 'report-metadata-outbox'));

  Future<File> createReportFile(String name, List<int> bytes) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  group('FirestoreReportMetadata UID validation', () {
    test('rejects invalid UID characters on flush and record', () async {
      final file = await createReportFile('rep.csv', utf8.encode('h\nrow\n'));

      await expectLater(
        () => service.flush('../bad'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => service.flush(''),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => service.flush('a' * 129),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => service.record('bad/uid', workspace, course, meeting, file, 'csv'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts valid UIDs with letters, digits, underscores, hyphens', () async {
      await service.flush('teacher_01-ABC');
      expect(service.warning, isNull);
    });
  });

  group('FirestoreReportMetadata.record and flush', () {
    test('writes deterministic outbox payload and flushes new metadata doc to Firestore', () async {
      final bytes = utf8.encode('Roll,Status\nSE180001,P\n');
      final file = await createReportFile('attendance_m1.csv', bytes);
      final digest = sha256.convert(bytes).toString();
      const uid = 'teacher_1';
      final expectedId = sha256
          .convert(
            utf8.encode(
              '$uid/${workspace.semester}/${course.id}/${meeting.id}/csv/$digest',
            ),
          )
          .toString();

      final docRef = _MockDocRef();
      final docSnap = _MockDocSnap();
      when(() => db.doc('reportMetadata/$expectedId')).thenReturn(docRef);
      when(() => docSnap.exists).thenReturn(false);
      when(() => tx.get<Map<String, dynamic>>(docRef)).thenAnswer((_) async => docSnap);
      Map<String, dynamic>? writtenData;
      when(() => tx.set<Map<String, dynamic>>(docRef, any())).thenAnswer((inv) {
        writtenData = inv.positionalArguments[1] as Map<String, dynamic>;
        return tx;
      });
      db.onRunTransaction = <T>(handler) => handler(tx);

      await service.record(uid, workspace, course, meeting, file, 'csv');

      expect(service.warning, isNull);
      expect(writtenData, isNotNull);
      expect(writtenData!['ownerUid'], uid);
      expect(
        writtenData!['classId'],
        firestoreClassId(uid, workspace.semester, course.id),
      );
      expect(writtenData!['meetingId'], meeting.id);
      expect(writtenData!['fileName'], 'attendance_m1.csv');
      expect(writtenData!['format'], 'csv');
      expect(writtenData!['bytes'], bytes.length);
      expect(writtenData!['at'], isA<FieldValue>());

      // Outbox JSON file should be deleted after successful flush
      final pending = File(p.join(queueDir(uid).path, '$expectedId.json'));
      expect(await pending.exists(), isFalse);
    });

    test('skips tx.set when metadata document already exists (idempotent)', () async {
      final file = await createReportFile('existing.pdf', [1, 2, 3, 4]);
      const uid = 'teacher_2';
      final docRef = _MockDocRef();
      final docSnap = _MockDocSnap();
      when(() => db.doc(any())).thenReturn(docRef);
      when(() => docSnap.exists).thenReturn(true);
      when(() => tx.get<Map<String, dynamic>>(docRef)).thenAnswer((_) async => docSnap);
      db.onRunTransaction = <T>(handler) => handler(tx);

      await service.record(uid, workspace, course, meeting, file, 'pdf');

      expect(service.warning, isNull);
      verifyNever(() => tx.set<Map<String, dynamic>>(any(), any()));
      final remaining = await queueDir(uid).list().toList();
      expect(remaining, isEmpty);
    });

    test('retains outbox file and sets sync warning when Firestore transaction fails', () async {
      final file = await createReportFile('offline.csv', utf8.encode('data'));
      const uid = 'teacher_offline';
      final docRef = _MockDocRef();
      when(() => db.doc(any())).thenReturn(docRef);
      db.onRunTransaction = <T>(_) => throw Exception('network down');

      await service.record(uid, workspace, course, meeting, file, 'csv');

      expect(
        service.warning,
        'Tệp đã lưu trên máy · Metadata báo cáo đang chờ đồng bộ.',
      );
      final files = await queueDir(uid).list().where((e) => e is File).toList();
      expect(files, hasLength(1));

      // Now recover network and flush again
      final docSnap = _MockDocSnap();
      when(() => docSnap.exists).thenReturn(false);
      when(() => tx.get<Map<String, dynamic>>(docRef)).thenAnswer((_) async => docSnap);
      when(() => tx.set<Map<String, dynamic>>(docRef, any())).thenReturn(tx);
      db.onRunTransaction = <T>(handler) => handler(tx);

      await service.flush(uid);
      expect(service.warning, isNull);
      expect(await queueDir(uid).list().toList(), isEmpty);
    });

    test('ignores non-json files and flags mismatched ownerUid in outbox', () async {
      const uid = 'teacher_owner';
      final q = queueDir(uid);
      await q.create(recursive: true);

      final txtFile = File(p.join(q.path, 'readme.txt'));
      await txtFile.writeAsString('ignore me');

      final mismatched = File(p.join(q.path, 'foreign.json'));
      await mismatched.writeAsString(jsonEncode({'ownerUid': 'other_teacher'}));

      await service.flush(uid);

      expect(
        service.warning,
        'Tệp đã lưu trên máy · Metadata báo cáo đang chờ đồng bộ.',
      );
      // Both non-json and failed mismatched file stay untouched
      expect(await txtFile.exists(), isTrue);
      expect(await mismatched.exists(), isTrue);
    });

    test('clears prior warning when flush succeeds cleanly or queue absent', () async {
      final file = await createReportFile('warn.csv', utf8.encode('x'));
      const uid = 'teacher_clear';
      final docRef = _MockDocRef();
      when(() => db.doc(any())).thenReturn(docRef);
      db.onRunTransaction = <T>(_) => throw StateError('err');

      await service.record(uid, workspace, course, meeting, file, 'csv');
      expect(service.warning, isNotNull);

      await service.flush('brand_new_teacher_with_no_outbox');
      expect(service.warning, isNull);
    });
  });
}
