import 'models.dart';
import 'schedule_service.dart';

class MakeupSlotCandidate {
  const MakeupSlotCandidate({
    required this.date,
    required this.dailySlot,
    required this.startAt,
    required this.endAt,
    required this.isPreferredWeekday,
  });

  final DateTime date;
  final int dailySlot;
  final DateTime startAt;
  final DateTime endAt;
  final bool isPreferredWeekday;

  Map<String, Object?> toJson() => {
    'date': date.toIso8601String(),
    'dailySlot': dailySlot,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'isPreferredWeekday': isPreferredWeekday,
  };
}

class SessionRecoveryPlan {
  const SessionRecoveryPlan({
    required this.classId,
    required this.courseCode,
    required this.classCode,
    required this.targetMeetingCount,
    required this.currentMeetingCount,
    required this.shortfallCount,
    required this.recommendedCandidates,
  });

  final String classId;
  final String courseCode;
  final String classCode;
  final int targetMeetingCount;
  final int currentMeetingCount;
  final int shortfallCount;
  final List<MakeupSlotCandidate> recommendedCandidates;

  bool get needsMakeup => shortfallCount > 0;

  Map<String, Object?> toJson() => {
    'classId': classId,
    'courseCode': courseCode,
    'classCode': classCode,
    'targetMeetingCount': targetMeetingCount,
    'currentMeetingCount': currentMeetingCount,
    'shortfallCount': shortfallCount,
    'needsMakeup': needsMakeup,
    'recommendedCandidates': recommendedCandidates
        .map((c) => c.toJson())
        .toList(),
  };
}

class SessionRecoveryPlanner {
  const SessionRecoveryPlanner();

  List<MakeupSlotCandidate> suggestMakeupSlots({
    required TeacherWorkspace workspace,
    required String classId,
    required DateTime searchFrom,
    int maxSuggestions = 5,
    int searchWindowDays = 30,
  }) {
    if (maxSuggestions < 1) {
      throw ArgumentError.value(
        maxSuggestions,
        'maxSuggestions',
        'Số lượng gợi ý tối thiểu phải từ 1 trở lên.',
      );
    }
    if (searchWindowDays < 1 || searchWindowDays > 180) {
      throw ArgumentError.value(
        searchWindowDays,
        'searchWindowDays',
        'Phạm vi tìm kiếm phải nằm trong khoảng 1–180 ngày.',
      );
    }

    final targetClass = workspace.classes
        .where((c) => c.id == classId)
        .firstOrNull;
    if (targetClass == null) {
      throw StateError('Không tìm thấy lớp học: $classId.');
    }

    final occupiedIntervals = <({DateTime start, DateTime end})>[];
    for (final courseClass in workspace.classes) {
      for (final meeting in courseClass.meetings) {
        occupiedIntervals.add((start: meeting.startAt, end: meeting.endAt));
      }
    }

    final excludedDateKeys = targetClass.scheduleRule.excludedDates
        .map(_dateKey)
        .toSet();
    final preferredWeekdays =
        (ScheduleService.weekdaysByGroup[targetClass.scheduleRule.dayGroup] ??
                const <int>[])
            .toSet();
    final preferredSlot = targetClass.scheduleRule.dailySlot;
    final slotOrder = <int>[
      if (ScheduleService.slotTimes.containsKey(preferredSlot)) preferredSlot,
      for (final slot in ScheduleService.slotTimes.keys)
        if (slot != preferredSlot) slot,
    ];

    final startDay = DateTime(
      searchFrom.year,
      searchFrom.month,
      searchFrom.day,
    );
    final candidates = <MakeupSlotCandidate>[];

    for (var offset = 0; offset < searchWindowDays; offset++) {
      final day = startDay.add(Duration(days: offset));
      if (day.weekday == DateTime.sunday) continue;
      if (excludedDateKeys.contains(_dateKey(day))) continue;

      for (final slotNumber in slotOrder) {
        final slot = ScheduleService.slotTimes[slotNumber]!;
        final startAt = DateTime(
          day.year,
          day.month,
          day.day,
          slot.startHour,
          slot.startMinute,
        );
        final endAt = DateTime(
          day.year,
          day.month,
          day.day,
          slot.endHour,
          slot.endMinute,
        );

        if (startAt.isBefore(searchFrom)) continue;
        final hasConflict = occupiedIntervals.any(
          (interval) =>
              startAt.isBefore(interval.end) && endAt.isAfter(interval.start),
        );
        if (hasConflict) continue;

        candidates.add(
          MakeupSlotCandidate(
            date: day,
            dailySlot: slotNumber,
            startAt: startAt,
            endAt: endAt,
            isPreferredWeekday: preferredWeekdays.contains(day.weekday),
          ),
        );
        if (candidates.length >= maxSuggestions) {
          return candidates;
        }
      }
    }

    return candidates;
  }

  SessionRecoveryPlan buildRecoveryPlan({
    required TeacherWorkspace workspace,
    required String classId,
    required DateTime searchFrom,
    int? targetMeetingCount,
  }) {
    final targetClass = workspace.classes
        .where((c) => c.id == classId)
        .firstOrNull;
    if (targetClass == null) {
      throw StateError('Không tìm thấy lớp học: $classId.');
    }

    final expectedTotal =
        targetMeetingCount ??
        (targetClass.scheduleRule.weeks *
            targetClass.scheduleRule.meetingsPerWeek);
    final currentCount = targetClass.meetings.length;
    final shortfall = expectedTotal > currentCount
        ? expectedTotal - currentCount
        : 0;

    final suggestions = shortfall == 0
        ? const <MakeupSlotCandidate>[]
        : suggestMakeupSlots(
            workspace: workspace,
            classId: classId,
            searchFrom: searchFrom,
            maxSuggestions: shortfall * 2,
          );

    return SessionRecoveryPlan(
      classId: targetClass.id,
      courseCode: targetClass.courseCode,
      classCode: targetClass.classCode,
      targetMeetingCount: expectedTotal,
      currentMeetingCount: currentCount,
      shortfallCount: shortfall,
      recommendedCandidates: suggestions,
    );
  }

  CourseClass scheduleMakeupMeeting({
    required CourseClass courseClass,
    required MakeupSlotCandidate candidate,
    String? customMeetingId,
  }) {
    final overlapsExisting = courseClass.meetings.any(
      (m) =>
          candidate.startAt.isBefore(m.endAt) &&
          candidate.endAt.isAfter(m.startAt),
    );
    if (overlapsExisting) {
      throw StateError('Slot học bù bị trùng thời gian với buổi học hiện có.');
    }

    final newId =
        customMeetingId ??
        '${courseClass.id}-makeup-${candidate.startAt.millisecondsSinceEpoch}';
    final addedMeeting = Meeting(
      id: newId,
      number: courseClass.meetings.length + 1,
      startAt: candidate.startAt,
      endAt: candidate.endAt,
      state: MeetingState.upcoming,
    );

    final sorted = [...courseClass.meetings, addedMeeting]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    final renumbered = <Meeting>[
      for (final (index, meeting) in sorted.indexed)
        Meeting(
          id: meeting.id,
          number: index + 1,
          startAt: meeting.startAt,
          endAt: meeting.endAt,
          state: meeting.state,
        ),
    ];

    return courseClass.copyWith(meetings: renumbered);
  }

  static String _dateKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
