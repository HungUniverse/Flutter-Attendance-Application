import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeAttendance, resolveAttendanceConflicts } from '../attendance-merge.mjs';

const record = (studentId, status, sessionId = 's') => ({ studentId, sessionId, status });

test('merges independent additions, edits, deletions and identical changes', () => {
  const base = [record('a', 'present'), record('b', 'absent'), record('c', 'present')];
  const left = [record('a', 'absent'), record('b', 'absent'), record('d', 'present')];
  const right = [record('a', 'present'), record('b', 'present'), record('c', 'present'), record('d', 'present')];
  assert.deepEqual(mergeAttendance(base, left, right), {
    records: [record('a', 'absent'), record('b', 'present'), record('d', 'present')], conflicts: [],
  });
  assert.equal(base[0].status, 'present');
});

test('detects edit versus delete and divergent concurrent additions', () => {
  const result = mergeAttendance([record('a', 'present')], [record('a', 'absent'), record('b', 'present')],
    [record('b', 'absent')]);
  assert.equal(result.records.length, 0);
  assert.deepEqual(result.conflicts.map((conflict) => conflict.studentId), ['a', 'b']);
  assert.equal(result.conflicts[0].right, null);
  assert.equal(result.conflicts[1].base, null);
  assert.deepEqual(resolveAttendanceConflicts(result, [
    { studentId: 'a', sessionId: 's', source: 'right' },
    { studentId: 'b', sessionId: 's', source: 'left' },
  ]), [record('b', 'present')]);
});

test('requires exactly one valid choice for each conflict', () => {
  const result = mergeAttendance([], [record('a', 'present')], [record('a', 'absent')]);
  const choice = { studentId: 'a', sessionId: 's', source: 'base' };
  assert.deepEqual(resolveAttendanceConflicts(result, [choice]), []);
  assert.throws(() => resolveAttendanceConflicts(result, []), /missing/);
  assert.throws(() => resolveAttendanceConflicts(result, [choice, choice]), /duplicate/);
  assert.throws(() => resolveAttendanceConflicts(result, [choice, { ...choice, studentId: 'b' }]), /does not match/);
  assert.throws(() => resolveAttendanceConflicts(result, [{ ...choice, source: 'other' }]), /invalid/);
});

test('rejects duplicate records and preserves IDs containing separators', () => {
  const item = record('a/s', 'present', 'b/s');
  assert.throws(() => mergeAttendance([item, item], [], []), /duplicate/);
  assert.deepEqual(mergeAttendance([], [item], []).records, [item]);
});

test('trims whitespace on conflict resolution choices and rejects blank IDs', () => {
  const result = mergeAttendance([], [record('a', 'present')], [record('a', 'absent')]);
  assert.deepEqual(
    resolveAttendanceConflicts(result, [{ studentId: ' a ', sessionId: ' s ', source: 'left' }]),
    [record('a', 'present')],
  );
  assert.throws(
    () => resolveAttendanceConflicts(result, [{ studentId: '   ', sessionId: 's', source: 'left' }]),
    /invalid conflict choice/,
  );
});
