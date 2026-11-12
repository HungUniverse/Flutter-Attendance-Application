import test from 'node:test';
import assert from 'node:assert/strict';
import { buildAttendanceReport } from '../attendance-report.mjs';

const roster = [{ id: 's1', name: 'Student', email: 's@example.com' }];

test('reports missing sessions separately from absences', () => {
  const report = buildAttendanceReport(roster, ['a', 'b', 'c'], [
    { studentId: 's1', sessionId: 'a', status: 'present' },
    { studentId: 's1', sessionId: 'b', status: 'absent' },
  ]);
  assert.equal(report[0].attendanceRate, 0.5);
  assert.equal(report[0].missing, 1);
  assert.deepEqual(report[0].sessions.map((entry) => entry.status), ['present', 'absent', 'missing']);
});

test('rejects records outside the supplied roster or sessions', () => {
  assert.throws(() => buildAttendanceReport(roster, ['a'], [
    { studentId: 'other', sessionId: 'a', status: 'present' },
  ]), /unknown student/);
  assert.throws(() => buildAttendanceReport(roster, ['a'], [
    { studentId: 's1', sessionId: 'b', status: 'present' },
  ]), /unknown session/);
  assert.throws(() => buildAttendanceReport(roster, ['a', ' a '], []), /duplicate session/);
});

test('returns a null rate when no attendance has been recorded', () => {
  assert.equal(buildAttendanceReport(roster, ['a'], [])[0].attendanceRate, null);
});
