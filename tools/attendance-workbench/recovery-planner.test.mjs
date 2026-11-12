import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { planAttendanceRecovery, recoveryPlanToCsv } from './recovery-planner.mjs';

function snapshot() {
  return createAttendanceSnapshot([
    { id: '=A', name: 'A Student', email: 'a@example.test' },
    { id: 'B', name: 'B Student', email: 'b@example.test' },
    { id: 'C', name: 'C Student', email: 'c@example.test' },
  ], ['S1', 'S2', 'S3', 'S4'], [
    { studentId: '=A', sessionId: 'S1', status: 'present' },
    { studentId: '=A', sessionId: 'S2', status: 'present' },
    { studentId: '=A', sessionId: 'S3', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'absent' },
    { studentId: 'B', sessionId: 'S2', status: 'absent' },
    { studentId: 'B', sessionId: 'S3', status: 'absent' },
  ]);
}

const policy = { minimumRate: 0.7, maximumAbsences: 2 };

test('calculates optimistic future attendance and keeps source records untouched', () => {
  const source = snapshot();
  const before = JSON.stringify(source);
  const result = planAttendanceRecovery(source, policy, { futureSessions: 3, includeStudentRows: true, minimumCohortSize: 2 });
  const first = result.students.find((item) => item.studentId === '=A');

  assert.equal(first.present, 2);
  assert.equal(first.absent, 1);
  assert.equal(first.missing, 1);
  assert.equal(first.effectivePresent, 3);
  assert.equal(first.requiredFuturePresent, 2);
  assert.equal(first.allowedFutureAbsences, 1);
  assert.equal(first.state, 'achievable');
  assert.equal(result.students.find((item) => item.studentId === 'B').state, 'not_achievable');
  assert.equal(JSON.stringify(source), before);
});

test('compares optimistic, pessimistic and excluded missing-data assumptions', () => {
  const source = snapshot();
  const calculate = (missingMode) => planAttendanceRecovery(source, policy,
    { futureSessions: 3, missingMode, includeStudentRows: true }).students.find((item) => item.studentId === '=A');

  const optimistic = calculate('optimistic');
  const pessimistic = calculate('pessimistic');
  const excluded = calculate('exclude');
  assert.equal(optimistic.requiredFuturePresent, 2);
  assert.equal(pessimistic.requiredFuturePresent, 3);
  assert.equal(pessimistic.effectiveAbsences, 2);
  assert.equal(excluded.countedSessions, 6);
  assert.equal(excluded.requiredFuturePresent, 3);
});

test('distinguishes a policy already met, an achievable target and an unreachable target', () => {
  const source = snapshot();
  const rows = planAttendanceRecovery(source, { minimumRate: 0, maximumAbsences: 2 },
    { futureSessions: 2, missingMode: 'exclude', includeStudentRows: true }).students;
  assert.equal(rows.find((item) => item.studentId === '=A').state, 'already_satisfied');
  assert.equal(rows.find((item) => item.studentId === 'B').reasons[0], 'absence_limit_already_exceeded');

  const impossibleRate = planAttendanceRecovery(source, { minimumRate: 0.95, maximumAbsences: 10 },
    { futureSessions: 1, missingMode: 'pessimistic', includeStudentRows: true }).students;
  assert.equal(impossibleRate.find((item) => item.studentId === '=A').state, 'not_achievable');
  assert.ok(impossibleRate.find((item) => item.studentId === '=A').reasons.includes('minimum_rate_unreachable'));
});

test('reports no counted sessions as undetermined and accepts a zero-future schedule', () => {
  const source = createAttendanceSnapshot([{ id: 'empty', name: 'Empty', email: 'empty@example.test' }], [], []);
  const result = planAttendanceRecovery(source, policy, { futureSessions: 0, includeStudentRows: true });
  assert.equal(result.students[0].state, 'undetermined');
  assert.ok(result.students[0].reasons.includes('no_counted_sessions'));
  assert.equal(result.summary.undetermined, 1);
});

test('suppresses small cohort results and emits aggregate summaries by default', () => {
  const result = planAttendanceRecovery(snapshot(), policy, {
    futureSessions: 3,
    minimumCohortSize: 2,
    cohorts: [
      { id: 'larger', studentIds: ['=A', 'B'] },
      { id: 'single', studentIds: ['C'] },
    ],
  });
  assert.equal('students' in result, false);
  assert.equal(result.cohorts[0].suppressed, false);
  assert.equal(result.cohorts[0].students, 2);
  assert.equal(result.cohorts[1].suppressed, true);
  assert.equal(result.cohorts[1].feasible, null);
});

test('exports summary, cohort and opted-in student CSV with formula protection', () => {
  const result = planAttendanceRecovery(snapshot(), policy, { futureSessions: 3, includeStudentRows: true,
    minimumCohortSize: 2, cohorts: [{ id: 'class', studentIds: ['=A', 'B'] }] });
  assert.match(recoveryPlanToCsv(result), /minimumRate/);
  assert.match(recoveryPlanToCsv(result, 'cohorts'), /class/);
  assert.match(recoveryPlanToCsv(result, 'students'), /'=A/);
  assert.match(recoveryPlanToCsv(result, 'students'), /A Student/);
  assert.throws(() => recoveryPlanToCsv(planAttendanceRecovery(snapshot(), policy, { futureSessions: 3 }), 'students'), /not enabled/);
  assert.throws(() => recoveryPlanToCsv(result, 'unknown'), /section/);
});

test('validates policies, limits, cohort membership and option types', () => {
  assert.throws(() => planAttendanceRecovery(snapshot(), { minimumRate: 1.1, maximumAbsences: 2 }, { futureSessions: 1 }), /minimumRate/);
  assert.throws(() => planAttendanceRecovery(snapshot(), { minimumRate: 0.5, maximumAbsences: -1 }, { futureSessions: 1 }), /maximumAbsences/);
  assert.throws(() => planAttendanceRecovery(snapshot(), policy, { futureSessions: -1 }), /futureSessions/);
  assert.throws(() => planAttendanceRecovery(snapshot(), policy, { futureSessions: 1, missingMode: 'fill' }), /missingMode/);
  assert.throws(() => planAttendanceRecovery(snapshot(), policy, { futureSessions: 1, includeStudentRows: true, maximumStudentRows: 2 }), /exceed/);
  assert.throws(() => planAttendanceRecovery(snapshot(), policy, { futureSessions: 1, cohorts: [{ id: 'bad', studentIds: ['missing'] }] }), /unknown student/);
});
