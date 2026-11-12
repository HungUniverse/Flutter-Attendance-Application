import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-recovery-plan';
const VERSION = 1;
const MAX_STUDENT_ROWS = 10_000;
const MAX_COHORTS = 100;
const STATES = Object.freeze(['already_satisfied', 'achievable', 'not_achievable', 'undetermined']);
const MISSING_MODES = new Set(['optimistic', 'pessimistic', 'exclude']);

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 160) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  }
  return value.trim();
}

function integer(value, field, minimum, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  return value;
}

function fraction(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) throw new RangeError(`${field} must be a fraction from 0 to 1`);
  return value;
}

function normalizePolicy(value) {
  const policy = object(value, 'attendance policy');
  return {
    minimumRate: fraction(policy.minimumRate, 'minimumRate'),
    maximumAbsences: integer(policy.maximumAbsences, 'maximumAbsences', 0),
  };
}

function normalizeCohorts(value, known) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > MAX_COHORTS) throw new RangeError(`cohorts must contain at most ${MAX_COHORTS} entries`);
  const ids = new Set();
  return value.map((entry, index) => {
    object(entry, `cohorts[${index}]`);
    const id = text(entry.id, `cohorts[${index}].id`, 80);
    if (ids.has(id)) throw new TypeError(`duplicate cohort ID: ${id}`);
    ids.add(id);
    if (!Array.isArray(entry.studentIds) || entry.studentIds.length > known.size) throw new RangeError(`cohorts[${index}].studentIds must be an array`);
    const studentIds = entry.studentIds.map((studentId, studentIndex) => text(studentId, `cohorts[${index}].studentIds[${studentIndex}]`, 256));
    if (new Set(studentIds).size !== studentIds.length) throw new TypeError(`cohort ${id} contains duplicate student IDs`);
    for (const studentId of studentIds) if (!known.has(studentId)) throw new TypeError(`cohort ${id} includes unknown student ${studentId}`);
    return { id, label: text(entry.label ?? id, `cohorts[${index}].label`, 160), studentIds };
  });
}

function normalizeOptions(value, roster) {
  const options = object(value, 'recovery options');
  const futureSessions = integer(options.futureSessions, 'futureSessions', 0, 10_000);
  const missingMode = options.missingMode ?? 'optimistic';
  if (!MISSING_MODES.has(missingMode)) throw new TypeError('missingMode must be optimistic, pessimistic or exclude');
  const includeStudentRows = options.includeStudentRows ?? false;
  if (typeof includeStudentRows !== 'boolean') throw new TypeError('includeStudentRows must be a boolean');
  const maximumStudentRows = integer(options.maximumStudentRows ?? 1_000, 'maximumStudentRows', 1, MAX_STUDENT_ROWS);
  if (includeStudentRows && roster.length > maximumStudentRows) throw new RangeError(`student rows exceed maximumStudentRows (${maximumStudentRows})`);
  const minimumCohortSize = integer(options.minimumCohortSize ?? 5, 'minimumCohortSize', 2, 1_000);
  return { futureSessions, missingMode, includeStudentRows, maximumStudentRows, minimumCohortSize,
    cohorts: normalizeCohorts(options.cohorts, new Set(roster.map((student) => student.id))) };
}

function requiredFuturePresent(present, total, remaining, targetRate) {
  if (total === 0) return null;
  if (present / total >= targetRate) return 0;
  if ((present + remaining) / total < targetRate) return null;
  let low = 1;
  let high = remaining;
  while (low < high) {
    const middle = low + Math.floor((high - low) / 2);
    if ((present + middle) / total >= targetRate) high = middle;
    else low = middle + 1;
  }
  return low;
}

function assessStudent(student, counts, policy, options) {
  let denominator = counts.present + counts.absent + counts.missing + options.futureSessions;
  let effectivePresent = counts.present;
  let effectiveAbsences = counts.absent;
  if (options.missingMode === 'optimistic') effectivePresent += counts.missing;
  if (options.missingMode === 'pessimistic') effectiveAbsences += counts.missing;
  if (options.missingMode === 'exclude') denominator -= counts.missing;
  const needed = requiredFuturePresent(effectivePresent, denominator, options.futureSessions, policy.minimumRate);
  const impossibleAbsenceLimit = effectiveAbsences > policy.maximumAbsences;
  const bestPossibleRate = denominator ? (effectivePresent + options.futureSessions) / denominator : null;
  const worstPossibleRate = denominator ? effectivePresent / denominator : null;
  const noOutcomes = denominator === 0;
  const achievable = !impossibleAbsenceLimit && needed !== null;
  let state = 'not_achievable';
  if (noOutcomes) state = 'undetermined';
  else if (achievable) state = needed === 0 ? 'already_satisfied' : 'achievable';
  const allowedFutureAbsences = impossibleAbsenceLimit ? null : Math.min(options.futureSessions, policy.maximumAbsences - effectiveAbsences);
  const reasons = [];
  if (impossibleAbsenceLimit) reasons.push('absence_limit_already_exceeded');
  if (needed === null && !noOutcomes) reasons.push('minimum_rate_unreachable');
  if (noOutcomes) reasons.push('no_counted_sessions');
  return {
    studentId: student.id,
    studentName: student.name,
    present: counts.present,
    absent: counts.absent,
    missing: counts.missing,
    futureSessions: options.futureSessions,
    countedSessions: denominator,
    effectivePresent,
    effectiveAbsences,
    missingMode: options.missingMode,
    requiredFuturePresent: needed,
    allowedFutureAbsences,
    bestPossibleRate,
    worstPossibleRate,
    state,
    reasons,
  };
}

function summarizeCohort(cohort, rows, minimumSize) {
  const members = rows.filter((row) => cohort.studentIds.includes(row.studentId));
  const suppressed = members.length < minimumSize;
  const stateCounts = Object.fromEntries(STATES.map((state) => [state, suppressed ? null : members.filter((row) => row.state === state).length]));
  const feasible = members.filter((row) => row.state === 'already_satisfied' || row.state === 'achievable');
  const required = feasible.map((row) => row.requiredFuturePresent).filter((value) => value !== null).sort((left, right) => left - right);
  const middle = Math.floor(required.length / 2);
  const medianRequiredFuturePresent = required.length === 0 ? null : required.length % 2
    ? required[middle] : (required[middle - 1] + required[middle]) / 2;
  return { cohortId: cohort.id, cohortLabel: cohort.label, suppressed,
    students: suppressed ? null : members.length,
    feasible: suppressed ? null : feasible.length,
    feasibleRate: suppressed || !members.length ? null : feasible.length / members.length,
    medianRequiredFuturePresent: suppressed ? null : medianRequiredFuturePresent,
    states: stateCounts };
}

/** Build an offline attendance recovery calculation; it never changes source records. */
export function planAttendanceRecovery(snapshotValue, policyValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const policy = normalizePolicy(policyValue);
  const options = normalizeOptions(optionsValue, snapshot.roster);
  const counts = new Map(snapshot.roster.map((student) => [student.id, { present: 0, absent: 0, missing: 0 }]));
  for (const record of snapshot.records) {
    const student = counts.get(record.studentId);
    if (student) student[record.status] += 1;
  }
  for (const student of snapshot.roster) counts.get(student.id).missing = snapshot.sessionIds.length -
    counts.get(student.id).present - counts.get(student.id).absent;
  const rows = snapshot.roster.map((student) => assessStudent(student, counts.get(student.id), policy, options));
  const summary = { students: rows.length, futureSessions: options.futureSessions,
    ...(Object.fromEntries(STATES.map((state) => [state, rows.filter((row) => row.state === state).length]))),
    missingCells: rows.reduce((sum, row) => sum + row.missing, 0),
    minimumRate: policy.minimumRate, maximumAbsences: policy.maximumAbsences, missingMode: options.missingMode };
  return {
    format: FORMAT,
    version: VERSION,
    policy,
    settings: { futureSessions: options.futureSessions, missingMode: options.missingMode,
      minimumCohortSize: options.minimumCohortSize, includeStudentRows: options.includeStudentRows },
    summary,
    cohorts: options.cohorts.map((cohort) => summarizeCohort(cohort, rows, options.minimumCohortSize)),
    ...(options.includeStudentRows ? { students: rows.slice(0, options.maximumStudentRows) } : {}),
    note: 'A hypothetical planning result. Missing outcomes use the selected mode; no attendance record is filled or changed.',
  };
}

/** Export selected recovery rows with spreadsheet formula prefixes escaped. */
export function recoveryPlanToCsv(planValue, section = 'summary') {
  const plan = object(planValue, 'recovery plan');
  if (plan.format !== FORMAT || plan.version !== VERSION || !plan.summary || !Array.isArray(plan.cohorts)) {
    throw new TypeError('invalid recovery plan');
  }
  const cell = (value) => {
    let source = value === null || value === undefined ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (section === 'summary') return csv(Object.keys(plan.summary), [Object.values(plan.summary)]);
  if (section === 'cohorts') return csv(['cohortId', 'cohortLabel', 'suppressed', 'students', 'feasible', 'feasibleRate',
    'medianRequiredFuturePresent', ...STATES.map((state) => `state_${state}`)], plan.cohorts.map((item) => [item.cohortId,
    item.cohortLabel, item.suppressed, item.students, item.feasible, item.feasibleRate, item.medianRequiredFuturePresent,
    ...STATES.map((state) => item.states[state])]));
  if (section === 'students') {
    if (!Array.isArray(plan.students)) throw new TypeError('student rows were not enabled in this recovery plan');
    return csv(['studentId', 'studentName', 'present', 'absent', 'missing', 'futureSessions', 'countedSessions',
      'effectivePresent', 'effectiveAbsences', 'missingMode', 'requiredFuturePresent', 'allowedFutureAbsences',
      'bestPossibleRate', 'worstPossibleRate', 'state', 'reasons'], plan.students.map((item) => [item.studentId,
      item.studentName, item.present, item.absent, item.missing, item.futureSessions, item.countedSessions,
      item.effectivePresent, item.effectiveAbsences, item.missingMode, item.requiredFuturePresent,
      item.allowedFutureAbsences, item.bestPossibleRate, item.worstPossibleRate, item.state, item.reasons.join(';')]));
  }
  throw new TypeError('section must be summary, cohorts or students');
}
