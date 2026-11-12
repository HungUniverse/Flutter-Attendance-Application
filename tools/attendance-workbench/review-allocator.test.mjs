import test from 'node:test';
import assert from 'node:assert/strict';
import { allocateReviewCasesConstrained, reviewAllocationToCsv } from './review-allocator.mjs';

const reviewers = [
  { id: 'r1', name: 'A Reviewer', skills: ['attendance'], capacityPoints: 8, currentLoadPoints: 2 },
  { id: 'r2', name: 'B Reviewer', skills: ['attendance', 'language-vi'], capacityPoints: 8 },
];

test('prioritizes urgent cases and spreads work using projected utilization', () => {
  const result = allocateReviewCasesConstrained([
    { caseId: 'routine', studentId: 's1' },
    { caseId: 'urgent', studentId: 's2', priority: 'urgent' },
    { caseId: 'high', studentId: 's3', priority: 'high' },
  ], reviewers);

  assert.deepEqual(result.assigned.map(({ caseId }) => caseId), ['urgent', 'high', 'routine']);
  assert.equal(result.summary.assigned, 3);
  assert.equal(result.summary.unassigned, 0);
  assert.deepEqual(result.reviewers.map(({ newLoadPoints }) => newLoadPoints), [5, 8]);
  assert.equal(result.assigned[0].reviewerId, 'r2');
});

test('uses required skills and declared preferences without exposing names by default', () => {
  const result = allocateReviewCasesConstrained([
    { caseId: 'translated', studentId: 's1', requiredSkills: ['language-vi'], preferredReviewerIds: ['r2'] },
  ], reviewers);

  assert.equal(result.assigned[0].reviewerId, 'r2');
  assert.equal('reviewerName' in result.assigned[0], false);
  assert.equal('name' in result.reviewers[0], false);
});

test('honors explicit maximum utilization and reports cases that cannot fit', () => {
  const result = allocateReviewCasesConstrained([
    { caseId: 'large', studentId: 's1', workloadWeight: 5 },
  ], reviewers, { maximumWorkloadRatio: 0.5 });

  assert.equal(result.summary.assigned, 0);
  assert.equal(result.unassigned[0].reason, 'capacity_exhausted');
});

test('applies per-reviewer case limits and distinguishes their blocker', () => {
  const result = allocateReviewCasesConstrained([
    { caseId: 'one', studentId: 's1' },
    { caseId: 'two', studentId: 's2' },
  ], [
    { id: 'only', name: 'Reviewer', skills: [], capacityPoints: 10, maxCases: 1 },
  ]);

  assert.equal(result.summary.assigned, 1);
  assert.equal(result.unassigned[0].reason, 'reviewer_case_limits_reached');
});

test('avoids conflicts and case-specific blocks before scoring eligible reviewers', () => {
  const result = allocateReviewCasesConstrained([
    { caseId: 'blocked', studentId: 's1', blockedReviewerIds: ['r2'] },
    { caseId: 'conflicted', studentId: 's2' },
  ], [
    { ...reviewers[0], conflictStudentIds: ['s2'] },
    { ...reviewers[1], blockedCaseIds: ['conflicted'] },
  ]);

  assert.deepEqual(result.assigned.map(({ reviewerId }) => reviewerId), ['r1']);
  assert.equal(result.unassigned[0].caseId, 'conflicted');
});

test('returns stable reasons for inactive, conflicted and unskilled reviewer pools', () => {
  const cases = [{ caseId: 'case', studentId: 's1', requiredSkills: ['legal'] }];
  assert.equal(allocateReviewCasesConstrained(cases, [{ id: 'r', name: 'R', active: false, capacityPoints: 2 }]).unassigned[0].reason,
    'no_active_reviewers');
  assert.equal(allocateReviewCasesConstrained(cases, [{ id: 'r', name: 'R', capacityPoints: 2, conflictStudentIds: ['s1'] }]).unassigned[0].reason,
    'all_reviewers_conflicted_or_blocked');
  assert.equal(allocateReviewCasesConstrained(cases, [{ id: 'r', name: 'R', capacityPoints: 2, skills: [] }]).unassigned[0].reason,
    'required_skills_unavailable');
});

test('balances repeated students and cohorts and reports aggregate fairness metrics', () => {
  const result = allocateReviewCasesConstrained([
    { caseId: 'a', studentId: 'same', cohortId: 'c1' },
    { caseId: 'b', studentId: 'same', cohortId: 'c1' },
    { caseId: 'c', studentId: 'other', cohortId: 'c1' },
  ], [
    { id: 'r1', name: 'First', capacityPoints: 5 },
    { id: 'r2', name: 'Second', capacityPoints: 5 },
  ]);

  assert.notEqual(result.assigned[0].reviewerId, result.assigned[1].reviewerId);
  assert.equal(result.summary.utilizationStandardDeviation >= 0, true);
  assert.equal(result.summary.capacityCoverage, 1);
});

test('allows opt-in reviewer names and emits spreadsheet-safe CSV sections', () => {
  const result = allocateReviewCasesConstrained([
    { caseId: '=2+2', studentId: '@student' },
  ], [{ id: 'r', name: 'Reviewer', capacityPoints: 4 }], { includeReviewerNames: true });

  assert.equal(result.assigned[0].reviewerName, 'Reviewer');
  assert.match(reviewAllocationToCsv(result), /'=2\+2/);
  assert.match(reviewAllocationToCsv(result, 'reviewers'), /Reviewer/);
  assert.match(reviewAllocationToCsv(result, 'unassigned'), /caseId/);
  assert.throws(() => reviewAllocationToCsv(result, 'other'), /section/);
});

test('rejects invalid options, duplicate identities and inconsistent reviewer loads', () => {
  assert.throws(() => allocateReviewCasesConstrained([{ caseId: 'a', studentId: 's' }, { caseId: 'a', studentId: 't' }], []), /duplicate review case/);
  assert.throws(() => allocateReviewCasesConstrained([], [{ id: 'r', name: 'One', capacityPoints: 1 }, { id: 'r', name: 'Two', capacityPoints: 1 }]), /duplicate reviewer/);
  assert.throws(() => allocateReviewCasesConstrained([], reviewers, { maximumWorkloadRatio: 2.1 }), /maximumWorkloadRatio/);
  assert.throws(() => allocateReviewCasesConstrained([], reviewers, { includeReviewerNames: 'yes' }), /includeReviewerNames/);
  assert.throws(() => allocateReviewCasesConstrained([], [{ id: 'r', name: 'R', capacityPoints: 1, currentLoadPoints: 2 }]), /exceeds capacity/);
  assert.throws(() => allocateReviewCasesConstrained([], reviewers, { priorityWeights: { urgent: 0 } }), /priorityWeights/);
});

test('reports blocked-only cases and rejects invalid workload declarations', () => {
  const cases = [{ caseId: 'a', studentId: 's', blockedReviewerIds: ['r'] }];
  const result = allocateReviewCasesConstrained(cases, [{ id: 'r', name: 'R', capacityPoints: 2 }]);
  assert.equal(result.unassigned[0].reason, 'all_reviewers_conflicted_or_blocked');
  assert.throws(() => allocateReviewCasesConstrained([{ caseId: 'a', studentId: 's', workloadWeight: 0 }], reviewers), /workloadWeight/);
});
