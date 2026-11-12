import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { createBundle, parseBundle, serializeBundle, putClass, removeClass, summarizeBundle,
  getClassSnapshot, summarizeStudentsAcrossClasses } from './bundle.mjs';

const snapshot = createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'a@example.com' }], ['1', '2'], [
  { studentId: 'A', sessionId: '1', status: 'present' },
]);

test('adds, replaces, reports and removes classes without modifying input', () => {
  const empty = createBundle();
  const first = putClass(empty, 'c1', 'Class 1', snapshot);
  const both = putClass(first, 'c2', 'Class 2', snapshot);
  const renamed = putClass(both, 'c1', 'Renamed', snapshot);
  assert.equal(empty.classes.length, 0);
  assert.deepEqual(renamed.classes.map((item) => item.name), ['Renamed', 'Class 2']);
  assert.deepEqual(summarizeBundle(renamed)[0], { id: 'c1', name: 'Renamed', students: 1,
    sessions: 2, expected: 2, recorded: 1, missing: 1, coverage: 0.5 });
  assert.deepEqual(removeClass(renamed, 'c1').classes.map((item) => item.id), ['c2']);
  assert.throws(() => removeClass(renamed, 'missing'), /unknown/);
  assert.deepEqual(parseBundle(serializeBundle(renamed)), renamed);
});

test('rejects invalid bundles and duplicate class IDs', () => {
  assert.throws(() => parseBundle('{}'), /invalid/);
  const valid = putClass(createBundle(), 'c1', 'Class', snapshot);
  assert.throws(() => parseBundle(JSON.stringify({ ...valid, classes: [...valid.classes, ...valid.classes] })), /duplicate/);
  assert.throws(() => putClass(valid, ' ', 'Class', snapshot), /class ID/);
  assert.throws(() => putClass(valid, 'c2', 'Class', { ...snapshot, version: 2 }), /version/);
});

test('aggregates recorded counts and highlights identity differences across classes', () => {
  const other = createAttendanceSnapshot([{ id: 'A', name: 'Anh', email: 'a@example.com' }], ['3'], [
    { studentId: 'A', sessionId: '3', status: 'absent' },
  ]);
  const bundle = putClass(putClass(createBundle(), 'c1', 'One', snapshot), 'c2', 'Two', other);
  const [student] = summarizeStudentsAcrossClasses(bundle);
  assert.deepEqual([student.present, student.absent, student.missing, student.attendanceRate], [1, 1, 1, 0.5]);
  assert.equal(student.identityConflict, true);
  assert.equal(student.classes.length, 2);
  assert.deepEqual(getClassSnapshot(bundle, 'c2'), other);
  assert.throws(() => getClassSnapshot(bundle, 'missing'), /unknown/);
});
