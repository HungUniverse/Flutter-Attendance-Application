import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { analyzeAttendancePatterns, attendancePatternsToCsv } from './attendance-patterns.mjs';

function snapshot() {
  const sessionIds = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6'];
  const students = [
    { id: 'A', name: 'An Example', email: 'an@example.test', statuses: ['present', 'present', 'present', 'absent', 'absent', 'missing'] },
    { id: 'B', name: 'Binh Example', email: 'binh@example.test', statuses: ['absent', 'absent', 'missing', 'present', 'present', 'present'] },
    { id: 'C', name: '=@Casey Example', email: 'casey@example.test', statuses: ['present', 'missing', 'present', 'missing', 'present', 'missing'] },
    { id: 'D', name: 'Dana Example', email: 'dana@example.test', statuses: ['missing', 'missing', 'missing', 'missing', 'missing', 'missing'] },
  ];
  const roster = students.map(({ id, name, email }) => ({ id, name, email }));
  const records = students.flatMap(({ id, statuses }) => statuses.flatMap((status, index) => status === 'missing' ? [] : [
    { studentId: id, sessionId: sessionIds[index], status },
  ]));
  return createAttendanceSnapshot(roster, sessionIds, records);
}

const options = {
  windowSize: 2, step: 2, minimumTrendWindows: 2, minimumRecordedSessions: 2,
  minimumGroupSize: 2, absenceStreakThreshold: 2, declineThreshold: 0.05,
  lowAttendanceThreshold: 0.65, lowCoverageThreshold: 0.7,
  cohorts: [
    { id: 'small', label: 'Small review group', studentIds: ['A'] },
    { id: 'three', label: 'Three students', studentIds: ['A', 'B', 'C'] },
  ],
};

test('summarizes session and window rates while preserving missing data', () => {
  const input = snapshot();
  const before = serializeAttendanceSnapshot(input);
  const report = analyzeAttendancePatterns(input, options);
  assert.equal(report.format, 'attendance-pattern-analysis');
  assert.equal(report.summary.students, 4);
  assert.equal(report.summary.sessions, 6);
  assert.equal(report.summary.windows, 3);
  assert.equal(report.summary.expectedCells, 24);
  assert.equal(report.summary.recorded, 13);
  assert.equal(report.summary.missing, 11);
  assert.equal(report.summary.coverage, 13 / 24);
  assert.deepEqual(report.windows.map((window) => window.windowId), ['w1', 'w2', 'w3']);
  assert.deepEqual(report.windows.map((window) => window.startSession), ['S1', 'S3', 'S5']);
  assert.equal(report.sessions.find((session) => session.sessionId === 'S6').missing, 3);
  assert.equal(serializeAttendanceSnapshot(input), before);
});

test('calculates trend directions, absence runs, missing runs and threshold flags', () => {
  const report = analyzeAttendancePatterns(snapshot(), { ...options, includeStudentRows: true });
  const rows = new Map(report.students.map((row) => [row.studentId, row]));
  assert.equal(rows.get('A').trend, 'declining');
  assert.equal(rows.get('A').longestAbsenceRun, 2);
  assert.ok(rows.get('A').flags.includes('absence_streak'));
  assert.ok(rows.get('A').flags.includes('low_attendance'));
  assert.equal(rows.get('B').trend, 'improving');
  assert.equal(rows.get('B').longestAbsenceRun, 2);
  assert.equal(rows.get('C').trend, 'stable');
  assert.equal(rows.get('C').longestMissingRun, 1);
  assert.ok(rows.get('C').flags.includes('low_coverage'));
  assert.equal(rows.get('D').trend, 'undetermined');
  assert.ok(rows.get('D').flags.includes('insufficient_recorded_sessions'));
  assert.equal(report.summary.flags.absence_streak, 2);
  assert.equal(report.summary.declining, 1);
  assert.equal(report.summary.improving, 1);
});

test('suppresses small cohort rates and counts while preserving report structure', () => {
  const report = analyzeAttendancePatterns(snapshot(), options);
  const small = report.cohorts.find((row) => row.cohortId === 'small' && row.windowId === 'w1');
  const three = report.cohorts.find((row) => row.cohortId === 'three' && row.windowId === 'w1');
  assert.equal(small.suppressed, true);
  assert.equal(small.students, null);
  assert.equal(small.present, null);
  assert.equal(small.rateDistribution, null);
  assert.equal(three.suppressed, false);
  assert.equal(three.students, 3);
  assert.equal(three.expected, 6);
  assert.equal(three.coverage, 5 / 6);
  assert.equal(three.trendCounts.declining, 1);
});

test('omits student-level identity by default and applies an explicit detail row cap', () => {
  const summary = analyzeAttendancePatterns(snapshot(), options);
  assert.equal(summary.students, null);
  assert.equal(summary.studentsTruncated, null);
  assert.equal(JSON.stringify(summary).includes('An Example'), false);
  const details = analyzeAttendancePatterns(snapshot(), { ...options, includeStudentRows: true, maximumStudentRows: 2 });
  assert.equal(details.students.length, 2);
  assert.equal(details.studentsTruncated, 2);
  assert.equal(details.students[0].studentId, 'A');
});

test('supports single-window, overlapping-window and empty-session snapshots', () => {
  const single = analyzeAttendancePatterns(snapshot(), { windowSize: 4, step: 1, minimumGroupSize: 2 });
  assert.equal(single.windows.length, 6);
  assert.equal(single.windows[0].sessionCount, 4);
  assert.equal(single.windows[1].startSession, 'S2');
  const noSessions = createAttendanceSnapshot(snapshot().roster, [], []);
  const empty = analyzeAttendancePatterns(noSessions, { minimumGroupSize: 2 });
  assert.equal(empty.summary.sessions, 0);
  assert.equal(empty.summary.windows, 0);
  assert.deepEqual(empty.windows, []);
  assert.deepEqual(empty.sessions, []);
});

test('exports window, cohort, session and opted-in student CSV safely', () => {
  const report = analyzeAttendancePatterns(snapshot(), { ...options, includeStudentRows: true });
  assert.match(attendancePatternsToCsv(report), /"windowId","startSession","endSession"/);
  assert.match(attendancePatternsToCsv(report, 'cohorts'), /"cohortId","cohortLabel","windowId"/);
  assert.match(attendancePatternsToCsv(report, 'sessions'), /"sessionId","students","present"/);
  assert.match(attendancePatternsToCsv(report, 'students'), /'=\@Casey Example/);
  const summary = analyzeAttendancePatterns(snapshot(), options);
  assert.throws(() => attendancePatternsToCsv(summary, 'students'), /student rows were not enabled/);
  assert.throws(() => attendancePatternsToCsv({ format: 'wrong', version: 1 }, 'windows'), /invalid/);
  assert.throws(() => attendancePatternsToCsv(report, 'raw'), /section must be/);
});

test('validates session windows, cohorts, thresholds, and option types', () => {
  const source = snapshot();
  assert.throws(() => analyzeAttendancePatterns(null), /snapshot must be an object/);
  assert.throws(() => analyzeAttendancePatterns(source, null), /pattern options must be an object/);
  assert.throws(() => analyzeAttendancePatterns(source, { windowSize: 0 }), /from 1 to 1000/);
  assert.throws(() => analyzeAttendancePatterns(source, { step: -1 }), /from 1 to 1000/);
  assert.throws(() => analyzeAttendancePatterns(source, { minimumTrendWindows: 1 }), /from 2 to 200/);
  assert.throws(() => analyzeAttendancePatterns(source, { minimumRecordedSessions: 0 }), /from 1 to 1000/);
  assert.throws(() => analyzeAttendancePatterns(source, { minimumGroupSize: 1 }), /from 2 to 1000/);
  assert.throws(() => analyzeAttendancePatterns(source, { declineThreshold: 2 }), /fraction from 0 to 1/);
  assert.throws(() => analyzeAttendancePatterns(source, { includeStudentRows: 'yes' }), /must be a boolean/);
  assert.throws(() => analyzeAttendancePatterns(source, { maximumStudentRows: 10_001 }), /from 1 to 10000/);
  assert.throws(() => analyzeAttendancePatterns(source, { cohorts: [{ id: 'dup', studentIds: ['A', 'A'] }] }), /duplicate students/);
  assert.throws(() => analyzeAttendancePatterns(source, { cohorts: [{ id: 'bad', studentIds: ['X'] }] }), /unknown student/);
  assert.throws(() => analyzeAttendancePatterns(source, { cohorts: [{ id: 'same', studentIds: [] }, { id: 'same', studentIds: [] }] }), /duplicate cohort ID/);
});
