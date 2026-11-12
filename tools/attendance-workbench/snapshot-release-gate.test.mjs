import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { decideSnapshotRelease, planSnapshotRelease, snapshotReleaseToCsv,
  compareSnapshotReleaseReceipts, snapshotReleaseDiffToCsv, verifySnapshotReleaseReceipt } from './snapshot-release-gate.mjs';

function snapshot() {
  return createAttendanceSnapshot([
    { id: 'A', name: 'An Example', email: 'an@example.test' },
    { id: 'B', name: 'Binh Example', email: 'binh@example.test' },
  ], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S1', status: 'absent' },
  ]);
}

function contract() {
  return { format: 'attendance-snapshot-contract', version: 1, id: 'release-contract', title: 'Snapshot release', revision: 2,
    checks: [
      { id: 'minimum-roster', type: 'min_students', value: 2 },
      { id: 'coverage-warning', type: 'minimum_coverage', value: 0.75, severity: 'warning' },
    ] };
}

function approved() {
  const plan = planSnapshotRelease(snapshot(), contract(), { requestedBy: 'data steward', createdAt: '2026-11-01T00:00:00Z' });
  return decideSnapshotRelease(plan, { actor: '=Reviewer', reason: 'Reviewed the import and coverage warning.',
    at: '2026-11-01T01:00:00Z', acknowledgedWarnings: ['coverage-warning'] });
}

test('prepares a compact approval plan without embedding snapshot identities', () => {
  const plan = planSnapshotRelease(snapshot(), contract(), { requestedBy: 'steward', createdAt: '2026-11-01T00:00:00Z' });
  assert.equal(plan.status, 'needs_approval');
  assert.deepEqual(plan.warningCheckIds, ['coverage-warning']);
  assert.deepEqual(plan.errorCheckIds, []);
  assert.equal(plan.contractRevision, 2);
  assert.equal(JSON.stringify(plan).includes('An Example'), false);
  assert.equal(JSON.stringify(plan).includes('an@example.test'), false);
});

test('blocks failed error checks and requires every failed warning to be acknowledged', () => {
  const failed = contract();
  failed.checks[0].value = 3;
  const blocked = planSnapshotRelease(snapshot(), failed, { createdAt: '2026-11-01T00:00:00Z' });
  assert.equal(blocked.status, 'blocked');
  assert.deepEqual(blocked.errorCheckIds, ['minimum-roster']);
  assert.throws(() => decideSnapshotRelease(blocked, { actor: 'reviewer', reason: 'approve', at: '2026-11-01T01:00:00Z' }), /only an accepted plan/);

  const plan = planSnapshotRelease(snapshot(), contract(), { createdAt: '2026-11-01T00:00:00Z' });
  assert.throws(() => decideSnapshotRelease(plan, { actor: 'reviewer', reason: 'approve', at: '2026-11-01T01:00:00Z' }), /require acknowledgement/);
  assert.throws(() => decideSnapshotRelease(plan, { actor: 'reviewer', reason: 'approve', at: '2026-11-01T01:00:00Z',
    acknowledgedWarnings: ['unknown'] }), /unknown warning/);
});

test('records named approval or rejection without writing or publishing the snapshot', () => {
  const plan = planSnapshotRelease(snapshot(), contract(), { requestedBy: 'steward', createdAt: '2026-11-01T00:00:00Z' });
  const rejected = decideSnapshotRelease(plan, { decision: 'reject', actor: 'reviewer', reason: 'Re-import required.', at: '2026-11-01T01:00:00Z' });
  assert.equal(rejected.status, 'rejected');
  assert.equal('receiptDigest' in rejected, false);
  const receipt = decideSnapshotRelease(plan, { actor: 'reviewer', reason: 'Accepted after review.',
    at: '2026-11-01T01:00:00Z', acknowledgedWarnings: ['coverage-warning'] });
  assert.equal(receipt.plan.status, 'approved');
  assert.equal(receipt.format, 'attendance-snapshot-release-receipt');
  assert.equal(receipt.plan.decision.actor, 'reviewer');
  assert.match(receipt.receiptDigest, /^[a-f0-9]{64}$/);
});

test('verifies the snapshot, contract and receipt checksum and detects later changes', () => {
  const receipt = approved();
  const valid = verifySnapshotReleaseReceipt(receipt, snapshot(), contract());
  assert.equal(valid.valid, true);
  assert.deepEqual(valid.checks, { digestMatches: true, snapshotMatches: true, contractMatches: true, contractAccepts: true });

  const modifiedReceipt = structuredClone(receipt);
  modifiedReceipt.plan.decision.reason = 'Edited after approval';
  assert.equal(verifySnapshotReleaseReceipt(modifiedReceipt, snapshot(), contract()).checks.digestMatches, false);

  const changedSnapshot = createAttendanceSnapshot([
    { id: 'A', name: 'An Example', email: 'an@example.test' },
    { id: 'B', name: 'Binh Example', email: 'binh@example.test' },
  ], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'absent' },
  ]);
  assert.equal(verifySnapshotReleaseReceipt(receipt, changedSnapshot, contract()).checks.snapshotMatches, false);

  const changedContract = { ...contract(), revision: 3 };
  assert.equal(verifySnapshotReleaseReceipt(receipt, snapshot(), changedContract).checks.contractMatches, false);
});

test('exports compact spreadsheet-safe receipt evidence and validates approval fields', () => {
  const receipt = approved();
  const csv = snapshotReleaseToCsv(receipt);
  assert.match(csv, /'=Reviewer/);
  assert.match(csv, /coverage-warning/);
  assert.doesNotMatch(csv, /An Example|an@example\.test/);
  const plan = planSnapshotRelease(snapshot(), contract());
  assert.throws(() => decideSnapshotRelease(plan, { actor: '', reason: 'reason' }), /actor/);
  assert.throws(() => decideSnapshotRelease(plan, { actor: 'reviewer', reason: '' }), /reason/);
  assert.throws(() => verifySnapshotReleaseReceipt('{bad', snapshot(), contract()), /valid JSON/);
});

test('compares approved receipts by snapshot, contract and approval metadata', () => {
  const first = approved();
  const samePlan = planSnapshotRelease(snapshot(), contract(), { requestedBy: 'steward', createdAt: '2026-11-02T00:00:00Z' });
  const second = decideSnapshotRelease(samePlan, { actor: 'reviewer two', reason: 'Second approved review.',
    at: '2026-11-02T01:00:00Z', acknowledgedWarnings: ['coverage-warning'] });
  const diff = compareSnapshotReleaseReceipts(first, second);
  assert.equal(diff.summary.outcome, 'approval_changed');
  assert.equal(diff.summary.snapshotChanged, false);
  assert.equal(diff.summary.contractChanged, false);
  assert.equal(diff.summary.approvalChanged, true);
  assert.match(snapshotReleaseDiffToCsv(diff), /'=Reviewer/);

  const corrupted = structuredClone(second);
  corrupted.plan.decision.reason = 'Tampered';
  assert.throws(() => compareSnapshotReleaseReceipts(first, corrupted), /digest does not match/);
});
