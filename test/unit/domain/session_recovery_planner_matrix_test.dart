import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/session_recovery_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = SessionRecoveryPlanner();
  final baseMonday = DateTime(2026, 9, 7);

  Meeting makeSlotMeeting({
    required String id,
    required int number,
    required DateTime day,
    required int dailySlot,
    MeetingState state = MeetingState.upcoming,
  }) {
    final hours = switch (dailySlot) {
      1 => (7, 30, 9, 15),
      2 => (9, 30, 11, 45),
      3 => (12, 30, 14, 45),
      _ => (15, 0, 17, 15),
    };
    return Meeting(
      id: id,
      number: number,
      startAt: DateTime(day.year, day.month, day.day, hours.$1, hours.$2),
      endAt: DateTime(day.year, day.month, day.day, hours.$3, hours.$4),
      state: state,
    );
  }

  CourseClass makeCourse({
    required String id,
    String scheduleCode = '12',
    int weeks = 10,
    int meetingsPerWeek = 2,
    List<DateTime> excludedDates = const [],
    List<Meeting> meetings = const [],
  }) => CourseClass(
    id: id,
    courseCode: 'PRM393',
    classCode: id.toUpperCase(),
    scheduleCode: scheduleCode,
    students: const [],
    scheduleRule: ScheduleRule(
      scheduleCode: scheduleCode,
      semesterStart: baseMonday,
      weeks: weeks,
      meetingsPerWeek: meetingsPerWeek,
      excludedDates: excludedDates,
    ),
    meetings: meetings,
  );

  group('SessionRecoveryPlanner suggestMakeupSlots constraints', () {
    test('validates maxSuggestions, searchWindowDays, and unknown classId', () {
      final ws = TeacherWorkspace(
        id: 'ws-1',
        semester: 'FA26',
        semesterStart: baseMonday,
        classes: [makeCourse(id: 'c1')],
      );

      expect(
        () => planner.suggestMakeupSlots(
          workspace: ws,
          classId: 'c1',
          searchFrom: baseMonday,
          maxSuggestions: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => planner.suggestMakeupSlots(
          workspace: ws,
          classId: 'c1',
          searchFrom: baseMonday,
          searchWindowDays: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => planner.suggestMakeupSlots(
          workspace: ws,
          classId: 'c1',
          searchFrom: baseMonday,
          searchWindowDays: 181,
        ),
        throwsArgumentError,
      );
      expect(
        () => planner.suggestMakeupSlots(
          workspace: ws,
          classId: 'missing',
          searchFrom: baseMonday,
        ),
        throwsStateError,
      );
    });

    test('skips Sundays, excludedDates, occupied slots across all classes, and earlier same-day slots', () {
      // Saturday Sep 12: slots 1,2 occupied; Sunday Sep 13 skipped; Monday Sep 14 excluded;
      // Tuesday Sep 15 free! And c1 prefers slot 2 on group 1 (Mon/Thu).
      final sat = DateTime(2026, 9, 12);
      final monExcluded = DateTime(2026, 9, 14);
      final tue = DateTime(2026, 9, 15);
      final thu = DateTime(2026, 9, 17);

      final c1 = makeCourse(
        id: 'c1',
        scheduleCode: '12', // prefers slot 2, Mon/Thu
        excludedDates: [monExcluded],
        meetings: [
          makeSlotMeeting(id: 'c1-m1', number: 1, day: sat, dailySlot: 2),
          makeSlotMeeting(id: 'c1-m2', number: 2, day: tue, dailySlot: 2),
        ],
      );
      final c2 = makeCourse(
        id: 'c2',
        scheduleCode: '21',
        meetings: [
          // Occupies Sat slots 3 & 4, and Tue slot 1
          makeSlotMeeting(id: 'c2-m1', number: 1, day: sat, dailySlot: 3),
          makeSlotMeeting(id: 'c2-m2', number: 2, day: sat, dailySlot: 4),
          makeSlotMeeting(id: 'c2-m3', number: 3, day: tue, dailySlot: 1),
        ],
      );

      final ws = TeacherWorkspace(
        id: 'ws-2',
        semester: 'FA26',
        semesterStart: baseMonday,
        classes: [c1, c2],
      );

      // Search starting Saturday 08:00 -> Sat slot 1 (07:30) is in past,
      // Sat slots 2, 3, 4 occupied, Sunday skipped, Mon Sep 14 excluded!
      // Next available: Tue Sep 15 -> slot 2 occupied (c1), slot 1 occupied (c2), so picks Tue slot 3 then Tue slot 4!
      final candidates = planner.suggestMakeupSlots(
        workspace: ws,
        classId: 'c1',
        searchFrom: DateTime(2026, 9, 12, 8, 0),
        maxSuggestions: 4,
      );

      expect(candidates, hasLength(4));
      expect(candidates[0].date, DateTime(2026, 9, 15));
      expect(candidates[0].dailySlot, 3);
      expect(candidates[0].isPreferredWeekday, isFalse);

      expect(candidates[1].date, DateTime(2026, 9, 15));
      expect(candidates[1].dailySlot, 4);
      expect(candidates[1].isPreferredWeekday, isFalse);

      // Wed Sep 16 has slot 2 free (preferred dailySlot = 2 comes before slot 1)
      expect(candidates[2].date, DateTime(2026, 9, 16));
      expect(candidates[2].dailySlot, 2);
      expect(candidates[2].isPreferredWeekday, isFalse);

      expect(candidates[3].date, DateTime(2026, 9, 16));
      expect(candidates[3].dailySlot, 1);

      // Verify toJson & Thursday preferred weekday flag when window includes Thu
      final thuCandidates = planner.suggestMakeupSlots(
        workspace: ws,
        classId: 'c1',
        searchFrom: thu,
        maxSuggestions: 1,
      );
      expect(thuCandidates.single.isPreferredWeekday, isTrue);
      expect(thuCandidates.single.dailySlot, 2);
      expect(thuCandidates.single.toJson()['dailySlot'], 2);
    });
  });

  group('SessionRecoveryPlanner buildRecoveryPlan & scheduleMakeupMeeting', () {
    test('calculates shortfall, returns no suggestions when complete, and serializes recovery plan', () {
      final partialClass = makeCourse(
        id: 'c1',
        weeks: 2,
        meetingsPerWeek: 2, // expects 4
        meetings: [
          makeSlotMeeting(
            id: 'm1',
            number: 1,
            day: baseMonday,
            dailySlot: 2,
            state: MeetingState.closed,
          ),
          makeSlotMeeting(
            id: 'm2',
            number: 2,
            day: baseMonday.add(const Duration(days: 3)),
            dailySlot: 2,
          ),
        ],
      );
      final completeClass = makeCourse(
        id: 'c2',
        weeks: 1,
        meetingsPerWeek: 1, // expects 1
        meetings: [
          makeSlotMeeting(id: 'c2-m1', number: 1, day: baseMonday, dailySlot: 1),
        ],
      );

      final ws = TeacherWorkspace(
        id: 'ws-plan',
        semester: 'FA26',
        semesterStart: baseMonday,
        classes: [partialClass, completeClass],
      );

      final planPartial = planner.buildRecoveryPlan(
        workspace: ws,
        classId: 'c1',
        searchFrom: baseMonday.add(const Duration(days: 7)),
      );
      expect(planPartial.needsMakeup, isTrue);
      expect(planPartial.targetMeetingCount, 4);
      expect(planPartial.currentMeetingCount, 2);
      expect(planPartial.shortfallCount, 2);
      expect(planPartial.recommendedCandidates, hasLength(4));
      expect(planPartial.toJson()['needsMakeup'], isTrue);

      final planComplete = planner.buildRecoveryPlan(
        workspace: ws,
        classId: 'c2',
        searchFrom: baseMonday.add(const Duration(days: 7)),
      );
      expect(planComplete.needsMakeup, isFalse);
      expect(planComplete.shortfallCount, 0);
      expect(planComplete.recommendedCandidates, isEmpty);

      // Override targetMeetingCount higher -> produces shortfall even for c2
      final planExpanded = planner.buildRecoveryPlan(
        workspace: ws,
        classId: 'c2',
        searchFrom: baseMonday.add(const Duration(days: 7)),
        targetMeetingCount: 3,
      );
      expect(planExpanded.shortfallCount, 2);
      expect(planExpanded.recommendedCandidates, hasLength(4));
    });

    test('scheduleMakeupMeeting validates IDs/overlaps, inserts chronologically, and renumbers all meetings', () {
      final course = makeCourse(
        id: 'c1',
        meetings: [
          makeSlotMeeting(
            id: 'm1',
            number: 1,
            day: DateTime(2026, 9, 7),
            dailySlot: 1,
            state: MeetingState.closed,
          ),
          makeSlotMeeting(
            id: 'm2',
            number: 2,
            day: DateTime(2026, 9, 14),
            dailySlot: 1,
          ),
        ],
      );

      final overlappingCandidate = MakeupSlotCandidate(
        date: DateTime(2026, 9, 14),
        dailySlot: 1,
        startAt: DateTime(2026, 9, 14, 8, 0),
        endAt: DateTime(2026, 9, 14, 9, 0),
        isPreferredWeekday: true,
      );
      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: course,
          candidate: overlappingCandidate,
        ),
        throwsStateError,
      );

      final validMidCandidate = MakeupSlotCandidate(
        date: DateTime(2026, 9, 10),
        dailySlot: 3,
        startAt: DateTime(2026, 9, 10, 12, 30),
        endAt: DateTime(2026, 9, 10, 14, 45),
        isPreferredWeekday: true,
      );

      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: course,
          candidate: validMidCandidate,
          customMeetingId: '   ',
        ),
        throwsArgumentError,
      );
      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: course,
          candidate: validMidCandidate,
          customMeetingId: 'm1',
        ),
        throwsStateError,
      );

      final updated = planner.scheduleMakeupMeeting(
        courseClass: course,
        candidate: validMidCandidate,
        customMeetingId: 'm-makeup-sep10',
      );

      expect(
        updated.meetings.map((m) => (m.id, m.number, m.state)).toList(),
        [
          ('m1', 1, MeetingState.closed),
          ('m-makeup-sep10', 2, MeetingState.upcoming),
          ('m2', 3, MeetingState.upcoming),
        ],
      );

      // Auto-generated meeting ID when customMeetingId omitted.
      final secondCandidate = MakeupSlotCandidate(
        date: DateTime(2026, 9, 11),
        dailySlot: 2,
        startAt: DateTime(2026, 9, 11, 9, 30),
        endAt: DateTime(2026, 9, 11, 11, 45),
        isPreferredWeekday: false,
      );
      final updated2 = planner.scheduleMakeupMeeting(
        courseClass: updated,
        candidate: secondCandidate,
      );
      expect(updated2.meetings, hasLength(4));
      expect(updated2.meetings[2].id, startsWith('c1-makeup-'));
      expect(updated2.meetings.map((m) => m.number).toList(), [1, 2, 3, 4]);
    });
  });
}
