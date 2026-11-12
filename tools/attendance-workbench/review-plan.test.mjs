import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { allocateReviewCases, buildReviewPlan, reviewPlanToCsv } from './review-plan.mjs';

function sourceSnapshot() {
  const roster = [
    { id: 'A', name: 'All absent', email: 'a@example.test' },
    { id: 'B', name: 'Unsteady', email: 'b@example.test' },
    { id: 'C', name: 'Missing outcomes', email: 'c@example.test' },
    { id: 'D', name: 'Consistent', email: 'd@example.test' },
  ];
  const sessionIds = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6'];
  const pattern = {
    A: ['absent', 'absent', 'absent', 'absent', 'absent', 'absent'],
    B: ['present', 'present', 'absent', 'present', 'absent', 'absent'],
    C: ['present', 'missing', 'present', 'missing', 'present', 'missing'],
    D: ['present', 'present', 'present', 'present', 'present', 'present'],
  };
  const records = roster.flatMap((student) => pattern[student.id].flatMap((status, index) => status === 'missing' ? [] :
    [{ studentId: student.id, sessionId: sessionIds[index], status }]));
  return createAttendanceSnapshot(roster, sessionIds, records);
}

test('builds stable, explainable review cases and never changes the source snapshot', () => {
  const source = sourceSnapshot();
  const original = JSON.stringify(source);
  const plan = buildReviewPlan(source, { futureSessions: 2, minimumObserved: 3, maximumMissing: 1,
    absenceStreak: 3, recentWindow: 3, declineBy: 0.2 });
  const again = buildReviewPlan(source, { futureSessions: 2, minimumObserved: 3, maximumMissing: 1,
    absenceStreak: 3, recentWindow: 3, declineBy: 0.2 });
  assert.deepEqual(plan, again);
  assert.equal(JSON.stringify(source), original);
  assert.equal(plan.summary.total, 3);
  assert.equal(plan.cases[0].studentId, 'A');
  assert.equal(plan.cases[0].priority, 'urgent');
  assert.ok(plan.cases[0].reasons.some((reason) => reason.code === 'absence_streak'));
  assert.ok(plan.cases[0].reasons.some((reason) => reason.code === 'target_unreachable'));
  assert.equal(plan.cases.find((item) => item.studentId === 'C').priority, 'review');
  assert.ok(plan.cases.find((item) => item.studentId === 'C').reasons.some((reason) => reason.code === 'missing_results'));
  assert.equal(plan.cases.some((item) => item.studentId === 'D'), false);
  assert.equal(plan.cases.every((item) => item.humanReviewRequired), true);
  assert.match(plan.notice, /Confirm source records/);
});

test('distinguishes data gaps from rate and trend signals using caller thresholds', () => {
  const plan = buildReviewPlan(sourceSnapshot(), { futureSessions: 0, lowRate: 0.8, criticalRate: 0.2,
    maximumMissing: 0, minimumObserved: 5, absenceStreak: 5, recentWindow: 2, declineBy: 0.1 });
  const allAbsent = plan.cases.find((item) => item.studentId === 'A');
  assert.equal(allAbsent.priority, 'urgent');
  assert.equal(allAbsent.target.reachable, false);
  assert.ok(allAbsent.reasons.some((reason) => reason.code === 'low_rate'));
  assert.ok(allAbsent.reasons.some((reason) => reason.code === 'target_unreachable'));
  assert.ok(plan.summary.byReason.missing_results >= 1);
  assert.ok(plan.cases.find((item) => item.studentId === 'B').reasons.some((reason) => reason.code === 'recent_decline'));
});

test('returns an empty queue when records meet all thresholds', () => {
  const snapshot = createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'a@example.test' }], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' }, { studentId: 'A', sessionId: 'S2', status: 'present' },
  ]);
  const plan = buildReviewPlan(snapshot, { minimumObserved: 2, maximumMissing: 0, futureSessions: 0 });
  assert.deepEqual(plan.cases, []);
  assert.deepEqual(plan.summary, { total: 0, urgent: 0, high: 0, review: 0, byReason: {} });
});

test('allocates highest-priority cases first and respects review capacity', () => {
  const plan = buildReviewPlan(sourceSnapshot(), { futureSessions: 2, maximumMissing: 1, absenceStreak: 3 });
  const result = allocateReviewCases(plan, [
    { id: 'r2', name: 'Reviewer B', capacity: 1 },
    { id: 'r1', name: 'Reviewer A', capacity: 1 },
  ]);
  assert.equal(result.summary.assigned, 2);
  assert.equal(result.summary.unassigned, plan.cases.length - 2);
  assert.equal(result.assigned[0].priority, 'urgent');
  assert.deepEqual(result.reviewers.map((reviewer) => reviewer.assigned), [1, 1]);
  assert.ok(result.unassigned.length > 0);
  assert.deepEqual(allocateReviewCases(plan, []).unassigned.length, plan.cases.length);
});

test('rejects invalid priorities, reviewer identities and capacity declarations', () => {
  const plan = buildReviewPlan(sourceSnapshot());
  assert.throws(() => allocateReviewCases({}, []), /review plan/);
  assert.throws(() => allocateReviewCases(plan, {}), /reviewers/);
  assert.throws(() => allocateReviewCases(plan, [{ id: 'r', name: 'R', capacity: 1 }, { id: 'r', name: 'Other', capacity: 2 }]), /duplicate reviewer/);
  assert.throws(() => allocateReviewCases(plan, [{ id: 'r', name: 'R', capacity: -1 }]), /capacity/);
  assert.throws(() => allocateReviewCases(plan, [{ id: '', name: 'R', capacity: 1 }]), /requires/);
});

test('exports a compact formula-safe worklist without embedding all attendance cells', () => {
  const snapshot = createAttendanceSnapshot([{ id: '=CMD()', name: '=Link', email: 'x@example.test' }], ['S1', 'S2'], [
    { studentId: '=CMD()', sessionId: 'S1', status: 'absent' }, { studentId: '=CMD()', sessionId: 'S2', status: 'absent' },
  ]);
  const plan = buildReviewPlan(snapshot, { minimumObserved: 1, absenceStreak: 2, futureSessions: 0 });
  const csv = reviewPlanToCsv(plan);
  assert.match(csv, /'="?CMD\(\)/);
  assert.match(csv, /'="?Link/);
  assert.doesNotMatch(csv, /"sessionIds"/);
  assert.throws(() => reviewPlanToCsv({ version: 2 }), /invalid/);
});

test('validates rate, window and output bounds', () => {
  assert.throws(() => buildReviewPlan(sourceSnapshot(), { lowRate: 0.2, criticalRate: 0.5 }), /criticalRate/);
  assert.throws(() => buildReviewPlan(sourceSnapshot(), { futureSessions: 501 }), /futureSessions/);
  assert.throws(() => buildReviewPlan(sourceSnapshot(), { recentWindow: 0 }), /recentWindow/);
  assert.throws(() => buildReviewPlan(sourceSnapshot(), { maximumCases: 1 }), /exceeds 1 cases/);
  assert.throws(() => buildReviewPlan(sourceSnapshot(), null), /options/);
});
