import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot }
  from '../../backend/attendance-snapshot.mjs';
import { normalizeRoster } from '../../backend/roster-reconciliation.mjs';

/**
 * Replace a roster or ordered session list in an independent snapshot. Records
 * that would become orphaned require an explicit dropRecords option.
 */
export function reviseSnapshot(snapshot, { roster, sessionIds, dropRecords = false } = {}) {
  if (typeof dropRecords !== 'boolean') throw new TypeError('dropRecords must be a boolean');
  const original = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshot));
  const nextRoster = roster === undefined ? original.roster : normalizeRoster(roster);
  const nextSessions = sessionIds === undefined ? original.sessionIds : sessionIds;
  // Validate references separately against the new roster and session order.
  const empty = createAttendanceSnapshot(nextRoster, nextSessions, []);
  const studentIds = new Set(empty.roster.map((student) => student.id));
  const knownSessions = new Set(empty.sessionIds);
  const kept = [];
  const removed = [];
  for (const record of original.records) {
    if (studentIds.has(record.studentId) && knownSessions.has(record.sessionId)) kept.push(record);
    else removed.push(record);
  }
  if (removed.length && !dropRecords) {
    throw new Error(`revision would remove ${removed.length} attendance record(s); use --drop-records to allow it`);
  }
  return { snapshot: createAttendanceSnapshot(empty.roster, empty.sessionIds, kept), removed };
}
