import test from 'node:test';
import assert from 'node:assert/strict';
import { auditAttendance } from '../attendance-audit.mjs';

const roster = [
  { id: 'A', name: 'An', email: 'a@example.com' },
  { id: 'B', name: 'Binh', email: 'b@example.com' },
];

test('reports invalid, unknown and duplicate rows without hiding missing pairs', () => {
  const records = [
    { studentId: ' A ', sessionId: ' 1 ', status: 'present' },
    { studentId: 'A', sessionId: '1', status: 'absent' },
    { studentId: 'B', sessionId: '1', status: 'late' },
    { studentId: 'C', sessionId: '2', status: 'present' },
    { studentId: '', sessionId: 'unknown', status: 'unknown' },
    null,
    { studentId: 'B', sessionId: '2', status: 'absent' },
  ];
  const result = auditAttendance(roster, ['1', '2'], records);
  assert.deepEqual(result.validRecords, [
    { studentId: 'A', sessionId: '1', status: 'present' },
    { studentId: 'B', sessionId: '2', status: 'absent' },
  ]);
  assert.deepEqual(result.issues, [
    { index: 1, code: 'duplicate', firstIndex: 0 },
    { index: 2, code: 'invalid_status' },
    { index: 3, code: 'unknown_student' },
    { index: 4, code: 'missing_student_id' },
    { index: 4, code: 'unknown_session' },
    { index: 4, code: 'invalid_status' },
    { index: 5, code: 'invalid_record' },
  ]);
  assert.deepEqual(result.missing, [
    { studentId: 'B', sessionId: '1' }, { studentId: 'A', sessionId: '2' },
  ]);
  assert.equal(records[0].studentId, ' A ');
});

test('invalid rows do not reserve a pair ahead of a valid row', () => {
  const result = auditAttendance(roster, ['1'], [
    { studentId: 'A', sessionId: '1', status: 'late' },
    { studentId: 'A', sessionId: '1', status: 'present' },
  ]);
  assert.equal(result.validRecords.length, 1);
  assert.deepEqual(result.missing, [{ studentId: 'B', sessionId: '1' }]);
});

test('validates reference data and handles empty inputs', () => {
  assert.deepEqual(auditAttendance([], [], []), { validRecords: [], issues: [], missing: [] });
  assert.throws(() => auditAttendance(roster, ['x', ' x '], []), /duplicate/);
  assert.throws(() => auditAttendance(roster, ['x'], null), /records/);
  assert.throws(() => auditAttendance([roster[0], roster[0]], [], []), /duplicate/);
});
