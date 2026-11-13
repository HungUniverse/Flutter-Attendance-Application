import 'package:attendance_core/attendance_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScheduleService service;

  setUp(() {
    service = ScheduleService();
  });

  group('ScheduleService.generate', () {
    test('generates 20 meetings for 10 weeks with 2 meetings/week in group 1 slot 1', () {
      final rule = ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7), // Monday
        weeks: 10,
        meetingsPerWeek: 2,
      );

      final meetings = service.generate(rule, 'cls-prm');
      expect(meetings, hasLength(20));
      expect(meetings.first.id, 'cls-prm-m1');
      expect(meetings.first.number, 1);
      expect(meetings.first.startAt, DateTime(2026, 9, 7, 7, 30));
      expect(meetings.first.endAt, DateTime(2026, 9, 7, 9, 15));
      expect(meetings.last.id, 'cls-prm-m20');
      expect(meetings.last.number, 20);
      for (final m in meetings) {
        expect(
          [DateTime.monday, DateTime.thursday],
          contains(m.startAt.weekday),
        );
        expect(m.state, MeetingState.upcoming);
      }
    });

    test('supports all slotTimes 1..4 and dayGroups 1..3', () {
      for (final group in [1, 2, 3]) {
        for (final slot in [1, 2, 3, 4]) {
          final rule = ScheduleRule(
            scheduleCode: '$group$slot',
            semesterStart: DateTime(2026, 9, 7),
            weeks: 1,
            meetingsPerWeek: 2,
          );
          final meetings = service.generate(rule, 'c$group$slot');
          expect(meetings, hasLength(2));
          final expectedSlot = ScheduleService.slotTimes[slot]!;
          for (final m in meetings) {
            expect(m.startAt.hour, expectedSlot.startHour);
            expect(m.startAt.minute, expectedSlot.startMinute);
            expect(m.endAt.hour, expectedSlot.endHour);
            expect(m.endAt.minute, expectedSlot.endMinute);
            expect(
              ScheduleService.weekdaysByGroup[group],
              contains(m.startAt.weekday),
            );
          }
        }
      }
    });

    test('supports meetingsPerWeek == 1 and custom weekday from group', () {
      final rule = ScheduleRule(
        scheduleCode: '22',
        semesterStart: DateTime(2026, 9, 7),
        weeks: 4,
        meetingsPerWeek: 1,
        weekdays: const [DateTime.friday],
      );
      final meetings = service.generate(rule, 'cls-fri');
      expect(meetings, hasLength(4));
      for (final m in meetings) {
        expect(m.startAt.weekday, DateTime.friday);
        expect(m.startAt.hour, 9);
        expect(m.startAt.minute, 30);
      }
    });

    test('applies excludedDates and deduplicates additionalStarts', () {
      final excluded = DateTime(2026, 9, 10); // Thursday
      final makeup = DateTime(2026, 9, 12); // Saturday makeup
      final duplicate = DateTime(2026, 9, 7); // Already Monday
      final rule = ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
        weeks: 1,
        meetingsPerWeek: 2,
        excludedDates: [excluded],
        additionalStarts: [makeup, duplicate],
      );

      final meetings = service.generate(rule, 'cls-ex');
      expect(meetings, hasLength(2));
      expect(meetings[0].startAt, DateTime(2026, 9, 7, 7, 30));
      expect(meetings[1].startAt, DateTime(2026, 9, 12, 7, 30));
      expect(meetings[1].number, 2);
    });

    test('throws FormatException on invalid schedule codes, weeks, meetingsPerWeek, or weekdays', () {
      final start = DateTime(2026, 9, 7);

      expect(
        () => service.generate(
          ScheduleRule(scheduleCode: '01', semesterStart: start),
          'c',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(scheduleCode: '41', semesterStart: start),
          'c',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(scheduleCode: '15', semesterStart: start),
          'c',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(scheduleCode: '11', semesterStart: start, weeks: 0),
          'c',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(scheduleCode: '11', semesterStart: start, weeks: 53),
          'c',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: start,
            meetingsPerWeek: 3,
          ),
          'c',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: start,
            meetingsPerWeek: 2,
            weekdays: const [DateTime.tuesday, DateTime.friday],
          ),
          'c',
        ),
        throwsFormatException,
      );
      expect(
        () => service.generate(
          ScheduleRule(
            scheduleCode: '11',
            semesterStart: start,
            meetingsPerWeek: 2,
            weekdays: const [DateTime.monday],
          ),
          'c',
        ),
        throwsFormatException,
      );
    });
  });

  group('ScheduleService.currentMeeting', () {
    test('returns meeting at inclusive start/end boundaries and inside interval', () {
      final m1 = Meeting(
        id: 'm1',
        number: 1,
        startAt: DateTime(2026, 9, 7, 7, 30),
        endAt: DateTime(2026, 9, 7, 9, 15),
      );
      final cls = CourseClass(
        id: 'c1',
        courseCode: 'PRJ301',
        classCode: 'SE1801',
        scheduleCode: '11',
        students: const [],
        scheduleRule: ScheduleRule(
          scheduleCode: '11',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [m1],
      );

      expect(service.currentMeeting(cls, DateTime(2026, 9, 7, 7, 29)), isNull);
      expect(service.currentMeeting(cls, DateTime(2026, 9, 7, 7, 30))?.id, 'm1');
      expect(service.currentMeeting(cls, DateTime(2026, 9, 7, 8, 15))?.id, 'm1');
      expect(service.currentMeeting(cls, DateTime(2026, 9, 7, 9, 15))?.id, 'm1');
      expect(service.currentMeeting(cls, DateTime(2026, 9, 7, 9, 16)), isNull);
    });
  });
}
