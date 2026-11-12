import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../attendance-snapshot.mjs';
import { compareAttendanceSnapshots, hasSnapshotChanges } from '../attendance-snapshot-diff.mjs';

const a = { id: 'A', name: 'An', email: 'a@example.com' };
const b = { id: 'B', name: 'Binh', email: 'b@example.com' };
const record = (studentId, sessionId, status) => ({ studentId, sessionId, status });

test('compares roster, session and attendance changes together', () => {
  const before = createAttendanceSnapshot([a, b], ['1', '2'], [
    record('A', '1', 'present'), record('B', '2', 'absent'),
  ]);
  const after = createAttendanceSnapshot([{ ...a, name: 'Anh' }], ['2', '3'], [
    record('A', '3', 'present'),
  ]);
  const diff = compareAttendanceSnapshots(before, after);
  assert.deepEqual(diff.roster.removed, [b]);
  assert.deepEqual(diff.roster.changed[0].fields, ['name']);
  assert.deepEqual(diff.sessions.added, ['3']);
  assert.deepEqual(diff.sessions.removed, ['1']);
  assert.equal(diff.sessions.reordered, false);
  assert.equal(diff.attendance.removed.length, 2);
  assert.equal(diff.attendance.added.length, 1);
  assert.equal(hasSnapshotChanges(diff), true);
});

test('detects relative reordering independently of additions and deletions', () => {
  const before = createAttendanceSnapshot([], ['1', '2', '3'], []);
  const added = createAttendanceSnapshot([], ['1', '4', '2', '3'], []);
  const reordered = createAttendanceSnapshot([], ['3', '1', '2'], []);
  assert.equal(compareAttendanceSnapshots(before, added).sessions.reordered, false);
  assert.equal(compareAttendanceSnapshots(before, reordered).sessions.reordered, true);
  assert.equal(hasSnapshotChanges(compareAttendanceSnapshots(before, before)), false);
});

test('validates both snapshots and comparison shape', () => {
  const valid = createAttendanceSnapshot([], [], []);
  assert.throws(() => compareAttendanceSnapshots(valid, { ...valid, version: 2 }), /version/);
  assert.throws(() => hasSnapshotChanges({}), /invalid/);
});
