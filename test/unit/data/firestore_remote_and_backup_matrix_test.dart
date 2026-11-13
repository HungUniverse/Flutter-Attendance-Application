// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:fap_attendance/data/firestore_report_metadata.dart';
import 'package:fap_attendance/data/firestore_workspace_remote.dart';
import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/data/workspace_store.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryDocSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _InMemoryDocSnapshot(this._id, this._data);

  final String _id;
  final Map<String, dynamic>? _data;

  @override
  String get id => _id;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() =>
      _data == null ? null : _deepCloneMap(_data);
}

class _InMemoryQueryDocSnapshot extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _InMemoryQueryDocSnapshot(this._id, this._reference, this._data);

  final String _id;
  final DocumentReference<Map<String, dynamic>> _reference;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  bool get exists => true;

  @override
  DocumentReference<Map<String, dynamic>> get reference => _reference;

  @override
  Map<String, dynamic> data() => _deepCloneMap(_data);
}

class _InMemoryQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _InMemoryQuerySnapshot(this._docs);

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;
}

class _InMemoryDocRef extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _InMemoryDocRef(this.db, this._path);

  final _InMemoryFirestore db;
  final String _path;

  @override
  String get path => _path;

  @override
  String get id => _path.split('/').last;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    db.docReads.add(_path);
    return _InMemoryDocSnapshot(id, db.docs[_path]);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    db.docWrites.add(_path);
    db.docs[_path] = _deepCloneMap(data);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    db.docUpdates.add(_path);
    final current = Map<String, dynamic>.from(db.docs[_path] ?? const {});
    for (final entry in data.entries) {
      current[entry.key.toString()] = _deepCloneValue(entry.value);
    }
    db.docs[_path] = current;
  }
}

class _InMemoryQuery extends Fake implements Query<Map<String, dynamic>> {
  _InMemoryQuery(
    this.db,
    this.collectionPath,
    this.filters, {
    this.orderByField,
    this.descending = false,
    this.limitCount,
  });

  final _InMemoryFirestore db;
  final String collectionPath;
  final Map<String, Object?> filters;
  final String? orderByField;
  final bool descending;
  final int? limitCount;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) => _InMemoryQuery(
    db,
    collectionPath,
    {...filters, field.toString(): isEqualTo},
    orderByField: orderByField,
    descending: descending,
    limitCount: limitCount,
  );

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) =>
      _InMemoryQuery(
        db,
        collectionPath,
        filters,
        orderByField: field.toString(),
        descending: descending,
        limitCount: limitCount,
      );

  @override
  Query<Map<String, dynamic>> limit(int limit) => _InMemoryQuery(
    db,
    collectionPath,
    filters,
    orderByField: orderByField,
    descending: descending,
    limitCount: limit,
  );

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    db.queryReads.add(collectionPath);
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    final prefix = '$collectionPath/';
    for (final entry in db.docs.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final rest = entry.key.substring(prefix.length);
      if (rest.contains('/')) continue;
      var ok = true;
      for (final f in filters.entries) {
        if (entry.value[f.key] != f.value) {
          ok = false;
          break;
        }
      }
      if (ok) {
        entries.add(MapEntry(rest, entry.value));
      }
    }
    if (orderByField != null) {
      entries.sort((a, b) {
        final av = a.value[orderByField] as Comparable?;
        final bv = b.value[orderByField] as Comparable?;
        final cmp = (av == null || bv == null) ? 0 : av.compareTo(bv);
        return descending ? -cmp : cmp;
      });
    }
    final sliced =
        limitCount != null ? entries.take(limitCount!) : entries;
    return _InMemoryQuerySnapshot([
      for (final entry in sliced)
        _InMemoryQueryDocSnapshot(
          entry.key,
          _InMemoryDocRef(db, '$collectionPath/${entry.key}'),
          entry.value,
        ),
    ]);
  }
}

class _InMemoryCollectionRef extends _InMemoryQuery
    implements CollectionReference<Map<String, dynamic>> {
  _InMemoryCollectionRef(
    _InMemoryFirestore db,
    String path,
  ) : super(db, path, const {});

  @override
  String get path => collectionPath;

  @override
  String get id => collectionPath.split('/').last;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _InMemoryDocRef(db, '$collectionPath/$path');
}

class _InMemoryTransaction extends Fake implements Transaction {
  _InMemoryTransaction(this.db);

  final _InMemoryFirestore db;
  final Map<String, Map<String, dynamic>> stagedSets = {};
  final Map<String, Map<String, dynamic>> stagedUpdates = {};

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    db.txReads.add(documentReference.path);
    final data = db.docs[documentReference.path];
    return _InMemoryDocSnapshot(documentReference.id, data)
        as DocumentSnapshot<T>;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    final map = Map<String, dynamic>.from(data as Map);
    stagedSets[documentReference.path] = _deepCloneMap(map);
    return this;
  }

  @override
  Transaction update(
    DocumentReference<Object?> documentReference,
    Map<Object, Object?> data,
  ) {
    stagedUpdates[documentReference.path] = {
      for (final entry in data.entries)
        entry.key.toString(): _deepCloneValue(entry.value),
    };
    return this;
  }

  void commit() {
    for (final entry in stagedSets.entries) {
      db.txWrites.add(entry.key);
      db.docs[entry.key] = entry.value;
    }
    for (final entry in stagedUpdates.entries) {
      db.txUpdates.add(entry.key);
      final current = Map<String, dynamic>.from(db.docs[entry.key] ?? const {});
      current.addAll(entry.value);
      db.docs[entry.key] = current;
    }
  }
}

class _InMemoryFirestore extends Fake implements FirebaseFirestore {
  final Map<String, Map<String, dynamic>> docs = {};
  final List<String> docReads = [];
  final List<String> docWrites = [];
  final List<String> docUpdates = [];
  final List<String> queryReads = [];
  final List<String> txReads = [];
  final List<String> txWrites = [];
  final List<String> txUpdates = [];
  bool throwOnTransaction = false;
  void Function()? beforeTransactionCallback;

  void resetLogs() {
    docReads.clear();
    docWrites.clear();
    docUpdates.clear();
    queryReads.clear();
    txReads.clear();
    txWrites.clear();
    txUpdates.clear();
  }

  @override
  DocumentReference<Map<String, dynamic>> doc(String path) =>
      _InMemoryDocRef(this, path);

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _InMemoryCollectionRef(this, path);

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    if (throwOnTransaction) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'Simulated outage',
      );
    }
    final tx = _InMemoryTransaction(this);
    final result = await transactionHandler(tx);
    beforeTransactionCallback?.call();
    tx.commit();
    return result;
  }
}

class _FakeAuthService implements AuthService {
  _FakeAuthService([this.current]);

  @override
  TeacherIdentity? current;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {
    current = null;
  }

  @override
  Future<String> token() async => 'fake-token';
}

int _serverSeq = 0;

Map<String, dynamic> _deepCloneMap(Map<String, dynamic> source) => {
  for (final entry in source.entries) entry.key: _deepCloneValue(entry.value),
};

Object? _deepCloneValue(Object? value) {
  if (value is FieldValue) {
    return Timestamp.fromDate(
      DateTime.utc(2026, 1, 1).add(Duration(seconds: ++_serverSeq)),
    );
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _deepCloneValue(entry.value),
    };
  }
  if (value is List) {
    return value.map(_deepCloneValue).toList();
  }
  return value;
}

Student _student(int i, {String? emailOverride}) => Student(
  rollNumber: 'SE18${i.toString().padLeft(4, '0')}',
  fullName: 'Sinh vien $i',
  email: emailOverride ?? 'sv$i@fpt.edu.vn',
);

Meeting _meeting(
  String id,
  int number, {
  DateTime? start,
  MeetingState state = MeetingState.upcoming,
}) {
  final begin = start ?? DateTime(2026, 9, 7 + (number - 1) * 2, 7, 0);
  return Meeting(
    id: id,
    number: number,
    startAt: begin,
    endAt: begin.add(const Duration(minutes: 135)),
    state: state,
  );
}

TeacherWorkspace _sampleWorkspace({
  String semester = 'FA26',
  DateTime? updatedAt,
  List<CourseClass>? classes,
}) {
  final start = DateTime(2026, 9, 7);
  final defaultClasses = classes ??
      [
        CourseClass(
          id: 'c1',
          courseCode: 'SWD392',
          classCode: 'SE1801',
          scheduleCode: 'M1',
          students: [_student(1), _student(2)],
          scheduleRule: ScheduleRule(scheduleCode: 'M1', semesterStart: start),
          meetings: [
            _meeting('m1', 1, state: MeetingState.closed),
            _meeting('m2', 2, state: MeetingState.active),
          ],
          attendance: {
            'm1': {
              'SE180001': AttendanceRecord(
                status: AttendanceStatus.present,
                source: AttendanceSource.manual,
                recordedAt: DateTime(2026, 9, 7, 7, 15),
              ),
            },
          },
          auditEvents: [
            AuditEvent(
              id: 'ev1',
              meetingId: 'm1',
              rollNumber: 'SE180001',
              action: 'override',
              oldValue: 'absent',
              newValue: 'present',
              reason: 'Xac nhan lai',
              createdAt: DateTime(2026, 9, 7, 9, 0),
            ),
          ],
        ),
        CourseClass(
          id: 'c2',
          courseCode: 'PRM392',
          classCode: 'SE1802',
          scheduleCode: 'E2',
          students: [_student(3)],
          scheduleRule: ScheduleRule(scheduleCode: 'E2', semesterStart: start),
          meetings: [_meeting('m3', 1)],
        ),
      ];
  return TeacherWorkspace(
    id: 'ws-$semester',
    semester: semester,
    semesterStart: start,
    teacherEmail: 'teacher@fpt.edu.vn',
    updatedAt: updatedAt ?? DateTime(2026, 9, 8, 8, 0),
    classes: defaultClasses,
  );
}

void main() {
  group('firestoreWorkspaceId & firestoreClassId SHA-256 hashing', () {
    test('produces deterministic SHA-256 hex IDs across callers', () {
      expect(
        firestoreWorkspaceId('teacher-1', 'FA26'),
        sha256.convert(utf8.encode('teacher-1/FA26')).toString(),
      );
      expect(
        firestoreWorkspaceId('uid_A', 'SP26'),
        sha256.convert(utf8.encode('uid_A/SP26')).toString(),
      );
      expect(
        firestoreClassId('teacher-1', 'FA26', 'c1'),
        sha256.convert(utf8.encode('teacher-1/FA26/c1')).toString(),
      );
    });

    test('produces distinct document IDs across classes and semesters', () {
      final a = firestoreClassId('t1', 'FA26', 'c1');
      final b = firestoreClassId('t1', 'FA26', 'c2');
      final c = firestoreClassId('t1', 'SP26', 'c1');
      expect({a, b, c}.length, 3);
    });
  });

  group('FirestoreWorkspaceRemote access & authorization', () {
    late _InMemoryFirestore db;
    late _FakeAuthService auth;
    late FirestoreWorkspaceRemote remote;

    setUp(() {
      db = _InMemoryFirestore();
      auth = _FakeAuthService(
        const TeacherIdentity('teacher-1', 'teacher@fpt.edu.vn', 'Giang vien'),
      );
      remote = FirestoreWorkspaceRemote(db, auth);
    });

    test('throws WorkspaceAccessDenied when user is not signed in and AppProblem on owner getter', () async {
      auth.current = null;
      expect(
        () => remote.owner,
        throwsA(
          isA<AppProblem>().having(
            (e) => e.message,
            'message',
            'Vui lòng đăng nhập.',
          ),
        ),
      );
      await expectLater(
        () => remote.requireTeacher(),
        throwsA(isA<WorkspaceAccessDenied>()),
      );
    });

    test('throws WorkspaceAccessDenied when email is empty or directory inactive', () async {
      auth.current = const TeacherIdentity('teacher-1', '', 'No Mail');
      await expectLater(
        () => remote.requireTeacher(),
        throwsA(isA<WorkspaceAccessDenied>()),
      );

      auth.current = const TeacherIdentity(
        'teacher-1',
        'Teacher@FPT.EDU.VN',
        'Teacher',
      );
      db.docs['teacherDirectory/teacher@fpt.edu.vn'] = {'status': 'inactive'};
      await expectLater(
        () => remote.requireTeacher(),
        throwsA(isA<WorkspaceAccessDenied>()),
      );
    });

    test('grants access for active teacherDirectory record regardless of email case', () async {
      auth.current = const TeacherIdentity(
        'teacher-1',
        'Teacher@FPT.EDU.VN',
        'Teacher',
      );
      db.docs['teacherDirectory/teacher@fpt.edu.vn'] = {'status': 'active'};

      await expectLater(remote.requireTeacher(), completes);
    });

    test('grants access when directory inactive but users/{uid} has admin role', () async {
      db.docs['teacherDirectory/teacher@fpt.edu.vn'] = {'status': 'inactive'};
      db.docs['users/teacher-1'] = {'role': 'admin'};

      await expectLater(remote.requireTeacher(), completes);
    });
  });

  group('FirestoreWorkspaceRemote writeWorkspace & readWorkspace', () {
    late _InMemoryFirestore db;
    late _FakeAuthService auth;
    late FirestoreWorkspaceRemote remote;

    setUp(() {
      db = _InMemoryFirestore();
      auth = _FakeAuthService(
        const TeacherIdentity('teacher-1', 'teacher@fpt.edu.vn', 'Teacher One'),
      );
      db.docs['teacherDirectory/teacher@fpt.edu.vn'] = {'status': 'active'};
      remote = FirestoreWorkspaceRemote(db, auth);
    });

    test('rejects workspace with duplicate student emails within the same class', () async {
      final start = DateTime(2026, 9, 7);
      final ws = _sampleWorkspace(
        classes: [
          CourseClass(
            id: 'c-dup',
            courseCode: 'SWD392',
            classCode: 'SE1801',
            scheduleCode: 'M1',
            students: [
              _student(1, emailOverride: 'Same@FPT.EDU.VN'),
              _student(2, emailOverride: ' same@fpt.edu.vn '),
            ],
            scheduleRule: ScheduleRule(scheduleCode: 'M1', semesterStart: start),
            meetings: [_meeting('m1', 1)],
          ),
        ],
      );

      final wsDocId = firestoreWorkspaceId('teacher-1', 'FA26');
      await expectLater(
        () => remote.writeWorkspace({
          'mutationId': 'mut-dup',
          'revision': 0,
          'workspace': ws.toJson(),
        }),
        throwsA(isA<AppProblem>()),
      );
      expect(db.docs.containsKey('workspaces/$wsDocId'), isFalse);
    });

    test('writes decomposed class & meeting docs and reads identical workspace back', () async {
      final ws = _sampleWorkspace();
      final wsDocId = firestoreWorkspaceId('teacher-1', 'FA26');
      final c1DocId = firestoreClassId('teacher-1', 'FA26', 'c1');

      final written = await remote.writeWorkspace({
        'mutationId': 'mut-1',
        'revision': 0,
        'workspace': ws.toJson(),
      });

      final data = written['data'] as Map<String, dynamic>;
      expect(data['revision'], 1);
      expect(db.docs.containsKey('workspaces/$wsDocId'), isTrue);
      expect(db.docs.containsKey('classes/$c1DocId'), isTrue);
      expect(db.docs.containsKey('classes/$c1DocId/meetings/m1'), isTrue);
      expect(db.docs.containsKey('classes/$c1DocId/meetings/m2'), isTrue);

      final readBack = await remote.readWorkspace(semester: 'FA26');
      final readData = readBack['data'] as Map<String, dynamic>;
      expect(readData['revision'], 1);

      final parsed = TeacherWorkspace.fromJson(
        Map<String, dynamic>.from(readData['workspace'] as Map),
      );
      expect(parsed.semester, 'FA26');
      expect(parsed.classes.length, 2);
      expect(parsed.classes.first.students.length, 2);
      expect(parsed.classes.first.meetings.length, 2);
      expect(
        parsed.classes.first.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
      expect(parsed.classes.first.auditEvents.single.reason, 'Xac nhan lai');
    });

    test('readWorkspace reuses cached workspace when server revision is unchanged', () async {
      final ws = _sampleWorkspace();
      final wsDocId = firestoreWorkspaceId('teacher-1', 'FA26');
      await remote.writeWorkspace({
        'mutationId': 'mut-1',
        'revision': 0,
        'workspace': ws.toJson(),
      });

      final first = await remote.readWorkspace(semester: 'FA26');
      expect((first['data'] as Map)['revision'], 1);

      db.resetLogs();
      final second = await remote.readWorkspace(semester: 'FA26');
      expect((second['data'] as Map)['revision'], 1);
      expect(db.txReads, ['workspaces/$wsDocId']);
    });

    test('readWorkspace without semester selects workspace with highest updatedAt', () async {
      final oldWs = _sampleWorkspace(
        semester: 'SP26',
        updatedAt: DateTime(2026, 1, 10),
      );
      final newWs = _sampleWorkspace(
        semester: 'FA26',
        updatedAt: DateTime(2026, 9, 10),
      );

      await remote.writeWorkspace({
        'mutationId': 'mut-old',
        'revision': 0,
        'workspace': oldWs.toJson(),
      });
      await remote.writeWorkspace({
        'mutationId': 'mut-new',
        'revision': 0,
        'workspace': newWs.toJson(),
      });

      final latest = await remote.readWorkspace();
      final parsed = TeacherWorkspace.fromJson(
        Map<String, dynamic>.from(
          (latest['data'] as Map)['workspace'] as Map,
        ),
      );
      expect(parsed.semester, 'FA26');
    });

    test('readWorkspace returns null data when remote workspace does not exist', () async {
      final empty = await remote.readWorkspace(semester: 'SU26');
      expect(empty['data'], isNull);

      final emptyLatest = await remote.readWorkspace();
      expect(emptyLatest['data'], isNull);
    });

    test('writeWorkspace handles idempotent retry with matching mutationId', () async {
      final ws = _sampleWorkspace();
      final res1 = await remote.writeWorkspace({
        'mutationId': 'mut-same',
        'revision': 0,
        'workspace': ws.toJson(),
      });
      expect((res1['data'] as Map)['revision'], 1);

      db.resetLogs();
      final res2 = await remote.writeWorkspace({
        'mutationId': 'mut-same',
        'revision': 0,
        'workspace': ws.toJson(),
      });
      expect((res2['data'] as Map)['revision'], 1);
      expect(db.txWrites, isEmpty);
    });

    test('writeWorkspace throws SyncConflict when revision is stale', () async {
      final ws = _sampleWorkspace();
      await remote.writeWorkspace({
        'mutationId': 'mut-1',
        'revision': 0,
        'workspace': ws.toJson(),
      });

      await expectLater(
        () => remote.writeWorkspace({
          'mutationId': 'mut-2',
          'revision': 0,
          'workspace': ws.toJson(),
        }),
        throwsA(isA<SyncConflict>()),
      );
    });

    test('writeWorkspace skips unchanged docs, updates modified meetings, and archives dropped classes', () async {
      final ws1 = _sampleWorkspace();
      final c1DocId = firestoreClassId('teacher-1', 'FA26', 'c1');
      final c2DocId = firestoreClassId('teacher-1', 'FA26', 'c2');

      await remote.writeWorkspace({
        'mutationId': 'mut-1',
        'revision': 0,
        'workspace': ws1.toJson(),
      });

      db.resetLogs();
      final updatedC1 = ws1.classes.first.copyWith(
        attendance: {
          ...ws1.classes.first.attendance,
          'm2': {
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: DateTime(2026, 9, 9, 7, 20),
            ),
          },
        },
      );
      final ws2 = ws1.copyWith(
        updatedAt: DateTime(2026, 9, 9, 8, 0),
        classes: [updatedC1],
      );

      final res2 = await remote.writeWorkspace({
        'mutationId': 'mut-2',
        'revision': 1,
        'workspace': ws2.toJson(),
      });
      expect((res2['data'] as Map)['revision'], 2);

      expect(db.txUpdates, contains('classes/$c2DocId'));
      expect(db.docs['classes/$c2DocId']?['archived'], isTrue);
      expect(
        db.txWrites,
        isNot(contains('classes/$c1DocId/meetings/m1')),
      );
      expect(db.txWrites, contains('classes/$c1DocId/meetings/m2'));
    });

    test('writeWorkspace aborts cleanly if account changes mid-transaction', () async {
      final ws = _sampleWorkspace();
      db.beforeTransactionCallback = () {
        auth.current = const TeacherIdentity(
          'teacher-2',
          'teacher2@fpt.edu.vn',
          'Other',
        );
      };

      await expectLater(
        () => remote.writeWorkspace({
          'mutationId': 'mut-race',
          'revision': 0,
          'workspace': ws.toJson(),
        }),
        throwsA(
          isA<AppProblem>().having(
            (e) => e.message,
            'message',
            'Tài khoản đã thay đổi.',
          ),
        ),
      );
    });
  });

  group('SharedWorkspaceSync backed by FirestoreWorkspaceRemote', () {
    late Directory tempDir;
    late _InMemoryFirestore db;
    late _FakeAuthService auth;
    late FirestoreWorkspaceRemote remote;
    late SharedWorkspaceSync sync;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fw_sync_test_');
      db = _InMemoryFirestore();
      auth = _FakeAuthService(
        const TeacherIdentity('t-uid', 't@fpt.edu.vn', 'T'),
      );
      db.docs['teacherDirectory/t@fpt.edu.vn'] = {'status': 'active'};
      remote = FirestoreWorkspaceRemote(db, auth);
      sync = SharedWorkspaceSync(remote, tempDir);
    });

    tearDown(() async {
      sync.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('persists local outbox and syncs workspace bidirectionally with Firestore remote', () async {
      final ws = _sampleWorkspace();
      final saved = await sync.save(ws);
      expect(saved.semester, 'FA26');
      expect(sync.status, contains('Đã đồng bộ'));

      final tempDir2 = await Directory.systemTemp.createTemp('fw_sync_test2_');
      addTearDown(() async {
        if (await tempDir2.exists()) await tempDir2.delete(recursive: true);
      });
      final sync2 = SharedWorkspaceSync(remote, tempDir2);
      addTearDown(sync2.dispose);

      final pulled = await sync2.load(semester: 'FA26');
      expect(pulled, isNotNull);
      expect(pulled!.classes.length, 2);
      expect(
        pulled.classes.first.recordFor('m1', 'SE180001')?.status,
        AttendanceStatus.present,
      );
    });

    test('resolves non-overlapping attendance updates on SyncConflict during push', () async {
      final ws = _sampleWorkspace();
      await sync.save(ws);

      final remoteRead = await remote.readWorkspace(semester: 'FA26');
      final remoteData = remoteRead['data'] as Map<String, dynamic>;
      final remoteWs = TeacherWorkspace.fromJson(
        Map<String, dynamic>.from(remoteData['workspace'] as Map),
      );
      final remoteC1 = remoteWs.classes.first.copyWith(
        attendance: {
          ...remoteWs.classes.first.attendance,
          'm2': {
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.absent,
              source: AttendanceSource.manual,
              recordedAt: DateTime(2026, 9, 9, 8, 5),
            ),
          },
        },
      );
      await remote.writeWorkspace({
        'mutationId': 'device-2-mut',
        'revision': remoteData['revision'],
        'workspace': remoteWs
            .copyWith(classes: [remoteC1, remoteWs.classes.last])
            .toJson(),
      });

      final localC1 = ws.classes.first.copyWith(
        meetings: [
          ws.classes.first.meetings.first,
          ws.classes.first.meetings.last.copyWith(state: MeetingState.closed),
        ],
        attendance: {
          ...ws.classes.first.attendance,
          'm2': {
            'SE180001': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.manual,
              recordedAt: DateTime(2026, 9, 9, 8, 6),
            ),
            'SE180002': AttendanceRecord(
              status: AttendanceStatus.present,
              source: AttendanceSource.finalize,
              recordedAt: DateTime(2026, 9, 9, 8, 6),
            ),
          },
        },
      );
      final merged = await sync.save(
        ws.copyWith(classes: [localC1, ws.classes.last]),
        closing: (classId: 'c1', meetingId: 'm2'),
      );

      final m2Map = merged.classes.first.attendance['m2']!;
      expect(m2Map['SE180001']?.status, AttendanceStatus.present);
      expect(m2Map['SE180002']?.status, AttendanceStatus.absent);
    });
  });

  group('FirestoreReportMetadata outbox & transaction flush', () {
    late Directory tempDir;
    late _InMemoryFirestore db;
    late FirestoreReportMetadata metadata;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('report_meta_');
      db = _InMemoryFirestore();
      metadata = FirestoreReportMetadata(db, tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('computes sha256-derived doc id, flushes transactionally, and removes queued json file', () async {
      final reportFile = File('${tempDir.path}/report.csv')
        ..writeAsStringSync('Roll,Status\nSE180001,P\n');
      final digest = sha256.convert(reportFile.readAsBytesSync()).toString();
      final ws = _sampleWorkspace();
      final c = ws.classes.first;
      final m = c.meetings.first;
      final c1DocId = firestoreClassId('teacher-1', 'FA26', 'c1');
      final expectedDocId = sha256
          .convert(utf8.encode('teacher-1/FA26/c1/m1/csv/$digest'))
          .toString();

      await metadata.record('teacher-1', ws, c, m, reportFile, 'csv');

      expect(metadata.warning, isNull);
      final outboxDir = Directory(
        '${tempDir.path}/teachers/teacher-1/report-metadata-outbox',
      );
      expect(await outboxDir.list().length, 0);

      final savedDoc = db.docs['reportMetadata/$expectedDocId'];
      expect(savedDoc, isNotNull);
      expect(savedDoc!['classId'], c1DocId);
      expect(savedDoc['meetingId'], 'm1');
      expect(savedDoc['fileName'], 'report.csv');
      expect(savedDoc['format'], 'csv');
      expect(savedDoc['bytes'], reportFile.lengthSync());
      expect(savedDoc['ownerUid'], 'teacher-1');
    });

    test('preserves outbox file and sets warning when transaction fails, then flushes on recovery', () async {
      final reportFile = File('${tempDir.path}/report.json')
        ..writeAsStringSync('{"present":1}');
      final ws = _sampleWorkspace();
      final c = ws.classes.first;
      final m = c.meetings.last;
      final c1DocId = firestoreClassId('teacher-1', 'FA26', 'c1');

      db.throwOnTransaction = true;
      await metadata.record('teacher-1', ws, c, m, reportFile, 'json');

      expect(metadata.warning, isNotNull);
      final outboxDir = Directory(
        '${tempDir.path}/teachers/teacher-1/report-metadata-outbox',
      );
      expect(await outboxDir.list().length, 1);

      db.throwOnTransaction = false;
      await metadata.flush('teacher-1');
      expect(metadata.warning, isNull);
      expect(await outboxDir.list().length, 0);
      expect(
        db.docs.entries.any(
          (e) =>
              e.key.startsWith('reportMetadata/') &&
              e.value['classId'] == c1DocId &&
              e.value['format'] == 'json',
        ),
        isTrue,
      );
    });

    test('sets warning on corrupted JSON or ownerUid mismatch in outbox without throwing', () async {
      final outboxDir = Directory(
        '${tempDir.path}/teachers/teacher-1/report-metadata-outbox',
      )..createSync(recursive: true);
      File('${outboxDir.path}/foreign.json').writeAsStringSync(
        jsonEncode({
          'path': 'classes/other/reports/m1_csv',
          'ownerUid': 'other-uid',
        }),
      );

      await metadata.flush('teacher-1');
      expect(metadata.warning, isNotNull);
      expect(db.docs, isEmpty);
    });
  });

  group('WorkspaceStore persistence, backup fallback & archiving', () {
    late Directory tempDir;
    late WorkspaceStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ws_store_');
      store = WorkspaceStore(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves, lists, and loads workspaces', () async {
      final sp = _sampleWorkspace(
        semester: 'SP26',
        updatedAt: DateTime(2026, 2, 1),
      );
      final fa = _sampleWorkspace(
        semester: 'FA26',
        updatedAt: DateTime(2026, 9, 10),
      );

      await store.saveWorkspace(sp);
      await store.saveWorkspace(fa);

      final semesters = await store.listSemesters();
      expect(semesters, containsAll(['SP26', 'FA26']));

      final latest = await store.loadMostRecentWorkspace();
      expect(latest, isNotNull);

      final loadedSp = await store.loadWorkspace('SP26');
      expect(loadedSp?.classes.length, 2);
    });

    test('recovers cleanly from .bak when primary workspace.json is missing after update', () async {
      final ws1 = _sampleWorkspace(
        semester: 'FA26',
        updatedAt: DateTime(2026, 9, 7),
      );
      await store.saveWorkspace(ws1);

      final ws2 = _sampleWorkspace(
        semester: 'FA26',
        updatedAt: DateTime(2026, 9, 8),
      );
      await store.saveWorkspace(ws2);

      final primary = File('${tempDir.path}/FA26/workspace.json');
      final backup = File('${tempDir.path}/FA26/workspace.json.bak');
      expect(await primary.exists(), isTrue);
      expect(await backup.exists(), isTrue);
      await primary.delete();

      final recovered = await store.loadWorkspace('FA26');
      expect(recovered, isNotNull);
      expect(recovered!.semester, 'FA26');
    });

    test('archiveClass moves class directory and saveSource archives previous file', () async {
      final ws = _sampleWorkspace();
      final source1 = await store.saveSource(
        semester: 'FA26',
        fileName: 'FA26_roster.xlsx',
        bytes: [1, 2, 3, 4],
      );
      expect(await source1.exists(), isTrue);
      expect(await source1.readAsBytes(), [1, 2, 3, 4]);

      final source2 = await store.saveSource(
        semester: 'FA26',
        fileName: 'FA26_roster.xlsx',
        bytes: [9, 8, 7],
      );
      expect(await source2.readAsBytes(), [9, 8, 7]);
      final archiveDir = Directory('${tempDir.path}/FA26/source/archive');
      expect(await archiveDir.exists(), isTrue);

      await store.saveWorkspace(ws);
      final classFolder =
          '${ws.classes.first.courseCode}_${ws.classes.first.classCode}';
      final classDir = Directory('${tempDir.path}/FA26/classes/$classFolder');
      expect(await classDir.exists(), isTrue);

      final archived = await store.archiveClass(ws, ws.classes.first);
      expect(archived, isNotNull);
      expect(await classDir.exists(), isFalse);
      expect(await File('${archived!.path}/class.json').exists(), isTrue);
    });

    test('working session & final session snapshots write expected artifacts and index', () async {
      final ws = _sampleWorkspace();
      final course = ws.classes.first;
      final meeting = course.meetings.first;

      final working = await store.saveWorkingSession(ws, course, meeting);
      expect(await working.exists(), isTrue);

      final finalFile = await store.saveFinalVersion(ws, course, meeting);
      expect(await finalFile.exists(), isTrue);

      final indexFile = await store.rebuildIndex(ws);
      expect(await indexFile.exists(), isTrue);
      final indexJson = jsonDecode(await indexFile.readAsString()) as Map;
      expect(indexJson['semester'], 'FA26');
    });
  });
}
