import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-forecast-evaluation';
const VERSION = 1;
const METHODS = new Set(['mean', 'last_result', 'recent_weighted', 'linear_trend']);
const MAX_STUDENTS = 10_000;
const MAX_COHORTS = 100;

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

function normalizeOptions(value, snapshot) {
  const options = object(value, 'forecast evaluation options');
  if (snapshot.sessionIds.length < 2) throw new RangeError('forecast evaluation requires at least 2 sessions');
  const holdoutSessions = integer(options.holdoutSessions ?? Math.max(1, Math.floor(snapshot.sessionIds.length / 4)),
    'holdoutSessions', 1, snapshot.sessionIds.length - 1);
  const minimumTrainingRecords = integer(options.minimumTrainingRecords ?? 3, 'minimumTrainingRecords', 1, 1_000);
  const targetRate = fraction(options.targetRate ?? 0.75, 'targetRate');
  const minimumGroupSize = integer(options.minimumGroupSize ?? 5, 'minimumGroupSize', 2, 1_000);
  const bins = integer(options.calibrationBins ?? 5, 'calibrationBins', 2, 10);
  const recencyHalfLife = integer(options.recencyHalfLife ?? 4, 'recencyHalfLife', 1, 100);
  const includeStudentRows = options.includeStudentRows ?? false;
  if (typeof includeStudentRows !== 'boolean') throw new TypeError('includeStudentRows must be a boolean');
  const maximumStudentRows = integer(options.maximumStudentRows ?? 1_000, 'maximumStudentRows', 1, MAX_STUDENTS);
  const methods = options.methods ?? [...METHODS];
  if (!Array.isArray(methods) || methods.length < 1 || methods.length > METHODS.size || methods.some((method) => !METHODS.has(method)) ||
      new Set(methods).size !== methods.length) throw new TypeError('methods must contain unique supported forecast methods');
  const baselineMethod = options.baselineMethod ?? methods[0];
  if (!methods.includes(baselineMethod)) throw new TypeError('baselineMethod must be included in methods');
  const cohorts = normalizeCohorts(options.cohorts, snapshot);
  return { holdoutSessions, minimumTrainingRecords, targetRate, minimumGroupSize, bins, recencyHalfLife,
    includeStudentRows, maximumStudentRows, methods: [...methods], baselineMethod, cohorts };
}

function normalizeCohorts(value, snapshot) {
  const known = new Set(snapshot.roster.map((student) => student.id));
  if (value === undefined) return [{ id: 'all', label: 'All students', studentIds: [...known] }];
  if (!Array.isArray(value) || value.length > MAX_COHORTS) throw new RangeError(`cohorts must contain at most ${MAX_COHORTS} entries`);
  const ids = new Set();
  return value.map((entry, index) => {
    object(entry, `cohorts[${index}]`);
    const id = text(entry.id, `cohorts[${index}].id`, 80);
    if (ids.has(id)) throw new TypeError(`duplicate cohort ID: ${id}`);
    ids.add(id);
    if (!Array.isArray(entry.studentIds) || entry.studentIds.length > known.size) throw new RangeError(`cohorts[${index}].studentIds must be an array`);
    const studentIds = entry.studentIds.map((value, studentIndex) => text(value, `cohorts[${index}].studentIds[${studentIndex}]`, 256));
    if (new Set(studentIds).size !== studentIds.length) throw new TypeError(`cohort ${id} contains duplicate students`);
    for (const studentId of studentIds) if (!known.has(studentId)) throw new TypeError(`cohort ${id} includes unknown student ${studentId}`);
    return { id, label: text(entry.label ?? id, `cohorts[${index}].label`, 160), studentIds };
  });
}

function valueOf(status) {
  if (status === 'present') return 1;
  if (status === 'absent') return 0;
  return null;
}

function predict(method, points, holdoutIndices, halfLife) {
  if (!points.length) return null;
  if (method === 'mean') return points.reduce((sum, point) => sum + point.value, 0) / points.length;
  if (method === 'last_result') return points.at(-1).value;
  if (method === 'recent_weighted') {
    const lastIndex = points.at(-1).index;
    let weighted = 0;
    let totalWeight = 0;
    for (const point of points) {
      const weight = 0.5 ** ((lastIndex - point.index) / halfLife);
      weighted += point.value * weight;
      totalWeight += weight;
    }
    return weighted / totalWeight;
  }
  if (points.length < 2) return null;
  const xMean = points.reduce((sum, point) => sum + point.index, 0) / points.length;
  const yMean = points.reduce((sum, point) => sum + point.value, 0) / points.length;
  const denominator = points.reduce((sum, point) => sum + (point.index - xMean) ** 2, 0);
  if (denominator === 0) return null;
  const slope = points.reduce((sum, point) => sum + (point.index - xMean) * (point.value - yMean), 0) / denominator;
  const intercept = yMean - slope * xMean;
  return Math.max(0, Math.min(1, holdoutIndices.reduce((sum, index) => sum + intercept + slope * index, 0) / holdoutIndices.length));
}

function metricRows(rows, method, targetRate) {
  const scored = rows.filter((row) => row.predictions[method] !== null && row.actualRate !== null);
  const n = scored.length;
  const errors = scored.map((row) => row.predictions[method] - row.actualRate);
  const absoluteError = errors.reduce((sum, value) => sum + Math.abs(value), 0);
  const squaredError = errors.reduce((sum, value) => sum + value ** 2, 0);
  const bias = errors.reduce((sum, value) => sum + value, 0);
  const confusion = { truePositive: 0, falsePositive: 0, trueNegative: 0, falseNegative: 0 };
  for (const row of scored) {
    const predicted = row.predictions[method] >= targetRate;
    const observed = row.actualRate >= targetRate;
    if (predicted && observed) confusion.truePositive++;
    else if (predicted) confusion.falsePositive++;
    else if (observed) confusion.falseNegative++;
    else confusion.trueNegative++;
  }
  const precisionDenominator = confusion.truePositive + confusion.falsePositive;
  const recallDenominator = confusion.truePositive + confusion.falseNegative;
  return { scoredStudents: n, mae: n ? absoluteError / n : null,
    rmse: n ? Math.sqrt(squaredError / n) : null, bias: n ? bias / n : null,
    targetAccuracy: n ? (confusion.truePositive + confusion.trueNegative) / n : null,
    precision: precisionDenominator ? confusion.truePositive / precisionDenominator : null,
    recall: recallDenominator ? confusion.truePositive / recallDenominator : null,
    confusion };
}

function calibration(rows, method, bins, minimumGroupSize) {
  const bucketRows = Array.from({ length: bins }, (_, index) => ({
    lower: index / bins, upper: (index + 1) / bins, count: 0, predictedTotal: 0, observedTotal: 0,
  }));
  for (const row of rows) {
    const prediction = row.predictions[method];
    if (prediction === null || row.actualRate === null) continue;
    const index = Math.min(bins - 1, Math.floor(prediction * bins));
    const bucket = bucketRows[index];
    bucket.count++;
    bucket.predictedTotal += prediction;
    bucket.observedTotal += row.actualRate;
  }
  return bucketRows.map((bucket) => {
    const suppressed = bucket.count > 0 && bucket.count < minimumGroupSize;
    return { lower: bucket.lower, upper: bucket.upper, suppressed,
      count: suppressed ? null : bucket.count,
      meanPrediction: bucket.count >= minimumGroupSize ? bucket.predictedTotal / bucket.count : null,
      meanObserved: bucket.count >= minimumGroupSize ? bucket.observedTotal / bucket.count : null,
      calibrationGap: bucket.count >= minimumGroupSize ? (bucket.predictedTotal - bucket.observedTotal) / bucket.count : null };
  });
}

function summarizeCohort(cohort, rows, options) {
  const members = rows.filter((row) => cohort.studentIds.includes(row.studentId));
  const suppressed = members.length < options.minimumGroupSize;
  const methods = Object.fromEntries(options.methods.map((method) => [method, suppressed ? null : metricRows(members, method, options.targetRate)]));
  return { cohortId: cohort.id, cohortLabel: cohort.label, suppressed,
    students: suppressed ? null : members.length,
    validatedStudents: suppressed ? null : members.filter((row) => row.actualRate !== null).length,
    coverage: suppressed || members.length === 0 ? null : members.filter((row) => row.actualRate !== null).length / members.length,
    methods };
}

/** Backtest transparent attendance estimators against a held-out suffix of sessions. */
export function evaluateAttendanceForecasts(snapshotValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  if (snapshot.roster.length * snapshot.sessionIds.length > 2_000_000) throw new RangeError('forecast evaluation is limited to 2000000 student-session cells');
  const options = normalizeOptions(optionsValue, snapshot);
  const split = snapshot.sessionIds.length - options.holdoutSessions;
  const trainingSessions = snapshot.sessionIds.slice(0, split);
  const holdoutSessions = snapshot.sessionIds.slice(split);
  const matrix = new Map(snapshot.records.map((record) => [JSON.stringify([record.studentId, record.sessionId]), record.status]));
  const students = snapshot.roster.map((student) => {
    const points = trainingSessions.flatMap((sessionId, index) => {
      const value = valueOf(matrix.get(JSON.stringify([student.id, sessionId])));
      return value === null ? [] : [{ index, value }];
    });
    const outcomes = holdoutSessions.map((sessionId) => valueOf(matrix.get(JSON.stringify([student.id, sessionId])))).filter((value) => value !== null);
    const actualRate = outcomes.length ? outcomes.reduce((sum, value) => sum + value, 0) / outcomes.length : null;
    const predictions = Object.fromEntries(options.methods.map((method) => [method,
      points.length >= options.minimumTrainingRecords ? predict(method, points,
        holdoutSessions.map((_, index) => split + index), options.recencyHalfLife) : null]));
    return { studentId: student.id, studentName: student.name,
      trainingRecorded: points.length, trainingPresent: points.reduce((sum, point) => sum + point.value, 0),
      holdoutRecorded: outcomes.length, holdoutExpected: holdoutSessions.length,
      holdoutCoverage: outcomes.length / holdoutSessions.length, actualRate,
      predictions, scored: options.methods.some((method) => predictions[method] !== null) && actualRate !== null };
  });
  const metrics = Object.fromEntries(options.methods.map((method) => [method, {
    ...metricRows(students, method, options.targetRate), calibration: calibration(students, method, options.bins, options.minimumGroupSize),
  }]));
  const comparisons = options.methods.filter((method) => method !== options.baselineMethod).map((method) => {
    const comparable = students.filter((row) => row.actualRate !== null && row.predictions[method] !== null && row.predictions[options.baselineMethod] !== null);
    const difference = comparable.map((row) => Math.abs(row.predictions[method] - row.actualRate) -
      Math.abs(row.predictions[options.baselineMethod] - row.actualRate));
    return { method, baselineMethod: options.baselineMethod, comparableStudents: comparable.length,
      meanAbsoluteErrorDifference: difference.length ? difference.reduce((sum, value) => sum + value, 0) / difference.length : null,
      better: difference.filter((value) => value < 0).length,
      worse: difference.filter((value) => value > 0).length,
      tied: difference.filter((value) => value === 0).length };
  });
  const cohorts = options.cohorts.map((cohort) => summarizeCohort(cohort, students, options));
  return { format: FORMAT, version: VERSION,
    settings: { holdoutSessions: options.holdoutSessions, minimumTrainingRecords: options.minimumTrainingRecords,
      targetRate: options.targetRate, minimumGroupSize: options.minimumGroupSize, calibrationBins: options.bins,
      recencyHalfLife: options.recencyHalfLife, baselineMethod: options.baselineMethod,
      methods: [...options.methods], includeStudentRows: options.includeStudentRows, maximumStudentRows: options.maximumStudentRows },
    split: { trainingSessions, holdoutSessions },
    summary: { students: students.length, withHoldoutResults: students.filter((row) => row.actualRate !== null).length,
      withTrainingHistory: students.filter((row) => row.trainingRecorded >= options.minimumTrainingRecords).length,
      withAnyForecast: students.filter((row) => row.scored).length,
      holdoutRecorded: students.reduce((sum, row) => sum + row.holdoutRecorded, 0),
      holdoutExpected: students.reduce((sum, row) => sum + row.holdoutExpected, 0),
      holdoutCoverage: students.length ? students.reduce((sum, row) => sum + row.holdoutRecorded, 0) /
        Math.max(1, students.reduce((sum, row) => sum + row.holdoutExpected, 0)) : null },
    metrics, cohorts, comparisons,
    students: options.includeStudentRows ? students.slice(0, options.maximumStudentRows) : null,
    studentsTruncated: options.includeStudentRows ? Math.max(0, students.length - options.maximumStudentRows) : null,
    note: 'This is a historical backtest of simple estimators. It does not predict an individual outcome or change attendance records.' };
}

function csv(headers, rows) {
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  return [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
}

/** Export aggregate model metrics, cohort comparisons, calibration or opted-in student details. */
export function forecastEvaluationToCsv(reportValue, section = 'metrics') {
  const report = object(reportValue, 'forecast evaluation report');
  if (report.format !== FORMAT || report.version !== VERSION) throw new TypeError('invalid forecast evaluation report');
  const methodRows = Object.entries(report.metrics);
  if (section === 'metrics') return csv(['method', 'scoredStudents', 'mae', 'rmse', 'bias', 'targetAccuracy', 'precision', 'recall',
    'truePositive', 'falsePositive', 'trueNegative', 'falseNegative'], methodRows.map(([method, metric]) => [method,
    metric.scoredStudents, metric.mae, metric.rmse, metric.bias, metric.targetAccuracy, metric.precision, metric.recall,
    metric.confusion.truePositive, metric.confusion.falsePositive, metric.confusion.trueNegative, metric.confusion.falseNegative]));
  if (section === 'cohorts') return csv(['cohortId', 'cohortLabel', 'suppressed', 'students', 'validatedStudents', 'coverage', 'methodMetrics'],
    report.cohorts.map((cohort) => [cohort.cohortId, cohort.cohortLabel, cohort.suppressed, cohort.students,
      cohort.validatedStudents, cohort.coverage, JSON.stringify(cohort.methods)]));
  if (section === 'calibration') return csv(['method', 'lower', 'upper', 'suppressed', 'count', 'meanPrediction', 'meanObserved', 'calibrationGap'],
    methodRows.flatMap(([method, metric]) => metric.calibration.map((bin) => [method, bin.lower, bin.upper, bin.suppressed,
      bin.count, bin.meanPrediction, bin.meanObserved, bin.calibrationGap])));
  if (section === 'comparisons') return csv(['method', 'baselineMethod', 'comparableStudents', 'meanAbsoluteErrorDifference', 'better', 'worse', 'tied'],
    report.comparisons.map((item) => [item.method, item.baselineMethod, item.comparableStudents,
      item.meanAbsoluteErrorDifference, item.better, item.worse, item.tied]));
  if (section === 'students') {
    if (!Array.isArray(report.students)) throw new TypeError('student rows were not enabled');
    const methods = Object.keys(report.metrics);
    return csv(['studentId', 'studentName', 'trainingRecorded', 'holdoutRecorded', 'holdoutExpected', 'holdoutCoverage',
      'actualRate', ...methods], report.students.map((row) => [row.studentId, row.studentName, row.trainingRecorded,
      row.holdoutRecorded, row.holdoutExpected, row.holdoutCoverage, row.actualRate, ...methods.map((method) => row.predictions[method])]));
  }
  throw new TypeError('section must be metrics, cohorts, calibration, comparisons or students');
}
