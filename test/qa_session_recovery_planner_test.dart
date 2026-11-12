import 'package:flutter_test/flutter_test.dart';

import 'package:fap_attendance/domain/models.dart';
import 'package:fap_attendance/domain/session_recovery_planner.dart';

TeacherWorkspace _sampleWorkspace() {
  final start = DateTime(2026, 11, 2, 7, 0); // Monday
  final class1 = CourseClass(
    id: 'c1',
    courseCode: 'PRM393',
    classCode: 'SE1901',
    scheduleCode: '11', // Group 1 (Mon/Thu), Slot 1 (7:00-9:15)
    students: const [
      Student(
        rollNumber: 'SE194673',
        email: 'duongthanhduy@fpt.edu.vn',
        fullName: 'Dương Thành Thanh Duy',
      ),
    ],
    scheduleRule: ScheduleRule(
      scheduleCode: '11',
      semesterStart: start,
      weeks: 2,
      meetingsPerWeek: 2,
      excludedDates: [DateTime(2026, 11, 5)], // Thursday holiday
    ),
    meetings: [
      Meeting(
        id: 'c1-m1',
        number: 1,
        startAt: DateTime(2026, 11, 2, 7, 0),
        endAt: DateTime(2026, 11, 2, 9, 15),
        state: MeetingState.closed,
      ),
      Meeting(
        id: 'c1-m2',
        number: 2,
        startAt: DateTime(2026, 11, 9, 7, 0),
        endAt: DateTime(2026, 11, 9, 9, 15),
        state: MeetingState.upcoming,
      ),
      Meeting(
        id: 'c1-m3',
        number: 3,
        startAt: DateTime(2026, 11, 12, 7, 0),
        endAt: DateTime(2026, 11, 12, 9, 15),
        state: MeetingState.upcoming,
      ),
    ],
    attendance: {
      'c1-m1': {
        'SE194673': AttendanceRecord(
          status: AttendanceStatus.present,
          source: AttendanceSource.manual,
          recordedAt: start,
        ),
      },
    },
  );

  final class2 = CourseClass(
    id: 'c2',
    courseCode: 'SWP391',
    classCode: 'SE1902',
    scheduleCode: '12', // Group 1, Slot 2 (9:30-11:45)
    students: const [],
    scheduleRule: ScheduleRule(scheduleCode: '12', semesterStart: start),
    meetings: [
      Meeting(
        id: 'c2-m1',
        number: 1,
        startAt: DateTime(2026, 11, 2, 9, 30),
        endAt: DateTime(2026, 11, 2, 11, 45),
        state: MeetingState.closed,
      ),
    ],
  );

  return TeacherWorkspace(
    id: 'w1',
    semester: 'FA26',
    semesterStart: start,
    classes: [class1, class2],
  );
}

void main() {
  const planner = SessionRecoveryPlanner();

  group('SessionRecoveryPlanner - Slot Suggestion & Conflict Avoidance', () {
    test('should suggest conflict-free makeup slots skipping Sundays, holidays, and other class meetings', () {
      // Arrange
      final workspace = _sampleWorkspace();

      // Act
      final candidates = planner.suggestMakeupSlots(
        workspace: workspace,
        classId: 'c1',
        searchFrom: DateTime(2026, 11, 2, 7, 0),
        maxSuggestions: 5,
      );

      // Assert
      expect(candidates, hasLength(5));
      for (final candidate in candidates) {
        // Must never schedule on Sunday
        expect(candidate.date.weekday, isNot(equals(DateTime.sunday)));
        // Must skip excluded holiday 2026-11-05
        expect(
          candidate.date,
          isNot(equals(DateTime(2026, 11, 5))),
        );
        // Must not collide with c1-m1 (Nov 2, 7:00-9:15) or c2-m1 (Nov 2, 9:30-11:45)
        expect(
          candidate.startAt,
          isNot(equals(DateTime(2026, 11, 2, 7, 0))),
        );
        expect(
          candidate.startAt,
          isNot(equals(DateTime(2026, 11, 2, 9, 30))),
        );
      }
      // First available slot on Nov 2 should be Slot 3 (12:30-14:45)
      expect(candidates.first.startAt, equals(DateTime(2026, 11, 2, 12, 30)));
      expect(candidates.first.dailySlot, equals(3));
      expect(candidates.first.isPreferredWeekday, isTrue);
    });

    test('should compute shortfall count and recovery plan accurately', () {
      // Arrange: 2 weeks * 2 meetings = 4 expected, currently has 3 meetings (1 holiday missed)
      final workspace = _sampleWorkspace();

      // Act
      final plan = planner.buildRecoveryPlan(
        workspace: workspace,
        classId: 'c1',
        searchFrom: DateTime(2026, 11, 3, 7, 0),
      );

      // Assert
      expect(plan.targetMeetingCount, equals(4));
      expect(plan.currentMeetingCount, equals(3));
      expect(plan.shortfallCount, equals(1));
      expect(plan.needsMakeup, isTrue);
      expect(plan.recommendedCandidates, isNotEmpty);
      expect(plan.toJson()['shortfallCount'], equals(1));
    });

    test('should insert makeup meeting in chronological order, renumber meetings, and preserve attendance', () {
      // Arrange
      final workspace = _sampleWorkspace();
      final course = workspace.classes.first;
      final candidate = MakeupSlotCandidate(
        date: DateTime(2026, 11, 6), // Friday between m1 (Nov 2) and m2 (Nov 9)
        dailySlot: 1,
        startAt: DateTime(2026, 11, 6, 7, 0),
        endAt: DateTime(2026, 11, 6, 9, 15),
        isPreferredWeekday: false,
      );

      // Act
      final updated = planner.scheduleMakeupMeeting(
        courseClass: course,
        candidate: candidate,
        customMeetingId: 'c1-makeup-1',
      );

      // Assert
      expect(updated.meetings, hasLength(4));
      expect(updated.meetings.map((m) => m.id), equals([
        'c1-m1',
        'c1-makeup-1',
        'c1-m2',
        'c1-m3',
      ]));
      expect(updated.meetings.map((m) => m.number), equals([1, 2, 3, 4]));
      expect(
        updated.recordFor('c1-m1', 'SE194673')?.status,
        equals(AttendanceStatus.present),
        reason: 'Existing attendance record on c1-m1 must remain intact',
      );
    });

    test('should throw StateError or ArgumentError on invalid parameters or overlapping makeup slot', () {
      // Arrange
      final workspace = _sampleWorkspace();
      final course = workspace.classes.first;
      final collidingCandidate = MakeupSlotCandidate(
        date: DateTime(2026, 11, 2),
        dailySlot: 1,
        startAt: DateTime(2026, 11, 2, 7, 0),
        endAt: DateTime(2026, 11, 2, 9, 15),
        isPreferredWeekday: true,
      );

      // Act & Assert
      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: course,
          candidate: collidingCandidate,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => planner.suggestMakeupSlots(
          workspace: workspace,
          classId: 'unknown_class',
          searchFrom: DateTime(2026, 11, 2),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => planner.suggestMakeupSlots(
          workspace: workspace,
          classId: 'c1',
          searchFrom: DateTime(2026, 11, 2),
          maxSuggestions: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
      final validCandidate = MakeupSlotCandidate(
        date: DateTime(2026, 11, 6),
        dailySlot: 1,
        startAt: DateTime(2026, 11, 6, 7, 0),
        endAt: DateTime(2026, 11, 6, 9, 15),
        isPreferredWeekday: false,
      );
      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: course,
          candidate: validCandidate,
          customMeetingId: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => planner.scheduleMakeupMeeting(
          courseClass: course,
          candidate: validCandidate,
          customMeetingId: 'c1-m1', // Existing meeting ID
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
