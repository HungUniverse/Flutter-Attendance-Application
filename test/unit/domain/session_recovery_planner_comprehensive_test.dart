import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/session_recovery_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SessionRecoveryPlanner planner;

  setUp(() {
    planner = const SessionRecoveryPlanner();
  });

  TeacherWorkspace buildWorkspace({
    List<Meeting>? meetings,
    List<DateTime> excludedDates = const [],
    List<CourseClass> extraClasses = const [],
  }) {
    final c1 = CourseClass(
      id: 'cls-1',
      courseCode: 'PRM392',
      classCode: 'SE1801',
      scheduleCode: '11',
      students: const [],
      scheduleRule: ScheduleRule(
        scheduleCode: '11',
        semesterStart: DateTime(2026, 9, 7),
        weeks: 2,
        meetingsPerWeek: 2,
        excludedDates: excludedDates,
      ),
      meetings: meetings ??
          [
            Meeting(
              id: 'cls-1-m1',
              number: 1,
              startAt: DateTime(2026, 9, 7, 7, 30),
              endAt: DateTime(2026, 9, 7, 9, 15),
            ),
            Meeting(
              id: 'cls-1-m2',
              number: 2,
              startAt: DateTime(2026, 9, 10, 7, 30),
              endAt: DateTime(2026, 9, 10, 9, 15),
            ),
          ],
    );
    return TeacherWorkspace(
      id: 'ws-1',
      semester: 'FA26',
      semesterStart: DateTime(2026, 9, 7),
      classes: [c1, ...extraClasses],
    );
  }

  group('suggestMakeupSlots', () {
    test('skips Sundays, excluded dates, past slots, and cross-class conflicts', () {
      // 2026-09-12 is Saturday, 2026-09-13 is Sunday, 2026-09-14 is Monday (excluded)
      final blockingClass = CourseClass(
        id: 'cls-2',
        courseCode: 'SWD392',
        classCode: 'SE1802',
        scheduleCode: '31',
        students: const [],
        scheduleRule: ScheduleRule(
          scheduleCode: '31',
          semesterStart: DateTime(2026, 9, 7),
        ),
        meetings: [
          Meeting(
            id: 'cls-2-m1',
            number: 1,
            startAt: DateTime(2026, 9, 12, 7, 30),
            endAt: DateTime(2026, 9, 12, 9, 15),
          ),
        ],
      );

      final ws = buildWorkspace(
        excludedDates: [DateTime(2026, 9, 14)],
        extraClasses: [blockingClass],
      );

      final candidates = planner.suggestMakeupSlots(
        workspace: ws,
        classId: 'cls-1',
        searchFrom: DateTime(2026, 9, 12, 7, 30),
        maxSuggestions: 4,
        searchWindowDays: 10,
      );

      expect(candidates, hasLength(4));
      // Slot 1 on 2026-09-12 is occupied by cls-2, so first free on 2026-09-12 is slot 2
      expect(candidates.first.date, DateTime(2026, 9, 12));
      expect(candidates.first.dailySlot, 2);
      expect(candidates.first.isPreferredWeekday, isFalse);

      for (final c in candidates) {
        expect(c.date.weekday, isNot(DateTime.sunday));
        expect(c.date, isNot(DateTime(2026, 9, 14)));
      }
      expect(candidates.first.toJson()['dailySlot'], 2);
    });

    test('validates maxSuggestions, searchWindowDays, and classId', () {
      final ws = buildWorkspace();
      expect(
        () => planner.suggestMakeupSlots(
          workspace: ws,
          classId: 'cls-1',
          searchFrom: DateTime(2026, 9, 12),
          maxSuggestions: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => planner.suggestMakeupSlots(
          workspace: ws,
          classId: 'cls-1',
          searchFrom: DateTime(2026, 9, 12),
          searchWindowDays: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => planner.suggestMakeupSlots(
          workspace: ws,
          classId: 'cls-1',
          searchFrom: DateTime(2026, 9, 12),
          searchWindowDays: 181,
        ),
        throwsArgumentError,
      );
      expect(
        () => planner.suggestMakeupSlots(
          workspace: ws,
          classId: 'missing',
          searchFrom: DateTime(2026, 9, 12),
        ),
        throwsStateError,
      );
    });
  });

  group('buildRecoveryPlan', () {
    test('detects shortfall and recommends candidates', () {
      final ws = buildWorkspace(); // target = 2 * 2 = 4, current = 2 -> shortfall 2
      final plan = planner.buildRecoveryPlan(
        workspace: ws,
        classId: 'cls-1',
        searchFrom: DateTime(2026, 9, 14, 7, 0),
      );

      expect(plan.needsMakeup, isTrue);
      expect(plan.targetMeetingCount, 4);
      expect(plan.currentMeetingCount, 2);
      expect(plan.shortfallCount, 2);
      expect(plan.recommendedCandidates, hasLength(4));

      final json = plan.toJson();
      expect(json['needsMakeup'], isTrue);
      expect(json['shortfallCount'], 2);
    });

    test('returns needsMakeup false when target already met', () {
      final ws = buildWorkspace();
      final plan = planner.buildRecoveryPlan(
        workspace: ws,
        classId: 'cls-1',
        searchFrom: DateTime(2026, 9, 14),
        targetMeetingCount: 2,
      );
      expect(plan.needsMakeup, isFalse);
      expect(plan.shortfallCount, 0);
      expect(plan.recommendedCandidates, isEmpty);
    });
  });

  group('scheduleMakeupMeeting', () {
    test('inserts makeup meeting in chronological order and renumbers meetings', () {
      final ws = buildWorkspace();
      final cls = ws.classes.first;
      // Insert between m1 (Sep 7) and m2 (Sep 10) -> Sep 8
      final candidate = MakeupSlotCandidate(
        date: DateTime(2026, 9, 8),
        dailySlot: 1,
        startAt: DateTime(2026, 9, 8, 7, 30),
        endAt: DateTime(2026, 9, 8, 9, 15),
        isPreferredWeekday: false,
      );

      final updated = planner.scheduleMakeupMeeting(
        courseClass: cls,
        candidate: candidate,
        customMeetingId: 'cls-1-makeup-a',
      );
      expect(updated.meetings, hasLength(3));
      expect(updated.meetings[0].id, 'cls-1-m1');
      expect(updated.meetings[0].number, 1);
      expect(updated.meetings[1].id, 'cls-1-makeup-a');
      expect(updated.meetings[1].number, 2);
      expect(updated.meetings[2].id, 'cls-1-m2');
      expect(updated.meetings[2].number, 3);
    });

    test('throws on blank customMeetingId, overlapping time, or duplicate meeting id', () {
      final cls = buildWorkspace().classes.first;
      final freeCandidate = MakeupSlotCandidate(
        date: DateTime(2026, 9, 8),
        dailySlot: 1,
        startAt: DateTime(2026, 9, 8, 7, 30),
        endAt: DateTime(2026, 9, 8, 9, 15),
        isPreferredWeekday: false,
      );
      final overlappingCandidate = MakeupSlotCandidate(
        date: DateTime(2026, 9, 7),
        dailySlot: 1,
        startAt: DateTime(2026, 9, 7, 8, 0),
        endAt: DateTime(2026, 9, 7, 9, 45),
        isPreferredWeekday: true,
      );

      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: cls,
          candidate: freeCandidate,
          customMeetingId: '   ',
        ),
        throwsArgumentError,
      );
      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: cls,
          candidate: overlappingCandidate,
        ),
        throwsStateError,
      );
      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: cls,
          candidate: freeCandidate,
          customMeetingId: 'cls-1-m1',
        ),
        throwsStateError,
      );
    });
  });
}
