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
  const sessionSet = new Set(sessions);
  const byStudent = new Map(students.map((student) => [student.id, new Map()]));
  for (const record of normalizeRecords(records)) {
    const statuses = byStudent.get(record.studentId);
    if (!statuses) throw new TypeError(`unknown student: ${record.studentId}`);
    if (!sessionSet.has(record.sessionId)) throw new TypeError(`unknown session: ${record.sessionId}`);
    statuses.set(record.sessionId, record.status);
  }
  return students.map((student) => {
    const recorded = byStudent.get(student.id);
    let present = 0;
    let absent = 0;
    const statuses = sessions.map((sessionId) => {
      const status = recorded.get(sessionId) ?? 'missing';
      if (status === 'present') present++;
      if (status === 'absent') absent++;
      return { sessionId, status };
    });
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
