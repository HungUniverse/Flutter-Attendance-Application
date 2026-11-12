import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../attendance-snapshot.mjs';
import { applyAttendanceBatch } from '../attendance-batch.mjs';

const roster = [
  { id: 'A', name: 'An', email: 'a@example.com' },
  { id: 'B', name: 'Binh', email: 'b@example.com' },
];
const snapshot = createAttendanceSnapshot(roster, ['1', '2'], [
  { studentId: 'A', sessionId: '1', status: 'present' },
  { studentId: 'B', sessionId: '1', status: 'absent' },
]);

test('applies additions, updates and removals without modifying the input', () => {
  const result = applyAttendanceBatch(snapshot, [
    { studentId: ' A ', sessionId: '1', expected: 'present', status: 'absent' },
    { studentId: 'B', sessionId: '1', expected: 'absent', status: null },
    { studentId: 'B', sessionId: '2', expected: null, status: 'present' },
  ]);
  assert.deepEqual(result.conflicts, []);
  assert.deepEqual(result.snapshot.records, [
    { studentId: 'A', sessionId: '1', status: 'absent' },
    { studentId: 'B', sessionId: '2', status: 'present' },
  ]);
  assert.equal(snapshot.records[0].status, 'present');
  assert.equal(snapshot.records.length, 2);
});

test('returns all conflicts and applies no partial result', () => {
  const result = applyAttendanceBatch(snapshot, [
    { studentId: 'A', sessionId: '1', expected: null, status: 'absent' },
    { studentId: 'B', sessionId: '2', expected: 'present', status: null },
  ]);
  assert.equal(result.snapshot, null);
  assert.deepEqual(result.conflicts.map(({ index, actual }) => [index, actual]), [[0, 'present'], [1, null]]);
  assert.equal(snapshot.records.length, 2);
});

test('rejects duplicate keys, invalid statuses and unknown references', () => {
  const change = { studentId: 'A', sessionId: '1', expected: 'present', status: 'absent' };
  assert.throws(() => applyAttendanceBatch(snapshot, [change, change]), /duplicate/);
  assert.throws(() => applyAttendanceBatch(snapshot, [{ ...change, expected: undefined }]), /status/);
  assert.throws(() => applyAttendanceBatch(snapshot, [{ ...change, studentId: 'C' }]), /unknown student/);
  assert.throws(() => applyAttendanceBatch(snapshot, [{ ...change, sessionId: '3' }]), /unknown session/);
  assert.deepEqual(applyAttendanceBatch(snapshot, []).snapshot, snapshot);
});
