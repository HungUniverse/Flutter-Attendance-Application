import { parseAttendanceSnapshot, serializeAttendanceSnapshot, createAttendanceSnapshot } from './attendance-snapshot.mjs';

const validStatuses = new Set([null, 'present', 'absent']);

/**
 * Apply a batch to an in-memory snapshot. Each change supplies the expected
 * current status (null means no record) and the desired status (null deletes).
 * A mismatch returns every conflict and no snapshot. The caller must perform
 * its own atomic persistence if multiple processes share stored data.
 */
export function applyAttendanceBatch(snapshot, changes) {
  const input = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshot));
  if (!Array.isArray(changes)) throw new TypeError('changes must be an array');
  const students = new Set(input.roster.map((student) => student.id));
  const sessions = new Set(input.sessionIds);
  const indexed = new Map(input.records.map((record) => [
    JSON.stringify([record.studentId, record.sessionId]), record,
  ]));
  const seen = new Set();
  const prepared = changes.map((change, index) => {
    if (!change || typeof change !== 'object' || Array.isArray(change) ||
        typeof change.studentId !== 'string' || typeof change.sessionId !== 'string') {
      throw new TypeError(`invalid change at index ${index}`);
    }
    const studentId = change.studentId.trim();
    const sessionId = change.sessionId.trim();
    if (!students.has(studentId)) throw new TypeError(`unknown student at index ${index}`);
    if (!sessions.has(sessionId)) throw new TypeError(`unknown session at index ${index}`);
    if (!validStatuses.has(change.expected) || !validStatuses.has(change.status)) {
      throw new TypeError(`invalid status at index ${index}`);
    }
    const key = JSON.stringify([studentId, sessionId]);
    if (seen.has(key)) throw new TypeError(`duplicate change at index ${index}`);
    seen.add(key);
    return { index, key, studentId, sessionId, expected: change.expected, status: change.status };
  });

  const conflicts = [];
  for (const change of prepared) {
    const actual = indexed.get(change.key)?.status ?? null;
    if (actual !== change.expected) {
      conflicts.push({ index: change.index, studentId: change.studentId, sessionId: change.sessionId,
        expected: change.expected, actual });
    }
  }
  if (conflicts.length) return { snapshot: null, conflicts };
  for (const change of prepared) {
    if (change.status === null) indexed.delete(change.key);
    else indexed.set(change.key, { studentId: change.studentId, sessionId: change.sessionId, status: change.status });
  }
  return { snapshot: createAttendanceSnapshot(input.roster, input.sessionIds, [...indexed.values()]), conflicts: [] };
}
