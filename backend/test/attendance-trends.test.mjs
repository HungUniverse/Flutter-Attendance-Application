import test from 'node:test';
import assert from 'node:assert/strict';
import { rollingAttendance, compareAttendancePeriods } from '../attendance-trends.mjs';

const roster = [{ id: 'A', name: 'An', email: 'a@example.com' }];
const sessions = ['1', '2', '3', '4'];
const records = [
  { studentId: 'A', sessionId: '1', status: 'present' },
  { studentId: 'A', sessionId: '2', status: 'absent' },
  { studentId: 'A', sessionId: '4', status: 'present' },
];

test('calculates rolling windows while distinguishing missing data', () => {
  const windows = rollingAttendance(roster, sessions, records, 2)[0].windows;
  assert.deepEqual(windows.map(({ present, absent, missing, attendanceRate }) =>
    [present, absent, missing, attendanceRate]), [[1, 1, 0, 0.5], [0, 1, 1, 0], [1, 0, 1, 1]]);
  assert.equal(windows[1].startSessionId, '2');
  assert.equal(windows[1].endSessionId, '3');
  assert.deepEqual(rollingAttendance(roster, sessions, records, 5)[0].windows, []);
  assert.equal(rollingAttendance(roster, sessions, [], 1)[0].windows[0].attendanceRate, null);
});

test('compares chronological ranges and avoids a rate for missing data', () => {
  const [result] = compareAttendancePeriods(roster, sessions, records,
    { start: '1', end: '2' }, { start: '3', end: '4' });
  assert.equal(result.first.attendanceRate, 0.5);
  assert.equal(result.second.attendanceRate, 1);
  assert.equal(result.second.missing, 1);
  assert.equal(result.change, 0.5);
  assert.equal(compareAttendancePeriods(roster, sessions, [],
    { start: '1', end: '1' }, { start: '2', end: '2' })[0].change, null);
});

test('validates window size and period boundaries', () => {
  assert.throws(() => rollingAttendance(roster, sessions, records, 0), RangeError);
  assert.throws(() => compareAttendancePeriods(roster, sessions, records,
    { start: '1', end: '3' }, { start: '3', end: '4' }), /disjoint/);
  assert.throws(() => compareAttendancePeriods(roster, sessions, records,
    { start: '2', end: '1' }, { start: '3', end: '4' }), /ordered/);
  assert.throws(() => compareAttendancePeriods(roster, sessions, records, null, {}), TypeError);
});
