import 'dart:convert';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/lab3/services/attendance_link_service.dart';
import 'package:fap_attendance/lab3/services/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _StubAuth implements AuthService {
  @override
  TeacherIdentity? current = const TeacherIdentity(
    'teacher-1',
    'gv@fpt.edu.vn',
    'GV',
  );

  @override
  Stream<TeacherIdentity?> get changes => const Stream.empty();

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async => current = null;

  @override
  Future<String> token() async => 'bearer-token-xyz';
}

class _MockHttpClient extends http.BaseClient {
  _MockHttpClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request, String body)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final response = await handler(request, utf8.decode(bytes));
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  final auth = _StubAuth();
  final course = CourseClass(
    id: 'cls-link',
    courseCode: 'PRM393',
    classCode: 'SE1801',
    scheduleCode: '11',
    students: const [
      Student(
        rollNumber: 'SE180001',
        email: '  AnNV@FPT.EDU.VN ',
        fullName: 'An',
      ),
      Student(
        rollNumber: 'SE180002',
        email: 'Binh@fpt.edu.vn',
        fullName: 'Binh',
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
        startAt: DateTime(2026, 9, 14, 7, 30),
        endAt: DateTime(2026, 9, 14, 9, 30),
        state: MeetingState.active,
      ),
    ],
  );

  group('HttpAttendanceLinkService configuration validation', () {
    test('accepts strict HTTPS URLs without query, fragment, or userinfo', () {
      final valid = HttpAttendanceLinkService(
        auth,
        baseUrl: 'https://relay.fap.example.com/v1',
        client: _MockHttpClient((_, _) async => http.Response('{}', 200)),
      );
      expect(valid.configured, isTrue);

      for (final invalidUrl in [
        '',
        'http://relay.fap.example.com',
        'https://user:pass@relay.fap.example.com',
        'https://relay.fap.example.com?foo=bar',
        'https://relay.fap.example.com#section',
        'https://',
      ]) {
        final svc = HttpAttendanceLinkService(
          auth,
          baseUrl: invalidUrl,
          client: _MockHttpClient((_, _) async => http.Response('{}', 200)),
        );
        expect(svc.configured, isFalse, reason: 'Expected false for $invalidUrl');
      }
    });

    test('throws AppProblem when invoking methods while unconfigured', () async {
      final svc = HttpAttendanceLinkService(
        auth,
        baseUrl: 'http://insecure.local',
        client: _MockHttpClient((_, _) async => http.Response('{}', 200)),
      );

      await expectLater(() => svc.current(), throwsA(isA<AppProblem>()));
    });
  });

  group('HttpAttendanceLinkService CRUD requests & error handling', () {
    test('current(), createQr(otp), poll(), and stop() serialize expected HTTP calls and parse responses', () async {
      final recorded = <({String method, Uri url, Map<String, dynamic>? body})>[];

      final client = _MockHttpClient((req, body) async {
        expect(req.headers['authorization'], 'Bearer bearer-token-xyz');
        recorded.add((
          method: req.method,
          url: req.url,
          body: body.isEmpty ? null : jsonDecode(body) as Map<String, dynamic>,
        ));

        if (req.method == 'GET' && req.url.path.endsWith('/api/sessions/current')) {
          return http.Response(jsonEncode({'session': null}), 200);
        }
        if (req.method == 'POST' && req.url.path.endsWith('/api/sessions')) {
          return http.Response(
            jsonEncode({
              'id': 'sess 1',
              'classId': 'cls-link',
              'meetingId': 'm1',
              'url': 'https://fap.test/join/sess-1',
              'expiresAt': '2026-09-14T08:30:00.000Z',
              'receiving': true,
              'mode': 'otp',
              'otp': '424242',
            }),
            201,
          );
        }
        if (req.method == 'GET' && req.url.path.contains('/api/sessions/')) {
          return http.Response(
            jsonEncode({
              'id': 'sess 1',
              'classId': 'cls-link',
              'meetingId': 'm1',
              'url': 'https://fap.test/join/sess-1',
              'expiresAt': '2026-09-14T08:30:00.000Z',
              'receiving': true,
              'submissions': [
                {'email': 'annv@fpt.edu.vn', 'at': '2026-09-14T07:35:00.000Z'},
              ],
            }),
            200,
          );
        }
        if (req.method == 'DELETE') {
          return http.Response(jsonEncode({'stopped': true}), 200);
        }
        return http.Response('unexpected', 500);
      });

      final service = HttpAttendanceLinkService(
        auth,
        baseUrl: 'https://relay.example.com///',
        client: client,
      );

      expect(await service.current(), isNull);

      final session = await service.createQr(
        course,
        course.meetings.single,
        otp: true,
      );
      expect(session.id, 'sess 1');
      expect(session.url, 'https://fap.test/join/sess-1');

      final postPayload = recorded[1].body!;
      expect(postPayload['classId'], 'cls-link');
      expect(postPayload['mode'], 'otp');
      expect(postPayload['meetingId'], 'm1');
      expect(postPayload['label'], 'PRM393 · SE1801');
      expect(postPayload['number'], 1);
      expect(postPayload['meetingDate'], '2026-09-14');
      expect(postPayload['students'], [
        {'email': 'annv@fpt.edu.vn'},
        {'email': 'binh@fpt.edu.vn'},
      ]);

      final update = await service.poll(session);
      expect(recorded[2].url.path, '/api/sessions/sess%201');
      expect(update.submissions, hasLength(1));
      expect(update.submissions.single.email, 'annv@fpt.edu.vn');
      expect(update.submissions.single.at.isUtc, isFalse);

      await service.stop(session);
      expect(recorded[3].method, 'DELETE');
      expect(recorded[3].url.path, '/api/sessions/sess%201');
    });

    test('maps HTTP 401 to re-login prompt and 500 to retry prompt', () async {
      var code = 401;
      final service = HttpAttendanceLinkService(
        auth,
        baseUrl: 'https://relay.example.com',
        client: _MockHttpClient((_, _) async => http.Response('err', code)),
      );

      await expectLater(
        () => service.current(),
        throwsA(
          isA<AppProblem>().having(
            (e) => e.message,
            'message',
            contains('hết hạn'),
          ),
        ),
      );

      code = 500;
      await expectLater(
        () => service.current(),
        throwsA(
          isA<AppProblem>().having(
            (e) => e.message,
            'message',
            contains('(500)'),
          ),
        ),
      );
    });
  });
}
