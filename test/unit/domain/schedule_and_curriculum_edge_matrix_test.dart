import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = ScheduleService();

  group('ScheduleService scheduleCode matrix and slot mapping', () {
    test('maps every valid scheduleCode 11..34 to expected dayGroup and slot times', () {
      const expected = <String, (int group, int slot, int firstHour, int firstMin, List<int> days)>{
        '11': (1, 1, 7, 30, [DateTime.monday, DateTime.thursday]),
        '12': (1, 2, 9, 30, [DateTime.monday, DateTime.thursday]),
        '13': (1, 3, 12, 30, [DateTime.monday, DateTime.thursday]),
        '14': (1, 4, 15, 0, [DateTime.monday, DateTime.thursday]),
        '21': (2, 1, 7, 30, [DateTime.tuesday, DateTime.friday]),
        '22': (2, 2, 9, 30, [DateTime.tuesday, DateTime.friday]),
        '23': (2, 3, 12, 30, [DateTime.tuesday, DateTime.friday]),
        '24': (2, 4, 15, 0, [DateTime.tuesday, DateTime.friday]),
        '31': (3, 1, 7, 30, [DateTime.wednesday, DateTime.saturday]),
        '32': (3, 2, 9, 30, [DateTime.wednesday, DateTime.saturday]),
        '33': (3, 3, 12, 30, [DateTime.wednesday, DateTime.saturday]),
        '34': (3, 4, 15, 0, [DateTime.wednesday, DateTime.saturday]),
      };

      for (final entry in expected.entries) {
        final code = entry.key;
        final (group, slot, hour, min, days) = entry.value;
        final rule = ScheduleRule(
          scheduleCode: code,
          semesterStart: DateTime(2026, 11, 2), // Monday
          weeks: 2,
          meetingsPerWeek: 2,
        );
        expect(rule.dayGroup, group);
        expect(rule.dailySlot, slot);

        final meetings = service.generate(rule, 'c-$code');
        expect(meetings.length, 4, reason: 'code=$code should emit 4 meetings in 2 weeks');
        expect(meetings.map((m) => m.number).toList(), [1, 2, 3, 4]);
        for (final m in meetings) {
          expect(days, contains(m.startAt.weekday));
          expect(m.startAt.hour, hour);
          expect(m.startAt.minute, min);
          expect(m.state, MeetingState.upcoming);
        }
      }
    });

    test('rejects invalid scheduleCode, weeks, meetingsPerWeek, and mismatched weekdays', () {
      final monday = DateTime(2026, 11, 2);

      for (final badCode in ['', '00', '10', '15', '41', 'M1', '111', '99']) {
        expect(
          () => service.generate(
            ScheduleRule(scheduleCode: badCode, semesterStart: monday),
            'c-bad',
          ),
          throwsFormatException,
          reason: 'badCode=$badCode should throw',
        );
      }

      for (final badWeeks in [0, -1, 53]) {
        expect(
          () => service.generate(
            ScheduleRule(
              scheduleCode: '11',
              semesterStart: monday,
              weeks: badWeeks,
            ),
            'c-w',
          ),
          throwsFormatException,
        );
      }

      for (final badPerWeek in [0, 3]) {
        expect(
          () => service.generate(
            ScheduleRule(
              scheduleCode: '11',
              semesterStart: monday,
              meetingsPerWeek: badPerWeek,
            ),
            'c-p',
          ),
          throwsFormatException,
        );
      }

      // Wednesday is not in Group 1 (Mon/Thu)
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: monday,
            meetingsPerWeek: 1,
            weekdays: const [DateTime.wednesday],
          ),
          'c-day',
        ),
        throwsFormatException,
      );

      // Too many weekdays for meetingsPerWeek == 1
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: monday,
            meetingsPerWeek: 1,
            weekdays: const [DateTime.monday, DateTime.thursday],
          ),
          'c-len',
        ),
        throwsFormatException,
      );
    });

    test('handles single-slot week with explicit secondary weekday, exclusions, and make-up sessions', () {
      final monday = DateTime(2026, 11, 2);
      final rule = ScheduleRule(
        scheduleCode: '23', // Group 2 (Tue/Fri), Slot 3 (12:30-14:45)
        semesterStart: monday,
        weeks: 3,
        meetingsPerWeek: 1,
        weekdays: const [DateTime.friday], // Explicit secondary weekday in Group 2
        excludedDates: [
          DateTime(2026, 11, 6, 23, 59), // Exclude Fri 06/11 (time-of-day ignored)
        ],
        additionalStarts: [
          DateTime(2026, 11, 8, 8, 0), // Sunday make-up (normalized to slot 3 start)
          DateTime(2026, 11, 13, 18, 0), // Duplicate of Fri 13/11 should not double-count
        ],
      );

      final meetings = service.generate(rule, 'c-sec');
      // Base Fridays: 06/11 (excluded), 13/11, 20/11 + Make-up 08/11 -> 3 sorted meetings
      expect(meetings.length, 3);
      expect(
        meetings.map((m) => DateTime(m.startAt.year, m.startAt.month, m.startAt.day)).toList(),
        [
          DateTime(2026, 11, 8),
          DateTime(2026, 11, 13),
          DateTime(2026, 11, 20),
        ],
      );
      expect(meetings.map((m) => m.number).toList(), [1, 2, 3]);
      for (final m in meetings) {
        expect(m.startAt.hour, 12);
        expect(m.startAt.minute, 30);
        expect(m.endAt.hour, 14);
        expect(m.endAt.minute, 45);
      }
    });

    test('renumbers meetings sequentially when make-up date precedes first regular slot', () {
      final wednesday = DateTime(2026, 11, 4);
      final rule = ScheduleRule(
        scheduleCode: '31', // Group 3 (Wed/Sat), Slot 1
        semesterStart: wednesday,
        weeks: 1,
        meetingsPerWeek: 2,
        additionalStarts: [DateTime(2026, 11, 2)], // Mon before Wed semesterStart
      );

      final meetings = service.generate(rule, 'c-early');
      expect(meetings.length, 3);
      expect(meetings[0].startAt, DateTime(2026, 11, 2, 7, 30));
      expect(meetings[1].startAt, DateTime(2026, 11, 4, 7, 30));
      expect(meetings[2].startAt, DateTime(2026, 11, 7, 7, 30));
      expect(meetings.map((m) => m.number).toList(), [1, 2, 3]);
    });

    test('handles year rollover and leap-day generation cleanly', () {
      final feb26 = DateTime(2024, 2, 26); // 2024 is leap year (Mon 26 -> Thu 29)
      final rule = ScheduleRule(
        scheduleCode: '14', // Group 1 (Mon/Thu), Slot 4
        semesterStart: feb26,
        weeks: 2,
        meetingsPerWeek: 2,
      );

      final meetings = service.generate(rule, 'c-leap');
      expect(meetings.length, 4);
      expect(meetings[1].startAt, DateTime(2024, 2, 29, 15, 0));
      expect(meetings[1].endAt, DateTime(2024, 2, 29, 17, 15));
      expect(meetings[2].startAt, DateTime(2024, 3, 4, 15, 0));
    });
  });
}
