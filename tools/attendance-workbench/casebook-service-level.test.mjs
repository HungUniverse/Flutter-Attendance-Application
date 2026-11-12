import test from 'node:test';
import assert from 'node:assert/strict';
import { createCasebook, updateCasebook } from './casebook.mjs';
import { casebookServiceLevelsToCsv, evaluateCasebookServiceLevels } from './casebook-service-level.mjs';

function at(hours) {
  return new Date(Date.parse('2026-11-01T00:00:00Z') + hours * 3_600_000).toISOString();
}

function book() {
  const cases = [
    { caseId: '=urgent', studentId: 'A', studentName: 'Alpha', priority: 'urgent' },
    { caseId: 'high', studentId: 'B', studentName: 'Beta', priority: 'high' },
  ].map((item) => ({ ...item, attendanceRate: 0.5, present: 1, absent: 1, missing: 0, reasons: [], suggestedSteps: [] }));
  return createCasebook({ version: 1, snapshotFingerprint: 'fp', generatedFor: { students: 2, sessions: 2, records: 4 },
    summary: { total: 2 }, cases }, { id: 'sla-book', createdAt: at(0) });
}

function history() {
  let result = book();
  result = updateCasebook(result, '=urgent', { status: 'data_needed' }, { expectedRevision: 1, actor: 'staff', at: at(1) });
  result = updateCasebook(result, '=urgent', { status: 'in_review' }, { expectedRevision: 2, actor: 'staff', at: at(10) });
  result = updateCasebook(result, '=urgent', { status: 'resolved' }, { expectedRevision: 3, actor: 'staff', at: at(20) });
  return updateCasebook(result, 'high', { assigneeId: 'team' }, { expectedRevision: 1, actor: 'staff', at: at(6) });
}

test('evaluates response and resolution targets using active time with data-needed pauses', () => {
  const report = evaluateCasebookServiceLevels(history(), { from: at(0), to: at(1), asOf: at(80),
    rules: { urgent: { responseHours: 4, resolutionHours: 12 } } });
  assert.equal(report.summary.cases, 2);
  assert.equal(report.summary.responsesMet, 2);
  assert.equal(report.summary.responsesMissed, 0);
  assert.equal(report.summary.resolutionCycles, 1);
  assert.equal(report.summary.resolutionMet, 1);
  assert.equal(report.summary.resolutionsBreachedOpen, 1);
  assert.equal(report.summary.responseMetRate, 1);
  assert.equal(report.summary.resolutionMetRate, 1);
  assert.equal('cases' in report, false);
});

test('reports case-level timing only with opt-in and protects formula-prefixed identifiers', () => {
  const report = evaluateCasebookServiceLevels(history(), { from: at(0), to: at(1), asOf: at(80), includeCaseRows: true });
  const urgent = report.cases.find((item) => item.caseId === '=urgent');
  assert.equal(urgent.responseHours, 1);
  assert.equal(urgent.responseState, 'met');
  assert.equal(urgent.resolutionCycles[0].hours, 11);
  assert.equal(urgent.resolutionCycles[0].state, 'met');
  assert.equal(report.cases.find((item) => item.caseId === 'high').resolutionState, 'breached_open');
  assert.match(casebookServiceLevelsToCsv(report, 'cases'), /'=urgent/);
  assert.match(casebookServiceLevelsToCsv(report, 'priority'), /urgent/);
  assert.match(casebookServiceLevelsToCsv(report, 'summary'), /responseMetRate/);
  assert.throws(() => casebookServiceLevelsToCsv(evaluateCasebookServiceLevels(history(), { from: at(0), to: at(1), asOf: at(80) }), 'cases'), /not enabled/);
});

test('uses as-of time for pending and breached response deadlines and excludes later events', () => {
  const early = evaluateCasebookServiceLevels(history(), { from: at(0), to: at(0.5), asOf: at(0.5), includeCaseRows: true });
  assert.equal(early.summary.responsesPending, 2);
  assert.equal(early.cases.find((item) => item.caseId === '=urgent').responseAt, null);
  const late = evaluateCasebookServiceLevels(book(), { from: at(0), to: at(1), asOf: at(5), includeCaseRows: true,
    rules: { urgent: { responseHours: 4, resolutionHours: 24 } } });
  assert.equal(late.summary.responsesBreachedOpen, 1);
});

test('filters by case creation window and validates thresholds, time and row limits', () => {
  const source = history();
  assert.throws(() => evaluateCasebookServiceLevels(source, { from: at(2), to: at(1), asOf: at(80) }), /from must not be after to/);
  assert.throws(() => evaluateCasebookServiceLevels(source, { from: at(0), to: at(1), asOf: at(0) }), /to must not be after asOf/);
  assert.throws(() => evaluateCasebookServiceLevels(source, { from: at(0), to: at(1), asOf: at(80), rules: { urgent: { responseHours: -1 } } }), /responseHours/);
  assert.throws(() => evaluateCasebookServiceLevels(source, { from: at(0), to: at(1), asOf: at(80), includeCaseRows: true, maximumCaseRows: 1 }), /exceed/);
  assert.throws(() => casebookServiceLevelsToCsv(evaluateCasebookServiceLevels(source, { from: at(0), to: at(1), asOf: at(80) }), 'other'), /section/);
});
