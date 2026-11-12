import 'models.dart';

class RosterMergeResult {
  const RosterMergeResult({
    required this.classes,
    required this.addedClasses,
    required this.updatedClasses,
    required this.addedStudents,
    required this.retainedStudents,
  });

  final List<CourseClass> classes;
  final int addedClasses;
  final int updatedClasses;
  final int addedStudents;
  final int retainedStudents;
}

class RosterMergeService {
  RosterMergeResult merge({
    required List<CourseClass> existing,
    required List<CourseClass> imported,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final existingByKey = {
      for (final courseClass in existing) _classKey(courseClass): courseClass,
    };
    final importedKeys = imported.map(_classKey).toSet();
    var addedClasses = 0;
    var updatedClasses = 0;
    var addedStudents = 0;
    var retainedStudents = 0;
    final classes = <CourseClass>[];

    for (final incoming in imported) {
      final previous = existingByKey[_classKey(incoming)];
      if (previous == null) {
        classes.add(incoming);
        addedClasses++;
        addedStudents += incoming.students.length;
        continue;
      }
      final merged = _mergeClass(previous, incoming, current);
      classes.add(merged.courseClass);
      updatedClasses++;
      addedStudents += merged.addedStudents;
      retainedStudents += merged.retainedStudents;
    }

    for (final previous in existing) {
      if (!importedKeys.contains(_classKey(previous))) {
        classes.add(previous);
      }
    }

    return RosterMergeResult(
      classes: classes,
      addedClasses: addedClasses,
      updatedClasses: updatedClasses,
      addedStudents: addedStudents,
      retainedStudents: retainedStudents,
    );
  }

  _MergedClass _mergeClass(
    CourseClass previous,
    CourseClass incoming,
    DateTime now,
  ) {
    final oldByRoll = {
      for (final student in previous.students)
        student.rollNumber.trim().toUpperCase(): student,
    };
    final oldByEmail = {
      for (final student in previous.students) student.normalizedEmail: student,
    };
    final consumedOldRolls = <String>{};
    final seenIncomingRolls = <String>{};
    final mergedStudents = <Student>[];
    final rollRenames = <String, String>{};
    var addedStudents = 0;

    for (final student in incoming.students) {
      final incomingRollUpper = student.rollNumber.trim().toUpperCase();
      if (!seenIncomingRolls.add(incomingRollUpper)) continue;
      final matched =
          oldByRoll[incomingRollUpper] ??
          oldByEmail[student.normalizedEmail];
      if (matched == null) {
        mergedStudents.add(student);
        addedStudents++;
        continue;
      }
      consumedOldRolls.add(matched.rollNumber.trim().toUpperCase());
      mergedStudents.add(student);
      if (matched.rollNumber != student.rollNumber) {
        rollRenames[matched.rollNumber] = student.rollNumber;
      }
    }

    final retained = previous.students
        .where(
          (student) => !consumedOldRolls.contains(
            student.rollNumber.trim().toUpperCase(),
          ),
        )
        .toList();
    mergedStudents.addAll(retained);

    final canonicalRollByUpper = {
      for (final student in mergedStudents)
        student.rollNumber.trim().toUpperCase(): student.rollNumber,
    };
    final attendance = previous.attendance.map(
      (meetingId, records) => MapEntry(meetingId, Map.of(records)),
    );
    for (final records in attendance.values) {
      for (final rename in rollRenames.entries) {
        final renameUpper = rename.key.trim().toUpperCase();
        AttendanceRecord? migratedRecord = records.remove(rename.key);
        final variantKeys = records.keys
            .where((k) => k.trim().toUpperCase() == renameUpper)
            .toList();
        for (final key in variantKeys) {
          migratedRecord ??= records.remove(key);
        }
        if (migratedRecord != null) {
          records.putIfAbsent(rename.value, () => migratedRecord!);
        }
      }
      final caseVariants = records.keys
          .where((k) {
            final canonical = canonicalRollByUpper[k.trim().toUpperCase()];
            return canonical != null && canonical != k;
          })
          .toList();
      for (final key in caseVariants) {
        final canonical = canonicalRollByUpper[key.trim().toUpperCase()]!;
        final record = records.remove(key);
        if (record != null) {
          records.putIfAbsent(canonical, () => record);
        }
      }
    }

    for (final meeting in previous.meetings) {
      if (meeting.state != MeetingState.closed) continue;
      final records = attendance.putIfAbsent(meeting.id, () => {});
      for (final student in mergedStudents) {
        records.putIfAbsent(
          student.rollNumber,
          () => AttendanceRecord(
            status: AttendanceStatus.absent,
            source: AttendanceSource.finalize,
            recordedAt: now,
            note: 'Tự động bổ sung khi cập nhật danh sách lớp.',
          ),
        );
      }
    }

    return _MergedClass(
      courseClass: previous.copyWith(
        students: mergedStudents,
        attendance: attendance,
      ),
      addedStudents: addedStudents,
      retainedStudents: retained.length,
    );
  }

  String _classKey(CourseClass courseClass) =>
      '${courseClass.courseCode.trim().toUpperCase()}|${courseClass.classCode.trim().toUpperCase()}';
}

class _MergedClass {
  const _MergedClass({
    required this.courseClass,
    required this.addedStudents,
    required this.retainedStudents,
  });

  final CourseClass courseClass;
  final int addedStudents;
  final int retainedStudents;
}
