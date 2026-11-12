import test from 'node:test';
import assert from 'node:assert/strict';
import { createCasebook, updateCasebook } from './casebook.mjs';
import { casebookSlaToCsv, reportCasebookSla } from './casebook-sla.mjs';

function plan(cases = [{ caseId: '=urgent', studentId: 'S-1', studentName: 'A Student', priority: 'urgent',
  attendanceRate: 0.5, present: 1, absent: 1, missing: 0, reasons: [], suggestedSteps: [] }]) {
  return { version: 1, snapshotFingerprint: 'snapshot-fingerprint', generatedFor: { students: cases.length, sessions: 2, records: 2 },
    summary: { total: cases.length }, cases };
}

function at(hours) {
  return new Date(Date.parse('2026-11-01T00:00:00Z') + hours * 3_600_000).toISOString();
}

function book(cases) {
  return createCasebook(plan(cases), { id: 'book-1', createdAt: at(0), actor: 'reviewer' });
}

test('classifies open cases by priority thresholds using deterministic elapsed time', () => {
  const source = book([
    { caseId: 'u', studentId: 's1', studentName: 'Student 1', priority: 'urgent', attendanceRate: 0.5,
      present: 1, absent: 1, missing: 0, reasons: [], suggestedSteps: [] },
    { caseId: 'h', studentId: 's2', studentName: 'Student 2', priority: 'high', attendanceRate: 0.5,
      present: 1, absent: 1, missing: 0, reasons: [], suggestedSteps: [] },
  ]);
  const report = reportCasebookSla(source, { asOf: at(25) });

  assert.equal(report.summary.total, 2);
  assert.equal(report.summary.breached, 1);
  assert.equal(report.summary.due_soon, 1);
  assert.deepEqual(report.cases.map(({ caseId }) => caseId), ['u', 'h']);
  assert.equal(report.cases[0].activeHours, 25);
  assert.equal(report.cases[0].state, 'breached');
  assert.equal(report.cases[1].hoursUntilBreach, 23);
});

test('pauses the clock while data is requested and resumes after the pause ends', () => {
  const initial = book();
  const id = initial.cases[0].caseId;
  const requested = updateCasebook(initial, id, { status: 'data_needed' }, { expectedRevision: 1, at: at(2) });
  const paused = reportCasebookSla(requested, { asOf: at(20) });
  assert.equal(paused.cases[0].activeHours, 2);
  assert.equal(paused.cases[0].pausedHours, 18);
  assert.equal(paused.cases[0].state, 'paused');

  const resumed = updateCasebook(requested, id, { status: 'in_review' }, { expectedRevision: 2, at: at(20) });
  const active = reportCasebookSla(resumed, { asOf: at(24) });
  assert.equal(active.cases[0].activeHours, 6);
  assert.equal(active.cases[0].pausedHours, 18);
  assert.equal(active.cases[0].state, 'due_soon');
});

test('excludes terminal time, marks stale cases and counts assignments separately', () => {
  const initial = book();
  const id = initial.cases[0].caseId;
  const assigned = updateCasebook(initial, id, { status: 'in_review', assigneeId: 'staff-1' },
    { expectedRevision: 1, at: at(1) });
  const resolved = updateCasebook(assigned, id, { status: 'resolved' }, { expectedRevision: 3, at: at(3) });
  const report = reportCasebookSla(resolved, { asOf: at(100) });

  assert.equal(report.cases[0].activeHours, 3);
  assert.equal(report.cases[0].state, 'closed');
  assert.equal(report.summary.closed, 1);
  assert.equal(report.summary.assigned, 1);
});

test('supports caller thresholds and can report the student fields only by explicit opt-in', () => {
  const report = reportCasebookSla(book(), {
    asOf: at(3),
    rules: { urgent: { warnAfterHours: 2, breachAfterHours: 3 } },
    includeStudentDetails: true,
  });
  assert.equal(report.cases[0].state, 'breached');
  assert.equal(report.cases[0].studentId, 'S-1');
  assert.equal(report.cases[0].studentName, 'A Student');

  const privateByDefault = reportCasebookSla(book(), { asOf: at(1) });
  assert.equal('studentId' in privateByDefault.cases[0], false);
  assert.equal('studentName' in privateByDefault.cases[0], false);
});

test('aggregates totals by priority and assignee without leaking case details', () => {
  const source = book([
    { caseId: 'a', studentId: 's1', studentName: 'One', priority: 'urgent', attendanceRate: null,
      present: 0, absent: 0, missing: 0, reasons: [], suggestedSteps: [] },
    { caseId: 'b', studentId: 's2', studentName: 'Two', priority: 'high', attendanceRate: null,
      present: 0, absent: 0, missing: 0, reasons: [], suggestedSteps: [] },
  ]);
  const assigned = updateCasebook(source, 'a', { assigneeId: 'staff' }, { expectedRevision: 1, at: at(1) });
  const report = reportCasebookSla(assigned, { asOf: at(2) });

  assert.equal(report.byPriority.length, 2);
  assert.deepEqual(report.byAssignee.map(({ key, total }) => [key, total]), [['staff', 1], ['unassigned', 1]]);
  assert.equal(report.summary.on_track, 2);
});

test('exports case, priority, assignee and summary sections with formula-safe cells', () => {
  const report = reportCasebookSla(book(), { asOf: at(1), includeStudentDetails: true });
  assert.match(casebookSlaToCsv(report), /'=urgent/);
  assert.match(casebookSlaToCsv(report), /A Student/);
  assert.match(casebookSlaToCsv(report, 'priority'), /urgent/);
  assert.match(casebookSlaToCsv(report, 'assignee'), /unassigned/);
  assert.match(casebookSlaToCsv(report, 'summary'), /casebookRevision/);
  assert.throws(() => casebookSlaToCsv(report, 'notes'), /section/);
});

test('validates thresholds, pause states, timestamps and future case events', () => {
  const source = book();
  assert.throws(() => reportCasebookSla(source, { asOf: 'yesterdayish' }), /asOf/);
  assert.throws(() => reportCasebookSla(source, { asOf: at(1), rules: { urgent: { warnAfterHours: 5, breachAfterHours: 4 } } }), /cannot exceed/);
  assert.throws(() => reportCasebookSla(source, { asOf: at(1), pauseStatuses: ['unknown'] }), /unsupported pause status/);
  assert.throws(() => reportCasebookSla(source, { asOf: at(1), includeStudentDetails: 'yes' }), /includeStudentDetails/);
  assert.throws(() => reportCasebookSla(source, { asOf: at(-1) }), /event after asOf/);
});
