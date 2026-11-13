// ignore_for_file: subtype_of_sealed_class

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:fap_attendance/data/firestore_workspace_remote.dart';
import 'package:fap_attendance/data/shared_workspace_sync.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockTransaction extends Mock implements Transaction {}

class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _MockDocSnap extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _MockCollectionRef extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class _MockQuerySnap extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class _MockQueryDocSnap extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class _FakeDocRef extends Fake
    implements DocumentReference<Map<String, dynamic>> {}

class _FakeGetOptions extends Fake implements GetOptions {}

class _StubAuth implements AuthService {
  @override
  TeacherIdentity? current;

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<String> token() async => 'stub-token';
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDocRef());
    registerFallbackValue(_FakeGetOptions());
  });

  late _MockFirestore db;
  late _StubAuth auth;
  late FirestoreWorkspaceRemote remote;

  setUp(() {
    db = _MockFirestore();
    auth = _StubAuth()
      ..current = const TeacherIdentity(
        'uid-1',
        'Teacher@FPT.EDU.VN ',
        'Giang Vien',
      );
    remote = FirestoreWorkspaceRemote(db, auth);
  });

  void stubActiveTeacher({
    String email = 'teacher@fpt.edu.vn',
    String status = 'active',
    String? role,
  }) {
    final dirRef = _MockDocRef();
    final dirSnap = _MockDocSnap();
    when(() => db.doc('teacherDirectory/$email')).thenReturn(dirRef);
    when(() => dirRef.get(any())).thenAnswer((_) async => dirSnap);
    when(() => dirSnap.data()).thenReturn({'status': status});

    final userRef = _MockDocRef();
    final userSnap = _MockDocSnap();
    when(() => db.doc('users/uid-1')).thenReturn(userRef);
    when(() => userRef.get(any())).thenAnswer((_) async => userSnap);
    when(() => userSnap.data()).thenReturn(role == null ? null : {'role': role});
  }

  TeacherWorkspace sampleWorkspace({
    String semester = 'FA26',
    bool duplicateEmails = false,
  }) {
    return TeacherWorkspace(
      id: 'ws-1',
      semester: semester,
      semesterStart: DateTime(2026, 9, 7),
      teacherEmail: 'teacher@fpt.edu.vn',
      classes: [
        CourseClass(
          id: 'cls-1',
          courseCode: 'PRM392',
          classCode: 'SE1801',
          scheduleCode: '11',
          students: [
            const Student(
              rollNumber: 'SE180001',
              email: 'An@FPT.EDU.VN',
              fullName: 'Nguyen Van An',
            ),
            Student(
              rollNumber: 'SE180002',
              email: duplicateEmails ? 'an@fpt.edu.vn' : 'binh@fpt.edu.vn',
              fullName: 'Tran Thi Binh',
            ),
          ],
          scheduleRule: ScheduleRule(
            scheduleCode: '11',
            semesterStart: DateTime(2026, 9, 7),
          ),
          meetings: [
            Meeting(
              id: 'm1',
              number: 1,
              startAt: DateTime(2026, 11, 3, 7, 30),
              endAt: DateTime(2026, 11, 3, 9, 45),
              state: MeetingState.closed,
            ),
          ],
          attendance: {
            'm1': {
              'SE180001': AttendanceRecord(
                status: AttendanceStatus.present,
                source: AttendanceSource.scan,
                recordedAt: DateTime(2026, 11, 3, 7, 35),
              ),
            },
          },
          auditEvents: [
            AuditEvent(
              id: 'aud-1',
              createdAt: DateTime(2026, 11, 3, 7, 35),
              action: 'scan',
              reason: 'Scan',
              rollNumber: 'SE180001',
              meetingId: 'm1',
              oldValue: '',
              newValue: 'P',
            ),
          ],
        ),
      ],
    );
  }

  group('Deterministic ID helpers', () {
    test('firestoreWorkspaceId and firestoreClassId compute stable SHA-256 hashes', () {
      expect(
        firestoreWorkspaceId('uid-1', 'FA26'),
        sha256.convert(utf8.encode('uid-1/FA26')).toString(),
      );
      expect(
        firestoreClassId('uid-1', 'FA26', 'cls-1'),
        sha256.convert(utf8.encode('uid-1/FA26/cls-1')).toString(),
      );
      expect(
        firestoreClassId('uid-1', 'FA26', 'cls-1'),
        isNot(firestoreClassId('uid-2', 'FA26', 'cls-1')),
      );
    });
  });

  group('FirestoreWorkspaceRemote authentication and role checks', () {
    test('owner getter throws AppProblem when signed out', () {
      auth.current = null;
      expect(() => remote.owner, throwsA(isA<AppProblem>()));
    });

    test('requireTeacher denies missing/empty email and inactive non-admin user', () async {
      auth.current = const TeacherIdentity('uid-1', '   ', 'Blank Email');
      await expectLater(
        () => remote.requireTeacher(),
        throwsA(isA<WorkspaceAccessDenied>()),
      );

      auth.current = const TeacherIdentity('uid-1', 'Teacher@FPT.EDU.VN', 'T');
      stubActiveTeacher(status: 'disabled', role: 'student');
      await expectLater(
        () => remote.requireTeacher(),
        throwsA(isA<WorkspaceAccessDenied>()),
      );
    });

    test('requireTeacher allows active teacher or admin fallback', () async {
      stubActiveTeacher(status: 'active');
      await remote.requireTeacher();

      stubActiveTeacher(status: 'inactive', role: 'admin');
      await remote.requireTeacher();
    });
  });

  group('FirestoreWorkspaceRemote.readWorkspace', () {
    test('returns {data: null} when querying latest workspace yields empty collection', () async {
      stubActiveTeacher();
      final col = _MockCollectionRef();
      final q1 = _MockQuery();
      final q2 = _MockQuery();
      final q3 = _MockQuery();
      final qSnap = _MockQuerySnap();

      when(() => db.collection('workspaces')).thenReturn(col);
      when(() => col.where('ownerUid', isEqualTo: 'uid-1')).thenReturn(q1);
      when(() => q1.orderBy('updatedAt', descending: true)).thenReturn(q2);
      when(() => q2.limit(1)).thenReturn(q3);
      when(() => q3.get(any())).thenAnswer((_) async => qSnap);
      when(() => qSnap.docs).thenReturn([]);

      final res = await remote.readWorkspace();
      expect(res, {'data': null});
    });

    test('reads full workspace graph, caches by revision, and serves cache hit without refetching child docs', () async {
      stubActiveTeacher();
      final ws = sampleWorkspace();
      final wsId = firestoreWorkspaceId('uid-1', 'FA26');
      final clsHash = firestoreClassId('uid-1', 'FA26', 'cls-1');

      final wsRef = _MockDocRef();
      when(() => wsRef.id).thenReturn(wsId);
      when(() => db.doc('workspaces/$wsId')).thenReturn(wsRef);

      final clsRef = _MockDocRef();
      when(() => db.doc('classes/$clsHash')).thenReturn(clsRef);

      final meetingRef = _MockDocRef();
      when(() => db.doc('classes/$clsHash/meetings/m1')).thenReturn(meetingRef);

      final wsSnap = _MockDocSnap();
      final clsSnap = _MockDocSnap();
      final mSnap = _MockDocSnap();

      final wsMeta = ws.toJson()..remove('classes');
      final clsMeta = ws.classes.single.toJson()
        ..remove('meetings')
        ..remove('attendance')
        ..remove('auditEvents');
      final mJson = ws.classes.single.meetings.single.toJson();

      when(() => wsSnap.data()).thenReturn({
        'ownerUid': 'uid-1',
        'revision': 3,
        'data': wsMeta,
        'layout': {
          clsHash: ['m1'],
        },
      });
      when(() => clsSnap.data()).thenReturn({'data': clsMeta});
      when(() => mSnap.data()).thenReturn({
        ...mJson,
        'records': {
          'SE180001': ws.classes.single.attendance['m1']!['SE180001']!.toJson(),
        },
        'auditEvents': [ws.classes.single.auditEvents.single.toJson()],
      });

      final tx = _MockTransaction();
      when(() => tx.get<Map<String, dynamic>>(wsRef)).thenAnswer((_) async => wsSnap);
      when(() => tx.get<Map<String, dynamic>>(clsRef)).thenAnswer((_) async => clsSnap);
      when(() => tx.get<Map<String, dynamic>>(meetingRef))
          .thenAnswer((_) async => mSnap);
      when(() => db.runTransaction<Map<String, dynamic>>(any()))
          .thenAnswer((inv) async {
        final cb = inv.positionalArguments[0]
            as Future<Map<String, dynamic>> Function(Transaction);
        return cb(tx);
      });

      final first = await remote.readWorkspace(semester: 'FA26');
      expect(first['data'], isNotNull);
      final data = first['data'] as Map<String, dynamic>;
      expect(data['revision'], 3);
      final parsed = TeacherWorkspace.fromJson(
        Map<String, Object?>.from(data['workspace'] as Map),
      );
      expect(parsed.classes.single.courseCode, 'PRM392');
      expect(parsed.classes.single.auditEvents, hasLength(1));
      verify(() => tx.get<Map<String, dynamic>>(clsRef)).called(1);

      // Second read with same revision returns cached workspace without hitting clsRef again
      final second = await remote.readWorkspace(semester: 'FA26');
      expect(second['data'], same(first['data']));
      verifyNever(() => tx.get<Map<String, dynamic>>(clsRef));
    });

    test('readWorkspace via latest query picks single doc reference', () async {
      stubActiveTeacher();
      final col = _MockCollectionRef();
      final q1 = _MockQuery();
      final q2 = _MockQuery();
      final q3 = _MockQuery();
      final qSnap = _MockQuerySnap();
      final qDoc = _MockQueryDocSnap();
      final wsRef = _MockDocRef();
      final wsSnap = _MockDocSnap();

      when(() => db.collection('workspaces')).thenReturn(col);
      when(() => col.where('ownerUid', isEqualTo: 'uid-1')).thenReturn(q1);
      when(() => q1.orderBy('updatedAt', descending: true)).thenReturn(q2);
      when(() => q2.limit(1)).thenReturn(q3);
      when(() => q3.get(any())).thenAnswer((_) async => qSnap);
      when(() => qSnap.docs).thenReturn([qDoc]);
      when(() => qDoc.reference).thenReturn(wsRef);
      when(() => wsRef.id).thenReturn('ws-doc-1');
      when(() => wsSnap.data()).thenReturn(null);

      final tx = _MockTransaction();
      when(() => tx.get<Map<String, dynamic>>(wsRef)).thenAnswer((_) async => wsSnap);
      when(() => db.runTransaction<Map<String, dynamic>>(any()))
          .thenAnswer((inv) async {
        final cb = inv.positionalArguments[0]
            as Future<Map<String, dynamic>> Function(Transaction);
        return cb(tx);
      });

      expect(await remote.readWorkspace(), {'data': null});
    });
  });

  group('FirestoreWorkspaceRemote.writeWorkspace', () {
    test('throws AppProblem when roster contains duplicate normalized emails', () async {
      stubActiveTeacher();
      final wsId = firestoreWorkspaceId('uid-1', 'FA26');
      when(() => db.doc('workspaces/$wsId')).thenReturn(_MockDocRef());
      final ws = sampleWorkspace(duplicateEmails: true);
      await expectLater(
        () => remote.writeWorkspace({
          'mutationId': 'mut-1',
          'revision': 0,
          'workspace': ws.toJson(),
        }),
        throwsA(isA<AppProblem>()),
      );
    });

    test('returns existing snapshot when mutationId matches (idempotent replay)', () async {
      stubActiveTeacher();
      final ws = sampleWorkspace();
      final wsId = firestoreWorkspaceId('uid-1', 'FA26');
      final wsRef = _MockDocRef();
      final wsSnap = _MockDocSnap();
      when(() => wsRef.id).thenReturn(wsId);
      when(() => db.doc('workspaces/$wsId')).thenReturn(wsRef);
      when(() => wsSnap.data()).thenReturn({
        'mutationId': 'mut-same',
        'revision': 5,
      });

      final tx = _MockTransaction();
      when(() => tx.get<Map<String, dynamic>>(wsRef)).thenAnswer((_) async => wsSnap);
      when(() => db.runTransaction<Map<String, dynamic>>(any()))
          .thenAnswer((inv) async {
        final cb = inv.positionalArguments[0]
            as Future<Map<String, dynamic>> Function(Transaction);
        return cb(tx);
      });

      final result = await remote.writeWorkspace({
        'mutationId': 'mut-same',
        'revision': 2,
        'workspace': ws.toJson(),
      });
      expect((result['data'] as Map)['revision'], 5);
      verifyNever(() => tx.set<Map<String, dynamic>>(any(), any()));
    });

    test('throws SyncConflict when server revision differs from pending revision', () async {
      stubActiveTeacher();
      final ws = sampleWorkspace();
      final wsId = firestoreWorkspaceId('uid-1', 'FA26');
      final wsRef = _MockDocRef();
      final wsSnap = _MockDocSnap();
      when(() => wsRef.id).thenReturn(wsId);
      when(() => db.doc('workspaces/$wsId')).thenReturn(wsRef);
      when(() => wsSnap.data()).thenReturn({
        'mutationId': 'other-mut',
        'revision': 4,
      });

      final tx = _MockTransaction();
      when(() => tx.get<Map<String, dynamic>>(wsRef)).thenAnswer((_) async => wsSnap);
      when(() => db.runTransaction<Map<String, dynamic>>(any()))
          .thenAnswer((inv) async {
        final cb = inv.positionalArguments[0]
            as Future<Map<String, dynamic>> Function(Transaction);
        return cb(tx);
      });

      await expectLater(
        () => remote.writeWorkspace({
          'mutationId': 'new-mut',
          'revision': 3,
          'workspace': ws.toJson(),
        }),
        throwsA(isA<SyncConflict>()),
      );
    });

    test('writes changed class/meeting docs, archives removed class, and increments revision', () async {
      stubActiveTeacher();
      final ws = sampleWorkspace();
      final wsId = firestoreWorkspaceId('uid-1', 'FA26');
      final clsHash = firestoreClassId('uid-1', 'FA26', 'cls-1');

      final wsRef = _MockDocRef();
      final clsRef = _MockDocRef();
      final meetingRef = _MockDocRef();
      final oldClsRef = _MockDocRef();
      when(() => wsRef.id).thenReturn(wsId);
      when(() => db.doc('workspaces/$wsId')).thenReturn(wsRef);
      when(() => db.doc('classes/$clsHash')).thenReturn(clsRef);
      when(() => db.doc('classes/$clsHash/meetings/m1')).thenReturn(meetingRef);
      when(() => db.doc('classes/old-removed-class')).thenReturn(oldClsRef);

      final prevWsSnap = _MockDocSnap();
      final emptySnap = _MockDocSnap();
      when(() => prevWsSnap.data()).thenReturn({
        'revision': 1,
        'mutationId': 'old-mut',
        'layout': {
          'old-removed-class': ['m0'],
        },
      });
      when(() => emptySnap.data()).thenReturn(null);

      final tx = _MockTransaction();
      when(() => tx.get<Map<String, dynamic>>(wsRef))
          .thenAnswer((_) async => prevWsSnap);
      when(() => tx.get<Map<String, dynamic>>(clsRef))
          .thenAnswer((_) async => emptySnap);
      when(() => tx.get<Map<String, dynamic>>(meetingRef))
          .thenAnswer((_) async => emptySnap);
      when(() => tx.get<Map<String, dynamic>>(oldClsRef))
          .thenAnswer((_) async => emptySnap);
      when(() => tx.set<Map<String, dynamic>>(any(), any())).thenReturn(tx);
      when(() => tx.update(oldClsRef, {'archived': true})).thenReturn(tx);

      when(() => db.runTransaction<Map<String, dynamic>>(any()))
          .thenAnswer((inv) async {
        final cb = inv.positionalArguments[0]
            as Future<Map<String, dynamic>> Function(Transaction);
        return cb(tx);
      });

      final result = await remote.writeWorkspace({
        'mutationId': 'mut-2',
        'revision': 1,
        'workspace': ws.toJson(),
      });

      final data = result['data'] as Map<String, dynamic>;
      expect(data['revision'], 2);
      verify(() => tx.update(oldClsRef, {'archived': true})).called(1);
      verify(() => tx.set<Map<String, dynamic>>(clsRef, any())).called(1);
      verify(() => tx.set<Map<String, dynamic>>(meetingRef, any())).called(1);
      verify(() => tx.set<Map<String, dynamic>>(wsRef, any())).called(1);
    });
  });
}
