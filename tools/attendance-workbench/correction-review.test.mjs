import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import {
  applyApprovedCorrections,
  auditCorrectionReview,
  correctionAuditToCsv,
  correctionReviewToCsv,
  createCorrectionReview,
  parseCorrectionReview,
  serializeCorrectionReview,
  summarizeCorrectionReview,
  updateCorrectionCase,
} from './correction-review.mjs';

const baseline = () => createAttendanceSnapshot([
  { id: 'A', name: 'An Nguyen', email: 'an@example.test' },
  { id: 'B', name: '=Binh Tran', email: 'binh@example.test' },
], ['S1', 'S2'], [
  { studentId: 'A', sessionId: 'S1', status: 'absent' },
  { studentId: 'A', sessionId: 'S2', status: 'present' },
  { studentId: 'B', sessionId: 'S1', status: 'present' },
]);

function submittedReview(snapshot = baseline()) {
  return createCorrectionReview(snapshot, [
    { studentId: 'A', sessionId: 'S1', expectedStatus: 'absent', proposedStatus: 'present',
      reasonCode: 'source_correction', reasonText: 'Verified against class sheet',
      evidence: [{ label: 'signed class sheet', referenceId: 'archive/2026-11-02', sha256: 'a'.repeat(64), receivedAt: '2026-11-03T10:00:00Z' }] },
    { studentId: 'B', sessionId: 'S2', expectedStatus: null, proposedStatus: 'absent', reasonCode: 'not_recorded' },
  ], { id: 'review-1', createdAt: '2026-11-03T09:00:00Z', actor: 'teacher-1' });
}

function update(review, targetIndex, action, at = '2026-11-03T11:00:00Z') {
  const target = review.cases[targetIndex];
  return updateCorrectionCase(review, target.caseId, action, { expectedRevision: target.revision, actor: 'reviewer-2', at });
}

test('creates a validated, versioned ledger with a frozen source baseline and stable case IDs', () => {
  const source = baseline();
  const before = serializeAttendanceSnapshot(source);
  const first = submittedReview(source);
  const second = submittedReview(source);
  assert.equal(first.format, 'attendance-correction-review');
  assert.equal(first.version, 1);
  assert.equal(first.revision, 1);
  assert.equal(first.cases.length, 2);
  assert.equal(first.cases[0].expectedStatus, 'absent');
  assert.equal(first.cases[0].evidence[0].sha256, 'a'.repeat(64));
  assert.equal(first.cases[0].caseId, second.cases[0].caseId);
  assert.equal(first.sourceSnapshot, before);
  assert.equal(serializeAttendanceSnapshot(source), before);
});

test('rejects unknown cells, stale assumptions, unchanged proposals and duplicate targets', () => {
  const source = baseline();
  assert.throws(() => createCorrectionReview(source, [{ studentId: 'unknown', sessionId: 'S1', expectedStatus: null,
    proposedStatus: 'present', reasonCode: 'other' }]), /unknown student/);
  assert.throws(() => createCorrectionReview(source, [{ studentId: 'A', sessionId: 'missing', expectedStatus: null,
    proposedStatus: 'present', reasonCode: 'other' }]), /unknown session/);
  assert.throws(() => createCorrectionReview(source, [{ studentId: 'A', sessionId: 'S1', expectedStatus: 'present',
    proposedStatus: 'absent', reasonCode: 'other' }]), /expected status/);
  assert.throws(() => createCorrectionReview(source, [{ studentId: 'A', sessionId: 'S1', expectedStatus: 'absent',
    proposedStatus: 'absent', reasonCode: 'other' }]), /does not change/);
  assert.throws(() => createCorrectionReview(source, [
    { studentId: 'A', sessionId: 'S1', expectedStatus: 'absent', proposedStatus: 'present', reasonCode: 'other' },
    { studentId: 'A', sessionId: 'S1', expectedStatus: 'absent', proposedStatus: 'missing', reasonCode: 'other' },
  ]), /duplicate correction target/);
  assert.throws(() => createCorrectionReview(source, [{ studentId: 'A', sessionId: 'S1', expectedStatus: 'absent',
    proposedStatus: 'present', reasonCode: 'unrecognized' }]), /invalid reasonCode/);
});

test('round trips JSON and validates event sequence, evidence digest and case uniqueness', () => {
  const review = submittedReview();
  const serialized = serializeCorrectionReview(review);
  assert.deepEqual(parseCorrectionReview(serialized), review);
  assert.throws(() => parseCorrectionReview('{broken'), /valid JSON/);
  assert.throws(() => parseCorrectionReview({ ...review, version: 2 }), /unsupported/);
  const sequenceTamper = structuredClone(review);
  sequenceTamper.cases[0].events[0].sequence = 3;
  assert.throws(() => parseCorrectionReview(sequenceTamper), /sequences must be consecutive/);
  const evidenceTamper = structuredClone(review);
  evidenceTamper.cases[0].evidence[0].sha256 = 'bad';
  assert.throws(() => parseCorrectionReview(evidenceTamper), /SHA-256/);
  const duplicateCase = structuredClone(review);
  duplicateCase.cases[1].caseId = duplicateCase.cases[0].caseId;
  assert.throws(() => parseCorrectionReview(duplicateCase), /duplicate correction case ID/);
  const duplicateCell = structuredClone(review);
  duplicateCell.cases[1].studentId = duplicateCell.cases[0].studentId;
  duplicateCell.cases[1].sessionId = duplicateCell.cases[0].sessionId;
  assert.throws(() => parseCorrectionReview(duplicateCell), /duplicate correction target cell/);
});

test('records reviewer transitions, notes and evidence as append-only events', () => {
  let review = submittedReview();
  const caseId = review.cases[0].caseId;
  review = update(review, 0, { status: 'in_review', note: 'Checking source record' });
  assert.equal(review.revision, 2);
  assert.equal(review.cases[0].revision, 3);
  assert.deepEqual(review.cases[0].events.slice(-2).map((event) => event.type), ['status', 'note']);
  assert.equal(review.cases[0].events.at(-1).actor, 'reviewer-2');
  review = update(review, 0, { status: 'needs_evidence' });
  review = update(review, 0, { evidence: [{ label: 'attendance export', referenceId: 'export-8' }] });
  review = update(review, 0, { status: 'in_review' });
  review = update(review, 0, { status: 'approved' });
  assert.equal(review.cases[0].caseId, caseId);
  assert.equal(review.cases[0].status, 'approved');
  assert.equal(review.cases[0].evidence.length, 2);
  assert.equal(review.cases[0].events.length, review.cases[0].revision);
});

test('requires optimistic revisions, valid transitions and non-empty actions', () => {
  const review = submittedReview();
  const target = review.cases[0];
  assert.throws(() => updateCorrectionCase(review, target.caseId, { status: 'approved' }, { expectedRevision: 2 }), /stale correction revision/);
  assert.throws(() => updateCorrectionCase(review, target.caseId, { status: 'applied' }, { expectedRevision: 1 }), /invalid reviewer-selected/);
  assert.throws(() => updateCorrectionCase(review, target.caseId, { status: 'approved' }, { expectedRevision: 1 }), /cannot move from submitted/);
  assert.throws(() => updateCorrectionCase(review, target.caseId, {}, { expectedRevision: 1 }), /must change status/);
  assert.throws(() => updateCorrectionCase(review, 'no-case', { note: 'x' }, { expectedRevision: 1 }), /unknown correction case/);
  assert.throws(() => updateCorrectionCase(review, target.caseId, { status: 'in_review' }, { expectedRevision: 1, at: 'invalid' }), /valid timestamp/);
});

test('allows requesting evidence, returning to review and withdrawing a submitted case', () => {
  let review = submittedReview();
  review = update(review, 1, { status: 'needs_evidence' });
  review = update(review, 1, { status: 'submitted' });
  review = update(review, 1, { status: 'withdrawn' });
  assert.equal(review.cases[1].status, 'withdrawn');
  assert.throws(() => update(review, 1, { status: 'in_review' }), /cannot move from withdrawn/);
});

test('applies approved cells only to a fresh copy and supports missing as an explicit deletion', () => {
  let review = submittedReview();
  review = update(review, 0, { status: 'in_review' });
  review = update(review, 0, { status: 'approved' });
  review = update(review, 1, { status: 'in_review' });
  review = update(review, 1, { status: 'approved' });
  const source = baseline();
  const before = serializeAttendanceSnapshot(source);
  const result = applyApprovedCorrections(review, source, { expectedReviewRevision: review.revision });
  assert.equal(result.ok, true);
  assert.equal(result.applied, 2);
  assert.equal(result.snapshot.records.some((record) => record.studentId === 'A' && record.sessionId === 'S1' && record.status === 'present'), true);
  assert.equal(result.snapshot.records.some((record) => record.studentId === 'B' && record.sessionId === 'S2'), true);
  assert.equal(result.snapshot.records.find((record) => record.studentId === 'B' && record.sessionId === 'S2').status, 'absent');
  assert.equal(serializeAttendanceSnapshot(source), before);
  assert.match(result.snapshotFingerprint, /^snapshot-/);
  assert.throws(() => applyApprovedCorrections(review, source, { expectedReviewRevision: 1 }), /stale review revision/);
});

test('blocks the entire approved batch when one expected cell or snapshot layout is stale', () => {
  let review = submittedReview();
  review = update(review, 0, { status: 'in_review' });
  review = update(review, 0, { status: 'approved' });
  review = update(review, 1, { status: 'in_review' });
  review = update(review, 1, { status: 'approved' });
  const changedCell = createAttendanceSnapshot(baseline().roster, ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'A', sessionId: 'S2', status: 'present' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
  ]);
  const blocked = applyApprovedCorrections(review, changedCell);
  assert.equal(blocked.ok, false);
  assert.equal(blocked.applied, 0);
  assert.equal(blocked.snapshot, null);
  assert.equal(blocked.conflicts.length, 1);
  const changedLayout = createAttendanceSnapshot(baseline().roster, ['S2', 'S1'], baseline().records);
  const layoutBlock = applyApprovedCorrections(review, changedLayout);
  assert.equal(layoutBlock.ok, false);
  assert.ok(layoutBlock.stale.some((item) => item.code === 'snapshot_roster_or_sessions_changed'));
  assert.equal(layoutBlock.snapshot, null);
});

test('audits pending and approved cases without modifying the review', () => {
  let review = submittedReview();
  review = update(review, 0, { status: 'in_review' });
  review = update(review, 0, { status: 'approved' });
  const changed = createAttendanceSnapshot(baseline().roster, ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'A', sessionId: 'S2', status: 'present' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
  ]);
  const before = serializeCorrectionReview(review);
  const audit = auditCorrectionReview(review, changed);
  assert.equal(audit.summary.stale, 1);
  assert.equal(audit.summary.approvedStale, 1);
  assert.equal(audit.summary.valid, false);
  assert.equal(audit.findings[0].code, 'expected_status_changed');
  assert.equal(serializeCorrectionReview(review), before);
  const layoutAudit = auditCorrectionReview(review, createAttendanceSnapshot(baseline().roster, ['S2', 'S1'], baseline().records));
  assert.equal(layoutAudit.layoutChanged, true);
  assert.equal(layoutAudit.findings[0].code, 'baseline_layout_changed');
});

test('summaries omit private note text while CSV opts into notes explicitly', () => {
  let review = submittedReview();
  review = update(review, 0, { status: 'in_review', note: '=private reviewer note' });
  review = update(review, 0, { status: 'approved' });
  const summary = summarizeCorrectionReview(review);
  assert.equal(summary.summary.byStatus.approved, 1);
  assert.equal(summary.summary.byStatus.submitted, 1);
  assert.equal(JSON.stringify(summary).includes('private reviewer note'), false);
  const safeCsv = correctionReviewToCsv(review);
  assert.equal(safeCsv.includes('private reviewer note'), false);
  assert.match(correctionReviewToCsv(review, { includeNotes: true }), /'=private reviewer note/);
  assert.match(correctionReviewToCsv(review), /'=Binh Tran/);
  const audit = auditCorrectionReview(review, baseline());
  assert.match(correctionAuditToCsv(audit), /"caseId","studentId","sessionId","code"/);
  assert.throws(() => correctionReviewToCsv(review, { includeNotes: 'yes' }), /must be a boolean/);
  assert.throws(() => correctionAuditToCsv({ format: 'wrong', version: 1, findings: [] }), /invalid correction audit/);
});

test('caps case, evidence, event, note and proposal payloads', () => {
  const source = baseline();
  assert.throws(() => createCorrectionReview(source, Array.from({ length: 50_001 }, () => ({}))), /at most 50000/);
  assert.throws(() => createCorrectionReview(source, [{ studentId: 'A', sessionId: 'S1', expectedStatus: 'absent',
    proposedStatus: 'present', reasonCode: 'other', evidence: Array.from({ length: 11 }, (_, index) => ({ label: `E${index}` })) }]), /at most 10 references/);
  let review = submittedReview();
  assert.throws(() => update(review, 0, { note: 'x'.repeat(2001) }), /up to 2000/);
  review = update(review, 0, { evidence: Array.from({ length: 9 }, (_, index) => ({ label: `extra-${index}` })) });
  assert.throws(() => update(review, 0, { evidence: [{ label: 'eleventh' }] }), /at most 10 references/);
});
