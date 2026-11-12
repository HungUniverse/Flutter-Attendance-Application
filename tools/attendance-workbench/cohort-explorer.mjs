import { buildAttendanceReport } from '../../backend/attendance-report.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-cohort-explorer';
const VERSION = 1;
const MAX_COHORTS = 100;
const MAX_WINDOWS = 100;

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 160) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function integer(value, field, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  return value;
}

function fraction(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) throw new RangeError(`${field} must be from 0 to 1`);
  return value;
}

function percentageDistribution(values) {
  if (!values.length) return { minimum: null, p25: null, median: null, p75: null, maximum: null, mean: null, standardDeviation: null };
  const sorted = [...values].sort((left, right) => left - right);
  const percentile = (fractionValue) => {
    const position = (sorted.length - 1) * fractionValue;
    const lower = Math.floor(position);
    const upper = Math.ceil(position);
    const weight = position - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  };
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  const variance = values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / values.length;
  return {
    minimum: sorted[0],
    p25: percentile(0.25),
    median: percentile(0.5),
    p75: percentile(0.75),
    maximum: sorted.at(-1),
    mean,
    standardDeviation: Math.sqrt(variance),
  };
}

function normalizeCohorts(value, roster) {
  const knownIds = new Set(roster.map((student) => student.id));
  if (value === undefined) return [{ id: 'all', label: 'All students', studentIds: [...knownIds] }];
  if (!Array.isArray(value) || value.length > MAX_COHORTS) throw new RangeError(`cohorts must be an array with at most ${MAX_COHORTS} entries`);
  const ids = new Set();
  const assignments = new Set();
  const cohorts = value.map((entry, index) => {
    object(entry, `cohorts[${index}]`);
    const id = text(entry.id, `cohorts[${index}].id`, 64);
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id)) throw new TypeError(`cohorts[${index}].id must use letters, numbers, dot, underscore or hyphen`);
    if (ids.has(id) || id === 'unassigned') throw new TypeError(`duplicate or reserved cohort ID: ${id}`);
    ids.add(id);
    if (!Array.isArray(entry.studentIds)) throw new TypeError(`cohorts[${index}].studentIds must be an array`);
    const studentIds = entry.studentIds.map((studentId, memberIndex) => {
      const normalized = text(studentId, `cohorts[${index}].studentIds[${memberIndex}]`, 256);
      if (!knownIds.has(normalized)) throw new TypeError(`cohort ${id} contains an unknown student ID`);
      if (assignments.has(normalized)) throw new TypeError(`student ${normalized} belongs to more than one cohort`);
      assignments.add(normalized);
      return normalized;
    });
    return { id, label: text(entry.label ?? id, `cohorts[${index}].label`), studentIds };
  });
  const unassigned = [...knownIds].filter((id) => !assignments.has(id));
  if (unassigned.length) cohorts.push({ id: 'unassigned', label: 'Unassigned', studentIds: unassigned });
  return cohorts;
}

function normalizeWindows(value, sessionIds) {
  if (value === undefined) return [{ id: 'full-period', label: 'Full period', sessionIds: [...sessionIds] }];
  if (!Array.isArray(value) || value.length < 1 || value.length > MAX_WINDOWS) throw new RangeError(`windows must contain from 1 to ${MAX_WINDOWS} entries`);
  const seen = new Set();
  return value.map((entry, index) => {
    object(entry, `windows[${index}]`);
    const id = text(entry.id, `windows[${index}].id`, 64);
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id) || seen.has(id)) throw new TypeError(`windows[${index}].id must be unique and contain only letters, numbers, dot, underscore or hyphen`);
    seen.add(id);
    const label = text(entry.label ?? id, `windows[${index}].label`);
    if (entry.sessionIds !== undefined) {
      if (!Array.isArray(entry.sessionIds) || !entry.sessionIds.length) throw new TypeError(`windows[${index}].sessionIds must be a non-empty array`);
      const unique = new Set(entry.sessionIds);
      if (unique.size !== entry.sessionIds.length) throw new TypeError(`windows[${index}].sessionIds must be unique`);
      for (const sessionId of entry.sessionIds) if (!sessionIds.includes(sessionId)) throw new TypeError(`window ${id} refers to an unknown session`);
      const selected = new Set(entry.sessionIds);
      return { id, label, sessionIds: sessionIds.filter((sessionId) => selected.has(sessionId)) };
    }
    const start = entry.startSessionId === undefined ? 0 : sessionIds.indexOf(entry.startSessionId);
    const end = entry.endSessionId === undefined ? sessionIds.length - 1 : sessionIds.indexOf(entry.endSessionId);
    if (start < 0 || end < 0 || start > end) throw new RangeError(`window ${id} must have valid ordered session bounds`);
    return { id, label, sessionIds: sessionIds.slice(start, end + 1) };
  });
}

function summarizeStudents(rows, minimumSize, lowRateThreshold) {
  if (rows.length < minimumSize) return { suppressed: true, size: null, attendance: null, coverage: null, lowRateCount: null,
    missingResults: null, rateDistribution: null };
  const rates = rows.flatMap((row) => row.attendanceRate === null ? [] : [row.attendanceRate]);
  const present = rows.reduce((sum, row) => sum + row.present, 0);
  const absent = rows.reduce((sum, row) => sum + row.absent, 0);
  const missing = rows.reduce((sum, row) => sum + row.missing, 0);
  const expected = rows.reduce((sum, row) => sum + row.expected, 0);
  const recorded = present + absent;
  return {
    suppressed: false,
    size: rows.length,
    present,
    absent,
    missingResults: missing,
    expectedResults: expected,
    recordedResults: recorded,
    coverage: expected ? recorded / expected : null,
    attendanceRate: recorded ? present / recorded : null,
    lowRateThreshold,
    lowRateCount: rows.filter((row) => row.attendanceRate !== null && row.attendanceRate < lowRateThreshold).length,
    noRecordedResults: rows.filter((row) => row.attendanceRate === null).length,
    rateDistribution: percentageDistribution(rates),
  };
}

function studentWindow(row, selectedSessions) {
  const selected = row.sessions.filter((session) => selectedSessions.has(session.sessionId));
  const present = selected.filter((session) => session.status === 'present').length;
  const absent = selected.filter((session) => session.status === 'absent').length;
  const missing = selected.length - present - absent;
  const recorded = present + absent;
  return { student: row.student, present, absent, missing, expected: selected.length, recorded,
    attendanceRate: recorded ? present / recorded : null, coverage: selected.length ? recorded / selected.length : null };
}

function summarizeSessions(rows, sessions, minimumSize) {
  return sessions.map((sessionId) => {
    if (rows.length < minimumSize) return { sessionId, suppressed: true, present: null, absent: null, missing: null, attendanceRate: null };
    const items = rows.flatMap((row) => {
      const item = row.sessions.find((candidate) => candidate.sessionId === sessionId);
      return item ? [item.status] : [];
    });
    const present = items.filter((status) => status === 'present').length;
    const absent = items.filter((status) => status === 'absent').length;
    const missing = items.length - present - absent;
    return { sessionId, suppressed: false, present, absent, missing,
      attendanceRate: present + absent ? present / (present + absent) : null };
  });
}

function compareWindows(perWindowRows, minimumSize) {
  const comparisons = [];
  for (let index = 1; index < perWindowRows.length; index++) {
    const before = perWindowRows[index - 1];
    const after = perWindowRows[index];
    if (before.rows.length < minimumSize || after.rows.length < minimumSize) {
      comparisons.push({ from: before.id, to: after.id, suppressed: true, comparableStudents: null,
        improved: null, declined: null, unchanged: null, averageChange: null });
      continue;
    }
    const beforeRates = new Map(before.rows.map((row) => [row.studentId, row.attendanceRate]));
    let improved = 0;
    let declined = 0;
    let unchanged = 0;
    let totalChange = 0;
    let comparableStudents = 0;
    for (const row of after.rows) {
      const previousRate = beforeRates.get(row.studentId);
      if (previousRate === null || previousRate === undefined || row.attendanceRate === null) continue;
      comparableStudents++;
      const change = row.attendanceRate - previousRate;
      totalChange += change;
      if (change > 0) improved++;
      else if (change < 0) declined++;
      else unchanged++;
    }
    if (comparableStudents < minimumSize) {
      comparisons.push({ from: before.id, to: after.id, suppressed: true, comparableStudents: null,
        improved: null, declined: null, unchanged: null, averageChange: null });
      continue;
    }
    comparisons.push({ from: before.id, to: after.id, suppressed: false, comparableStudents,
      improved, declined, unchanged, averageChange: comparableStudents ? totalChange / comparableStudents : null });
  }
  return comparisons;
}

/**
 * Analyze explicit roster cohorts over caller-selected session windows.
 * Metrics are descriptive aggregates, are suppressed for small cohorts, and
 * do not infer causes or change attendance records.
 */
export function buildCohortExplorer(snapshotValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = object(optionsValue, 'cohort explorer options');
  const minimumCohortSize = integer(options.minimumCohortSize ?? 5, 'minimumCohortSize', 2, 1000);
  const lowRateThreshold = fraction(options.lowRateThreshold ?? 0.6, 'lowRateThreshold');
  const includeStudentRows = options.includeStudentRows === undefined ? false : options.includeStudentRows;
  if (typeof includeStudentRows !== 'boolean') throw new TypeError('includeStudentRows must be a boolean');
  const maximumStudentRows = integer(options.maximumStudentRows ?? 10_000, 'maximumStudentRows', 1, 10_000);
  const cohorts = normalizeCohorts(options.cohorts, snapshot.roster);
  const windows = normalizeWindows(options.windows, snapshot.sessionIds);
  const sourceReport = buildAttendanceReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
  const reportByStudentId = new Map(sourceReport.map((row) => [row.student.id, row]));
  const cohortResults = cohorts.map((cohort) => {
    const windowsForCohort = windows.map((window) => {
      const sessions = new Set(window.sessionIds);
      const rows = cohort.studentIds.map((studentId) => {
        const student = reportByStudentId.get(studentId);
        const result = studentWindow(student, sessions);
        return { studentId, studentName: student.student.name, ...result };
      });
      const summary = summarizeStudents(rows, minimumCohortSize, lowRateThreshold);
      return {
        id: window.id,
        label: window.label,
        sessionCount: window.sessionIds.length,
        summary,
        sessions: summarizeSessions(rows.map((row) => reportByStudentId.get(row.studentId)), window.sessionIds, minimumCohortSize),
        ...(includeStudentRows && rows.length >= minimumCohortSize ? { students: rows.slice(0, maximumStudentRows).map((row) => ({
          studentId: row.studentId,
          studentName: row.studentName,
          present: row.present,
          absent: row.absent,
          missing: row.missing,
          expected: row.expected,
          recorded: row.recorded,
          attendanceRate: row.attendanceRate,
          coverage: row.coverage,
        })) } : {}),
        studentRowsTruncated: includeStudentRows && rows.length >= minimumCohortSize ? Math.max(0, rows.length - maximumStudentRows) : null,
        _rows: rows.map((row) => ({ studentId: row.studentId, attendanceRate: row.attendanceRate })),
      };
    });
    const comparable = windowsForCohort.map((window) => ({ id: window.id, rows: window._rows }));
    for (const window of windowsForCohort) delete window._rows;
    return {
      id: cohort.id,
      label: cohort.label,
      suppressed: cohort.studentIds.length < minimumCohortSize,
      windows: windowsForCohort,
      comparisons: compareWindows(comparable, minimumCohortSize),
    };
  });
  return {
    format: FORMAT,
    version: VERSION,
    generatedFor: { students: snapshot.roster.length, sessions: snapshot.sessionIds.length, records: snapshot.records.length },
    settings: { minimumCohortSize, lowRateThreshold, includeStudentRows, maximumStudentRows,
      cohortCount: cohorts.length, windowCount: windows.length },
    cohorts: cohortResults,
    note: 'Comparisons describe recorded attendance only. Missing results are excluded from attendance rates and are shown separately.',
  };
}

function csvCell(value) {
  let cell = String(value ?? '');
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

function csv(headers, rows) {
  return [headers, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}

/** Export aggregate cohort, session or explicit student rows. */
export function cohortExplorerToCsv(reportValue, section = 'cohorts') {
  const report = object(reportValue, 'cohort explorer report');
  if (report.format !== FORMAT || report.version !== VERSION || !Array.isArray(report.cohorts)) throw new TypeError('invalid cohort explorer report');
  if (section === 'cohorts') {
    return csv(['cohortId', 'cohortLabel', 'windowId', 'windowLabel', 'suppressed', 'students', 'present', 'absent',
      'missingResults', 'expectedResults', 'recordedResults', 'coverage', 'attendanceRate', 'lowRateThreshold',
      'lowRateCount', 'noRecordedResults', 'rateMinimum', 'rateP25', 'rateMedian', 'rateP75', 'rateMaximum',
      'rateMean', 'rateStandardDeviation'], report.cohorts.flatMap((cohort) => cohort.windows.map((window) => {
      const summary = window.summary;
      return [cohort.id, cohort.label, window.id, window.label, summary.suppressed, summary.size, summary.present,
        summary.absent, summary.missingResults, summary.expectedResults, summary.recordedResults, summary.coverage,
        summary.attendanceRate, summary.lowRateThreshold, summary.lowRateCount, summary.noRecordedResults,
        summary.rateDistribution?.minimum, summary.rateDistribution?.p25, summary.rateDistribution?.median,
        summary.rateDistribution?.p75, summary.rateDistribution?.maximum, summary.rateDistribution?.mean,
        summary.rateDistribution?.standardDeviation];
    })));
  }
  if (section === 'sessions') {
    return csv(['cohortId', 'cohortLabel', 'windowId', 'sessionId', 'suppressed', 'present', 'absent', 'missing', 'attendanceRate'],
      report.cohorts.flatMap((cohort) => cohort.windows.flatMap((window) => window.sessions.map((session) => [
        cohort.id, cohort.label, window.id, session.sessionId, session.suppressed, session.present, session.absent,
        session.missing, session.attendanceRate,
      ]))));
  }
  if (section === 'comparisons') {
    return csv(['cohortId', 'cohortLabel', 'fromWindow', 'toWindow', 'suppressed', 'comparableStudents',
      'improved', 'declined', 'unchanged', 'averageChange'], report.cohorts.flatMap((cohort) => cohort.comparisons.map((item) => [
      cohort.id, cohort.label, item.from, item.to, item.suppressed, item.comparableStudents,
      item.improved, item.declined, item.unchanged, item.averageChange,
    ])));
  }
  if (section === 'students') {
    if (!report.settings?.includeStudentRows) throw new TypeError('student rows were not enabled');
    return csv(['cohortId', 'windowId', 'studentId', 'studentName', 'present', 'absent', 'missing', 'expected', 'recorded', 'attendanceRate', 'coverage'],
      report.cohorts.flatMap((cohort) => cohort.windows.flatMap((window) => (window.students ?? []).map((student) => [
        cohort.id, window.id, student.studentId, student.studentName, student.present, student.absent, student.missing,
        student.expected, student.recorded, student.attendanceRate, student.coverage,
      ]))));
  }
  throw new TypeError('section must be cohorts, sessions, comparisons or students');
}
