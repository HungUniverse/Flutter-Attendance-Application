import { normalizeRecords } from './attendance-analytics.mjs';

function indexRecords(records) {
  return new Map(normalizeRecords(records).map((record) => [
    JSON.stringify([record.studentId, record.sessionId]), record,
  ]));
}

/**
 * Compare two edited snapshots against a common base. Missing records represent
 * deletion. Conflicting records are excluded from the merged result so callers
 * can resolve them deliberately before treating the result as complete.
 */
export function mergeAttendance(base, left, right) {
  const before = indexRecords(base);
  const first = indexRecords(left);
  const second = indexRecords(right);
  const keys = new Set([...before.keys(), ...first.keys(), ...second.keys()]);
  const records = [];
  const conflicts = [];
  for (const key of keys) {
    const original = before.get(key) ?? null;
    const leftRecord = first.get(key) ?? null;
    const rightRecord = second.get(key) ?? null;
    const originalStatus = original?.status ?? null;
    const leftStatus = leftRecord?.status ?? null;
    const rightStatus = rightRecord?.status ?? null;
    let selected;
    if (leftStatus === rightStatus) selected = leftRecord;
    else if (leftStatus === originalStatus) selected = rightRecord;
    else if (rightStatus === originalStatus) selected = leftRecord;
    else {
      const [studentId, sessionId] = JSON.parse(key);
      conflicts.push({ studentId, sessionId, base: original, left: leftRecord, right: rightRecord });
      continue;
    }
    if (selected) records.push(selected);
  }
  return { records, conflicts };
}

/** Resolve every conflict by choosing base, left, or right, including deletion. */
export function resolveAttendanceConflicts(result, choices) {
  if (!result || !Array.isArray(result.conflicts)) throw new TypeError('invalid merge result');
  if (!Array.isArray(choices)) throw new TypeError('choices must be an array');
  const records = normalizeRecords(result.records);
  const existing = new Set(records.map((record) => JSON.stringify([record.studentId, record.sessionId])));
  const resolutionMap = new Map();
  for (const choice of choices) {
    if (!choice || typeof choice.studentId !== 'string' || typeof choice.sessionId !== 'string' ||
        !['base', 'left', 'right'].includes(choice.source)) {
      throw new TypeError('invalid conflict choice');
    }
    const key = JSON.stringify([choice.studentId, choice.sessionId]);
    if (resolutionMap.has(key)) throw new TypeError('duplicate conflict choice');
    resolutionMap.set(key, choice.source);
  }
  for (const conflict of result.conflicts) {
    const key = JSON.stringify([conflict.studentId, conflict.sessionId]);
    if (existing.has(key)) throw new TypeError('duplicate conflict');
    existing.add(key);
    if (!resolutionMap.has(key)) throw new TypeError('missing conflict choice');
    const selected = conflict[resolutionMap.get(key)];
    if (selected !== null) {
      const [record] = normalizeRecords([selected]);
      if (record.studentId !== conflict.studentId || record.sessionId !== conflict.sessionId) {
        throw new TypeError('conflict record does not match its key');
      }
      records.push(record);
    }
    resolutionMap.delete(key);
  }
  if (resolutionMap.size) throw new TypeError('choice does not match a conflict');
  return records;
}
