import 'models.dart';

enum ConflictResolutionStrategy {
  preferTeacherManual,
  preferPresent,
  preferBase,
  preferIncoming,
}

class AttendanceCellDiff {
  const AttendanceCellDiff({
    required this.meetingId,
    required this.rollNumber,
    required this.oldStatus,
    required this.newStatus,
    this.oldSource,
    this.newSource,
    this.oldNote,
    this.newNote,
    required this.isConflict,
  });

  final String meetingId;
  final String rollNumber;
  final AttendanceStatus oldStatus;
  final AttendanceStatus newStatus;
  final AttendanceSource? oldSource;
  final AttendanceSource? newSource;
  final String? oldNote;
  final String? newNote;
  final bool isConflict;

  Map<String, Object?> toJson() => {
    'meetingId': meetingId,
    'rollNumber': rollNumber,
    'oldStatus': attendanceCode(oldStatus),
    'newStatus': attendanceCode(newStatus),
    if (oldSource != null) 'oldSource': oldSource!.name,
    if (newSource != null) 'newSource': newSource!.name,
    if (oldNote != null) 'oldNote': oldNote,
    if (newNote != null) 'newNote': newNote,
    'isConflict': isConflict,
  };
}

class ClassReconciliationDiff {
  const ClassReconciliationDiff({
    required this.classId,
    required this.addedStudents,
    required this.removedStudents,
    required this.cellDiffs,
  });

  final String classId;
  final List<Student> addedStudents;
  final List<Student> removedStudents;
  final List<AttendanceCellDiff> cellDiffs;

  bool get hasChanges =>
      addedStudents.isNotEmpty ||
      removedStudents.isNotEmpty ||
      cellDiffs.isNotEmpty;

  int get conflictCount => cellDiffs.where((d) => d.isConflict).length;

  Map<String, Object?> toJson() => {
    'classId': classId,
    'hasChanges': hasChanges,
    'conflictCount': conflictCount,
    'addedStudents': addedStudents.map((s) => s.toJson()).toList(),
    'removedStudents': removedStudents.map((s) => s.toJson()).toList(),
    'cellDiffs': cellDiffs.map((d) => d.toJson()).toList(),
  };
}

class ReconciliationMergeOutcome {
  const ReconciliationMergeOutcome({
    required this.mergedClass,
    required this.diff,
    required this.appliedChanges,
    required this.resolvedConflicts,
  });

  final CourseClass mergedClass;
  final ClassReconciliationDiff diff;
  final int appliedChanges;
  final int resolvedConflicts;
}

class AttendanceReconciliationService {
  const AttendanceReconciliationService();

  ClassReconciliationDiff diffClasses(
    CourseClass base,
    CourseClass incoming,
  ) {
    final baseStudentsByRoll = {
      for (final student in base.students)
        student.rollNumber.trim().toUpperCase(): student,
    };
    final incomingStudentsByRoll = {
      for (final student in incoming.students)
        student.rollNumber.trim().toUpperCase(): student,
    };

    final addedStudents = <Student>[
      for (final entry in incomingStudentsByRoll.entries)
        if (!baseStudentsByRoll.containsKey(entry.key)) entry.value,
    ];
    final removedStudents = <Student>[
      for (final entry in baseStudentsByRoll.entries)
        if (!incomingStudentsByRoll.containsKey(entry.key)) entry.value,
    ];

    final allMeetingIds = <String>{
      ...base.meetings.map((m) => m.id),
      ...incoming.meetings.map((m) => m.id),
    }.toList()..sort();

    final allRolls = <String>{
      ...baseStudentsByRoll.keys,
      ...incomingStudentsByRoll.keys,
    }.toList()..sort();

    final cellDiffs = <AttendanceCellDiff>[];

    for (final meetingId in allMeetingIds) {
      final baseMeetingRecords = base.attendance[meetingId] ?? const {};
      final incomingMeetingRecords = incoming.attendance[meetingId] ?? const {};

      for (final upperRoll in allRolls) {
        final canonicalRoll =
            incomingStudentsByRoll[upperRoll]?.rollNumber ??
            baseStudentsByRoll[upperRoll]!.rollNumber;
        final oldRec = _lookupCaseInsensitive(baseMeetingRecords, canonicalRoll);
        final newRec = _lookupCaseInsensitive(
          incomingMeetingRecords,
          canonicalRoll,
        );

        final oldStatus = oldRec?.status ?? AttendanceStatus.unmarked;
        final newStatus = newRec?.status ?? AttendanceStatus.unmarked;

        if (oldStatus == newStatus && (oldRec?.note ?? '') == (newRec?.note ?? '')) {
          continue;
        }

        final isConflict =
            oldStatus != AttendanceStatus.unmarked &&
            newStatus != AttendanceStatus.unmarked &&
            oldStatus != newStatus;

        cellDiffs.add(
          AttendanceCellDiff(
            meetingId: meetingId,
            rollNumber: canonicalRoll,
            oldStatus: oldStatus,
            newStatus: newStatus,
            oldSource: oldRec?.source,
            newSource: newRec?.source,
            oldNote: oldRec?.note,
            newNote: newRec?.note,
            isConflict: isConflict,
          ),
        );
      }
    }

    return ClassReconciliationDiff(
      classId: base.id,
      addedStudents: addedStudents,
      removedStudents: removedStudents,
      cellDiffs: cellDiffs,
    );
  }

  ReconciliationMergeOutcome reconcile({
    required CourseClass base,
    required CourseClass incoming,
    ConflictResolutionStrategy strategy =
        ConflictResolutionStrategy.preferTeacherManual,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final diff = diffClasses(base, incoming);

    final mergedStudents = <Student>[...base.students];
    final existingRolls = {
      for (final s in base.students) s.rollNumber.trim().toUpperCase(),
    };
    for (final added in diff.addedStudents) {
      if (existingRolls.add(added.rollNumber.trim().toUpperCase())) {
        mergedStudents.add(added);
      }
    }

    final mergedAttendance = <String, Map<String, AttendanceRecord>>{
      for (final entry in base.attendance.entries)
        entry.key: Map<String, AttendanceRecord>.of(entry.value),
    };

    final mergedAudit = <AuditEvent>[...base.auditEvents];
    var appliedChanges = 0;
    var resolvedConflicts = 0;

    for (final cell in diff.cellDiffs) {
      final baseRec = _lookupCaseInsensitive(
        base.attendance[cell.meetingId] ?? const {},
        cell.rollNumber,
      );
      final incomingRec = _lookupCaseInsensitive(
        incoming.attendance[cell.meetingId] ?? const {},
        cell.rollNumber,
      );

      if (incomingRec == null ||
          incomingRec.status == AttendanceStatus.unmarked) {
        continue;
      }

      if (baseRec == null || baseRec.status == AttendanceStatus.unmarked) {
        mergedAttendance.putIfAbsent(cell.meetingId, () => {})[cell.rollNumber] =
            incomingRec;
        appliedChanges++;
        continue;
      }

      if (!cell.isConflict) {
        if ((incomingRec.note ?? '').isNotEmpty &&
            (baseRec.note ?? '') != incomingRec.note) {
          mergedAttendance.putIfAbsent(
            cell.meetingId,
            () => {},
          )[cell.rollNumber] = incomingRec;
          appliedChanges++;
        }
        continue;
      }

      resolvedConflicts++;
      final chooseIncoming = _shouldChooseIncoming(
        baseRec: baseRec,
        incomingRec: incomingRec,
        strategy: strategy,
      );

      if (chooseIncoming) {
        mergedAttendance.putIfAbsent(
          cell.meetingId,
          () => {},
        )[cell.rollNumber] = incomingRec;
        appliedChanges++;
        mergedAudit.add(
          AuditEvent(
            id: 'reconcile_${cell.meetingId}_${cell.rollNumber}_${timestamp.millisecondsSinceEpoch}',
            createdAt: timestamp,
            action: 'reconcile_conflict',
            reason:
                incomingRec.note ??
                'Đồng bộ điểm danh theo chiến lược ${strategy.name}.',
            rollNumber: cell.rollNumber,
            meetingId: cell.meetingId,
            oldValue: attendanceCode(baseRec.status),
            newValue: attendanceCode(incomingRec.status),
          ),
        );
      }
    }

    return ReconciliationMergeOutcome(
      mergedClass: base.copyWith(
        students: mergedStudents,
        attendance: mergedAttendance,
        auditEvents: mergedAudit,
      ),
      diff: diff,
      appliedChanges: appliedChanges,
      resolvedConflicts: resolvedConflicts,
    );
  }

  bool _shouldChooseIncoming({
    required AttendanceRecord baseRec,
    required AttendanceRecord incomingRec,
    required ConflictResolutionStrategy strategy,
  }) {
    switch (strategy) {
      case ConflictResolutionStrategy.preferBase:
        return false;
      case ConflictResolutionStrategy.preferIncoming:
        return true;
      case ConflictResolutionStrategy.preferPresent:
        return incomingRec.status == AttendanceStatus.present &&
            baseRec.status != AttendanceStatus.present;
      case ConflictResolutionStrategy.preferTeacherManual:
        final baseIsManual =
            baseRec.source == AttendanceSource.manual ||
            (baseRec.note != null && baseRec.note!.trim().isNotEmpty);
        final incomingIsManual =
            incomingRec.source == AttendanceSource.manual ||
            (incomingRec.note != null && incomingRec.note!.trim().isNotEmpty);
        if (baseIsManual && !incomingIsManual) return false;
        if (incomingIsManual && !baseIsManual) return true;
        return incomingRec.recordedAt.isAfter(baseRec.recordedAt);
    }
  }

  AttendanceRecord? _lookupCaseInsensitive(
    Map<String, AttendanceRecord> records,
    String rollNumber,
  ) {
    final direct = records[rollNumber];
    if (direct != null) return direct;
    final target = rollNumber.trim().toUpperCase();
    for (final entry in records.entries) {
      if (entry.key.trim().toUpperCase() == target) {
        return entry.value;
      }
    }
    return null;
  }
}
