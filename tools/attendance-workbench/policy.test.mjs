import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { evaluatePolicy } from './policy.mjs';

const roster = ['A', 'B', 'C', 'D'].map((id) => ({ id, name: id, email: `${id.toLowerCase()}@example.com` }));
const records = [
  { studentId: 'A', sessionId: '1', status: 'present' },
  { studentId: 'A', sessionId: '2', status: 'present' },
  { studentId: 'B', sessionId: '1', status: 'absent' },
  { studentId: 'B', sessionId: '2', status: 'absent' },
  { studentId: 'C', sessionId: '1', status: 'present' },
];

test('distinguishes passing, failing and unresolved outcomes', () => {
  const snapshot = createAttendanceSnapshot(roster, ['1', '2'], records);
  const results = evaluatePolicy(snapshot, { minimumRate: 0.5, maximumAbsences: 1 });
  assert.deepEqual(results.map((item) => item.status), ['pass', 'fail', 'pass', 'undetermined']);
  assert.deepEqual(results[1].reasons, ['rate_below_minimum', 'absences_above_maximum']);
  assert.equal(results[2].minimumRate, 0.5);
  assert.equal(results[2].maximumRate, 1);
});

test('uses null bounds for no sessions and validates rules', () => {
  const empty = createAttendanceSnapshot(roster, [], []);
  assert.equal(evaluatePolicy(empty, { minimumRate: 0, maximumAbsences: 0 })[0].status, 'undetermined');
  assert.throws(() => evaluatePolicy(empty, { minimumRate: 2, maximumAbsences: 1 }), RangeError);
  assert.throws(() => evaluatePolicy(empty, { minimumRate: 0.5, maximumAbsences: -1 }), RangeError);
});
