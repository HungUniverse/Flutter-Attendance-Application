import { auditAttendance } from './attendance-audit.mjs';
import { normalizeRoster } from './roster-reconciliation.mjs';

/**
 * Summarize coverage after validating the snapshot. Invalid and duplicate rows
 * remain visible as issues and never count towards recorded attendance.
 */
export function attendanceQualityReport(roster, sessionIds, records) {
  const audit = auditAttendance(roster, sessionIds, records);
  const students = normalizeRoster(roster);
  const sessions = sessionIds.map((id) => id.trim());
  const perStudent = new Map(students.map((student) => [student.id, {
    student, present: 0, absent: 0, missingSessionIds: [],
  }]));
  const perSession = new Map(sessions.map((sessionId) => [sessionId, {
    sessionId, present: 0, absent: 0, missingStudentIds: [],
  }]));
  for (const record of audit.validRecords) {
    perStudent.get(record.studentId)[record.status]++;
    perSession.get(record.sessionId)[record.status]++;
  }
  for (const pair of audit.missing) {
    perStudent.get(pair.studentId).missingSessionIds.push(pair.sessionId);
    perSession.get(pair.sessionId).missingStudentIds.push(pair.studentId);
  }
  const expected = students.length * sessions.length;
  const recorded = audit.validRecords.length;
  return {
    expected,
    recorded,
    missing: audit.missing.length,
    coverage: expected ? recorded / expected : null,
    issues: audit.issues,
    students: [...perStudent.values()],
    sessions: [...perSession.values()],
  };
}

/** Select coverage gaps, preserving the original roster or session order. */
export function selectCoverageGaps(report, minimumMissing = 1) {
  if (!Number.isSafeInteger(minimumMissing) || minimumMissing < 1) {
    throw new RangeError('minimumMissing must be a positive safe integer');
  }
  if (!report || !Array.isArray(report.students) || !Array.isArray(report.sessions)) {
    throw new TypeError('invalid quality report');
  }
  return {
    students: report.students.filter((student) => student.missingSessionIds.length >= minimumMissing),
    sessions: report.sessions.filter((session) => session.missingStudentIds.length >= minimumMissing),
  };
}
