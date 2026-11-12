import { normalizeRecords } from './attendance-analytics.mjs';
import { buildAttendanceReport } from './attendance-report.mjs';
import { normalizeRoster } from './roster-reconciliation.mjs';

const FORMAT = 'attendance-snapshot';
const VERSION = 1;

/**
 * Create an independent, validated snapshot from caller-owned data. Session
 * ordering is retained because consumers may use it as chronological order.
 * The caller is responsible for storage and for recording creation time.
 */
export function createAttendanceSnapshot(roster, sessionIds, records) {
  const students = normalizeRoster(roster);
  const attendance = normalizeRecords(records);
  // This also validates session IDs and all references, including with an empty roster.
  buildAttendanceReport(students, sessionIds, attendance);
  return {
    format: FORMAT,
    version: VERSION,
    roster: students,
    sessionIds: sessionIds.map((id) => id.trim()),
    records: attendance,
  };
}

/** Serialize a validated snapshot. No file access occurs in this module. */
export function serializeAttendanceSnapshot(snapshot) {
  return JSON.stringify(validateSnapshot(snapshot), null, 2);
}

function validateSnapshot(snapshot) {
  if (!snapshot || typeof snapshot !== 'object' || Array.isArray(snapshot)) {
    throw new TypeError('snapshot must be an object');
  }
  if (snapshot.format !== FORMAT) throw new TypeError('unrecognized snapshot format');
  if (snapshot.version !== VERSION) throw new TypeError('unsupported snapshot version');
  return createAttendanceSnapshot(snapshot.roster, snapshot.sessionIds, snapshot.records);
}

/** Parse and validate snapshot JSON before returning fresh normalized data. */
export function parseAttendanceSnapshot(text) {
  if (typeof text !== 'string') throw new TypeError('snapshot JSON must be a string');
  return validateSnapshot(JSON.parse(text));
}

/**
 * Select a subset by ID. Requested order controls the result and all IDs must
 * exist in the original snapshot. Omitted filters retain the whole dimension.
 */
export function selectAttendanceSnapshot(snapshot, filters = {}) {
  const input = validateSnapshot(snapshot);
  if (!filters || typeof filters !== 'object' || Array.isArray(filters)) {
    throw new TypeError('filters must be an object');
  }
  function selectIds(requested, available, name) {
    if (requested === undefined) return available;
    if (!Array.isArray(requested)) throw new TypeError(`${name} must be an array`);
    const known = new Set(available);
    const selected = requested.map((id) => {
      if (typeof id !== 'string' || !id.trim()) throw new TypeError(`invalid ${name} ID`);
      const value = id.trim();
      if (!known.has(value)) throw new TypeError(`unknown ${name} ID: ${value}`);
      return value;
    });
    if (new Set(selected).size !== selected.length) throw new TypeError(`duplicate ${name} ID`);
    return selected;
  }
  const studentIds = selectIds(filters.studentIds, input.roster.map((student) => student.id), 'student');
  const sessionIds = selectIds(filters.sessionIds, input.sessionIds, 'session');
  const byStudent = new Map(input.roster.map((student) => [student.id, student]));
  const studentSet = new Set(studentIds);
  const sessionSet = new Set(sessionIds);
  return createAttendanceSnapshot(
    studentIds.map((id) => byStudent.get(id)),
    sessionIds,
    input.records.filter((record) => studentSet.has(record.studentId) && sessionSet.has(record.sessionId)),
  );
}
