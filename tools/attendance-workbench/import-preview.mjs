import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { importAttendanceCsv } from '../../backend/attendance-csv-import.mjs';
import { importRosterCsv } from '../../backend/roster-csv-import.mjs';

function inputText(value, name) {
  if (typeof value !== 'string') throw new TypeError(`${name} must be a string`);
  return value;
}

function sessionsFrom(value) {
  let sessions = value;
  if (typeof sessions === 'string') {
    try { sessions = JSON.parse(sessions); }
    catch { throw new TypeError('sessions must contain a JSON array'); }
  }
  if (!Array.isArray(sessions)) throw new TypeError('sessions must be an array');
  const normalized = sessions.map((id, index) => {
    if (typeof id !== 'string' || !id.trim()) throw new TypeError(`invalid session ID at index ${index}`);
    return id.trim();
  });
  if (new Set(normalized).size !== normalized.length) throw new TypeError('session IDs must be unique');
  return normalized;
}

function summarizeCsv(imported, errors, key) {
  const accepted = imported?.[key]?.length ?? 0;
  return { rows: accepted + errors.length, accepted, rejected: errors.length };
}

function rowErrors(source, issues) {
  return issues.map((item) => ({
    source,
    line: Number.isSafeInteger(item.line) ? item.line : null,
    code: item.code,
    message: item.message ?? item.code.replaceAll('_', ' '),
  }));
}

/**
 * Preview a three-file import without persisting data. A candidate snapshot is
 * returned only when every roster and attendance row is valid and referentially sound.
 */
export function previewAttendanceImport(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new TypeError('input must be an object');
  const errors = [];
  const warnings = [];
  let rosterResult = null;
  let attendanceResult = null;
  let sessionIds = [];

  try { rosterResult = importRosterCsv(inputText(input.rosterCsv, 'rosterCsv')); }
  catch (error) { errors.push({ source: 'roster', line: null, code: 'invalid_csv', message: error.message }); }
  try { sessionIds = sessionsFrom(input.sessions); }
  catch (error) { errors.push({ source: 'sessions', line: null, code: 'invalid_sessions', message: error.message }); }
  try { attendanceResult = importAttendanceCsv(inputText(input.attendanceCsv, 'attendanceCsv')); }
  catch (error) { errors.push({ source: 'attendance', line: null, code: 'invalid_csv', message: error.message }); }

  if (rosterResult) errors.push(...rowErrors('roster', rosterResult.errors));
  if (attendanceResult) errors.push(...rowErrors('attendance', attendanceResult.errors));
  const roster = rosterResult?.students ?? [];
  const records = attendanceResult?.records ?? [];
  const studentIds = new Set(roster.map((student) => student.id));
  const knownSessions = new Set(sessionIds);
  for (const record of records) {
    if (!studentIds.has(record.studentId)) errors.push({ source: 'attendance', line: null,
      code: 'unknown_student', message: `Attendance references unknown student ${record.studentId}.`, studentId: record.studentId });
    if (!knownSessions.has(record.sessionId)) errors.push({ source: 'attendance', line: null,
      code: 'unknown_session', message: `Attendance references unknown session ${record.sessionId}.`, sessionId: record.sessionId });
  }

  const rosterSummary = summarizeCsv(rosterResult, rosterResult?.errors ?? [], 'students');
  const expected = roster.length * sessionIds.length;
  const matchedRecords = records.filter((record) => studentIds.has(record.studentId) && knownSessions.has(record.sessionId)).length;
  const attendanceRows = records.length + (attendanceResult?.errors.length ?? 0);
  const attendanceSummary = { rows: attendanceRows, accepted: matchedRecords, rejected: attendanceRows - matchedRecords };
  const missing = Math.max(0, expected - matchedRecords);
  const coverage = expected ? matchedRecords / expected : null;
  if (missing > 0 && errors.length === 0) {
    warnings.push({ code: 'incomplete_coverage', message: `${missing} attendance cells have no result.`, missing, expected, coverage });
  }

  let snapshot = null;
  if (errors.length === 0) {
    try { snapshot = createAttendanceSnapshot(roster, sessionIds, records); }
    catch (error) { errors.push({ source: 'snapshot', line: null, code: 'snapshot_invalid', message: error.message }); }
  }
  return {
    version: 1,
    ready: snapshot !== null && errors.length === 0,
    summary: {
      roster: rosterSummary,
      sessions: sessionIds.length,
      attendance: attendanceSummary,
      expected,
      recorded: matchedRecords,
      missing,
      coverage,
    },
    errors,
    warnings,
    snapshot,
  };
}
