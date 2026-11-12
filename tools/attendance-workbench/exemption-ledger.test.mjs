import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { createExemptionLedger, evaluateExemptionLedger, exemptionToCsv, parseExemptionLedger,
  serializeExemptionLedger, summarizeExemptionLedger, updateExemption } from './exemption-ledger.mjs';

function baseline() {
  return createAttendanceSnapshot([
    { id: 'A', name: 'An Nguyen', email: 'an@example.test' },
    { id: 'B', name: '=Binh Tran', email: 'binh@example.test' },
  ], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'absent' },
  ]);
}

function ledgerWithProposals() {
  return createExemptionLedger(baseline(), [
    { id: 'excuse-a-s1', studentId: 'A', sessionId: 'S1', type: 'excused_absence', effect: 'exclude',
      expectedStatus: 'absent', reason: 'Documented approved leave', evidence: [{ label: 'signed leave note', referenceId: 'leave-9' }] },
    { id: 'makeup-b-s2', studentId: 'B', sessionId: 'S2', type: 'makeup_credit', effect: 'present_credit',
      expectedStatus: 'absent', reason: 'Completed approved make-up class' },
  ], { id: 'ledger-1', createdAt: '2026-11-02T09:00:00Z', actor: 'requester' });
}

function approve(ledger, id, revision) {
  let result = updateExemption(ledger, id, { state: 'in_review' }, { expectedRevision: revision, actor: 'reviewer', at: '2026-11-02T10:00:00Z' });
  const entry = result.entries.find((candidate) => candidate.id === id);
  return updateExemption(result, id, { state: 'approved' }, { expectedRevision: entry.revision, actor: 'reviewer', at: '2026-11-02T11:00:00Z' });
}

test('creates a versioned ledger bound to its baseline and validates target statuses', () => {
  const source = baseline();
  const before = serializeAttendanceSnapshot(source);
  const ledger = ledgerWithProposals();
  assert.equal(ledger.format, 'attendance-exemption-ledger');
  assert.equal(ledger.revision, 1);
  assert.equal(ledger.entries.length, 2);
  assert.equal(ledger.entries[0].state, 'pending');
  assert.equal(ledger.entries[0].expectedStatus, 'absent');
  assert.equal(ledger.entries[0].events[0].actor, 'requester');
  assert.equal(serializeAttendanceSnapshot(source), before);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'A', sessionId: 'S1', type: 'excused_absence',
    effect: 'exclude', expectedStatus: 'present', reason: 'invalid' }]), /expected present but snapshot contains absent/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'A', sessionId: 'S2', type: 'excused_absence',
    effect: 'exclude', expectedStatus: null, reason: 'invalid type status' }]), /must target an absent result/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'B', sessionId: 'S1', type: 'makeup_credit',
    effect: 'present_credit', expectedStatus: 'present', reason: 'invalid credit' }]), /already-present result/);
});

test('round trips JSON and rejects tampered baseline, repeated targets and invalid event history', () => {
  const ledger = ledgerWithProposals();
  assert.deepEqual(parseExemptionLedger(serializeExemptionLedger(ledger)), ledger);
  assert.throws(() => parseExemptionLedger('{bad'), /valid JSON/);
  const tamperedFingerprint = structuredClone(ledger);
  tamperedFingerprint.sourceFingerprint = 'snapshot-not-the-baseline';
  assert.throws(() => parseExemptionLedger(tamperedFingerprint), /fingerprint does not match/);
  const duplicateTarget = structuredClone(ledger);
  duplicateTarget.entries[1].studentId = 'A';
  duplicateTarget.entries[1].sessionId = 'S1';
  assert.throws(() => parseExemptionLedger(duplicateTarget), /duplicate exemption target/);
  const badEvent = structuredClone(ledger);
  badEvent.entries[0].events[0].sequence = 2;
  assert.throws(() => parseExemptionLedger(badEvent), /sequences must be consecutive/);
});

test('records review transitions, notes and evidence with append-only event sequences', () => {
  let ledger = ledgerWithProposals();
  ledger = updateExemption(ledger, 'excuse-a-s1', { state: 'in_review', note: 'Checking dated source' },
    { expectedRevision: 1, actor: 'reviewer', at: '2026-11-02T10:00:00Z' });
  let entry = ledger.entries[0];
  assert.equal(entry.revision, 3);
  assert.deepEqual(entry.events.slice(-2).map((event) => event.type), ['status', 'note']);
  ledger = updateExemption(ledger, 'excuse-a-s1', { evidence: [{ label: 'attendance register', referenceId: 'reg-4' }] },
    { expectedRevision: 3, actor: 'reviewer', at: '2026-11-02T10:30:00Z' });
  entry = ledger.entries[0];
  assert.equal(entry.revision, 4);
  assert.equal(entry.events[3].sequence, 4);
  assert.equal(entry.evidence.length, 2);
  assert.equal(ledger.revision, 3);
});

test('enforces optimistic revisions and explicit reviewer transitions', () => {
  const ledger = ledgerWithProposals();
  assert.throws(() => updateExemption(ledger, 'excuse-a-s1', { state: 'approved' }, { expectedRevision: 1 }), /cannot move from pending/);
  assert.throws(() => updateExemption(ledger, 'excuse-a-s1', { state: 'in_review' }, { expectedRevision: 2 }), /stale exemption revision/);
  assert.throws(() => updateExemption(ledger, 'missing', { note: 'x' }, { expectedRevision: 1 }), /unknown exemption ID/);
  assert.throws(() => updateExemption(ledger, 'excuse-a-s1', {}, { expectedRevision: 1 }), /must change state/);
  const rejected = updateExemption(ledger, 'excuse-a-s1', { state: 'rejected' }, { expectedRevision: 1 });
  assert.throws(() => updateExemption(rejected, 'excuse-a-s1', { state: 'approved' }, { expectedRevision: 2 }), /cannot move from rejected/);
});

test('applies approved exceptions to a report overlay without changing source statuses', () => {
  const source = baseline();
  const before = serializeAttendanceSnapshot(source);
  let ledger = ledgerWithProposals();
  ledger = approve(ledger, 'excuse-a-s1', 1);
  ledger = approve(ledger, 'makeup-b-s2', 1);
  const report = evaluateExemptionLedger(ledger, source);
  assert.equal(report.ok, true);
  assert.equal(report.summary.approved, 2);
  assert.equal(report.summary.appliedExclusions, 1);
  assert.equal(report.summary.makeupCredits, 1);
  assert.deepEqual(report.classSummary, { expected: 3, present: 2, absent: 0, missing: 1, excluded: 1,
    recorded: 2, coverage: 2 / 3, attendanceRate: 1, totalCells: 4 });
  assert.equal(report.students.find((student) => student.studentId === 'A').attendanceRate, null);
  assert.equal(report.students.find((student) => student.studentId === 'B').attendanceRate, 1);
  assert.equal(serializeAttendanceSnapshot(source), before);
  assert.match(report.notice, /Raw attendance statuses.*unchanged/);
});

test('ignores pending and rejected entries when creating the adjusted report', () => {
  let ledger = ledgerWithProposals();
  ledger = updateExemption(ledger, 'excuse-a-s1', { state: 'in_review' }, { expectedRevision: 1 });
  ledger = updateExemption(ledger, 'excuse-a-s1', { state: 'rejected' }, { expectedRevision: 2 });
  const report = evaluateExemptionLedger(ledger, baseline());
  assert.equal(report.ok, true);
  assert.equal(report.classSummary.expected, 4);
  assert.equal(report.classSummary.excluded, 0);
  assert.equal(report.summary.pending, 1);
});

test('blocks stale approvals and roster or session layout changes before producing a report', () => {
  let ledger = approve(ledgerWithProposals(), 'excuse-a-s1', 1);
  const changed = createAttendanceSnapshot(baseline().roster, ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'absent' },
  ]);
  const stale = evaluateExemptionLedger(ledger, changed);
  assert.equal(stale.ok, false);
  assert.equal(stale.classSummary, null);
  assert.equal(stale.stale[0].code, 'expected_status_changed');
  const changedLayout = createAttendanceSnapshot(baseline().roster, ['S2', 'S1'], baseline().records);
  const layout = evaluateExemptionLedger(ledger, changedLayout);
  assert.equal(layout.ok, false);
  assert.equal(layout.layoutChanged, true);
  assert.match(layout.notice, /layout differs/);
});

test('blocks an approved student exception that overlaps an approved session closure', () => {
  let ledger = createExemptionLedger(baseline(), [
    { id: 'closure-s2', sessionId: 'S2', type: 'official_closure', effect: 'exclude', expectedStatus: null,
      reason: 'Campus closure' },
    { id: 'makeup-b-s2', studentId: 'B', sessionId: 'S2', type: 'makeup_credit', effect: 'present_credit',
      expectedStatus: 'absent', reason: 'Make-up class' },
  ], { id: 'closure-ledger', createdAt: '2026-11-02T09:00:00Z' });
  ledger = approve(ledger, 'closure-s2', 1);
  ledger = approve(ledger, 'makeup-b-s2', 1);
  const report = evaluateExemptionLedger(ledger, baseline());
  assert.equal(report.ok, false);
  assert.equal(report.conflicts[0].code, 'session_closure_overlaps_student_exception');
  assert.equal(report.classSummary, null);
});

test('applies an approved session-wide closure only in the denominator overlay', () => {
  let ledger = createExemptionLedger(baseline(), [{ id: 'closure-s2', sessionId: 'S2', type: 'official_closure',
    effect: 'exclude', expectedStatus: null, reason: 'Campus was closed' }], { createdAt: '2026-11-02T09:00:00Z' });
  ledger = approve(ledger, 'closure-s2', 1);
  const report = evaluateExemptionLedger(ledger, baseline());
  assert.equal(report.ok, true);
  assert.equal(report.classSummary.expected, 2);
  assert.equal(report.classSummary.excluded, 2);
  assert.equal(report.sessions.find((session) => session.sessionId === 'S2').excluded, 2);
});

test('summarizes without notes, exports formula-safe case rows and validates CSV sections', () => {
  let ledger = ledgerWithProposals();
  ledger = updateExemption(ledger, 'excuse-a-s1', { state: 'in_review', note: '=private note' }, { expectedRevision: 1 });
  const summary = summarizeExemptionLedger(ledger);
  assert.equal(summary.summary.byState.in_review, 1);
  assert.equal(JSON.stringify(summary).includes('private note'), false);
  assert.match(exemptionToCsv(ledger), /"id","studentId","sessionId","type"/);
  assert.match(exemptionToCsv(ledger), /"Documented approved leave"/);
  assert.match(exemptionToCsv(evaluateExemptionLedger(approve(ledgerWithProposals(), 'excuse-a-s1', 1), baseline()), 'students'), /"studentId","studentName"/);
  assert.throws(() => exemptionToCsv(ledger, 'raw'), /section must be entries/);
  assert.throws(() => exemptionToCsv({ format: 'wrong', version: 1 }), /invalid or blocked/);
});

test('validates entry bounds, evidence, timestamps, IDs, and JSON schemas', () => {
  const source = baseline();
  assert.throws(() => createExemptionLedger(source, null), /proposals must contain/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'unknown', sessionId: 'S1', type: 'excused_absence',
    effect: 'exclude', expectedStatus: null, reason: 'bad student' }]), /unknown student/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'A', sessionId: 'unknown', type: 'excused_absence',
    effect: 'exclude', expectedStatus: 'absent', reason: 'bad session' }]), /unknown session/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: null, sessionId: 'S1', type: 'makeup_credit',
    effect: 'present_credit', expectedStatus: null, reason: 'bad session scope' }]), /must be an official_closure/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'A', sessionId: 'S1', type: 'excused_absence',
    effect: 'present_credit', expectedStatus: 'absent', reason: 'wrong effect' }]), /must use the exclude effect/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'A', sessionId: 'S1', type: 'excused_absence',
    effect: 'exclude', expectedStatus: 'absent', reason: 'bad evidence', evidence: [{ label: 'scan', sha256: 'bad' }] }]), /SHA-256/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'A', sessionId: 'S1', type: 'excused_absence',
    effect: 'exclude', expectedStatus: 'absent', reason: 'duplicate', id: 'same' },
  { studentId: 'A', sessionId: 'S1', type: 'excused_absence', effect: 'exclude', expectedStatus: 'absent', reason: 'duplicate', id: 'same-2' }]), /duplicate exemption target/);
  assert.throws(() => createExemptionLedger(source, [{ studentId: 'A', sessionId: 'S1', type: 'excused_absence',
    effect: 'exclude', expectedStatus: 'absent', reason: 'invalid time' }], { createdAt: 'not-time' }), /explicit UTC offset/);
});
