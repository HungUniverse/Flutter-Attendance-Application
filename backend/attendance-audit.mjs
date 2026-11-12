import { normalizeRoster } from './roster-reconciliation.mjs';

/**
 * Inspect an attendance snapshot without mutating it. Input row indices are
 * zero-based. A valid duplicate is flagged and does not replace the first row.
 * Missing pairs are based only on valid rows that reference known IDs.
 */
export function auditAttendance(roster, sessionIds, records) {
  const students = normalizeRoster(roster);
  if (!Array.isArray(sessionIds)) throw new TypeError('sessionIds must be an array');
  const sessions = sessionIds.map((id) => {
    if (typeof id !== 'string' || !id.trim()) throw new TypeError('invalid session ID');
    return id.trim();
  });
  if (new Set(sessions).size !== sessions.length) throw new TypeError('duplicate session ID');
  if (!Array.isArray(records)) throw new TypeError('records must be an array');
  const studentIds = new Set(students.map((student) => student.id));
  const knownSessions = new Set(sessions);
  const seen = new Map();
  const issues = [];
  const validRecords = [];

  records.forEach((record, index) => {
    if (!record || typeof record !== 'object' || Array.isArray(record)) {
      issues.push({ index, code: 'invalid_record' });
      return;
    }
    const studentId = typeof record.studentId === 'string' ? record.studentId.trim() : '';
    const sessionId = typeof record.sessionId === 'string' ? record.sessionId.trim() : '';
    const rowIssues = [];
    if (!studentId) rowIssues.push('missing_student_id');
    else if (!studentIds.has(studentId)) rowIssues.push('unknown_student');
    if (!sessionId) rowIssues.push('missing_session_id');
    else if (!knownSessions.has(sessionId)) rowIssues.push('unknown_session');
    if (record.status !== 'present' && record.status !== 'absent') rowIssues.push('invalid_status');
    if (rowIssues.length) {
      for (const code of rowIssues) issues.push({ index, code });
      return;
    }
    const key = JSON.stringify([studentId, sessionId]);
    if (seen.has(key)) {
      issues.push({ index, code: 'duplicate', firstIndex: seen.get(key) });
      return;
    }
    seen.set(key, index);
    validRecords.push({ studentId, sessionId, status: record.status });
  });

  const missing = [];
  for (const sessionId of sessions) {
    for (const student of students) {
      if (!seen.has(JSON.stringify([student.id, sessionId]))) {
        missing.push({ studentId: student.id, sessionId });
      }
    }
  }
  return { validRecords, issues, missing };
}
