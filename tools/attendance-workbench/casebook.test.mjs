import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { buildReviewPlan } from './review-plan.mjs';
import {
  casebookToCsv,
  casebookEventsToCsv,
  casebookHistoryAuditToCsv,
  auditCasebookHistory,
  createCasebook,
  listCasebookEvents,
  parseCasebook,
  reconcileCasebook,
  serializeCasebook,
  summarizeCasebook,
  updateCasebook,
} from './casebook.mjs';

function reviewSnapshot(absentCount = 4) {
  const roster = [{ id: 'A', name: 'An Example', email: 'an@example.test' }];
  const sessionIds = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6'];
  const records = sessionIds.map((sessionId, index) => ({ studentId: 'A', sessionId,
    status: index < absentCount ? 'absent' : 'present' }));
  return createAttendanceSnapshot(roster, sessionIds, records);
}

function planFor(absentCount = 4) {
  return buildReviewPlan(reviewSnapshot(absentCount), { futureSessions: 2, minimumObserved: 3,
    absenceStreak: 3, maximumMissing: 0, lowRate: 0.8, criticalRate: 0.4 });
}

test('creates a versioned casebook with an initial event per review case', () => {
  const book = createCasebook(planFor(), { createdAt: '2026-11-01T10:00:00Z', actor: 'Reviewer 1' });
  assert.equal(book.format, 'attendance-review-casebook');
  assert.equal(book.revision, 1);
  assert.equal(book.cases.length, 1);
  assert.equal(book.cases[0].status, 'new');
  assert.equal(book.cases[0].revision, 1);
  assert.equal(book.cases[0].events[0].actor, 'Reviewer 1');
  assert.equal(parseCasebook(serializeCasebook(book)).cases[0].caseId, book.cases[0].caseId);
});

test('updates status, assignment and note as a sequenced append-only history', () => {
  const initial = createCasebook(planFor(), { createdAt: '2026-11-01T10:00:00Z' });
  const caseId = initial.cases[0].caseId;
  const updated = updateCasebook(initial, caseId, { status: 'in_review', assigneeId: 'staff-3', note: 'Check the imported register.' },
    { expectedRevision: 1, actor: 'Reviewer 2', at: '2026-11-02T09:00:00Z' });
  const item = updated.cases[0];
  assert.equal(updated.revision, 2);
  assert.equal(item.revision, 4);
  assert.equal(item.status, 'in_review');
  assert.equal(item.assigneeId, 'staff-3');
  assert.deepEqual(item.events.map((event) => event.sequence), [1, 2, 3, 4]);
  assert.deepEqual(item.events.slice(1).map((event) => event.type), ['status', 'assigned', 'note']);
  assert.equal(item.events[2].to, 'staff-3');
  assert.equal(item.events[3].note, 'Check the imported register.');
  assert.equal(initial.cases[0].status, 'new');
  assert.equal(initial.cases[0].events.length, 1);
});

test('requires the current case revision and enforces valid status transitions', () => {
  const initial = createCasebook(planFor());
  const caseId = initial.cases[0].caseId;
  assert.throws(() => updateCasebook(initial, caseId, { note: 'Try stale update' }, { expectedRevision: 0 }), /stale case revision/);
  assert.throws(() => updateCasebook(initial, caseId, { status: 'reopened' }, { expectedRevision: 1 }), /cannot move/);
  assert.throws(() => updateCasebook(initial, caseId, { status: 'new' }, { expectedRevision: 1 }), /does not change/);
  const reviewing = updateCasebook(initial, caseId, { status: 'in_review' }, { expectedRevision: 1 });
  const resolved = updateCasebook(reviewing, caseId, { status: 'resolved' }, { expectedRevision: 2 });
  assert.equal(resolved.cases[0].status, 'resolved');
  const reopened = updateCasebook(resolved, caseId, { status: 'reopened' }, { expectedRevision: 3 });
  assert.equal(reopened.cases[0].status, 'reopened');
});

test('validates notes, assignees, action shape and case existence', () => {
  const initial = createCasebook(planFor());
  const caseId = initial.cases[0].caseId;
  assert.throws(() => updateCasebook(initial, caseId, { note: '' }, { expectedRevision: 1 }), /note/);
  assert.throws(() => updateCasebook(initial, caseId, { note: 'x'.repeat(2001) }, { expectedRevision: 1 }), /2000/);
  assert.throws(() => updateCasebook(initial, caseId, { assigneeId: 'x'.repeat(121) }, { expectedRevision: 1 }), /assigneeId/);
  assert.throws(() => updateCasebook(initial, caseId, {}, { expectedRevision: 1 }), /does not change/);
  assert.throws(() => updateCasebook(initial, 'unknown', { note: 'note' }, { expectedRevision: 1 }), /unknown case ID/);
  assert.throws(() => updateCasebook(initial, caseId, { status: 'bad' }, { expectedRevision: 1 }), /invalid case status/);
});

test('reconciles a refreshed plan without losing notes, ownership or prior decisions', () => {
  const oldPlan = planFor(4);
  const initial = createCasebook(oldPlan);
  const caseId = initial.cases[0].caseId;
  const assigned = updateCasebook(initial, caseId, { status: 'in_review', assigneeId: 'staff-2', note: 'Checked source CSV.' },
    { expectedRevision: 1, at: '2026-11-02T10:00:00Z' });
  const nextPlan = planFor(5);
  assert.equal(nextPlan.cases[0].caseId, caseId);
  const refreshed = reconcileCasebook(assigned, nextPlan, { expectedRevision: 2, at: '2026-11-03T10:00:00Z' });
  assert.equal(refreshed.sourceFingerprint, nextPlan.snapshotFingerprint);
  assert.equal(refreshed.cases[0].status, 'in_review');
  assert.equal(refreshed.cases[0].assigneeId, 'staff-2');
  assert.equal(refreshed.cases[0].events.at(-1).type, 'refreshed');
  assert.ok(refreshed.cases[0].events.some((event) => event.note === 'Checked source CSV.'));
  assert.equal(refreshed.cases[0].stale, false);
  assert.throws(() => reconcileCasebook(refreshed, nextPlan, { expectedRevision: 1 }), /stale casebook revision/);
});

test('marks cases stale when their signals disappear and appends new cases', () => {
  const initial = createCasebook(planFor(4));
  const cleanPlan = buildReviewPlan(reviewSnapshot(0), { futureSessions: 2, minimumObserved: 3,
    absenceStreak: 3, maximumMissing: 0, lowRate: 0.8, criticalRate: 0.4 });
  assert.equal(cleanPlan.cases.length, 0);
  const stale = reconcileCasebook(initial, cleanPlan, { at: '2026-11-04T10:00:00Z' });
  assert.equal(stale.cases.length, 1);
  assert.equal(stale.cases[0].stale, true);
  assert.equal(stale.cases[0].events.at(-1).type, 'stale');
  const summary = summarizeCasebook(stale);
  assert.equal(summary.summary.stale, 1);
  assert.equal(summary.summary.open, 1);
});

test('summarizes current states and keeps private note history out of CSV by default', () => {
  const initial = createCasebook(planFor());
  const item = initial.cases[0];
  const updated = updateCasebook(initial, item.caseId, { assigneeId: 'staff-1', note: '=HYPERLINK("https://unsafe.test")' },
    { expectedRevision: 1 });
  const summary = summarizeCasebook(updated).summary;
  assert.equal(summary.open, 1);
  assert.equal(summary.assigned, 1);
  assert.equal(summary.byPriority.urgent, 1);
  const compact = casebookToCsv(updated);
  assert.doesNotMatch(compact, /HYPERLINK|unsafe\.test/);
  const withNotes = casebookToCsv(updated, { includeNotes: true });
  assert.match(withNotes, /'=HYPERLINK/);
});

test('rejects malformed casebooks, duplicate IDs, invalid event history and unsupported actions', () => {
  const initial = createCasebook(planFor());
  assert.throws(() => parseCasebook('{'), /valid JSON/);
  assert.throws(() => parseCasebook({ ...initial, version: 2 }), /unsupported/);
  assert.throws(() => parseCasebook({ ...initial, cases: [initial.cases[0], initial.cases[0]] }), /duplicate case ID/);
  const badEvent = structuredClone(initial);
  badEvent.cases[0].events[0].sequence = 2;
  assert.throws(() => parseCasebook(badEvent), /sequences/);
  assert.throws(() => reconcileCasebook(initial, {}, {}), /review plan/);
  assert.throws(() => casebookToCsv(initial, null), /CSV options/);
});

test('lists case events in sequence with bounded paging and privacy-safe default fields', () => {
  const initial = createCasebook(planFor(), { createdAt: '2026-11-01T10:00:00Z', actor: 'Reviewer' });
  const item = initial.cases[0];
  const updated = updateCasebook(initial, item.caseId,
    { status: 'in_review', assigneeId: 'staff-1', note: 'Source register checked.' },
    { expectedRevision: 1, actor: 'Reviewer', at: '2026-11-02T10:00:00Z' });
  const events = listCasebookEvents(updated);
  assert.equal(events.summary.totalMatches, 4);
  assert.deepEqual(events.events.map((event) => event.sequence), [1, 2, 3, 4]);
  assert.equal(Object.hasOwn(events.events[0], 'studentId'), false);
  assert.equal(Object.hasOwn(events.events[3], 'note'), false);
  const page = listCasebookEvents(updated, { limit: 2, types: ['status', 'assigned', 'note'] });
  assert.equal(page.summary.totalMatches, 3);
  assert.equal(page.summary.matchedCases, 1);
  assert.equal(page.summary.byType.status, 1);
  assert.equal(page.summary.byType.note, 1);
  assert.equal(page.summary.returned, 2);
  assert.equal(page.summary.truncated, true);
  assert.deepEqual(page.events.map((event) => event.type), ['status', 'assigned']);
});

test('filters case history by actor and inclusive timestamp bounds', () => {
  const initial = createCasebook(planFor(), { createdAt: '2026-11-01T10:00:00Z', actor: 'Original' });
  const item = initial.cases[0];
  const updated = updateCasebook(initial, item.caseId, { status: 'in_review' },
    { expectedRevision: 1, actor: 'Reviewer', at: '2026-11-02T10:00:00Z' });
  const filtered = listCasebookEvents(updated, { actor: 'Reviewer', fromAt: '2026-11-02T10:00:00Z', toAt: '2026-11-02T10:00:00Z' });
  assert.equal(filtered.summary.totalMatches, 1);
  assert.equal(filtered.events[0].type, 'status');
  assert.throws(() => listCasebookEvents(updated, { fromAt: 'not-a-date' }), /valid timestamp/);
  assert.throws(() => listCasebookEvents(updated, { fromAt: '2026-11-03', toAt: '2026-11-02' }), /not be later/);
  assert.throws(() => listCasebookEvents(updated, { types: [] }), /non-empty array/);
  assert.throws(() => listCasebookEvents(updated, { limit: 0 }), /from 1 to 10000/);
});

test('includes student identity and private notes only after explicit opt-in', () => {
  const initial = createCasebook(planFor(), { createdAt: '2026-11-01T10:00:00Z', actor: '=SYSTEM()' });
  const item = initial.cases[0];
  const updated = updateCasebook(initial, item.caseId, { note: '=HYPERLINK("https://unsafe.test")' },
    { expectedRevision: 1, actor: 'Reviewer', at: '2026-11-02T10:00:00Z' });
  const safe = listCasebookEvents(updated);
  assert.doesNotMatch(JSON.stringify(safe), /An Example|HYPERLINK/);
  const detailed = listCasebookEvents(updated, { includeStudentDetails: true, includeNotes: true });
  assert.equal(detailed.events[0].studentName, 'An Example');
  assert.equal(detailed.events.at(-1).note, '=HYPERLINK("https://unsafe.test")');
  const csv = casebookEventsToCsv(detailed);
  assert.match(csv, /'=HYPERLINK/);
  assert.match(csv, /"studentId","studentName","note"/);
  assert.match(casebookEventsToCsv(safe), /"caseId","sequence","type"/);
  assert.doesNotMatch(casebookEventsToCsv(safe), /An Example|HYPERLINK|unsafe\.test/);
  assert.throws(() => listCasebookEvents(updated, { includeNotes: 'yes' }), /must be a boolean/);
  assert.throws(() => casebookEventsToCsv({ format: 'other', events: [] }), /invalid/);
});

test('audits current status, assignment and append-only event consistency', () => {
  const initial = createCasebook(planFor(), { createdAt: '2026-11-01T10:00:00Z', actor: 'Reviewer' });
  const item = initial.cases[0];
  const updated = updateCasebook(initial, item.caseId,
    { status: 'in_review', assigneeId: 'staff-1', note: 'Checked the source.' },
    { expectedRevision: 1, actor: 'Reviewer', at: '2026-11-02T10:00:00Z' });
  const clean = auditCasebookHistory(updated);
  assert.equal(clean.summary.valid, true);
  assert.equal(clean.summary.findings, 0);
  assert.equal(clean.summary.events, 4);

  const corrupt = structuredClone(updated);
  corrupt.cases[0].events[1].from = 'dismissed';
  corrupt.cases[0].events[1].to = 'in_review';
  corrupt.cases[0].events[2].from = 'someone-else';
  corrupt.cases[0].status = 'resolved';
  const audit = auditCasebookHistory(corrupt, { includeCaseIds: true, maximumFindings: 2 });
  assert.equal(audit.summary.valid, false);
  assert.equal(audit.summary.findingsTruncated, true);
  assert.equal(audit.findings.length, 2);
  assert.ok(audit.summary.byCode.status_from_mismatch >= 1);
  assert.ok(audit.summary.byCode.invalid_status_transition >= 1);
  assert.equal(audit.findings[0].caseId, item.caseId);
  assert.match(casebookHistoryAuditToCsv(audit), /"caseId","eventSequence","code"/);
  assert.equal(Object.hasOwn(auditCasebookHistory(corrupt).findings[0], 'caseId'), false);
  assert.throws(() => auditCasebookHistory(updated, { maximumFindings: 0 }), /from 1 to 10000/);
  assert.throws(() => auditCasebookHistory(updated, { includeCaseIds: 'yes' }), /must be a boolean/);
  assert.throws(() => casebookHistoryAuditToCsv({ format: 'bad', findings: [] }), /invalid/);
});

test('flags event timestamps that move backwards while retaining the audit result', () => {
  const initial = createCasebook(planFor(), { createdAt: '2026-11-01T10:00:00Z', actor: 'Reviewer' });
  const item = initial.cases[0];
  const updated = updateCasebook(initial, item.caseId, { status: 'in_review', note: 'Reviewed.' },
    { expectedRevision: 1, actor: 'Reviewer', at: '2026-11-02T10:00:00Z' });
  updated.cases[0].events.at(-1).at = '2026-11-01T09:00:00Z';
  const audit = auditCasebookHistory(updated);
  assert.equal(audit.summary.valid, false);
  assert.equal(audit.summary.byCode.event_timestamp_regressed, 1);
  assert.ok(audit.findings.some((finding) => finding.code === 'event_timestamp_regressed'));
});

test('counts event types after filtering even when the returned rows are capped', () => {
  const initial = createCasebook(planFor(), { createdAt: '2026-11-01T10:00:00Z' });
  const item = initial.cases[0];
  const updated = updateCasebook(initial, item.caseId, { status: 'in_review', assigneeId: 'staff-1', note: 'Checked.' },
    { expectedRevision: 1, at: '2026-11-02T10:00:00Z' });
  const result = listCasebookEvents(updated, { limit: 1 });
  assert.equal(result.summary.totalMatches, 4);
  assert.equal(result.summary.returned, 1);
  assert.equal(result.summary.truncated, true);
  assert.deepEqual(result.summary.byType, { created: 1, status: 1, assigned: 1, note: 1 });
});
