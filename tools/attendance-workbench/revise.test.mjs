import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { reviseSnapshot } from './revise.mjs';

const a = { id: 'A', name: 'An', email: 'a@example.com' };
const b = { id: 'B', name: 'Binh', email: 'b@example.com' };
const snapshot = createAttendanceSnapshot([a, b], ['1', '2'], [
  { studentId: 'A', sessionId: '1', status: 'present' },
  { studentId: 'B', sessionId: '2', status: 'absent' },
]);

test('adds and reorders sessions and updates student details', () => {
  const result = reviseSnapshot(snapshot, { roster: [{ ...a, name: 'Anh' }, b], sessionIds: ['2', '1', '3'] });
  assert.equal(result.snapshot.roster[0].name, 'Anh');
  assert.deepEqual(result.snapshot.sessionIds, ['2', '1', '3']);
  assert.equal(result.snapshot.records.length, 2);
  assert.equal(snapshot.roster[0].name, 'An');
});

test('requires explicit removal of orphaned attendance and reports removed records', () => {
  assert.throws(() => reviseSnapshot(snapshot, { roster: [a] }), /1 attendance record/);
  const result = reviseSnapshot(snapshot, { roster: [a], dropRecords: true });
  assert.deepEqual(result.removed, [{ studentId: 'B', sessionId: '2', status: 'absent' }]);
  assert.equal(result.snapshot.records.length, 1);
  assert.throws(() => reviseSnapshot(snapshot, { sessionIds: [] }), /2 attendance record/);
  assert.throws(() => reviseSnapshot(snapshot, { sessionIds: ['1', '1'] }), /duplicate/);
  assert.throws(() => reviseSnapshot(snapshot, { dropRecords: 'yes' }), /boolean/);
});
