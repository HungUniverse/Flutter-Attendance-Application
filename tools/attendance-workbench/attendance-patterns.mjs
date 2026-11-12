import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-pattern-analysis';
const VERSION = 1;
const MAX_WINDOWS = 200;
const MAX_COHORTS = 100;
const MAX_STUDENT_ROWS = 10_000;

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
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) throw new RangeError(`${field} must be a fraction from 0 to 1`);
  return value;
}

function distribution(values) {
  if (!values.length) return { minimum: null, p25: null, median: null, p75: null, maximum: null, mean: null, standardDeviation: null };
  const sorted = [...values].sort((left, right) => left - right);
  const percentile = (rate) => {
    const position = (sorted.length - 1) * rate;
    const low = Math.floor(position);
    const high = Math.ceil(position);
    const weight = position - low;
    return sorted[low] * (1 - weight) + sorted[high] * weight;
  };
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  const variance = values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / values.length;
  return { minimum: sorted[0], p25: percentile(0.25), median: percentile(0.5), p75: percentile(0.75),
    maximum: sorted.at(-1), mean, standardDeviation: Math.sqrt(variance) };
}

function normalizeOptions(value, snapshot) {
  const options = object(value, 'pattern options');
  const sessionCount = snapshot.sessionIds.length;
  const windowSize = integer(options.windowSize ?? Math.max(1, Math.ceil(sessionCount / 4)), 'windowSize', 1, 1_000);
  const step = integer(options.step ?? windowSize, 'step', 1, 1_000);
  const minimumTrendWindows = integer(options.minimumTrendWindows ?? 3, 'minimumTrendWindows', 2, 200);
  const minimumRecordedSessions = integer(options.minimumRecordedSessions ?? 3, 'minimumRecordedSessions', 1, 1_000);
  const minimumGroupSize = integer(options.minimumGroupSize ?? 5, 'minimumGroupSize', 2, 1_000);
  const absenceStreakThreshold = integer(options.absenceStreakThreshold ?? 3, 'absenceStreakThreshold', 1, 1_000);
  const declineThreshold = fraction(options.declineThreshold ?? 0.05, 'declineThreshold');
  const lowAttendanceThreshold = options.lowAttendanceThreshold === undefined ? null : fraction(options.lowAttendanceThreshold, 'lowAttendanceThreshold');
  const lowCoverageThreshold = options.lowCoverageThreshold === undefined ? null : fraction(options.lowCoverageThreshold, 'lowCoverageThreshold');
  const includeStudentRows = options.includeStudentRows ?? false;
  if (typeof includeStudentRows !== 'boolean') throw new TypeError('includeStudentRows must be a boolean');
  const maximumStudentRows = integer(options.maximumStudentRows ?? 1_000, 'maximumStudentRows', 1, MAX_STUDENT_ROWS);
  const cohorts = normalizeCohorts(options.cohorts, snapshot);
  return { windowSize, step, minimumTrendWindows, minimumRecordedSessions, minimumGroupSize,
    absenceStreakThreshold, declineThreshold, lowAttendanceThreshold, lowCoverageThreshold,
    includeStudentRows, maximumStudentRows, cohorts };
}

function normalizeCohorts(value, snapshot) {
  const rosterIds = new Set(snapshot.roster.map((student) => student.id));
  if (value === undefined) return [{ id: 'all', label: 'All students', studentIds: [...rosterIds] }];
  if (!Array.isArray(value) || value.length > MAX_COHORTS) throw new RangeError(`cohorts must be an array with at most ${MAX_COHORTS} entries`);
  const ids = new Set();
  return value.map((item, index) => {
    object(item, `cohorts[${index}]`);
    const id = text(item.id, `cohorts[${index}].id`, 80);
    if (ids.has(id)) throw new TypeError(`duplicate cohort ID: ${id}`);
    ids.add(id);
    if (!Array.isArray(item.studentIds) || item.studentIds.length > rosterIds.size) throw new RangeError(`cohorts[${index}].studentIds must be an array`);
    const studentIds = item.studentIds.map((studentId, studentIndex) => text(studentId, `cohorts[${index}].studentIds[${studentIndex}]`, 256));
    if (new Set(studentIds).size !== studentIds.length) throw new TypeError(`cohorts[${index}] contains duplicate students`);
    for (const studentId of studentIds) if (!rosterIds.has(studentId)) throw new TypeError(`cohort ${id} contains unknown student ${studentId}`);
    return { id, label: text(item.label ?? id, `cohorts[${index}].label`, 160), studentIds };
  });
}

function windowsFor(sessionIds, options) {
  const windows = [];
  for (let start = 0; start < sessionIds.length; start += options.step) {
    const end = Math.min(sessionIds.length, start + options.windowSize);
    windows.push({ id: `w${windows.length + 1}`, index: windows.length + 1,
      sessionIds: sessionIds.slice(start, end), startIndex: start, endIndex: end - 1 });
    if (windows.length > MAX_WINDOWS) throw new RangeError(`analysis would create more than ${MAX_WINDOWS} windows`);
  }
  return windows;
}

function longestRun(statuses, target) {
  let best = 0;
  let current = 0;
  for (const status of statuses) {
    current = status === target ? current + 1 : 0;
    best = Math.max(best, current);
  }
  return best;
}

function calculateWindow(studentId, window, recordsByCell) {
  let present = 0;
  let absent = 0;
  let missing = 0;
  const statuses = window.sessionIds.map((sessionId) => recordsByCell.get(JSON.stringify([studentId, sessionId])) ?? 'missing');
  for (const status of statuses) {
    if (status === 'present') present++;
    else if (status === 'absent') absent++;
    else missing++;
  }
  const expected = statuses.length;
  const recorded = present + absent;
  return { windowId: window.id, startSession: window.sessionIds[0] ?? null,
    endSession: window.sessionIds.at(-1) ?? null, sessionCount: expected, present, absent, missing, recorded,
    coverage: expected ? recorded / expected : null, attendanceRate: recorded ? present / recorded : null };
}

function regression(points) {
  if (points.length < 2) return null;
  const xMean = points.reduce((sum, point) => sum + point.x, 0) / points.length;
  const yMean = points.reduce((sum, point) => sum + point.y, 0) / points.length;
  const denominator = points.reduce((sum, point) => sum + (point.x - xMean) ** 2, 0);
  if (denominator === 0) return null;
  return points.reduce((sum, point) => sum + (point.x - xMean) * (point.y - yMean), 0) / denominator;
}

function patternFlags(summary, options) {
  const flags = [];
  if (summary.longestAbsenceRun >= options.absenceStreakThreshold) flags.push('absence_streak');
  if (options.lowAttendanceThreshold !== null && summary.attendanceRate !== null && summary.attendanceRate < options.lowAttendanceThreshold) flags.push('low_attendance');
  if (options.lowCoverageThreshold !== null && summary.coverage !== null && summary.coverage < options.lowCoverageThreshold) flags.push('low_coverage');
  if (summary.recorded < options.minimumRecordedSessions) flags.push('insufficient_recorded_sessions');
  if (summary.trend === 'declining') flags.push('declining_window_rates');
  return flags;
}

/** Analyze runs, rates, coverage and window trends from a snapshot without changing it. */
export function analyzeAttendancePatterns(snapshotValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = normalizeOptions(optionsValue, snapshot);
  const windows = windowsFor(snapshot.sessionIds, options);
  const cells = snapshot.roster.length * snapshot.sessionIds.length;
  if (cells > 2_000_000) throw new RangeError('pattern analysis is limited to 2000000 student-session cells');
  if (cells * Math.max(1, windows.length) > 20_000_000) throw new RangeError('window analysis work exceeds the 20000000 cell-window limit');
  const recordsByCell = new Map(snapshot.records.map((record) => [JSON.stringify([record.studentId, record.sessionId]), record.status]));
  const roster = new Map(snapshot.roster.map((student) => [student.id, student]));
  const allRows = [];
  const sessions = snapshot.sessionIds.map((sessionId) => {
    const rows = snapshot.roster.map((student) => recordsByCell.get(JSON.stringify([student.id, sessionId])) ?? 'missing');
    const present = rows.filter((status) => status === 'present').length;
    const absent = rows.filter((status) => status === 'absent').length;
    const missing = rows.length - present - absent;
    const recorded = present + absent;
    return { sessionId, students: rows.length, present, absent, missing, recorded,
      coverage: rows.length ? recorded / rows.length : null, attendanceRate: recorded ? present / recorded : null };
  });
  for (const student of snapshot.roster) {
    const fullStatuses = snapshot.sessionIds.map((sessionId) => recordsByCell.get(JSON.stringify([student.id, sessionId])) ?? 'missing');
    const windowRows = windows.map((window) => calculateWindow(student.id, window, recordsByCell));
    const recorded = fullStatuses.filter((status) => status !== 'missing').length;
    const present = fullStatuses.filter((status) => status === 'present').length;
    const absent = fullStatuses.filter((status) => status === 'absent').length;
    const missing = fullStatuses.length - recorded;
    const totalRate = recorded ? present / recorded : null;
    const totalCoverage = fullStatuses.length ? recorded / fullStatuses.length : null;
    const ratePoints = windowRows.flatMap((row, index) => row.attendanceRate === null ? [] : [{ x: index, y: row.attendanceRate }]);
    const slope = recorded >= options.minimumRecordedSessions && ratePoints.length >= options.minimumTrendWindows ? regression(ratePoints) : null;
    const trend = slope === null ? 'undetermined' : slope < -options.declineThreshold ? 'declining' : slope > options.declineThreshold ? 'improving' : 'stable';
    const base = { studentId: student.id, studentName: student.name, present, absent, missing, recorded,
      expected: fullStatuses.length, attendanceRate: totalRate, coverage: totalCoverage,
      longestAbsenceRun: longestRun(fullStatuses, 'absent'), longestMissingRun: longestRun(fullStatuses, 'missing'),
      rateSlopePerWindow: slope, trend, windows: windowRows };
    base.flags = patternFlags(base, options);
    allRows.push(base);
  }
  const cohortReports = options.cohorts.flatMap((cohort) => windows.map((window) => {
    const students = cohort.studentIds.map((studentId) => allRows.find((row) => row.studentId === studentId)).filter(Boolean);
    const size = students.length;
    const suppressed = size < options.minimumGroupSize;
    const expected = students.reduce((sum, row) => sum + window.sessionIds.length, 0);
    const present = students.reduce((sum, row) => sum + (row.windows.find((entry) => entry.windowId === window.id)?.present ?? 0), 0);
    const absent = students.reduce((sum, row) => sum + (row.windows.find((entry) => entry.windowId === window.id)?.absent ?? 0), 0);
    const missing = expected - present - absent;
    const recorded = present + absent;
    const rates = students.map((row) => row.windows.find((entry) => entry.windowId === window.id)?.attendanceRate ?? null).filter((rate) => rate !== null);
    const trendCounts = { improving: students.filter((row) => row.trend === 'improving').length,
      declining: students.filter((row) => row.trend === 'declining').length, stable: students.filter((row) => row.trend === 'stable').length,
      undetermined: students.filter((row) => row.trend === 'undetermined').length };
    return { cohortId: cohort.id, cohortLabel: cohort.label, windowId: window.id,
      startSession: window.sessionIds[0] ?? null, endSession: window.sessionIds.at(-1) ?? null, suppressed,
      students: suppressed ? null : size,
      present: suppressed ? null : present, absent: suppressed ? null : absent, missing: suppressed ? null : missing,
      recorded: suppressed ? null : recorded, expected: suppressed ? null : expected,
      coverage: suppressed || expected === 0 ? null : recorded / expected,
      attendanceRate: suppressed || recorded === 0 ? null : present / recorded,
      rateDistribution: suppressed ? null : distribution(rates),
      trendCounts: suppressed ? null : trendCounts,
      flaggedStudents: suppressed ? null : students.filter((row) => row.flags.length).length };
  }));
  const windowSummaries = windows.map((window) => {
    const rows = allRows.map((student) => student.windows.find((item) => item.windowId === window.id));
    const present = rows.reduce((sum, row) => sum + row.present, 0);
    const absent = rows.reduce((sum, row) => sum + row.absent, 0);
    const missing = rows.reduce((sum, row) => sum + row.missing, 0);
    const expected = rows.reduce((sum, row) => sum + row.sessionCount, 0);
    const recorded = present + absent;
    const rates = rows.map((row) => row.attendanceRate).filter((rate) => rate !== null);
    return { windowId: window.id, startSession: window.sessionIds[0] ?? null,
      endSession: window.sessionIds.at(-1) ?? null, sessionCount: window.sessionIds.length,
      students: snapshot.roster.length, present, absent, missing, recorded, expected,
      coverage: expected ? recorded / expected : null, attendanceRate: recorded ? present / recorded : null,
      rateDistribution: distribution(rates) };
  });
  const fullRecorded = presentStatusCount(sessions, 'present') + presentStatusCount(sessions, 'absent');
  const totalExpected = sessions.reduce((sum, session) => sum + session.students, 0);
  const totalPresent = presentStatusCount(sessions, 'present');
  const totalAbsent = presentStatusCount(sessions, 'absent');
  const flags = {};
  for (const row of allRows) for (const flag of row.flags) flags[flag] = (flags[flag] ?? 0) + 1;
  return { format: FORMAT, version: VERSION,
    settings: { windowSize: options.windowSize, step: options.step, minimumTrendWindows: options.minimumTrendWindows,
      minimumRecordedSessions: options.minimumRecordedSessions, minimumGroupSize: options.minimumGroupSize,
      absenceStreakThreshold: options.absenceStreakThreshold, declineThreshold: options.declineThreshold,
      includeStudentRows: options.includeStudentRows, maximumStudentRows: options.maximumStudentRows },
    summary: { students: snapshot.roster.length, sessions: snapshot.sessionIds.length, windows: windows.length,
      expectedCells: totalExpected, recorded: fullRecorded, present: totalPresent, absent: totalAbsent,
      missing: totalExpected - fullRecorded, coverage: totalExpected ? fullRecorded / totalExpected : null,
      attendanceRate: fullRecorded ? totalPresent / fullRecorded : null,
      improving: allRows.filter((row) => row.trend === 'improving').length,
      declining: allRows.filter((row) => row.trend === 'declining').length,
      stable: allRows.filter((row) => row.trend === 'stable').length,
      undeterminedTrend: allRows.filter((row) => row.trend === 'undetermined').length, flags },
    windows: windowSummaries, cohorts: cohortReports, sessions,
    students: options.includeStudentRows ? allRows.slice(0, options.maximumStudentRows) : null,
    studentsTruncated: options.includeStudentRows ? Math.max(0, allRows.length - options.maximumStudentRows) : null,
    note: 'Window trends describe recorded results only. They are descriptive signals, not explanations of why attendance changed.' };
}

function csv(headers, rows) {
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  return [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
}

/** Export one aggregate or opted-in detail section. */
export function attendancePatternsToCsv(reportValue, section = 'windows') {
  const report = object(reportValue, 'attendance pattern report');
  if (report.format !== FORMAT || report.version !== VERSION) throw new TypeError('invalid attendance pattern report');
  if (section === 'windows') return csv(['windowId', 'startSession', 'endSession', 'sessionCount', 'students', 'present', 'absent', 'missing',
    'recorded', 'expected', 'coverage', 'attendanceRate', 'rateMedian', 'rateMean'], report.windows.map((row) => [row.windowId,
    row.startSession, row.endSession, row.sessionCount, row.students, row.present, row.absent, row.missing,
    row.recorded, row.expected, row.coverage, row.attendanceRate, row.rateDistribution.median, row.rateDistribution.mean]));
  if (section === 'cohorts') return csv(['cohortId', 'cohortLabel', 'windowId', 'suppressed', 'students', 'present', 'absent', 'missing',
    'recorded', 'expected', 'coverage', 'attendanceRate', 'flaggedStudents'], report.cohorts.map((row) => [row.cohortId,
    row.cohortLabel, row.windowId, row.suppressed, row.students, row.present, row.absent, row.missing,
    row.recorded, row.expected, row.coverage, row.attendanceRate, row.flaggedStudents]));
  if (section === 'sessions') return csv(['sessionId', 'students', 'present', 'absent', 'missing', 'recorded', 'coverage', 'attendanceRate'],
    report.sessions.map((row) => [row.sessionId, row.students, row.present, row.absent, row.missing, row.recorded, row.coverage, row.attendanceRate]));
  if (section === 'students') {
    if (!Array.isArray(report.students)) throw new TypeError('student rows were not enabled');
    return csv(['studentId', 'studentName', 'present', 'absent', 'missing', 'expected', 'recorded', 'attendanceRate', 'coverage',
      'longestAbsenceRun', 'longestMissingRun', 'rateSlopePerWindow', 'trend', 'flags'], report.students.map((row) => [row.studentId,
      row.studentName, row.present, row.absent, row.missing, row.expected, row.recorded, row.attendanceRate, row.coverage,
      row.longestAbsenceRun, row.longestMissingRun, row.rateSlopePerWindow, row.trend, row.flags.join('|')]));
  }
  throw new TypeError('section must be windows, cohorts, sessions or students');
}

function presentStatusCount(sessions, status) {
  return sessions.reduce((sum, session) => sum + session[status], 0);
}
