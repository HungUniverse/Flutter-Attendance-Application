import 'models.dart';

class SlotTime {
  const SlotTime(
    this.startHour,
    this.startMinute,
    this.endHour,
    this.endMinute,
  );

  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
}

class ScheduleService {
  static const slotTimes = <int, SlotTime>{
    1: SlotTime(7, 0, 9, 15),
    2: SlotTime(9, 30, 11, 45),
    3: SlotTime(12, 30, 14, 45),
    4: SlotTime(15, 0, 17, 15),
  };

  static const weekdaysByGroup = <int, List<int>>{
    1: [DateTime.monday, DateTime.thursday],
    2: [DateTime.tuesday, DateTime.friday],
    3: [DateTime.wednesday, DateTime.saturday],
  };

  List<Meeting> generate(ScheduleRule rule, String classId) {
    if (!RegExp(r'^[1-3][1-4]$').hasMatch(rule.scheduleCode)) {
      throw const FormatException('Mã lịch phải nằm trong khoảng 11–34.');
    }
    if (rule.weeks < 1 ||
        rule.meetingsPerWeek < 1 ||
        rule.meetingsPerWeek > 2) {
      throw const FormatException(
        'Số tuần hoặc số slot mỗi tuần không hợp lệ.',
      );
    }
    final groupWeekdays = weekdaysByGroup[rule.dayGroup]!;
    final weekdays =
        (rule.weekdays.isEmpty
                ? groupWeekdays.take(rule.meetingsPerWeek)
                : rule.weekdays)
            .toSet();
    if (weekdays.length != rule.meetingsPerWeek ||
        weekdays.any((day) => !groupWeekdays.contains(day))) {
      throw const FormatException('Ngày học không khớp nhóm lịch đã chọn.');
    }
    final slot = slotTimes[rule.dailySlot]!;
    final semesterDay = DateTime(
      rule.semesterStart.year,
      rule.semesterStart.month,
      rule.semesterStart.day,
    );
    final endExclusive = semesterDay.add(Duration(days: rule.weeks * 7));
    final excluded = rule.excludedDates.map(_dateKey).toSet();
    final starts = <DateTime>[];
    for (
      var day = semesterDay;
      day.isBefore(endExclusive);
      day = day.add(const Duration(days: 1))
    ) {
      if (weekdays.contains(day.weekday) && !excluded.contains(_dateKey(day))) {
        starts.add(
          DateTime(
            day.year,
            day.month,
            day.day,
            slot.startHour,
            slot.startMinute,
          ),
        );
      }
    }
    starts.addAll(
      rule.additionalStarts.map(
        (day) => DateTime(
          day.year,
          day.month,
          day.day,
          slot.startHour,
          slot.startMinute,
        ),
      ),
    );
    starts.sort();
    final unique = <String, DateTime>{
      for (final value in starts) value.toIso8601String(): value,
    };
    return unique.values.indexed.map((entry) {
      final (index, start) = entry;
      final end = DateTime(
        start.year,
        start.month,
        start.day,
        slot.endHour,
        slot.endMinute,
      );
      return Meeting(
        id: '$classId-m${index + 1}',
        number: index + 1,
        startAt: start,
        endAt: end,
      );
    }).toList();
  }

  Meeting? currentMeeting(CourseClass courseClass, DateTime now) {
    for (final meeting in courseClass.meetings) {
      if (!now.isBefore(meeting.startAt) && !now.isAfter(meeting.endAt)) {
        return meeting;
      }
    }
    return null;
  }

  static String _dateKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
