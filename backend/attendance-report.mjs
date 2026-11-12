import { normalizeRecords } from './attendance-analytics.mjs';
import { normalizeRoster } from './roster-reconciliation.mjs';

/** Build a roster-based attendance report in the supplied session order. */
export function buildAttendanceReport(roster, sessionIds, records) {
  const students = normalizeRoster(roster);
  if (!Array.isArray(sessionIds)) throw new TypeError('sessionIds must be an array');
  const sessions = sessionIds.map((id) => {
    if (typeof id !== 'string' || !id.trim()) throw new TypeError('invalid session ID');
    return id.trim();
  });
  if (new Set(sessions).size !== sessions.length) throw new TypeError('duplicate session ID');
  const studentIds = new Set(students.map((student) => student.id));
  const sessionSet = new Set(sessions);
  const byStudent = new Map(students.map((student) => [student.id, new Map()]));
  for (const record of normalizeRecords(records)) {
    if (!studentIds.has(record.studentId)) throw new TypeError(`unknown student: ${record.studentId}`);
    if (!sessionSet.has(record.sessionId)) throw new TypeError(`unknown session: ${record.sessionId}`);
    byStudent.get(record.studentId).set(record.sessionId, record.status);
  }
  return students.map((student) => {
    const statuses = sessions.map((sessionId) => ({
      sessionId,
      status: byStudent.get(student.id).get(sessionId) ?? 'missing',
    }));
    const present = statuses.filter((entry) => entry.status === 'present').length;
    const absent = statuses.filter((entry) => entry.status === 'absent').length;
    return {
      student,
      present,
      absent,
      missing: sessions.length - present - absent,
      attendanceRate: present + absent ? present / (present + absent) : null,
      sessions: statuses,
    };
  });
}
