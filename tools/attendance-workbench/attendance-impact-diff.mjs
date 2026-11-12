import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { evaluatePolicy } from './policy.mjs';

const FORMAT = 'attendance-impact-diff';
const VERSION = 1;
const MAX_STUDENT_ROWS = 10_000;
const MAX_COHORTS = 100;
const CHANGES = ['improved', 'declined', 'data_changed', 'unchanged', 'added_student', 'removed_student'];
const POLICY_SCORE = Object.freeze({ fail: 0, undetermined: 1, pass: 2 });

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 160) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function integer(value, field, minimum, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  return value;
}

function normalizeOptions(value, before, after) {
  const options = object(value, 'impact diff options');
  const includeStudentRows = options.includeStudentRows ?? false;
  const includeStudentNames = options.includeStudentNames ?? false;
  if (typeof includeStudentRows !== 'boolean' || typeof includeStudentNames !== 'boolean') throw new TypeError('student detail options must be booleans');
  const maximumStudentRows = integer(options.maximumStudentRows ?? 1_000, 'maximumStudentRows', 1, MAX_STUDENT_ROWS);
  const minimumCohortSize = integer(options.minimumCohortSize ?? 5, 'minimumCohortSize', 2, 1_000);
  const allIds = new Set([...before.roster, ...after.roster].map((student) => student.id));
  const cohorts = options.cohorts ?? [];
  if (!Array.isArray(cohorts) || cohorts.length > MAX_COHORTS) throw new RangeError(`cohorts must contain at most ${MAX_COHORTS} entries`);
  const seen = new Set();
  const normalizedCohorts = cohorts.map((entry, index) => {
    object(entry, `cohorts[${index}]`);
    const id = text(entry.id, `cohorts[${index}].id`, 80);
    if (seen.has(id)) throw new TypeError(`duplicate cohort ID: ${id}`);
    seen.add(id);
    if (!Array.isArray(entry.studentIds) || entry.studentIds.length > allIds.size) throw new RangeError(`cohorts[${index}].studentIds must be an array`);
    const studentIds = entry.studentIds.map((studentId, studentIndex) => text(studentId, `cohorts[${index}].studentIds[${studentIndex}]`, 256));
    if (new Set(studentIds).size !== studentIds.length) throw new TypeError(`cohort ${id} contains duplicate student IDs`);
    for (const studentId of studentIds) if (!allIds.has(studentId)) throw new TypeError(`cohort ${id} includes unknown student ${studentId}`);
    return { id, label: text(entry.label ?? id, `cohorts[${index}].label`, 160), studentIds };
  });
  return { includeStudentRows, includeStudentNames, maximumStudentRows, minimumCohortSize, cohorts: normalizedCohorts };
}

function counts(snapshot) {
  const byStudent = new Map(snapshot.roster.map((student) => [student.id, { present: 0, absent: 0 }]));
  for (const record of snapshot.records) byStudent.get(record.studentId)[record.status] += 1;
  for (const result of byStudent.values()) result.missing = snapshot.sessionIds.length - result.present - result.absent;
  return byStudent;
}

function rateRange(value, sessions) {
  if (!sessions) return { minimum: null, maximum: null };
  return { minimum: value.present / sessions, maximum: (value.present + value.missing) / sessions };
}

function policyMap(snapshot, policy) {
  if (policy === undefined) return null;
  const entries = evaluatePolicy(snapshot, policy);
  return new Map(entries.map((entry) => [entry.student.id, entry.status]));
}

function classify(beforeCounts, afterCounts, beforeSessions, afterSessions, beforePolicy, afterPolicy) {
  if (!beforeCounts) return 'added_student';
  if (!afterCounts) return 'removed_student';
  const sameCounts = beforeCounts.present === afterCounts.present && beforeCounts.absent === afterCounts.absent &&
    beforeCounts.missing === afterCounts.missing && beforeSessions === afterSessions;
  if (sameCounts) return 'unchanged';
  if (beforePolicy && afterPolicy) {
    const delta = POLICY_SCORE[afterPolicy] - POLICY_SCORE[beforePolicy];
    if (delta > 0) return 'improved';
    if (delta < 0) return 'declined';
    return 'data_changed';
  }
  const oldRange = rateRange(beforeCounts, beforeSessions);
  const newRange = rateRange(afterCounts, afterSessions);
  if (oldRange.minimum !== null && newRange.minimum !== null && newRange.minimum > oldRange.maximum) return 'improved';
  if (oldRange.minimum !== null && newRange.minimum !== null && newRange.maximum < oldRange.minimum) return 'declined';
  return 'data_changed';
}

function changedCellCount(before, after, studentId) {
  const beforeSessions = new Set(before.sessionIds);
  const afterSessions = new Set(after.sessionIds);
  const beforeCells = new Map(before.records.filter((item) => item.studentId === studentId).map((item) => [item.sessionId, item.status]));
  const afterCells = new Map(after.records.filter((item) => item.studentId === studentId).map((item) => [item.sessionId, item.status]));
  let count = 0;
  for (const sessionId of before.sessionIds) {
    if (!afterSessions.has(sessionId)) continue;
    if ((beforeCells.get(sessionId) ?? 'missing') !== (afterCells.get(sessionId) ?? 'missing')) count += 1;
  }
  return count;
}

function cohortRows(cohorts, rows, minimumSize) {
  return cohorts.map((cohort) => {
    const members = rows.filter((row) => cohort.studentIds.includes(row.studentId));
    const suppressed = members.length < minimumSize;
    return { cohortId: cohort.id, cohortLabel: cohort.label, suppressed,
      students: suppressed ? null : members.length,
      changes: Object.fromEntries(CHANGES.map((change) => [change,
        suppressed ? null : members.filter((row) => row.change === change).length])),
      changedCells: suppressed ? null : members.reduce((sum, row) => sum + row.changedCells, 0),
      meanRateDelta: suppressed ? null : mean(members.map((row) => row.rateDelta).filter((value) => value !== null)) };
  });
}

function mean(values) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : null;
}

/** Compare two validated snapshots as a read-only attendance outcome impact report. */
export function compareAttendanceImpact(beforeValue, afterValue, optionsValue = {}) {
  const before = parseAttendanceSnapshot(serializeAttendanceSnapshot(beforeValue));
  const after = parseAttendanceSnapshot(serializeAttendanceSnapshot(afterValue));
  const options = normalizeOptions(optionsValue, before, after);
  const beforeCounts = counts(before);
  const afterCounts = counts(after);
  const beforePolicy = policyMap(before, optionsValue.policy);
  const afterPolicy = policyMap(after, optionsValue.policy);
  const beforeRoster = new Map(before.roster.map((student) => [student.id, student]));
  const afterRoster = new Map(after.roster.map((student) => [student.id, student]));
  const studentIds = [...new Set([...beforeRoster.keys(), ...afterRoster.keys()])].sort((left, right) => left.localeCompare(right));
  if (options.includeStudentRows && studentIds.length > options.maximumStudentRows) throw new RangeError(`student rows exceed maximumStudentRows (${options.maximumStudentRows})`);
  const rows = studentIds.map((studentId) => {
    const oldCounts = beforeCounts.get(studentId);
    const newCounts = afterCounts.get(studentId);
    const oldPolicy = beforePolicy?.get(studentId) ?? null;
    const newPolicy = afterPolicy?.get(studentId) ?? null;
    const change = classify(oldCounts, newCounts, before.sessionIds.length, after.sessionIds.length, oldPolicy, newPolicy);
    const oldRate = oldCounts ? rateRange(oldCounts, before.sessionIds.length) : { minimum: null, maximum: null };
    const newRate = newCounts ? rateRange(newCounts, after.sessionIds.length) : { minimum: null, maximum: null };
    const oldMidpoint = oldRate.minimum === null ? null : (oldRate.minimum + oldRate.maximum) / 2;
    const newMidpoint = newRate.minimum === null ? null : (newRate.minimum + newRate.maximum) / 2;
    const oldStudent = beforeRoster.get(studentId);
    const newStudent = afterRoster.get(studentId);
    return { studentId,
      ...(options.includeStudentNames ? { studentName: newStudent?.name ?? oldStudent?.name ?? null } : {}),
      change,
      before: oldCounts ? { ...oldCounts, sessions: before.sessionIds.length, policyOutcome: oldPolicy,
        minimumRate: oldRate.minimum, maximumRate: oldRate.maximum } : null,
      after: newCounts ? { ...newCounts, sessions: after.sessionIds.length, policyOutcome: newPolicy,
        minimumRate: newRate.minimum, maximumRate: newRate.maximum } : null,
      rateDelta: oldMidpoint === null || newMidpoint === null ? null : newMidpoint - oldMidpoint,
      changedCells: oldCounts && newCounts ? changedCellCount(before, after, studentId) : 0 };
  });
  const byChange = Object.fromEntries(CHANGES.map((change) => [change, rows.filter((row) => row.change === change).length]));
  const sharedStudents = rows.filter((row) => row.before && row.after);
  const changedCells = sharedStudents.reduce((sum, row) => sum + row.changedCells, 0);
  const sharedSessions = before.sessionIds.filter((sessionId) => after.sessionIds.includes(sessionId));
  const addedSessions = after.sessionIds.filter((sessionId) => !before.sessionIds.includes(sessionId)).length;
  const removedSessions = before.sessionIds.filter((sessionId) => !after.sessionIds.includes(sessionId)).length;
  const summary = { beforeStudents: before.roster.length, afterStudents: after.roster.length,
    addedStudents: byChange.added_student, removedStudents: byChange.removed_student,
    sharedStudents: sharedStudents.length, beforeSessions: before.sessionIds.length, afterSessions: after.sessionIds.length,
    sharedSessions: sharedSessions.length, addedSessions, removedSessions, changedCells,
    improved: byChange.improved, declined: byChange.declined, dataChanged: byChange.data_changed, unchanged: byChange.unchanged,
    meanRateDelta: mean(sharedStudents.map((row) => row.rateDelta).filter((value) => value !== null)),
    policyApplied: Boolean(optionsValue.policy) };
  return { format: FORMAT, version: VERSION, beforeFingerprint: before.fingerprint, afterFingerprint: after.fingerprint,
    policy: optionsValue.policy ?? null,
    settings: { minimumCohortSize: options.minimumCohortSize, includeStudentRows: options.includeStudentRows,
      includeStudentNames: options.includeStudentNames }, summary, byChange,
    cohorts: cohortRows(options.cohorts, rows, options.minimumCohortSize),
    ...(options.includeStudentRows ? { students: rows } : {}),
    note: 'Attendance rates include unresolved cells as a range. The comparison does not modify either snapshot.',
  };
}

/** Export aggregate impact rows or student details explicitly enabled in the report. */
export function attendanceImpactDiffToCsv(reportValue, section = 'summary') {
  const report = object(reportValue, 'attendance impact report');
  if (report.format !== FORMAT || report.version !== VERSION || !report.summary || !Array.isArray(report.cohorts)) {
    throw new TypeError('invalid attendance impact report');
  }
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (section === 'summary') return csv(Object.keys(report.summary), [Object.values(report.summary)]);
  if (section === 'cohorts') return csv(['cohortId', 'cohortLabel', 'suppressed', 'students', 'changedCells', 'meanRateDelta', ...CHANGES],
    report.cohorts.map((item) => [item.cohortId, item.cohortLabel, item.suppressed, item.students, item.changedCells,
      item.meanRateDelta, ...CHANGES.map((change) => item.changes[change])]));
  if (section === 'students') {
    if (!Array.isArray(report.students)) throw new TypeError('student rows were not enabled in this impact report');
    return csv(['studentId', 'studentName', 'change', 'beforePresent', 'beforeAbsent', 'beforeMissing', 'beforePolicyOutcome',
      'afterPresent', 'afterAbsent', 'afterMissing', 'afterPolicyOutcome', 'rateDelta', 'changedCells'], report.students.map((item) => [
      item.studentId, item.studentName, item.change, item.before?.present, item.before?.absent, item.before?.missing,
      item.before?.policyOutcome, item.after?.present, item.after?.absent, item.after?.missing,
      item.after?.policyOutcome, item.rateDelta, item.changedCells]));
  }
  throw new TypeError('section must be summary, cohorts or students');
}
