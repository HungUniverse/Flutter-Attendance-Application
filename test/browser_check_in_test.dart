import 'dart:convert';
import 'dart:io';

import 'package:fap_attendance/application/attendance_controller.dart';
import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/qr_protocol.dart';
import 'package:fap_attendance/network/attendance_lan_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'camera QR opens browser login with two-minute check-in window',
    () async {
      final now = DateTime.now();
      final meeting = Meeting(
        id: 'meeting-1',
        number: 1,
        startAt: DateTime(now.year, now.month, now.day, 7),
        endAt: DateTime(now.year, now.month, now.day, 9, 15),
        state: MeetingState.active,
      );
      final course = CourseClass(
        id: 'class-1',
        courseCode: 'PRM393',
        classCode: 'SE1917',
        scheduleCode: '11',
        students: const [
          Student(
            rollNumber: 'SE000001',
            email: 'student@example.com',
            fullName: 'Demo Student',
          ),
        ],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(now.year, now.month, now.day),
        ),
        meetings: [meeting],
      );
      final controller = AttendanceController()
        ..workspace = TeacherWorkspace(
          id: 'workspace-1',
          semester: 'FA26',
          semesterStart: DateTime(now.year, now.month, now.day),
          classes: [course],
        );
      final issuer = RollingQrIssuer(secret: 'browser-test-secret');
      final server = AttendanceLanServer(
        controller: controller,
        issuer: issuer,
      );
      await server.start(port: 18887);
      addTearDown(() async {
        await server.stop();
        controller.dispose();
      });
      final payload = issuer.issue(
        endpoint: server.endpoint,
        classId: course.id,
        meetingId: meeting.id,
        certificateFingerprint: server.certificateFingerprint,
        mode: QrMode.normal,
      );
      final joinUrl = Uri.parse(server.localBrowserEndpoint)
          .replace(path: '/join', queryParameters: {'qr': payload.encode()})
          .toString();
      expect(joinUrl, startsWith('http://'));
      expect(joinUrl, contains('/join?qr='));
      expect(
        server.joinUrl(payload, publicOrigin: 'https://demo.trycloudflare.com'),
        startsWith('https://demo.trycloudflare.com/join?qr='),
      );
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final pageResponse = await (await http.getUrl(Uri.parse(joinUrl)))
          .close();
      expect(pageResponse.statusCode, 200);
      final html = await utf8.decoder.bind(pageResponse).join();
      expect(html, contains('Điểm danh sinh viên'));
      final match = RegExp(r'const config=(\{[^;]+\});').firstMatch(html);
      expect(match, isNotNull);
      final config = (jsonDecode(match!.group(1)!) as Map)
          .cast<String, Object?>();
      final deadline = DateTime.parse(config['expiresAt']! as String);
      expect(
        deadline.difference(DateTime.now().toUtc()).inSeconds,
        inInclusiveRange(115, 120),
      );

      Future<HttpClientResponse> submit(String email) async {
        final request = await http.postUrl(
          Uri.parse('${server.localBrowserEndpoint}/api/v1/check-ins'),
        );
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({
            'challengeId': config['challengeId'],
            'deviceId': config['deviceId'],
            'email': email,
          }),
        );
        return request.close();
      }

      final wrong = await submit('other@example.com');
      expect(wrong.statusCode, 400);
      await wrong.drain();
      final accepted = await submit('student@example.com');
      expect(accepted.statusCode, 200);
      await accepted.drain();
      expect(
        controller
            .classById(course.id)
            .recordFor(meeting.id, 'SE000001')
            ?.status,
        AttendanceStatus.present,
      );
    },
  );
}
