import { compareAttendance } from './attendance-analytics.mjs';
import { compareRosters } from './roster-reconciliation.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from './attendance-snapshot.mjs';

/**
 * Compare validated snapshots. Session order is significant: reordered is true
 * when sessions present in both snapshots change relative order. Additions and
 * deletions alone do not count as reordering.
 */
export function compareAttendanceSnapshots(previous, current) {
  const before = parseAttendanceSnapshot(serializeAttendanceSnapshot(previous));
  const after = parseAttendanceSnapshot(serializeAttendanceSnapshot(current));
  const oldSet = new Set(before.sessionIds);
  const newSet = new Set(after.sessionIds);
  const oldCommon = before.sessionIds.filter((id) => newSet.has(id));
  const newCommon = after.sessionIds.filter((id) => oldSet.has(id));
  return {
    roster: compareRosters(before.roster, after.roster),
    sessions: {
      added: after.sessionIds.filter((id) => !oldSet.has(id)),
      removed: before.sessionIds.filter((id) => !newSet.has(id)),
      reordered: oldCommon.some((id, index) => id !== newCommon[index]),
      previousOrder: before.sessionIds,
      currentOrder: after.sessionIds,
    },
    attendance: compareAttendance(before.records, after.records),
  };
}

/** Check whether a comparison contains any semantic or session-order change. */
export function hasSnapshotChanges(comparison) {
  if (!comparison || !comparison.roster || !comparison.sessions || !comparison.attendance) {
    throw new TypeError('invalid snapshot comparison');
  }
  const collections = [comparison.roster.added, comparison.roster.removed, comparison.roster.changed,
    comparison.sessions.added, comparison.sessions.removed, comparison.attendance.added,
    comparison.attendance.removed, comparison.attendance.changed];
  if (collections.some((items) => !Array.isArray(items)) || typeof comparison.sessions.reordered !== 'boolean') {
    throw new TypeError('invalid snapshot comparison');
  }
  return comparison.sessions.reordered || collections.some((items) => items.length > 0);
}
