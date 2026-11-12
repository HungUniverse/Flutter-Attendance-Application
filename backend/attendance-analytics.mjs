// Standalone attendance analysis helpers. Nothing in the running server imports
// this module; callers supply their own data and decide how to use the results.
// A record is { studentId, sessionId, status }, with status present or absent.

const STATUSES = new Set(['present', 'absent']);

function requireId(value, name) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new TypeError(`${name} must be a non-empty string`);
  }
  return value.trim();
}

function validateRecord(record) {
  if (!record || typeof record !== 'object') throw new TypeError('record must be an object');
  const studentId = requireId(record.studentId, 'studentId');
  const sessionId = requireId(record.sessionId, 'sessionId');
  if (!STATUSES.has(record.status)) throw new TypeError('status must be present or absent');
  return { studentId, sessionId, status: record.status };
}

/** Validate records and return trimmed copies, rejecting duplicate student/session pairs. */
export function normalizeRecords(records) {
  if (!Array.isArray(records)) throw new TypeError('records must be an array');
  const seen = new Map();
  return records.map((item) => {
    const record = validateRecord(item);
    if (!seen.has(record.studentId)) seen.set(record.studentId, new Set());
    if (seen.get(record.studentId).has(record.sessionId)) {
      throw new TypeError(`duplicate attendance: ${record.studentId} / ${record.sessionId}`);
    }
    seen.get(record.studentId).add(record.sessionId);
    return record;
  });
}

/** Summarize counts and rate; a dataset with no records has a null rate. */
export function summarizeAttendance(records) {
  const normalized = normalizeRecords(records);
  const present = normalized.filter((record) => record.status === 'present').length;
  return { total: normalized.length, present, absent: normalized.length - present,
    attendanceRate: normalized.length ? present / normalized.length : null };
}

function group(records, key) {
  const groups = new Map();
  for (const record of normalizeRecords(records)) {
    if (!groups.has(record[key])) groups.set(record[key], []);
    groups.get(record[key]).push(record);
  }
  return groups;
}

/** Produce one summary per student, sorted by student ID. */
export function summarizeStudents(records) {
  return [...group(records, 'studentId')].map(([studentId, items]) =>
    ({ studentId, ...summarizeAttendance(items) }))
    .sort((a, b) => a.studentId.localeCompare(b.studentId));
}

/** Produce one summary per session, sorted by session ID. */
export function summarizeSessions(records) {
  return [...group(records, 'sessionId')].map(([sessionId, items]) =>
    ({ sessionId, ...summarizeAttendance(items) }))
    .sort((a, b) => a.sessionId.localeCompare(b.sessionId));
}

/** Find students whose recorded attendance rate is strictly below a threshold. */
export function findStudentsBelowRate(records, threshold) {
  if (!Number.isFinite(threshold) || threshold < 0 || threshold > 1) {
    throw new RangeError('threshold must be between 0 and 1');
  }
  return summarizeStudents(records).filter((item) => item.attendanceRate < threshold);
}

/** Find roster members without a recorded result for a particular session. */
export function findMissingStudents(records, roster, sessionId) {
  const target = requireId(sessionId, 'sessionId');
  if (!Array.isArray(roster)) throw new TypeError('roster must be an array');
  const ids = roster.map((id) => requireId(id, 'studentId'));
  if (new Set(ids).size !== ids.length) throw new TypeError('duplicate student in roster');
  const recorded = new Set(normalizeRecords(records)
    .filter((record) => record.sessionId === target).map((record) => record.studentId));
  return ids.filter((id) => !recorded.has(id));
}

/** Compare two snapshots without modifying either. */
export function compareAttendance(before, after) {
  const index = (records) => new Map(normalizeRecords(records).map((r) =>
    [JSON.stringify([r.studentId, r.sessionId]), r]));
  const oldRecords = index(before);
  const newRecords = index(after);
  const added = [], removed = [], changed = [];
  for (const [key, current] of newRecords) {
    const previous = oldRecords.get(key);
    if (!previous) added.push(current);
    else if (previous.status !== current.status) changed.push({ before: previous, after: current });
  }
  for (const [key, previous] of oldRecords) if (!newRecords.has(key)) removed.push(previous);
  return { added, removed, changed };
}

/** Count consecutive absences at the end of a caller-provided chronological session list. */
export function currentAbsenceStreak(records, studentId, chronologicalSessionIds) {
  const id = requireId(studentId, 'studentId');
  if (!Array.isArray(chronologicalSessionIds)) throw new TypeError('session IDs must be an array');
  const ids = chronologicalSessionIds.map((value) => requireId(value, 'sessionId'));
  if (new Set(ids).size !== ids.length) throw new TypeError('duplicate session ID');
  const statuses = new Map(normalizeRecords(records).filter((r) => r.studentId === id)
    .map((r) => [r.sessionId, r.status]));
  let count = 0;
  for (let i = ids.length - 1; i >= 0 && statuses.get(ids[i]) === 'absent'; i--) count++;
  return count;
}

/** Calculate the minimum remaining sessions needed to reach a target rate. */
export function sessionsNeededForRate(present, total, target) {
  if (!Number.isInteger(present) || !Number.isInteger(total) || present < 0 || total < present) {
    throw new RangeError('counts must be non-negative integers and present cannot exceed total');
  }
  if (!Number.isFinite(target) || target < 0 || target > 1) throw new RangeError('invalid target');
  if (total > 0 && present / total >= target) return 0;
  if (target === 1) return total === present ? (total === 0 ? 1 : 0) : null;
  return Math.max(total === 0 ? 1 : 0, Math.ceil((target * total - present) / (1 - target)));
}

/** Export records as RFC 4180-style CSV, with spreadsheet formula injection escaped. */
export function attendanceToCsv(records) {
  const escape = (value) => {
    const safe = /^[\t\r\n ]*[=+\-@]/.test(value) ? `'${value}` : value;
    return `"${safe.replaceAll('"', '""')}"`;
  };
  const lines = normalizeRecords(records).map((record) =>
    [record.studentId, record.sessionId, record.status].map(escape).join(','));
  return ['studentId,sessionId,status', ...lines].join('\r\n');
}
