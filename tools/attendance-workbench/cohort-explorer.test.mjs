import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { buildCohortExplorer, cohortExplorerToCsv } from './cohort-explorer.mjs';

function sourceSnapshot() {
  const roster = [
    { id: 'A', name: 'An Example', email: 'a@example.test' },
    { id: 'B', name: 'Bao Example', email: 'b@example.test' },
    { id: 'C', name: 'Chi Example', email: 'c@example.test' },
    { id: 'D', name: 'Dung Example', email: 'd@example.test' },
  ];
  const sessionIds = ['S1', 'S2', 'S3', 'S4'];
  const statuses = {
    A: ['present', 'present', 'absent', 'absent'],
    B: ['present', 'absent', 'present', 'present'],
    C: ['present', 'present', 'present', 'present'],
    D: ['missing', 'missing', 'absent', 'missing'],
  };
  const records = roster.flatMap((student) => statuses[student.id].flatMap((status, index) => status === 'missing' ? [] : [
    { studentId: student.id, sessionId: sessionIds[index], status },
  ]));
  return createAttendanceSnapshot(roster, sessionIds, records);
}

const cohorts = [
  { id: 'alpha', label: 'Alpha', studentIds: ['A', 'B', 'C'] },
  { id: 'small', label: 'Small cohort', studentIds: ['D'] },
];

function twoWindows() {
  return [
    { id: 'early', label: 'Early', startSessionId: 'S1', endSessionId: 'S2' },
    { id: 'late', label: 'Late', startSessionId: 'S3', endSessionId: 'S4' },
  ];
}

test('summarizes explicit cohorts with weighted totals, distribution and missing-data coverage', () => {
  const source = sourceSnapshot();
  const before = serializeAttendanceSnapshot(source);
  const report = buildCohortExplorer(source, { cohorts, minimumCohortSize: 3, lowRateThreshold: 0.6 });
  assert.equal(report.format, 'attendance-cohort-explorer');
  assert.deepEqual(report.generatedFor, { students: 4, sessions: 4, records: 13 });
  const alpha = report.cohorts[0].windows[0].summary;
  assert.equal(alpha.suppressed, false);
  assert.equal(alpha.size, 3);
  assert.equal(alpha.present, 9);
  assert.equal(alpha.absent, 3);
  assert.equal(alpha.missingResults, 0);
  assert.equal(alpha.expectedResults, 12);
  assert.equal(alpha.recordedResults, 12);
  assert.equal(alpha.coverage, 1);
  assert.equal(alpha.attendanceRate, 0.75);
  assert.equal(alpha.lowRateCount, 1);
  assert.equal(alpha.rateDistribution.minimum, 0.5);
  assert.equal(alpha.rateDistribution.median, 0.75);
  assert.equal(alpha.rateDistribution.maximum, 1);
  assert.equal(report.cohorts[1].windows[0].summary.suppressed, true);
  assert.equal(report.cohorts[1].windows[0].summary.size, null);
  assert.equal(serializeAttendanceSnapshot(source), before);
});

test('compares adjacent windows with paired students and reports descriptive directions', () => {
  const report = buildCohortExplorer(sourceSnapshot(), { cohorts, windows: twoWindows(), minimumCohortSize: 3 });
  const alpha = report.cohorts[0];
  assert.deepEqual(alpha.windows.map((window) => [window.id, window.sessionCount]), [['early', 2], ['late', 2]]);
  assert.equal(alpha.comparisons.length, 1);
  assert.equal(alpha.comparisons[0].suppressed, false);
  assert.equal(alpha.comparisons[0].comparableStudents, 3);
  assert.equal(alpha.comparisons[0].improved, 1);
  assert.equal(alpha.comparisons[0].declined, 1);
  assert.equal(alpha.comparisons[0].unchanged, 1);
  assert.ok(Math.abs(alpha.comparisons[0].averageChange - (-1 / 6)) < 1e-12);
  assert.equal(report.cohorts[1].comparisons[0].suppressed, true);
  assert.equal(report.cohorts[1].comparisons[0].improved, null);
});

test('summarizes each session separately and suppresses small-group session cells', () => {
  const report = buildCohortExplorer(sourceSnapshot(), { cohorts, minimumCohortSize: 3 });
  const alpha = report.cohorts[0].windows[0].sessions;
  assert.deepEqual(alpha.map(({ sessionId, present, absent, missing }) => [sessionId, present, absent, missing]), [
    ['S1', 3, 0, 0], ['S2', 2, 1, 0], ['S3', 2, 1, 0], ['S4', 2, 1, 0],
  ]);
  const small = report.cohorts[1].windows[0].sessions;
  assert.ok(small.every((row) => row.suppressed && row.present === null && row.attendanceRate === null));
});

test('adds unassigned students to a suppressed-safe cohort without dropping them', () => {
  const report = buildCohortExplorer(sourceSnapshot(), { cohorts: [
    { id: 'selected', studentIds: ['A', 'B', 'C'] },
  ], minimumCohortSize: 2 });
  assert.deepEqual(report.cohorts.map((cohort) => cohort.id), ['selected', 'unassigned']);
  assert.equal(report.cohorts[1].windows[0].summary.suppressed, true);
});

test('includes bounded student rows only when explicitly requested and suppresses small identities', () => {
  const report = buildCohortExplorer(sourceSnapshot(), { cohorts, windows: twoWindows(), minimumCohortSize: 3,
    includeStudentRows: true, maximumStudentRows: 2 });
  const alphaEarly = report.cohorts[0].windows[0];
  assert.equal(alphaEarly.students.length, 2);
  assert.equal(alphaEarly.studentRowsTruncated, 1);
  assert.equal(Object.hasOwn(report.cohorts[1].windows[0], 'students'), false);
  assert.throws(() => cohortExplorerToCsv(buildCohortExplorer(sourceSnapshot(), { cohorts, minimumCohortSize: 3 }), 'students'), /not enabled/);
  assert.match(cohortExplorerToCsv(report, 'students'), /"cohortId","windowId","studentId"/);
  assert.doesNotMatch(cohortExplorerToCsv(report, 'students'), /Dung Example/);
});

test('accepts exact session lists while retaining the source snapshot order', () => {
  const report = buildCohortExplorer(sourceSnapshot(), { cohorts: [cohorts[0]], minimumCohortSize: 2,
    windows: [{ id: 'picked', label: 'Selected sessions', sessionIds: ['S4', 'S1'] }] });
  assert.equal(report.cohorts[0].windows[0].sessionCount, 2);
  assert.deepEqual(report.cohorts[0].windows[0].sessions.map((session) => session.sessionId), ['S1', 'S4']);
});

test('exports formula-safe aggregate, session, comparison and opted-in student CSV', () => {
  const report = buildCohortExplorer(sourceSnapshot(), { cohorts: [
    { id: 'alpha', label: '=HYPERLINK("bad")', studentIds: ['A', 'B', 'C'] },
  ], windows: twoWindows(), minimumCohortSize: 2, includeStudentRows: true });
  assert.match(cohortExplorerToCsv(report), /'=HYPERLINK/);
  assert.match(cohortExplorerToCsv(report, 'sessions'), /"cohortId","cohortLabel","windowId","sessionId"/);
  assert.match(cohortExplorerToCsv(report, 'comparisons'), /"fromWindow","toWindow"/);
  assert.throws(() => cohortExplorerToCsv(report, 'raw'), /section must be/);
  assert.throws(() => cohortExplorerToCsv({ format: 'wrong', version: 1, cohorts: [] }), /invalid/);
});

test('validates cohort membership, IDs, thresholds and limits', () => {
  const source = sourceSnapshot();
  assert.throws(() => buildCohortExplorer(source, { cohorts: [{ id: 'bad id', studentIds: [] }] }), /letters, numbers/);
  assert.throws(() => buildCohortExplorer(source, { cohorts: [
    { id: 'x', studentIds: ['A'] }, { id: 'y', studentIds: ['A'] },
  ] }), /more than one cohort/);
  assert.throws(() => buildCohortExplorer(source, { cohorts: [{ id: 'x', studentIds: ['unknown'] }] }), /unknown student ID/);
  assert.throws(() => buildCohortExplorer(source, { minimumCohortSize: 1 }), /from 2 to 1000/);
  assert.throws(() => buildCohortExplorer(source, { lowRateThreshold: -0.1 }), /from 0 to 1/);
  assert.throws(() => buildCohortExplorer(source, { includeStudentRows: 'yes' }), /must be a boolean/);
  assert.throws(() => buildCohortExplorer(source, { maximumStudentRows: 0 }), /from 1 to 10000/);
  assert.throws(() => buildCohortExplorer(source, { cohorts: Array(101).fill({ id: 'x', studentIds: [] }) }), /at most 100/);
});

test('validates windows, date-like session boundaries and section requirements', () => {
  const source = sourceSnapshot();
  assert.throws(() => buildCohortExplorer(source, { windows: [] }), /from 1 to 100/);
  assert.throws(() => buildCohortExplorer(source, { windows: [
    { id: 'same', sessionIds: ['S1'] }, { id: 'same', sessionIds: ['S2'] },
  ] }), /must be unique/);
  assert.throws(() => buildCohortExplorer(source, { windows: [{ id: 'bad', startSessionId: 'S4', endSessionId: 'S1' }] }), /ordered session bounds/);
  assert.throws(() => buildCohortExplorer(source, { windows: [{ id: 'bad', sessionIds: ['S9'] }] }), /unknown session/);
  assert.throws(() => buildCohortExplorer(source, { windows: [{ id: 'bad', sessionIds: ['S1', 'S1'] }] }), /must be unique/);
  assert.throws(() => cohortExplorerToCsv({ format: 'attendance-cohort-explorer', version: 1, cohorts: [] }, 'students'), /student rows were not enabled/);
});

test('reports no-session and all-missing cohorts without fabricating a rate', () => {
  const source = createAttendanceSnapshot([
    { id: 'A', name: 'An', email: 'a@example.test' },
    { id: 'B', name: 'Bao', email: 'b@example.test' },
  ], ['S1', 'S2'], []);
  const report = buildCohortExplorer(source, { cohorts: [{ id: 'all', studentIds: ['A', 'B'] }], minimumCohortSize: 2 });
  assert.equal(report.cohorts[0].windows[0].summary.coverage, 0);
  assert.equal(report.cohorts[0].windows[0].summary.attendanceRate, null);
  assert.equal(report.cohorts[0].windows[0].summary.noRecordedResults, 2);
  assert.equal(report.cohorts[0].comparisons.length, 0);
});
