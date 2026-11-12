import test from 'node:test';
import assert from 'node:assert/strict';
import { attendanceRuns, longestAttendanceRuns, findConsecutiveAbsences } from '../attendance-streaks.mjs';

const roster = [{ id: 'A', name: 'An', email: 'a@example.com' }];
const sessions = ['1', '2', '3', '4', '5', '6', '7'];
const records = [
  { studentId: 'A', sessionId: '1', status: 'absent' },
  { studentId: 'A', sessionId: '2', status: 'absent' },
  { studentId: 'A', sessionId: '4', status: 'absent' },
  { studentId: 'A', sessionId: '5', status: 'absent' },
  { studentId: 'A', sessionId: '6', status: 'present' },
  { studentId: 'A', sessionId: '7', status: 'present' },
];

test('missing sessions break runs and maintain caller session order', () => {
  assert.deepEqual(attendanceRuns(roster, sessions, records)[0].runs, [
    { status: 'absent', sessionIds: ['1', '2'] },
    { status: 'missing', sessionIds: ['3'] },
    { status: 'absent', sessionIds: ['4', '5'] },
    { status: 'present', sessionIds: ['6', '7'] },
  ]);
});

test('returns all longest ties and filters absence runs by length', () => {
  const [longest] = longestAttendanceRuns(roster, sessions, records, 'absent');
  assert.equal(longest.length, 2);
  assert.equal(longest.runs.length, 2);
  assert.deepEqual(findConsecutiveAbsences(roster, sessions, records, 2).map((item) => item.sessionIds),
    [['1', '2'], ['4', '5']]);
  assert.deepEqual(findConsecutiveAbsences(roster, sessions, records, 3), []);
});

test('handles no sessions and validates arguments', () => {
  assert.deepEqual(longestAttendanceRuns(roster, [], [], 'present')[0].runs, []);
  assert.throws(() => longestAttendanceRuns(roster, sessions, records, 'late'), TypeError);
  assert.throws(() => findConsecutiveAbsences(roster, sessions, records, 0), RangeError);
  assert.throws(() => attendanceRuns(roster, ['1', '1'], []), /duplicate/);
});
