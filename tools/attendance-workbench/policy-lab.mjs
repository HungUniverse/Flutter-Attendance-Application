import { buildAttendanceReport } from '../../backend/attendance-report.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-policy-lab';
const VERSION = 1;
const MODES = new Set(['bounded', 'assume-present', 'assume-absent', 'exclude-missing']);
const STATUSES = ['pass', 'fail', 'undetermined'];
const TRANSITIONS = Object.freeze(STATUSES.flatMap((from) => STATUSES.map((to) => `${from}_to_${to}`)));

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 120) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum || /[\u0000-\u001f\u007f]/.test(value)) {
    throw new TypeError(`${field} must be a non-empty text value of at most ${maximum} characters`);
  }
  return value.trim();
}

function fraction(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
    throw new RangeError(`${field} must be a number from 0 to 1`);
  }
  return value;
}

function safeCount(value, field, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < 0 || value > maximum) {
    throw new RangeError(`${field} must be a non-negative safe integer${maximum < Number.MAX_SAFE_INTEGER ? ` no greater than ${maximum}` : ''}`);
  }
  return value;
}

function normalizePolicies(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 40) {
    throw new RangeError('policies must contain from 1 to 40 candidate policies');
  }
  const ids = new Set();
  return value.map((candidate, index) => {
    object(candidate, `policies[${index}]`);
    const id = text(candidate.id, `policies[${index}].id`, 64);
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id)) throw new TypeError(`policies[${index}].id must use letters, numbers, dot, underscore or hyphen`);
    if (ids.has(id)) throw new TypeError(`duplicate policy id: ${id}`);
    ids.add(id);
    return {
      id,
      name: text(candidate.name ?? id, `policies[${index}].name`, 160),
      minimumRate: fraction(candidate.minimumRate, `policies[${index}].minimumRate`),
      maximumAbsences: safeCount(candidate.maximumAbsences, `policies[${index}].maximumAbsences`),
    };
  });
}

function normalizeModes(value) {
  const modes = value ?? ['bounded', 'assume-present', 'assume-absent', 'exclude-missing'];
  if (!Array.isArray(modes) || modes.length < 1 || modes.length > MODES.size) {
    throw new RangeError(`missingModes must contain from 1 to ${MODES.size} modes`);
  }
  const unique = new Set();
  for (const mode of modes) {
    if (!MODES.has(mode)) throw new TypeError(`unsupported missing-data mode: ${mode}`);
    if (unique.has(mode)) throw new TypeError(`duplicate missing-data mode: ${mode}`);
    unique.add(mode);
  }
  return [...modes];
}

function normalizeCohorts(value, roster) {
  if (value === undefined) return [{ id: 'all', label: 'All students', studentIds: roster.map((student) => student.id) }];
  if (!Array.isArray(value) || value.length > 100) throw new RangeError('cohorts must be an array with at most 100 entries');
  const ids = new Set();
  const assigned = new Set();
  const known = new Set(roster.map((student) => student.id));
  const cohorts = value.map((entry, index) => {
    object(entry, `cohorts[${index}]`);
    const id = text(entry.id, `cohorts[${index}].id`, 64);
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id)) throw new TypeError(`cohorts[${index}].id must use letters, numbers, dot, underscore or hyphen`);
    if (ids.has(id)) throw new TypeError(`duplicate cohort id: ${id}`);
    ids.add(id);
    if (!Array.isArray(entry.studentIds)) throw new TypeError(`cohorts[${index}].studentIds must be an array`);
    const studentIds = entry.studentIds.map((studentId, memberIndex) => {
      const normalized = text(studentId, `cohorts[${index}].studentIds[${memberIndex}]`, 160);
      if (!known.has(normalized)) throw new TypeError(`cohort ${id} refers to unknown student id: ${normalized}`);
      if (assigned.has(normalized)) throw new TypeError(`student is assigned to more than one cohort: ${normalized}`);
      assigned.add(normalized);
      return normalized;
    });
    return { id, label: text(entry.label ?? id, `cohorts[${index}].label`, 160), studentIds };
  });
  const unassigned = roster.filter((student) => !assigned.has(student.id)).map((student) => student.id);
  if (unassigned.length) cohorts.push({ id: 'unassigned', label: 'Unassigned', studentIds: unassigned });
  return cohorts;
}

function decisionFor(report, policy, mode) {
  const total = report.present + report.absent + report.missing;
  if (total === 0) return {
    status: 'undetermined', reasons: ['no_sessions'], present: 0, absent: 0, missing: 0,
    denominator: 0, minimumRate: null, maximumRate: null,
  };

  let present = report.present;
  let absent = report.absent;
  let denominator = total;
  let minimumRate;
  let maximumRate;
  if (mode === 'bounded') {
    denominator = total;
    minimumRate = report.present / total;
    maximumRate = (report.present + report.missing) / total;
  } else if (mode === 'assume-present') {
    present += report.missing;
    minimumRate = present / denominator;
    maximumRate = minimumRate;
  } else if (mode === 'assume-absent') {
    absent += report.missing;
    minimumRate = present / denominator;
    maximumRate = minimumRate;
  } else {
    denominator = report.present + report.absent;
    if (!denominator) return {
      status: 'undetermined', reasons: ['no_recorded_results'], present, absent, missing: report.missing,
      denominator: 0, minimumRate: null, maximumRate: null,
    };
    minimumRate = present / denominator;
    maximumRate = minimumRate;
  }

  const reasons = [];
  if (maximumRate < policy.minimumRate) reasons.push('rate_below_minimum');
  if (absent > policy.maximumAbsences) reasons.push('absences_above_maximum');
  let status = reasons.length ? 'fail' : 'pass';
  if (status === 'pass' && (minimumRate < policy.minimumRate || absent + (mode === 'bounded' ? report.missing : 0) > policy.maximumAbsences)) {
    status = 'undetermined';
    reasons.push('missing_results');
  }
  return { status, reasons, present, absent, missing: report.missing, denominator, minimumRate, maximumRate };
}

function blankCounts() {
  return { students: 0, pass: 0, fail: 0, undetermined: 0 };
}

function summarize(rows) {
  const summary = blankCounts();
  for (const row of rows) {
    summary.students++;
    summary[row.status]++;
  }
  const determined = summary.pass + summary.fail;
  summary.determined = determined;
  summary.passRateAmongDetermined = determined ? summary.pass / determined : null;
  summary.undeterminedRate = summary.students ? summary.undetermined / summary.students : null;
  return summary;
}

function cohortSummaries(cohorts, rowById, minimumSize) {
  return cohorts.map((cohort) => {
    const rows = cohort.studentIds.map((id) => rowById.get(id));
    if (rows.length < minimumSize) return { id: cohort.id, label: cohort.label, suppressed: true, summary: null };
    return { id: cohort.id, label: cohort.label, suppressed: false, summary: summarize(rows) };
  });
}

function transitionCounts(rows, baselineById) {
  const transitions = Object.fromEntries(TRANSITIONS.map((key) => [key, 0]));
  let changed = 0;
  for (const row of rows) {
    const before = baselineById.get(row.studentId);
    if (!before || before.status === row.status) continue;
    changed++;
    transitions[`${before.status}_to_${row.status}`]++;
  }
  return { changed, transitions };
}

function cohortTransitionCounts(cohorts, rowById, baselineById, minimumSize) {
  return cohorts.map((cohort) => {
    if (cohort.studentIds.length < minimumSize) return { id: cohort.id, label: cohort.label, suppressed: true, comparison: null };
    const rows = cohort.studentIds.map((id) => rowById.get(id));
    return { id: cohort.id, label: cohort.label, suppressed: false, comparison: transitionCounts(rows, baselineById) };
  });
}

/**
 * Compare caller-supplied attendance rules against one validated snapshot.
 * Results are descriptive, carry no student-level rows by default, and never
 * modify the input snapshot or establish an institution's official policy.
 */
export function buildPolicyLab(snapshotValue, optionsValue) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = object(optionsValue, 'options');
  const policies = normalizePolicies(options.policies);
  const missingModes = normalizeModes(options.missingModes);
  const minimumCohortSize = safeCount(options.minimumCohortSize ?? 5, 'minimumCohortSize', 1000);
  if (minimumCohortSize < 2) throw new RangeError('minimumCohortSize must be at least 2 to avoid singleton cohort output');
  const cohorts = normalizeCohorts(options.cohorts, snapshot.roster);
  const includeStudentRows = options.includeStudentRows === true;
  if (options.includeStudentRows !== undefined && typeof options.includeStudentRows !== 'boolean') {
    throw new TypeError('includeStudentRows must be a boolean');
  }
  const maximumStudentRows = safeCount(options.maximumStudentRows ?? 10_000, 'maximumStudentRows', 10_000);
  if (includeStudentRows && snapshot.roster.length > maximumStudentRows) {
    throw new RangeError(`student-level output is limited to ${maximumStudentRows} rows`);
  }
  const baselinePolicyId = options.baselinePolicyId ?? policies[0].id;
  if (!policies.some((policy) => policy.id === baselinePolicyId)) throw new TypeError('baselinePolicyId must identify one of the supplied policies');

  const reports = buildAttendanceReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
  const evaluated = new Map();
  for (const mode of missingModes) {
    for (const policy of policies) {
      const rows = reports.map((report) => ({
        studentId: report.student.id,
        studentName: report.student.name,
        ...decisionFor(report, policy, mode),
      }));
      evaluated.set(`${mode}\u0000${policy.id}`, rows);
    }
  }

  const scenarios = [];
  for (const mode of missingModes) {
    const baselineRows = evaluated.get(`${mode}\u0000${baselinePolicyId}`);
    const baselineById = new Map(baselineRows.map((row) => [row.studentId, row]));
    for (const policy of policies) {
      const rows = evaluated.get(`${mode}\u0000${policy.id}`);
      const rowById = new Map(rows.map((row) => [row.studentId, row]));
      scenarios.push({
        id: `${policy.id}--${mode}`,
        policy: { ...policy },
        missingMode: mode,
        summary: summarize(rows),
        cohorts: cohortSummaries(cohorts, rowById, minimumCohortSize),
        comparisonToBaseline: policy.id === baselinePolicyId ? null : {
          ...transitionCounts(rows, baselineById),
          cohorts: cohortTransitionCounts(cohorts, rowById, baselineById, minimumCohortSize),
        },
        ...(includeStudentRows ? { students: rows } : {}),
      });
    }
  }
  return {
    format: FORMAT,
    version: VERSION,
    generatedFor: { students: snapshot.roster.length, sessions: snapshot.sessionIds.length, records: snapshot.records.length },
    settings: {
      policies,
      missingModes,
      baselinePolicyId,
      minimumCohortSize,
      cohortCount: cohorts.length,
      includeStudentRows,
    },
    scenarios,
    note: 'Comparisons are descriptive. Missing-data modes are hypothetical assumptions, and caller-supplied rules do not establish official policy.',
  };
}

/** Build a bounded grid of candidate rate and absence thresholds. */
export function createPolicyGrid(optionsValue) {
  const options = object(optionsValue, 'grid options');
  if (!Array.isArray(options.minimumRates) || !options.minimumRates.length || options.minimumRates.length > 20) {
    throw new RangeError('minimumRates must contain from 1 to 20 values');
  }
  if (!Array.isArray(options.maximumAbsences) || !options.maximumAbsences.length || options.maximumAbsences.length > 20) {
    throw new RangeError('maximumAbsences must contain from 1 to 20 values');
  }
  if (options.minimumRates.length * options.maximumAbsences.length > 40) throw new RangeError('policy grid must contain at most 40 candidates');
  const rates = options.minimumRates.map((value, index) => fraction(value, `minimumRates[${index}]`));
  const absences = options.maximumAbsences.map((value, index) => safeCount(value, `maximumAbsences[${index}]`));
  if (new Set(rates).size !== rates.length) throw new TypeError('minimumRates values must be unique');
  if (new Set(absences).size !== absences.length) throw new TypeError('maximumAbsences values must be unique');
  const prefix = options.idPrefix === undefined ? 'grid' : text(options.idPrefix, 'idPrefix', 32);
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(prefix)) throw new TypeError('idPrefix must use letters, numbers, dot, underscore or hyphen');
  const pad = (value) => String(value).padStart(2, '0');
  return rates.flatMap((minimumRate, rateIndex) => absences.map((maximumAbsences, absenceIndex) => ({
    id: `${prefix}-r${pad(rateIndex + 1)}-a${pad(absenceIndex + 1)}`,
    name: `Minimum ${Math.round(minimumRate * 100)}%, at most ${maximumAbsences} absences`,
    minimumRate,
    maximumAbsences,
  })));
}

function csvCell(value) {
  let cell = String(value ?? '');
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

function csvRows(headers, rows) {
  return [headers, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}

/** Export one report section. Student identifiers are available only when the
 * caller explicitly enabled includeStudentRows while creating the lab. */
export function policyLabToCsv(labValue, section = 'summary') {
  const lab = object(labValue, 'policy lab');
  if (lab.format !== FORMAT || lab.version !== VERSION || !Array.isArray(lab.scenarios)) {
    throw new TypeError('invalid policy lab report');
  }
  if (section === 'summary') {
    return csvRows(['scenarioId', 'policyId', 'policyName', 'minimumRate', 'maximumAbsences', 'missingMode',
      'students', 'pass', 'fail', 'undetermined', 'passRateAmongDetermined'], lab.scenarios.map((scenario) => [
      scenario.id, scenario.policy.id, scenario.policy.name, scenario.policy.minimumRate,
      scenario.policy.maximumAbsences, scenario.missingMode, scenario.summary.students,
      scenario.summary.pass, scenario.summary.fail, scenario.summary.undetermined,
      scenario.summary.passRateAmongDetermined,
    ]));
  }
  if (section === 'cohorts') {
    return csvRows(['scenarioId', 'cohortId', 'cohortLabel', 'suppressed', 'students', 'pass', 'fail', 'undetermined'],
      lab.scenarios.flatMap((scenario) => scenario.cohorts.map((cohort) => [
        scenario.id, cohort.id, cohort.label, cohort.suppressed,
        cohort.summary?.students ?? '', cohort.summary?.pass ?? '', cohort.summary?.fail ?? '', cohort.summary?.undetermined ?? '',
      ])));
  }
  if (section === 'students') {
    if (!lab.settings?.includeStudentRows || lab.scenarios.some((scenario) => !Array.isArray(scenario.students))) {
      throw new TypeError('student rows were not enabled for this report');
    }
    return csvRows(['scenarioId', 'studentId', 'studentName', 'status', 'reasons', 'present', 'absent', 'missing', 'denominator', 'minimumRate', 'maximumRate'],
      lab.scenarios.flatMap((scenario) => scenario.students.map((student) => [
        scenario.id, student.studentId, student.studentName, student.status, student.reasons.join('|'),
        student.present, student.absent, student.missing, student.denominator, student.minimumRate, student.maximumRate,
      ])));
  }
  if (section === 'comparisons') {
    const headers = ['scenarioId', 'missingMode', 'policyId', 'cohortId', 'cohortLabel', 'suppressed', 'changed', ...TRANSITIONS];
    const rows = [];
    for (const scenario of lab.scenarios) {
      const comparison = scenario.comparisonToBaseline;
      if (!comparison) continue;
      rows.push([scenario.id, scenario.missingMode, scenario.policy.id, 'all', 'All students', false,
        comparison.changed, ...TRANSITIONS.map((name) => comparison.transitions[name])]);
      for (const cohort of comparison.cohorts) {
        rows.push([scenario.id, scenario.missingMode, scenario.policy.id, cohort.id, cohort.label, cohort.suppressed,
          cohort.comparison?.changed ?? '', ...TRANSITIONS.map((name) => cohort.comparison?.transitions[name] ?? '')]);
      }
    }
    return csvRows(headers, rows);
  }
  throw new TypeError('section must be summary, cohorts, students or comparisons');
}
