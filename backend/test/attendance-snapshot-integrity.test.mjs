import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../attendance-snapshot.mjs';
import { digestAttendanceSnapshot, signAttendanceSnapshot, verifyAttendanceSnapshot }
  from '../attendance-snapshot-integrity.mjs';

const roster = [{ id: 'A', name: 'An', email: 'a@example.com' }];
const snapshot = createAttendanceSnapshot(roster, ['1', '2'], [
  { studentId: 'A', sessionId: '1', status: 'present' },
]);
const key = Buffer.alloc(32, 1);

test('digest is stable for equivalent normalized snapshots and changes with data', () => {
  const equivalent = createAttendanceSnapshot([{ ...roster[0], email: 'A@EXAMPLE.COM' }], ['1', '2'], snapshot.records);
  assert.equal(digestAttendanceSnapshot(snapshot), digestAttendanceSnapshot(equivalent));
  const reordered = createAttendanceSnapshot(roster, ['2', '1'], snapshot.records);
  assert.notEqual(digestAttendanceSnapshot(snapshot), digestAttendanceSnapshot(reordered));
});

test('verifies the intended data and secret', () => {
  const signature = signAttendanceSnapshot(snapshot, key);
  assert.equal(verifyAttendanceSnapshot(snapshot, key, signature), true);
  assert.equal(verifyAttendanceSnapshot(snapshot, Buffer.alloc(32, 2), signature), false);
  const changed = createAttendanceSnapshot(roster, ['1', '2'], [
    { studentId: 'A', sessionId: '1', status: 'absent' },
  ]);
  assert.equal(verifyAttendanceSnapshot(changed, key, signature), false);
});

test('validates keys, signatures and snapshot structure', () => {
  assert.throws(() => signAttendanceSnapshot(snapshot, Buffer.alloc(31)), /key/);
  assert.throws(() => signAttendanceSnapshot(snapshot, 'secret'), /key/);
  assert.throws(() => verifyAttendanceSnapshot(snapshot, key, 'bad'), /signature/);
  assert.throws(() => digestAttendanceSnapshot({ ...snapshot, version: 2 }), /version/);
});
