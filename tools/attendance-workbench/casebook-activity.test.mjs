import test from 'node:test';
import assert from 'node:assert/strict';
import { createCasebook, updateCasebook } from './casebook.mjs';
import { casebookActivityToCsv, reportCasebookActivity } from './casebook-activity.mjs';

function at(day, hour = 0) {
  return new Date(Date.parse(`2026-11-${String(day).padStart(2, '0')}T00:00:00Z`) + hour * 3_600_000).toISOString();
}

function book() {
  const plan = { version: 1, snapshotFingerprint: 'fp', generatedFor: { students: 1, sessions: 2, records: 2 },
    summary: { total: 1 }, cases: [{ caseId: 'case-1', studentId: 'S1', studentName: 'Student Name', priority: 'urgent',
      attendanceRate: 0.5, present: 1, absent: 1, missing: 0, reasons: [], suggestedSteps: [] }] };
  return createCasebook(plan, { id: '=activity-book', createdAt: at(1), actor: 'requester' });
}

function fullHistory() {
  let result = book();
  result = updateCasebook(result, 'case-1', { status: 'in_review', assigneeId: 'staff-a' },
    { expectedRevision: 1, actor: 'reviewer-a', at: at(2) });
  result = updateCasebook(result, 'case-1', { note: 'Sensitive internal note' },
    { expectedRevision: 3, actor: 'reviewer-a', at: at(2, 1) });
  result = updateCasebook(result, 'case-1', { status: 'resolved' },
    { expectedRevision: 4, actor: 'reviewer-b', at: at(3) });
  result = updateCasebook(result, 'case-1', { status: 'reopened' },
    { expectedRevision: 5, actor: 'reviewer-a', at: at(4) });
  result = updateCasebook(result, 'case-1', { status: 'in_review' },
    { expectedRevision: 6, actor: 'reviewer-a', at: at(4, 1) });
  return updateCasebook(result, 'case-1', { status: 'resolved' },
    { expectedRevision: 7, actor: 'reviewer-b', at: at(4, 2) });
}

test('summarizes event types, UTC days, reopenings and resolution cycle durations', () => {
  const report = reportCasebookActivity(fullHistory(), { from: at(1), to: at(5) });
  assert.equal(report.summary.totalEvents, 8);
  assert.equal(report.summary.openedCases, 1);
  assert.equal(report.summary.resolvedCases, 1);
  assert.equal(report.summary.reopenedCases, 1);
  assert.equal(report.summary.byType.note, 1);
  assert.equal(report.summary.resolvedDuration.count, 2);
  assert.equal(report.summary.resolvedDuration.meanHours, 25);
  assert.equal(report.summary.resolvedDuration.medianHours, 25);
  assert.equal(report.summary.resolvedDuration.p90Hours, 48);
  assert.deepEqual(report.byDay.map((item) => item.date), ['2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04']);
  assert.ok(report.transitions.some((item) => item.transition === 'resolved->reopened' && item.total === 1));
});

test('filters event and resolution counts to the inclusive requested window', () => {
  const report = reportCasebookActivity(fullHistory(), { from: at(3), to: at(4, 2) });
  assert.equal(report.summary.totalEvents, 4);
  assert.equal(report.summary.resolvedCases, 1);
  assert.equal(report.summary.reopenedCases, 1);
  assert.equal(report.summary.resolvedDuration.count, 2);
  const singleDay = reportCasebookActivity(fullHistory(), { from: at(3), to: at(3, 23) });
  assert.equal(singleDay.summary.totalEvents, 1);
  assert.equal(singleDay.summary.resolvedDuration.count, 1);
});

test('keeps event rows and actor aggregates opt-in and always omits notes and student identities', () => {
  const report = reportCasebookActivity(fullHistory(), { from: at(1), to: at(5), includeEventRows: true,
    includeActorBreakdown: true });
  assert.equal(report.actors.length, 3);
  assert.equal(report.events.length, 8);
  assert.equal('actor' in report.events[0], true);
  assert.equal(JSON.stringify(report).includes('Sensitive internal note'), false);
  assert.equal(JSON.stringify(report).includes('Student Name'), false);
  const defaults = reportCasebookActivity(fullHistory(), { from: at(1), to: at(5), includeEventRows: true });
  assert.equal('actor' in defaults.events[0], false);
  assert.deepEqual(defaults.actors, []);
});

test('caps opted-in event lists and rejects backwards or malformed time windows', () => {
  const source = fullHistory();
  assert.throws(() => reportCasebookActivity(source, { from: at(1), to: at(5), includeEventRows: true, maximumEventRows: 2 }), /exceed maximumEventRows/);
  assert.throws(() => reportCasebookActivity(source, { from: at(5), to: at(1) }), /from must not be after to/);
  assert.throws(() => reportCasebookActivity(source, { from: 'invalid' }), /from must be a valid timestamp/);
});

test('exports daily, transition, actor, event and formula-safe summary CSV', () => {
  const report = reportCasebookActivity(fullHistory(), { from: at(1), to: at(5), includeEventRows: true,
    includeActorBreakdown: true });
  assert.match(casebookActivityToCsv(report), /'=activity-book/);
  assert.match(casebookActivityToCsv(report, 'daily'), /2026-11-01/);
  assert.match(casebookActivityToCsv(report, 'transitions'), /resolved->reopened/);
  assert.match(casebookActivityToCsv(report, 'actors'), /reviewer-a/);
  assert.match(casebookActivityToCsv(report, 'events'), /caseId/);
  assert.throws(() => casebookActivityToCsv(reportCasebookActivity(fullHistory(), { from: at(1), to: at(5) }), 'events'), /not enabled/);
  assert.throws(() => casebookActivityToCsv(report, 'unknown'), /section/);
});

test('rejects event histories whose timestamps move backwards', () => {
  const malformed = structuredClone(fullHistory());
  malformed.cases[0].events[2].at = at(1);
  assert.throws(() => reportCasebookActivity(malformed, { from: at(1), to: at(5) }), /not chronological/);
});
