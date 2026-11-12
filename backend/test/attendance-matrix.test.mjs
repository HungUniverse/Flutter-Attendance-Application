import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSessionMatrix, findMissingAttendance } from '../attendance-matrix.mjs';

const roster = [
  { id: 'A', name: 'An', email: 'a@example.com' },
  { id: 'B', name: 'Binh', email: 'b@example.com' },
];
const records = [
  { studentId: 'A', sessionId: '1', status: 'present' },
  { studentId: 'B', sessionId: '1', status: 'absent' },
  { studentId: 'B', sessionId: '2', status: 'present' },
];

test('summarizes session attendance without treating missing records as absences', () => {
  const matrix = buildSessionMatrix(roster, [' 1 ', '2'], records);
  assert.deepEqual(matrix.map(({ sessionId, present, absent, missing, attendanceRate }) =>
    ({ sessionId, present, absent, missing, attendanceRate })), [
    { sessionId: '1', present: 1, absent: 1, missing: 0, attendanceRate: 0.5 },
    { sessionId: '2', present: 1, absent: 0, missing: 1, attendanceRate: 1 },
  ]);
  assert.deepEqual(findMissingAttendance(roster, ['1', '2'], records), [
    { sessionId: '2', student: roster[0] },
  ]);
});

test('handles empty rosters and rejects invalid session or record references', () => {
  assert.equal(buildSessionMatrix([], ['1'], [])[0].attendanceRate, null);
  assert.throws(() => buildSessionMatrix([], ['1', ' 1 '], []), /duplicate/);
  assert.throws(() => buildSessionMatrix(roster, ['1'], records), /unknown session/);
});
