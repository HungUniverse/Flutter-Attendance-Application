import test from 'node:test';
import assert from 'node:assert/strict';
import { createCasebook, updateCasebook } from './casebook.mjs';
import { planReviewBoard, reviewBoardToCsv } from './review-board.mjs';

function casebook() {
  const cases = [
    ['existing', 'S1', 'Existing Student', 'high'],
    ['orphan', 'S2', 'Orphan Student', 'review'],
    ['unassigned', 'S3', 'Unassigned Student', 'review'],
  ].map(([caseId, studentId, studentName, priority]) => ({ caseId, studentId, studentName, priority,
    attendanceRate: 0.5, present: 1, absent: 1, missing: 0, reasons: [], suggestedSteps: [] }));
  let book = createCasebook({ version: 1, snapshotFingerprint: 'fp', generatedFor: { students: 3, sessions: 2, records: 6 },
    summary: { total: 3 }, cases }, { id: 'review-board-book', createdAt: '2026-11-01T00:00:00Z' });
  book = updateCasebook(book, 'existing', { assigneeId: 'r1' }, { expectedRevision: 1, at: '2026-11-01T01:00:00Z' });
  return updateCasebook(book, 'orphan', { assigneeId: 'retired-reviewer' }, { expectedRevision: 1, at: '2026-11-01T01:00:00Z' });
}

const plan = { version: 1, cases: [
  { caseId: 'existing', studentId: 'S1', studentName: 'Existing Student', priority: 'high', requiredSkills: ['attendance'] },
  { caseId: '=urgent', studentId: 'S4', studentName: 'New Student', priority: 'urgent', requiredSkills: ['attendance'] },
  { caseId: 'routine', studentId: 'S5', studentName: 'Routine Student', priority: 'normal' },
] };

const reviewers = [
  { id: 'r1', name: 'Reviewer One', skills: ['attendance'], capacityCases: 3, capacityPoints: 10 },
  { id: 'r2', name: 'Reviewer Two', skills: ['attendance'], capacityCases: 2, capacityPoints: 8 },
];

test('combines open casebook load and incoming plan without double-assigning known cases', () => {
  const source = casebook();
  const before = JSON.stringify(source);
  const board = planReviewBoard(source, plan, reviewers);

  assert.equal(board.summary.currentOpenCases, 3);
  assert.equal(board.summary.currentUnassignedCases, 1);
  assert.equal(board.summary.orphanedAssignments, 1);
  assert.equal(board.summary.incomingCases, 3);
  assert.equal(board.summary.alreadyTrackedCases, 1);
  assert.equal(board.summary.newCases, 2);
  assert.equal(board.summary.proposedAssignments, 2);
  assert.equal(board.summary.proposedUnassigned, 0);
  assert.equal(JSON.stringify(source), before);
  assert.equal(board.assignments.some((item) => 'studentId' in item), false);
  assert.equal(board.assignments.some((item) => 'reviewerName' in item), false);
});

test('respects existing load, skills and declared capacity limits', () => {
  const board = planReviewBoard(casebook(), plan, reviewers);
  const urgent = board.assignments.find((item) => item.caseId === '=urgent');
  assert.equal(urgent.reviewerId, 'r2');
  assert.equal(urgent.workloadWeight, 8);
  const first = board.reviewers.find((item) => item.id === 'r1');
  assert.equal(first.currentPoints, 4);
  assert.equal(first.proposedCases, 1);
  assert.equal(first.finalPoints, 5);
  assert.equal(first.overCapacity, false);
});

test('holds over-capacity reviewers out of new work and retains actionable unassigned reasons', () => {
  const board = planReviewBoard(casebook(), plan, [
    { ...reviewers[0], capacityPoints: 2 },
    reviewers[1],
  ]);
  assert.equal(board.summary.currentOverCapacityReviewers, 1);
  assert.equal(board.summary.proposedAssignments, 1);
  assert.equal(board.summary.proposedUnassigned, 1);
  assert.ok(board.unassigned.some((item) => item.reason === 'capacity_exhausted'));
});

test('exports summary, reviewer, assignment and unassigned sections safely', () => {
  const board = planReviewBoard(casebook(), plan, reviewers, { includeStudentIds: true, includeReviewerNames: true });
  assert.match(reviewBoardToCsv(board, 'summary'), /alreadyTrackedCases/);
  assert.match(reviewBoardToCsv(board), /Reviewer Two/);
  assert.match(reviewBoardToCsv(board, 'assignments'), /'=urgent/);
  assert.match(reviewBoardToCsv(board, 'assignments'), /S4/);
  assert.match(reviewBoardToCsv(board, 'unassigned'), /reason/);
  assert.throws(() => reviewBoardToCsv(board, 'other'), /section/);
});

test('validates reviewer roster and report options', () => {
  assert.throws(() => planReviewBoard(casebook(), plan, [{ id: 'r', name: 'R', capacityCases: -1, capacityPoints: 1 }]), /capacityCases/);
  assert.throws(() => planReviewBoard(casebook(), plan, [reviewers[0], reviewers[0]]), /duplicate reviewer/);
  assert.throws(() => planReviewBoard(casebook(), plan, reviewers, { includeStudentIds: 'yes' }), /booleans/);
  assert.throws(() => planReviewBoard(casebook(), { version: 0, cases: [] }, reviewers), /invalid or oversized/);
});
