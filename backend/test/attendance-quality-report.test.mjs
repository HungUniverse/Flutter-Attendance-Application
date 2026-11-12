import test from 'node:test';
import assert from 'node:assert/strict';
import { attendanceQualityReport, selectCoverageGaps } from '../attendance-quality-report.mjs';

const roster = [
  { id: 'A', name: 'An', email: 'a@example.com' },
  { id: 'B', name: 'Binh', email: 'b@example.com' },
];

test('reports coverage and breakdowns with invalid and duplicate rows', () => {
  const report = attendanceQualityReport(roster, [' 1 ', '2'], [
    { studentId: 'A', sessionId: '1', status: 'present' },
    { studentId: 'A', sessionId: '1', status: 'absent' },
    { studentId: 'B', sessionId: '1', status: 'late' },
    { studentId: 'B', sessionId: '2', status: 'absent' },
  ]);
  assert.deepEqual([report.expected, report.recorded, report.missing, report.coverage], [4, 2, 2, 0.5]);
  assert.deepEqual(report.issues.map((issue) => issue.code), ['duplicate', 'invalid_status']);
  assert.deepEqual(report.students.map((student) => student.missingSessionIds), [['2'], ['1']]);
  assert.deepEqual(report.sessions.map((session) => session.missingStudentIds), [['B'], ['A']]);
  assert.equal(report.students[0].present, 1);
  assert.equal(report.sessions[1].absent, 1);
  assert.equal(selectCoverageGaps(report).students.length, 2);
  assert.equal(selectCoverageGaps(report, 2).sessions.length, 0);
});

test('uses null coverage for an empty expected set and validates inputs', () => {
  assert.equal(attendanceQualityReport([], ['1'], []).coverage, null);
  assert.equal(attendanceQualityReport(roster, [], []).coverage, null);
  assert.throws(() => attendanceQualityReport(roster, ['1', ' 1 '], []), /duplicate/);
  assert.throws(() => selectCoverageGaps({}, 1), /invalid/);
  assert.throws(() => selectCoverageGaps({ students: [], sessions: [] }, 0), RangeError);
});
