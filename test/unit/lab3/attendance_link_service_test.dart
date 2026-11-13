import 'dart:convert';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/attendance_link_service.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StubAuth implements AuthService {
  @override
  TeacherIdentity? get current => const TeacherIdentity('u1', 'gv@fpt.edu.vn', 'GV');

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<String> token() async => 'jwt-token';
}

void main() {
  CourseClass sampleCourse() => CourseClass(
        id: 'cls-1',
        courseCode: 'PRM392',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE180001',
            email: '  An@FPT.EDU.VN ',
            fullName: 'An',
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
            startAt: DateTime(2026, 9, 7, 7, 30),
            endAt: DateTime(2026, 9, 7, 9, 15),
          ),
        ],
      );

  test('configured validates HTTPS origin without query, fragment, or userInfo', () {
    final auth = _StubAuth();
    expect(HttpAttendanceLinkService(auth, baseUrl: 'https://relay.example.com').configured, isTrue);
    expect(HttpAttendanceLinkService(auth, baseUrl: 'http://relay.example.com').configured, isFalse);
    expect(HttpAttendanceLinkService(auth, baseUrl: 'https://u@relay.example.com').configured, isFalse);
    expect(HttpAttendanceLinkService(auth, baseUrl: 'https://relay.example.com?a=1').configured, isFalse);
    expect(HttpAttendanceLinkService(auth, baseUrl: 'https://relay.example.com#frag').configured, isFalse);
  });

  test('createQr, current, poll, and stop send expected HTTP requests and parse responses', () async {
    final requests = <String>[];
    final client = MockClient((req) async {
      requests.add('${req.method} ${req.url.path}');
      expect(req.headers['authorization'], 'Bearer jwt-token');
      if (req.method == 'POST' && req.url.path == '/api/sessions') {
        final body = jsonDecode(req.body) as Map;
        expect(body['mode'], 'otp');
        expect((body['students'] as List).first['email'], 'an@fpt.edu.vn');
        return http.Response(
          jsonEncode({
            'id': 'sess-1',
            'classId': 'cls-1',
            'meetingId': 'm1',
            'url': 'https://relay.example.com/s/sess-1',
            'expiresAt': '2026-09-07T08:00:00.000Z',
            'receiving': true,
            'code': '123456',
          }),
          200,
        );
      }
      if (req.method == 'GET' && req.url.path == '/api/sessions/current') {
        return http.Response(jsonEncode({'session': null}), 200);
      }
      if (req.method == 'GET' && req.url.path == '/api/sessions/sess-1') {
        return http.Response(
          jsonEncode({
            'id': 'sess-1',
            'classId': 'cls-1',
            'meetingId': 'm1',
            'url': 'https://relay.example.com/s/sess-1',
            'expiresAt': '2026-09-07T08:00:00.000Z',
            'receiving': true,
            'submissions': [
              {'email': 'an@fpt.edu.vn', 'at': '2026-09-07T07:35:00.000Z'},
            ],
          }),
          200,
        );
      }
      if (req.method == 'DELETE' && req.url.path == '/api/sessions/sess-1') {
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      return http.Response('unexpected', 404);
    });

    final service = HttpAttendanceLinkService(
      _StubAuth(),
      baseUrl: 'https://relay.example.com/',
      client: client,
    );
    final course = sampleCourse();
    final meeting = course.meetings.first;

    expect(await service.current(), isNull);
    final session = await service.createQr(course, meeting, otp: true);
    expect(session.id, 'sess-1');
    expect(session.code, '123456');

    final update = await service.poll(session);
    expect(update.submissions, hasLength(1));
    expect(update.submissions.first.email, 'an@fpt.edu.vn');

    await service.stop(session);
    expect(requests, [
      'GET /api/sessions/current',
      'POST /api/sessions',
      'GET /api/sessions/sess-1',
      'DELETE /api/sessions/sess-1',
    ]);
  });

  test('throws AppProblem when unconfigured or server returns 401/500', () async {
    final unconfigured = HttpAttendanceLinkService(_StubAuth(), baseUrl: '');
    await expectLater(unconfigured.current(), throwsA(isA<AppProblem>()));

    final client401 = MockClient((_) async => http.Response('no', 401));
    final s401 = HttpAttendanceLinkService(
      _StubAuth(),
      baseUrl: 'https://relay.example.com',
      client: client401,
    );
    await expectLater(s401.current(), throwsA(isA<AppProblem>()));
  });
}
