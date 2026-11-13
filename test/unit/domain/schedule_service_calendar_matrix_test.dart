import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = ScheduleService();
  final mondayStart = DateTime(2026, 9, 7);

  group('ScheduleService scheduleCode 11..34 matrix', () {
    for (var dayGroup = 1; dayGroup <= 3; dayGroup++) {
      for (var dailySlot = 1; dailySlot <= 4; dailySlot++) {
        final code = '$dayGroup$dailySlot';
        test('generates accurate weekdays and timestamps for scheduleCode=$code', () {
          final rule = ScheduleRule(
            scheduleCode: code,
            semesterStart: mondayStart,
            weeks: 4,
            meetingsPerWeek: 2,
          );
          final meetings = service.generate(rule, 'cls-$code');

          expect(meetings, hasLength(8));
          final expectedWeekdays = ScheduleService.weekdaysByGroup[dayGroup]!;
          final expectedSlot = ScheduleService.slotTimes[dailySlot]!;

          for (var i = 0; i < meetings.length; i++) {
            final meeting = meetings[i];
            expect(meeting.id, 'cls-$code-m${i + 1}');
            expect(meeting.number, i + 1);
            expect(meeting.state, MeetingState.upcoming);
            expect(expectedWeekdays, contains(meeting.startAt.weekday));
            expect(meeting.startAt.hour, expectedSlot.startHour);
            expect(meeting.startAt.minute, expectedSlot.startMinute);
            expect(meeting.endAt.hour, expectedSlot.endHour);
            expect(meeting.endAt.minute, expectedSlot.endMinute);
            if (i > 0) {
              expect(
                meeting.startAt.isAfter(meetings[i - 1].startAt),
                isTrue,
              );
            }
          }
        });
      }
    }
  });

  group('ScheduleService rule validation, exclusions & additionalStarts', () {
    final invalidCodes = ['', '01', '10', '15', '41', '35', 'ab', '111'];
    for (final badCode in invalidCodes) {
      test('rejects invalid scheduleCode "$badCode"', () {
        final rule = ScheduleRule(
          scheduleCode: badCode,
          semesterStart: mondayStart,
        );
        expect(
          () => service.generate(rule, 'cls-bad'),
          throwsFormatException,
        );
      });
    }

    test('rejects invalid weeks, meetingsPerWeek, and mismatched weekdays', () {
      expect(
        () => service.generate(
          ScheduleRule(scheduleCode: '11', semesterStart: mondayStart, weeks: 0),
          'c1',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: mondayStart,
            weeks: 53,
          ),
          'c1',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: mondayStart,
            meetingsPerWeek: 0,
          ),
          'c1',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: mondayStart,
            meetingsPerWeek: 3,
          ),
          'c1',
        ),
        throwsFormatException,
      );
      // Mismatched weekday for group 1 (Monday/Thursday)
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: mondayStart,
            meetingsPerWeek: 1,
            weekdays: const [DateTime.tuesday],
          ),
          'c1',
        ),
        throwsFormatException,
      );
      // Duplicate / wrong cardinality of weekdays
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: mondayStart,
            meetingsPerWeek: 2,
            weekdays: const [DateTime.monday, DateTime.monday],
          ),
          'c1',
        ),
        throwsFormatException,
      );
    });

    test('supports 1 meeting/week with secondary weekday override', () {
      final rule = ScheduleRule(
        scheduleCode: '23',
        semesterStart: mondayStart,
        weeks: 3,
        meetingsPerWeek: 1,
        weekdays: const [DateTime.friday],
      );
      final meetings = service.generate(rule, 'cls-fri');

      expect(meetings, hasLength(3));
      expect(
        meetings.every((m) => m.startAt.weekday == DateTime.friday),
        isTrue,
      );
      expect(meetings.map((m) => m.startAt.day).toList(), [11, 18, 25]);
    });

    test('removes excludedDates, inserts additionalStarts sorted, and deduplicates overlapping dates', () {
      final excludedMondayWeek2 = DateTime(2026, 9, 14, 23, 59);
      final makeupWednesday = DateTime(2026, 9, 16);
      final duplicateRegularThursday = DateTime(2026, 9, 17, 18, 0);

      final rule = ScheduleRule(
        scheduleCode: '12',
        semesterStart: mondayStart,
        weeks: 2,
        meetingsPerWeek: 2,
        excludedDates: [excludedMondayWeek2],
        additionalStarts: [makeupWednesday, duplicateRegularThursday],
      );

      final meetings = service.generate(rule, 'cls-mod');

      // Base: Sep 7 (Mon), Sep 10 (Thu), Sep 14 (Mon - excluded), Sep 17 (Thu)
      // Added: Sep 16 (Wed), Sep 17 (deduped)
      expect(meetings.map((m) => (m.number, m.startAt.day)).toList(), [
        (1, 7),
        (2, 10),
        (3, 16),
        (4, 17),
      ]);
      expect(meetings.every((m) => m.startAt.hour == 9 && m.startAt.minute == 30), isTrue);
    });

    test('handles semesterStart in mid-week without emitting earlier days of first week', () {
      // Wednesday Sep 9 -> window covers Sep 9 .. Sep 22 (14 days)
      // Group 1 (Mon/Thu): Sep 10 (Thu), Sep 14 (Mon), Sep 17 (Thu), Sep 21 (Mon)
      final wednesdayStart = DateTime(2026, 9, 9);
      final rule = ScheduleRule(
        scheduleCode: '11',
        semesterStart: wednesdayStart,
        weeks: 2,
      );
      final meetings = service.generate(rule, 'cls-mid');

      expect(meetings.map((m) => m.startAt.day).toList(), [10, 14, 17, 21]);
    });

    test('currentMeeting matches exact inclusive startAt/endAt boundaries', () {
      final rule = ScheduleRule(
        scheduleCode: '11',
        semesterStart: mondayStart,
        weeks: 1,
      );
      final meetings = service.generate(rule, 'cls-now');
      final course = CourseClass(
        id: 'cls-now',
        courseCode: 'SWP391',
        classCode: 'SE1803',
        scheduleCode: '11',
        students: const [],
        scheduleRule: rule,
        meetings: meetings,
      );

      final m1 = meetings.first;
      expect(
        service.currentMeeting(
          course,
          m1.startAt.subtract(const Duration(seconds: 1)),
        ),
        isNull,
      );
      expect(service.currentMeeting(course, m1.startAt)?.id, m1.id);
      expect(service.currentMeeting(course, m1.endAt)?.id, m1.id);
      expect(
        service.currentMeeting(
          course,
          m1.endAt.add(const Duration(seconds: 1)),
        ),
        isNull,
      );
    });
  });
}
