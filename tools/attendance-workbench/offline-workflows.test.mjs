import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { applyAttendanceBatch } from '../../backend/attendance-batch.mjs';
import { buildReviewPlan } from './review-plan.mjs';
import { createCasebook, serializeCasebook } from './casebook.mjs';
import { planReviewBoard } from './review-board.mjs';
import { applyCasebookBatch } from './casebook-batch.mjs';
import { reportCasebookSla } from './casebook-sla.mjs';
import { evaluateCasebookServiceLevels } from './casebook-service-level.mjs';
import { reportCasebookActivity } from './casebook-activity.mjs';
import { reportCasebookWorkload } from './casebook-workload.mjs';
import { compareAttendanceImpact } from './attendance-impact-diff.mjs';
import { createSnapshotContract, validateSnapshotContract } from './snapshot-contract.mjs';
import { decideSnapshotRelease, planSnapshotRelease, verifySnapshotReleaseReceipt } from './snapshot-release-gate.mjs';

function attendanceSnapshot() {
  const roster = [
    { id: 'A', name: 'Alpha Student', email: 'alpha@example.test' },
    { id: 'B', name: 'Beta Student', email: 'beta@example.test' },
  ];
  const sessionIds = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6'];
  const records = sessionIds.flatMap((sessionId, index) => [
    { studentId: 'A', sessionId, status: index < 4 ? 'absent' : 'present' },
    { studentId: 'B', sessionId, status: 'present' },
  ]);
  return createAttendanceSnapshot(roster, sessionIds, records);
}

const reviewerRoster = [{ id: 'reviewer-a', name: 'Reviewer A', skills: ['attendance'],
  capacityCases: 10, capacityPoints: 100 }];

test('runs a review queue through allocation, casebook batch and read-only operational reports', () => {
  const snapshot = attendanceSnapshot();
  const snapshotBefore = serializeAttendanceSnapshot(snapshot);
  const plan = buildReviewPlan(snapshot, { targetRate: 0.8, futureSessions: 2, absenceStreak: 3,
    maximumMissing: 0, lowRate: 0.8, criticalRate: 0.4, minimumObserved: 3 });
  assert.ok(plan.cases.some((item) => item.studentId === 'A'));
  const book = createCasebook(plan, { id: 'integration-casebook', createdAt: '2026-11-01T00:00:00Z' });
  const bookBefore = serializeCasebook(book);
  const followUpPlan = { ...plan, cases: [{ ...plan.cases[0], caseId: 'follow-up-a' }] };
  const board = planReviewBoard(book, followUpPlan, reviewerRoster);
  assert.equal(board.summary.proposedAssignments, 1);

  const batch = { expectedBookRevision: book.revision, actor: 'reviewer-a', at: '2026-11-02T00:00:00Z',
    operations: book.cases.map((item) => ({ caseId: item.caseId, expectedRevision: item.revision,
      action: { status: 'in_review', assigneeId: 'reviewer-a' } })) };
  const updated = applyCasebookBatch(book, batch);
  assert.equal(updated.revision, book.revision + book.cases.length);
  assert.equal(reportCasebookSla(updated, { asOf: '2026-11-08T00:00:00Z' }).summary.breached, book.cases.length);

  const service = evaluateCasebookServiceLevels(updated, { from: '2026-11-01T00:00:00Z',
    to: '2026-11-01T00:00:00Z', asOf: '2026-11-08T00:00:00Z' });
  assert.equal(service.summary.cases, book.cases.length);
  assert.equal(service.summary.responsesMissed, book.cases.length);
  assert.equal(reportCasebookActivity(updated, { from: '2026-11-01T00:00:00Z',
    to: '2026-11-08T00:00:00Z' }).summary.totalEvents, book.cases.length * 3);

  const workload = reportCasebookWorkload(updated, reviewerRoster);
  assert.equal(workload.summary.openCases, book.cases.length);
  assert.equal(workload.summary.unassignedOpenCases, 0);
  assert.equal(workload.reviewers[0].openCases, book.cases.length);
  assert.equal(serializeCasebook(book), bookBefore);
  assert.equal(serializeAttendanceSnapshot(snapshot), snapshotBefore);
});

test('runs contract acceptance, named release approval and correction impact comparison', () => {
  const before = attendanceSnapshot();
  const beforeText = serializeAttendanceSnapshot(before);
  const contract = createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1,
    id: 'intake-contract', title: 'Attendance intake', revision: 1,
    checks: [
      { id: 'roster-size', type: 'min_students', value: 2 },
      { id: 'complete', type: 'minimum_coverage', value: 1 },
    ] });
  const validation = validateSnapshotContract(before, contract);
  assert.equal(validation.accepted, true);
  const releasePlan = planSnapshotRelease(before, contract, { requestedBy: 'data steward', createdAt: '2026-11-01T00:00:00Z' });
  const receipt = decideSnapshotRelease(releasePlan, { actor: 'reviewer', reason: 'Contract checks passed.', at: '2026-11-01T01:00:00Z' });
  assert.equal(verifySnapshotReleaseReceipt(receipt, before, contract).valid, true);

  const correction = applyAttendanceBatch(before, [{ studentId: 'A', sessionId: 'S1', expected: 'absent', status: 'present' }]);
  assert.deepEqual(correction.conflicts, []);
  const after = correction.snapshot;
  const impact = compareAttendanceImpact(before, after, { policy: { minimumRate: 0.5, maximumAbsences: 4 },
    includeStudentRows: true, minimumCohortSize: 2 });
  assert.equal(impact.summary.changedCells, 1);
  assert.equal(impact.summary.improved, 1);
  assert.equal(impact.students.find((item) => item.studentId === 'A').after.policyOutcome, 'pass');
  assert.equal(verifySnapshotReleaseReceipt(receipt, after, contract).checks.snapshotMatches, false);
  assert.equal(serializeAttendanceSnapshot(before), beforeText);
});
