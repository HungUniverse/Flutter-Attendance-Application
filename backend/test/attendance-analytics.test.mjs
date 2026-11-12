import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeRecords, summarizeAttendance, summarizeStudents, summarizeSessions,
  findStudentsBelowRate, findMissingStudents, compareAttendance, currentAbsenceStreak,
  sessionsNeededForRate, attendanceToCsv } from '../attendance-analytics.mjs';

const records = [
  { studentId: 'A', sessionId: '1', status: 'present' },
  { studentId: 'A', sessionId: '2', status: 'absent' },
  { studentId: 'B', sessionId: '1', status: 'absent' },
];

test('normalization checks status and duplicate pairs after trimming', () => {
  assert.equal(normalizeRecords([{ ...records[0], studentId: ' A ' }])[0].studentId, 'A');
  assert.throws(() => normalizeRecords([records[0], { ...records[0], studentId: ' A ' }]), /duplicate/);
  assert.throws(() => normalizeRecords([{ ...records[0], status: 'late' }]), /status/);
});

test('summaries calculate recorded attendance, including empty input', () => {
  assert.deepEqual(summarizeAttendance([]), { total: 0, present: 0, absent: 0, attendanceRate: null });
  assert.deepEqual(summarizeAttendance(records), { total: 3, present: 1, absent: 2, attendanceRate: 1 / 3 });
  assert.deepEqual(summarizeStudents(records).map((s) => [s.studentId, s.attendanceRate]), [['A', 0.5], ['B', 0]]);
  assert.deepEqual(summarizeSessions(records).map((s) => [s.sessionId, s.total]), [['1', 2], ['2', 1]]);
});

test('thresholds and missing records are explicit', () => {
  assert.deepEqual(findStudentsBelowRate(records, 0.5).map((s) => s.studentId), ['B']);
  assert.throws(() => findStudentsBelowRate(records, 2), RangeError);
  assert.deepEqual(findMissingStudents(records, ['A', 'B', 'C'], '2'), ['B', 'C']);
  assert.throws(() => findMissingStudents(records, ['A', ' A '], '2'), /duplicate/);
});

test('comparison detects additions, removals and status changes', () => {
  const result = compareAttendance(records, [{ ...records[0], status: 'absent' }, records[2],
    { studentId: 'C', sessionId: '1', status: 'present' }]);
  assert.equal(result.added[0].studentId, 'C');
  assert.equal(result.removed[0].sessionId, '2');
  assert.equal(result.changed[0].after.status, 'absent');
});

test('absence streak stops at a missing record as well as a present record', () => {
  assert.equal(currentAbsenceStreak(records, 'A', ['1', '2']), 1);
  assert.equal(currentAbsenceStreak(records, 'A', ['1', '2', '3']), 0);
  assert.throws(() => currentAbsenceStreak(records, 'A', ['1', '1']), /duplicate/);
});

test('required sessions handles impossible perfect attendance and empty history', () => {
  assert.equal(sessionsNeededForRate(1, 2, 0.75), 2);
  assert.equal(sessionsNeededForRate(1, 2, 1), null);
  assert.equal(sessionsNeededForRate(0, 0, 0.8), 1);
  assert.throws(() => sessionsNeededForRate(2, 1, 0.5), RangeError);
});

test('required sessions meets exact decimal thresholds with the minimum count', () => {
  assert.equal(sessionsNeededForRate(0, 1, 0.8), 4);
  assert.equal(sessionsNeededForRate(0, 1, 0.9), 9);
  assert.equal(sessionsNeededForRate(4, 5, 0.8), 0);
  assert.equal(sessionsNeededForRate(0, Number.MAX_SAFE_INTEGER, 0.8), null);
  assert.throws(() => sessionsNeededForRate(0, Number.MAX_SAFE_INTEGER + 1, 0.8), RangeError);
});

test('CSV quotes values and escapes spreadsheet formulas', () => {
  assert.equal(attendanceToCsv([{ studentId: '=A1', sessionId: 'a,"b', status: 'present' }]),
    'studentId,sessionId,status\r\n"\'=A1","a,""b","present"');
});
