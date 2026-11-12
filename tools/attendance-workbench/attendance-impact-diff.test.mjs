import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { attendanceImpactDiffToCsv, compareAttendanceImpact } from './attendance-impact-diff.mjs';

function before() {
  return createAttendanceSnapshot([
    { id: '=A', name: 'Alpha', email: 'a@example.test' },
    { id: 'B', name: 'Beta', email: 'b@example.test' },
  ], ['S1', 'S2'], [
    { studentId: '=A', sessionId: 'S1', status: 'present' },
    { studentId: '=A', sessionId: 'S2', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'present' },
  ]);
}

function after() {
  return createAttendanceSnapshot([
    { id: '=A', name: 'Alpha', email: 'a@example.test' },
    { id: 'B', name: 'Beta', email: 'b@example.test' },
    { id: 'C', name: 'Gamma', email: 'c@example.test' },
  ], ['S1', 'S2'], [
    { studentId: '=A', sessionId: 'S1', status: 'present' },
    { studentId: '=A', sessionId: 'S2', status: 'present' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'C', sessionId: 'S1', status: 'absent' },
  ]);
}

test('compares attendance changes and policy outcomes without returning student rows by default', () => {
  const report = compareAttendanceImpact(before(), after(), { policy: { minimumRate: 0.75, maximumAbsences: 1 }, minimumCohortSize: 2 });
  assert.equal(report.summary.beforeStudents, 2);
  assert.equal(report.summary.afterStudents, 3);
  assert.equal(report.summary.addedStudents, 1);
  assert.equal(report.summary.sharedStudents, 2);
  assert.equal(report.summary.changedCells, 2);
  assert.equal(report.summary.improved, 1);
  assert.equal(report.summary.declined, 1);
  assert.equal(report.summary.policyApplied, true);
  assert.equal('students' in report, false);
});

test('classifies rate-range shifts when no policy is supplied', () => {
  const report = compareAttendanceImpact(before(), after(), { includeStudentRows: true });
  const alpha = report.students.find((item) => item.studentId === '=A');
  const beta = report.students.find((item) => item.studentId === 'B');
  assert.equal(alpha.change, 'improved');
  assert.equal(beta.change, 'data_changed');
  assert.equal(alpha.before.minimumRate, 0.5);
  assert.equal(alpha.after.maximumRate, 1);
  assert.equal(beta.after.minimumRate, 0.5);
  assert.equal(beta.after.maximumRate, 1);
});

test('suppresses small cohort results and computes cohort impact for shared and new students', () => {
  const report = compareAttendanceImpact(before(), after(), { minimumCohortSize: 2,
    cohorts: [
      { id: 'shared', studentIds: ['=A', 'B'] },
      { id: 'new', studentIds: ['C'] },
    ] });
  assert.equal(report.cohorts[0].suppressed, false);
  assert.equal(report.cohorts[0].students, 2);
  assert.equal(report.cohorts[0].changedCells, 2);
  assert.equal(report.cohorts[1].suppressed, true);
  assert.equal(report.cohorts[1].changes.added_student, null);
});

test('reports session additions, removals, roster removal and shared-session cell changes', () => {
  const original = before();
  const reduced = createAttendanceSnapshot([{ id: '=A', name: 'Alpha', email: 'a@example.test' }], ['S2', 'S3'], [
    { studentId: '=A', sessionId: 'S2', status: 'absent' },
  ]);
  const report = compareAttendanceImpact(original, reduced, { includeStudentRows: true });
  assert.equal(report.summary.addedSessions, 1);
  assert.equal(report.summary.removedSessions, 1);
  assert.equal(report.summary.removedStudents, 1);
  assert.equal(report.students.find((item) => item.studentId === '=A').changedCells, 0);
});

test('exports aggregate and explicit student detail CSV with spreadsheet-safe IDs', () => {
  const report = compareAttendanceImpact(before(), after(), { includeStudentRows: true, includeStudentNames: true,
    minimumCohortSize: 2, cohorts: [{ id: 'class', label: 'Class A', studentIds: ['=A', 'B'] }] });
  assert.match(attendanceImpactDiffToCsv(report), /changedCells/);
  assert.match(attendanceImpactDiffToCsv(report, 'cohorts'), /Class A/);
  assert.match(attendanceImpactDiffToCsv(report, 'students'), /'=A/);
  assert.match(attendanceImpactDiffToCsv(report, 'students'), /Alpha/);
  assert.throws(() => attendanceImpactDiffToCsv(compareAttendanceImpact(before(), after()), 'students'), /not enabled/);
  assert.throws(() => attendanceImpactDiffToCsv(report, 'other'), /section/);
});

test('validates policies, cohort membership, and row limits', () => {
  assert.throws(() => compareAttendanceImpact(before(), after(), { policy: { minimumRate: 2, maximumAbsences: 1 } }), /minimumRate/);
  assert.throws(() => compareAttendanceImpact(before(), after(), { cohorts: [{ id: 'x', studentIds: ['unknown'] }] }), /unknown student/);
  assert.throws(() => compareAttendanceImpact(before(), after(), { includeStudentRows: true, maximumStudentRows: 2 }), /exceed/);
  assert.throws(() => compareAttendanceImpact(before(), after(), { includeStudentNames: 'yes' }), /booleans/);
});
