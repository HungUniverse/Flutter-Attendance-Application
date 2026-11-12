import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { evaluateAttendanceForecasts, forecastEvaluationToCsv } from './forecast-evaluation.mjs';

function snapshot() {
  const rows = [
    { id: 'A', name: 'An Example', statuses: ['present', 'present', 'absent', 'absent', 'absent', 'absent'] },
    { id: 'B', name: 'Binh Example', statuses: ['absent', 'absent', 'present', 'present', 'present', 'present'] },
    { id: 'C', name: '=@Casey Example', statuses: ['present', 'missing', 'present', 'missing', 'present', 'missing'] },
    { id: 'D', name: 'Dana Example', statuses: ['missing', 'missing', 'missing', 'missing', 'missing', 'missing'] },
  ];
  const roster = rows.map(({ id, name }) => ({ id, name, email: `${id.toLowerCase()}@example.test` }));
  const sessions = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6'];
  const records = rows.flatMap(({ id, statuses }) => statuses.flatMap((status, index) => status === 'missing' ? [] : [
    { studentId: id, sessionId: sessions[index], status },
  ]));
  return createAttendanceSnapshot(roster, sessions, records);
}

const options = { holdoutSessions: 2, minimumTrainingRecords: 2, targetRate: 0.6, minimumGroupSize: 2,
  calibrationBins: 2, recencyHalfLife: 2, methods: ['mean', 'last_result', 'recent_weighted', 'linear_trend'],
  baselineMethod: 'mean', cohorts: [{ id: 'small', label: 'One student', studentIds: ['A'] },
    { id: 'class', label: 'Full class', studentIds: ['A', 'B', 'C', 'D'] }] };

test('splits sessions chronologically and measures held-out coverage without mutating the snapshot', () => {
  const input = snapshot();
  const before = serializeAttendanceSnapshot(input);
  const report = evaluateAttendanceForecasts(input, options);
  assert.equal(report.format, 'attendance-forecast-evaluation');
  assert.deepEqual(report.split.trainingSessions, ['S1', 'S2', 'S3', 'S4']);
  assert.deepEqual(report.split.holdoutSessions, ['S5', 'S6']);
  assert.equal(report.summary.students, 4);
  assert.equal(report.summary.withHoldoutResults, 3);
  assert.equal(report.summary.withTrainingHistory, 3);
  assert.equal(report.summary.withAnyForecast, 3);
  assert.equal(report.summary.holdoutRecorded, 5);
  assert.equal(report.summary.holdoutExpected, 8);
  assert.equal(report.summary.holdoutCoverage, 5 / 8);
  assert.equal(serializeAttendanceSnapshot(input), before);
});

test('evaluates mean, last-result, recency-weighted and linear estimators transparently', () => {
  const report = evaluateAttendanceForecasts(snapshot(), { ...options, includeStudentRows: true });
  const students = new Map(report.students.map((student) => [student.studentId, student]));
  assert.equal(students.get('A').actualRate, 0);
  assert.equal(students.get('A').predictions.mean, 0.5);
  assert.equal(students.get('A').predictions.last_result, 0);
  assert.equal(students.get('B').actualRate, 1);
  assert.equal(students.get('B').predictions.mean, 0.5);
  assert.equal(students.get('B').predictions.last_result, 1);
  assert.equal(students.get('B').predictions.linear_trend, 1);
  assert.equal(students.get('C').trainingRecorded, 2);
  assert.equal(students.get('C').actualRate, 1);
  assert.equal(students.get('D').actualRate, null);
  assert.equal(students.get('D').predictions.mean, null);
  assert.equal(report.metrics.mean.scoredStudents, 3);
  assert.ok(report.metrics.mean.mae > 0);
  assert.equal(report.metrics.mean.confusion.falseNegative, 1);
  assert.equal(report.metrics.last_result.confusion.truePositive, 2);
});

test('compares methods on the same students and builds small-bin-safe calibration buckets', () => {
  const report = evaluateAttendanceForecasts(snapshot(), options);
  assert.equal(report.comparisons.length, 3);
  assert.ok(report.comparisons.every((item) => item.baselineMethod === 'mean'));
  assert.ok(report.comparisons.every((item) => item.comparableStudents === 3));
  const lastBins = report.metrics.last_result.calibration;
  assert.equal(lastBins.length, 2);
  assert.equal(lastBins[0].suppressed, true);
  assert.equal(lastBins[0].count, null);
  assert.equal(lastBins[0].meanObserved, null);
  assert.equal(lastBins[1].suppressed, false);
  assert.equal(lastBins[1].count, 2);
});

test('suppresses small cohorts and reports aggregate model metrics for larger groups', () => {
  const report = evaluateAttendanceForecasts(snapshot(), options);
  const small = report.cohorts.find((cohort) => cohort.cohortId === 'small');
  const full = report.cohorts.find((cohort) => cohort.cohortId === 'class');
  assert.equal(small.suppressed, true);
  assert.equal(small.students, null);
  assert.equal(small.methods.mean, null);
  assert.equal(full.suppressed, false);
  assert.equal(full.students, 4);
  assert.equal(full.validatedStudents, 3);
  assert.equal(full.methods.mean.scoredStudents, 3);
});

test('omits individual predictions by default and applies a detail-row cap when enabled', () => {
  const hidden = evaluateAttendanceForecasts(snapshot(), options);
  assert.equal(hidden.students, null);
  assert.equal(JSON.stringify(hidden).includes('An Example'), false);
  const detail = evaluateAttendanceForecasts(snapshot(), { ...options, includeStudentRows: true, maximumStudentRows: 2 });
  assert.equal(detail.students.length, 2);
  assert.equal(detail.studentsTruncated, 2);
});

test('exports model, cohort, calibration and comparison sections as CSV', () => {
  const report = evaluateAttendanceForecasts(snapshot(), { ...options, includeStudentRows: true });
  assert.match(forecastEvaluationToCsv(report), /"method","scoredStudents","mae"/);
  assert.match(forecastEvaluationToCsv(report, 'cohorts'), /"cohortId","cohortLabel","suppressed"/);
  assert.match(forecastEvaluationToCsv(report, 'calibration'), /"method","lower","upper","suppressed"/);
  assert.match(forecastEvaluationToCsv(report, 'comparisons'), /"method","baselineMethod","comparableStudents"/);
  assert.match(forecastEvaluationToCsv(report, 'students'), /'=\@Casey Example/);
  assert.throws(() => forecastEvaluationToCsv(evaluateAttendanceForecasts(snapshot(), options), 'students'), /student rows were not enabled/);
  assert.throws(() => forecastEvaluationToCsv({ format: 'bad', version: 1 }), /invalid/);
  assert.throws(() => forecastEvaluationToCsv(report, 'raw'), /section must be/);
});

test('validates holdout split, methods, target, cohorts and privacy settings', () => {
  const data = snapshot();
  assert.throws(() => evaluateAttendanceForecasts(null), /snapshot must be an object/);
  assert.throws(() => evaluateAttendanceForecasts(data, null), /forecast evaluation options must be an object/);
  assert.throws(() => evaluateAttendanceForecasts(data, { holdoutSessions: 0 }), /from 1 to/);
  assert.throws(() => evaluateAttendanceForecasts(data, { holdoutSessions: 6 }), /from 1 to 5/);
  assert.throws(() => evaluateAttendanceForecasts(createAttendanceSnapshot(data.roster, ['S1'], [])), /at least 2 sessions/);
  assert.throws(() => evaluateAttendanceForecasts(data, { minimumTrainingRecords: 0 }), /from 1 to 1000/);
  assert.throws(() => evaluateAttendanceForecasts(data, { targetRate: 2 }), /fraction from 0 to 1/);
  assert.throws(() => evaluateAttendanceForecasts(data, { minimumGroupSize: 1 }), /from 2 to 1000/);
  assert.throws(() => evaluateAttendanceForecasts(data, { calibrationBins: 1 }), /from 2 to 10/);
  assert.throws(() => evaluateAttendanceForecasts(data, { recencyHalfLife: 0 }), /from 1 to 100/);
  assert.throws(() => evaluateAttendanceForecasts(data, { methods: ['mean', 'mean'] }), /unique supported/);
  assert.throws(() => evaluateAttendanceForecasts(data, { methods: ['linear'] }), /unique supported/);
  assert.throws(() => evaluateAttendanceForecasts(data, { methods: ['mean'], baselineMethod: 'last_result' }), /must be included/);
  assert.throws(() => evaluateAttendanceForecasts(data, { includeStudentRows: 1 }), /must be a boolean/);
  assert.throws(() => evaluateAttendanceForecasts(data, { maximumStudentRows: 10_001 }), /from 1 to 10000/);
  assert.throws(() => evaluateAttendanceForecasts(data, { cohorts: [{ id: 'one', studentIds: ['A', 'A'] }] }), /duplicate students/);
  assert.throws(() => evaluateAttendanceForecasts(data, { cohorts: [{ id: 'one', studentIds: ['Z'] }] }), /unknown student/);
});
