import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { approveGovernedExport, governedExportToCsv, planGovernedExport } from './export-gate.mjs';

const asOf = '2026-11-13T12:00:00Z';

function snapshot() {
  return createAttendanceSnapshot([
    { id: 'A', name: 'An Nguyen', email: 'an@example.test' },
    { id: 'B', name: 'Binh Tran', email: 'binh@example.test' },
    { id: 'C', name: '=Casey Tran', email: 'casey@example.test' },
    { id: 'D', name: 'Dana Tran', email: 'dana@example.test' },
  ], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'A', sessionId: 'S2', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'present' },
    { studentId: 'C', sessionId: 'S1', status: 'absent' },
    { studentId: 'C', sessionId: 'S2', status: 'present' },
    { studentId: 'D', sessionId: 'S1', status: 'present' },
  ]);
}

function policy(options = {}) {
  return { id: 'class-support-policy', allowedRecipients: ['internal'], allowedPurposes: ['class support'],
    allowedFields: ['studentId', 'studentName', 'studentEmail', 'sessionId', 'status'], minimumAggregateGroupSize: 3,
    maximumRows: 100, maximumAggregateGroups: 20, maximumValidityDays: 30, ...options };
}

function request(options = {}) {
  return { id: 'request-1', recipient: 'instructor-team', recipientType: 'internal', purpose: 'class support',
    requestedAt: '2026-11-01T00:00:00Z', validUntil: '2026-11-30T00:00:00Z', mode: 'records',
    fields: ['studentId', 'sessionId', 'status'], studentIds: ['A', 'B'], sessionIds: ['S1'], ...options };
}

test('previews an explicitly scoped internal export with only requested columns', () => {
  const source = snapshot();
  const before = serializeAttendanceSnapshot(source);
  const plan = planGovernedExport(source, policy(), request(), { asOf });
  assert.equal(plan.format, 'attendance-governed-export-plan');
  assert.equal(plan.status, 'ready');
  assert.equal(plan.summary.matchedRows, 2);
  assert.equal(plan.summary.outputRows, 2);
  assert.deepEqual(plan.summary.fields, ['studentId', 'sessionId', 'status']);
  assert.deepEqual(Object.keys(plan.payload.rows[0]), ['studentId', 'sessionId', 'status']);
  assert.equal(plan.payload.rows.some((row) => Object.hasOwn(row, 'studentEmail')), false);
  assert.equal(serializeAttendanceSnapshot(source), before);
});

test('blocks fields, purpose and recipient types outside the supplied policy', () => {
  const denied = planGovernedExport(snapshot(), policy({ allowedFields: ['sessionId', 'status'] }),
    request({ fields: ['studentId', 'sessionId', 'status'] }), { asOf });
  assert.equal(denied.status, 'rejected');
  assert.equal(denied.payload, null);
  assert.ok(denied.issues.some((issue) => issue.code === 'field_not_allowed' && issue.blocking));
  const wrongPurpose = planGovernedExport(snapshot(), policy(), request({ purpose: 'marketing' }), { asOf });
  assert.ok(wrongPurpose.issues.some((issue) => issue.code === 'purpose_not_allowed'));
  const wrongRecipient = planGovernedExport(snapshot(), policy(), request({ recipientType: 'partner' }), { asOf });
  assert.ok(wrongRecipient.issues.some((issue) => issue.code === 'recipient_not_allowed'));
});

test('requires a reviewer for record-level exports to external recipients', () => {
  const externalPolicy = policy({ allowedRecipients: ['external'] });
  const externalRequest = request({ recipientType: 'external', fields: ['studentId', 'sessionId', 'status'] });
  const pending = planGovernedExport(snapshot(), externalPolicy, externalRequest, { asOf });
  assert.equal(pending.status, 'needs_approval');
  assert.equal(pending.payload, null);
  assert.ok(pending.issues.some((issue) => issue.code === 'external_record_export'));
  assert.throws(() => governedExportToCsv(pending), /unavailable until the request is approved/);
  const approved = approveGovernedExport(snapshot(), externalPolicy, externalRequest,
    { actor: 'privacy-reviewer', reason: 'Approved for the stated support purpose', at: asOf });
  assert.equal(approved.status, 'ready');
  assert.equal(approved.approval.actor, 'privacy-reviewer');
  assert.equal(approved.payload.rows.length, 2);
  assert.match(governedExportToCsv(approved), /"studentId","sessionId","status"/);
});

test('policy-required review gates payload until approval and preserves the approval trace', () => {
  const pending = planGovernedExport(snapshot(), policy({ requiresApproval: true }), request(), { asOf });
  assert.equal(pending.status, 'needs_approval');
  assert.equal(pending.payload, null);
  const approved = approveGovernedExport(snapshot(), policy({ requiresApproval: true }), request(),
    { actor: 'department-head', reason: 'Reviewed the exact recipient and scope', at: asOf });
  assert.equal(approved.status, 'ready');
  assert.deepEqual(approved.approval, { actor: 'department-head', reason: 'Reviewed the exact recipient and scope', at: new Date(asOf).toISOString() });
});

test('creates aggregate-only exports with small groups suppressed', () => {
  const aggregateRequest = request({ recipientType: 'external', mode: 'aggregate', fields: ['sessionId'],
    groupBy: ['sessionId'], studentIds: ['A', 'B'], sessionIds: ['S1'] });
  const plan = planGovernedExport(snapshot(), policy({ allowedRecipients: ['external'] }), aggregateRequest, { asOf });
  assert.equal(plan.status, 'ready');
  assert.equal(plan.payload.mode, 'aggregate');
  assert.equal(plan.payload.rows, null);
  assert.equal(plan.payload.groups.length, 1);
  assert.equal(plan.payload.groups[0].suppressed, true);
  assert.equal(plan.payload.groups[0].studentCount, null);
  const csv = governedExportToCsv(plan);
  assert.match(csv, /"sessionId","studentCount","sessionCount"/);
  assert.doesNotMatch(csv, /studentId/);
});

test('allows sufficiently large aggregate groups and includes only aggregate-safe dimensions', () => {
  const aggregateRequest = request({ mode: 'aggregate', fields: ['status'], groupBy: ['status'],
    studentIds: ['A', 'B', 'C', 'D'], sessionIds: ['S1'] });
  const plan = planGovernedExport(snapshot(), policy({ allowedRecipients: ['partner'] }),
    { ...aggregateRequest, recipientType: 'partner' }, { asOf });
  assert.equal(plan.status, 'ready');
  assert.equal(plan.payload.groups.length, 2);
  assert.equal(plan.payload.groups.find((group) => group.status === 'present').suppressed, false);
  assert.equal(plan.payload.groups.find((group) => group.status === 'present').studentCount, 3);
  assert.equal(plan.payload.groups.find((group) => group.status === 'absent').suppressed, true);
  assert.equal(plan.summary.suppressedGroups, 1);
});

test('rejects expired, future, too-long, and too-large requests without payloads', () => {
  const expired = planGovernedExport(snapshot(), policy(), request({ requestedAt: '2026-10-01T00:00:00Z',
    validUntil: '2026-11-01T00:00:00Z' }), { asOf });
  assert.equal(expired.status, 'rejected');
  assert.ok(expired.issues.some((issue) => issue.code === 'request_expired'));
  const future = planGovernedExport(snapshot(), policy(), request({ requestedAt: '2026-11-20T00:00:00Z', validUntil: '2026-11-25T00:00:00Z' }), { asOf });
  assert.ok(future.issues.some((issue) => issue.code === 'request_not_started'));
  const tooLong = planGovernedExport(snapshot(), policy(), request({ validUntil: '2027-01-01T00:00:00Z' }), { asOf });
  assert.ok(tooLong.issues.some((issue) => issue.code === 'validity_exceeds_policy'));
  const rowLimited = planGovernedExport(snapshot(), policy({ maximumRows: 2 }), request({ studentIds: null, sessionIds: null }), { asOf });
  assert.equal(rowLimited.status, 'rejected');
  assert.ok(rowLimited.issues.some((issue) => issue.code === 'row_limit_exceeded'));
  assert.equal(rowLimited.payload, null);
});

test('checks request scope IDs, statuses, aggregate dimensions and max group counts', () => {
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ studentIds: ['UNKNOWN'] }), { asOf }), /unknown ID/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ sessionIds: ['UNKNOWN'] }), { asOf }), /unknown ID/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ statuses: ['late'] }), { asOf }), /present, absent or missing/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ mode: 'aggregate' }), { asOf }), /requires at least one groupBy/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ groupBy: ['studentId'] }), { asOf }), /aggregate-safe fields/);
  const tooManyGroups = planGovernedExport(snapshot(), policy({ maximumAggregateGroups: 1 }),
    request({ mode: 'aggregate', fields: ['status'], groupBy: ['status'], studentIds: null, sessionIds: null }), { asOf });
  assert.equal(tooManyGroups.status, 'rejected');
  assert.ok(tooManyGroups.issues.some((issue) => issue.code === 'group_limit_exceeded'));
});

test('handles explicit empty scopes and missing attendance without widening the request', () => {
  const empty = planGovernedExport(snapshot(), policy(), request({ studentIds: [] }), { asOf });
  assert.equal(empty.status, 'ready');
  assert.equal(empty.summary.matchedRows, 0);
  assert.deepEqual(empty.payload.rows, []);
  const missing = planGovernedExport(snapshot(), policy(), request({ statuses: ['missing'], includeUnrecorded: true,
    studentIds: null, sessionIds: null }), { asOf });
  assert.equal(missing.summary.matchedRows, 1);
  assert.equal(missing.payload.rows[0].status, 'missing');
});

test('rejects approvals outside the date window and cannot override policy denials', () => {
  const externalPolicy = policy({ allowedRecipients: ['external'] });
  const externalRequest = request({ recipientType: 'external' });
  assert.throws(() => approveGovernedExport(snapshot(), externalPolicy, externalRequest,
    { actor: 'r', reason: 'late approval', at: '2026-12-01T00:00:00Z' }), /validity window/);
  assert.throws(() => approveGovernedExport(snapshot(), policy(), request(),
    { actor: '', reason: 'x', at: asOf }), /approval actor/);
  assert.throws(() => approveGovernedExport(snapshot(), externalPolicy, externalRequest,
    { actor: 'r', reason: 'too early', at: '2026-10-31T00:00:00Z' }), /validity window/);
  assert.throws(() => approveGovernedExport(snapshot(), policy(), request({ purpose: 'unapproved purpose' }),
    { actor: 'r', reason: 'cannot waive denial', at: asOf }), /is rejected and cannot be approved/);
});

test('formula-protects exported cells and rejects malformed policy/request values', () => {
  const approved = planGovernedExport(snapshot(), policy(), request({ studentIds: ['C'], fields: ['studentName', 'studentEmail'] }), { asOf });
  assert.match(governedExportToCsv(approved), /'=Casey Tran/);
  assert.throws(() => planGovernedExport(snapshot(), { ...policy(), id: '' }, request(), { asOf }), /export policy ID/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ id: '' }), { asOf }), /request ID/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ recipientType: 'friend' }), { asOf }), /recipientType is unsupported/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ mode: 'raw' }), { asOf }), /mode must be records or aggregate/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request({ validUntil: 'bad' }), { asOf }), /explicit UTC offset/);
  assert.throws(() => planGovernedExport(snapshot(), policy({ allowedRecipients: ['internal', 'internal'] }), request(), { asOf }), /unique supported recipient types/);
  assert.throws(() => planGovernedExport(snapshot(), policy({ allowedFields: ['studentId', 'studentId'] }), request(), { asOf }), /unique supported fields/);
  assert.throws(() => planGovernedExport(snapshot(), policy({ maximumRows: 0 }), request(), { asOf }), /from 1 to/);
  assert.throws(() => planGovernedExport(snapshot(), policy(), request(), { asOf: 'bad' }), /explicit UTC offset/);
});
