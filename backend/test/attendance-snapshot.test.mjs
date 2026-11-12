import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot, parseAttendanceSnapshot,
  selectAttendanceSnapshot } from '../attendance-snapshot.mjs';

const roster = [
  { id: ' A ', name: 'An', email: 'A@example.com' },
  { id: 'B', name: 'Binh', email: 'b@example.com' },
];
const records = [
  { studentId: 'A', sessionId: '1', status: 'present' },
  { studentId: 'B', sessionId: '2', status: 'absent' },
];

test('round trips normalized snapshots without retaining input references', () => {
  const snapshot = createAttendanceSnapshot(roster, [' 1 ', '2'], records);
  const parsed = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshot));
  assert.deepEqual(parsed, snapshot);
  assert.equal(parsed.roster[0].email, 'a@example.com');
  parsed.roster[0].name = 'changed';
  assert.equal(roster[0].name, 'An');
  assert.equal(snapshot.roster[0].name, 'An');
});

test('rejects malformed, unsupported and inconsistent snapshots', () => {
  const snapshot = createAttendanceSnapshot(roster, ['1', '2'], records);
  assert.throws(() => parseAttendanceSnapshot('{'), SyntaxError);
  assert.throws(() => parseAttendanceSnapshot('null'), /object/);
  assert.throws(() => serializeAttendanceSnapshot({ ...snapshot, format: 'other' }), /format/);
  assert.throws(() => serializeAttendanceSnapshot({ ...snapshot, version: 2 }), /version/);
  assert.throws(() => createAttendanceSnapshot(roster, ['1'], records), /unknown session/);
  assert.throws(() => createAttendanceSnapshot([], ['1'], records), /unknown student/);
  assert.throws(() => createAttendanceSnapshot(roster, ['1', ' 1 '], []), /duplicate/);
});

test('selects requested students and sessions in supplied order', () => {
  const snapshot = createAttendanceSnapshot(roster, ['1', '2'], records);
  const selection = selectAttendanceSnapshot(snapshot, { studentIds: ['B', 'A'], sessionIds: ['2'] });
  assert.deepEqual(selection.roster.map((student) => student.id), ['B', 'A']);
  assert.deepEqual(selection.sessionIds, ['2']);
  assert.deepEqual(selection.records, [records[1]]);
  assert.deepEqual(selectAttendanceSnapshot(snapshot, { studentIds: [] }).records, []);
  assert.throws(() => selectAttendanceSnapshot(snapshot, { studentIds: ['A', ' A '] }), /duplicate/);
  assert.throws(() => selectAttendanceSnapshot(snapshot, { sessionIds: ['3'] }), /unknown/);
});
