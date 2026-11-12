import test from 'node:test';
import assert from 'node:assert/strict';
import { createCasebook, updateCasebook } from './casebook.mjs';
import { casebookWorkloadToCsv, reportCasebookWorkload } from './casebook-workload.mjs';

function startingBook() {
  const cases = [
    ['=urgent', 'S1', 'Student One', 'urgent'],
    ['high', 'S2', 'Student Two', 'high'],
    ['orphan', 'S3', 'Student Three', 'review'],
    ['unassigned', 'S4', 'Student Four', 'review'],
    ['inactive', 'S5', 'Student Five', 'review'],
    ['done', 'S6', 'Student Six', 'high'],
  ].map(([caseId, studentId, studentName, priority]) => ({ caseId, studentId, studentName, priority,
    attendanceRate: null, present: 0, absent: 0, missing: 0, reasons: [], suggestedSteps: [] }));
  let book = createCasebook({ version: 1, snapshotFingerprint: 'fp', generatedFor: { students: 6, sessions: 0, records: 0 },
    summary: { total: cases.length }, cases }, { id: 'workload-book', createdAt: '2026-11-01T00:00:00Z' });
  for (const [caseId, assigneeId] of [['=urgent', 'r1'], ['high', 'r1'], ['orphan', 'ghost'], ['inactive', 'r2'], ['done', 'r1']]) {
    const current = book.cases.find((item) => item.caseId === caseId);
    const action = caseId === 'done' ? { assigneeId, status: 'resolved' } : { assigneeId };
    book = updateCasebook(book, caseId, action, { expectedRevision: current.revision, actor: 'reviewer', at: '2026-11-02T00:00:00Z' });
  }
  return book;
}

const reviewers = [
  { id: 'r1', name: 'Reviewer One', capacityCases: 1, capacityPoints: 4 },
  { id: 'r2', name: 'Reviewer Two', active: false, capacityCases: 2, capacityPoints: 5 },
];

test('compares open case assignments with active reviewer capacities', () => {
  const report = reportCasebookWorkload(startingBook(), reviewers);

  assert.equal(report.summary.totalCases, 6);
  assert.equal(report.summary.openCases, 5);
  assert.equal(report.summary.terminalCases, 1);
  assert.equal(report.summary.assignedOpenCases, 3);
  assert.equal(report.summary.unassignedOpenCases, 1);
  assert.equal(report.summary.orphanedAssignments, 1);
  assert.equal(report.summary.inactiveAssignedCases, 1);
  assert.equal(report.summary.reviewersOverCapacity, 1);
  const first = report.reviewers.find((item) => item.id === 'r1');
  assert.equal(first.openCases, 2);
  assert.equal(first.workloadPoints, 5);
  assert.equal(first.overCapacity, true);
  assert.equal(first.utilizationPercent, 200);
  assert.equal('name' in first, false);
});

test('tunes workload weights, warning thresholds and explicit identity fields', () => {
  const report = reportCasebookWorkload(startingBook(), reviewers, {
    priorityWeights: { urgent: 1, high: 4, review: 1 },
    utilizationWarningPercent: 50,
    includeReviewerNames: true,
    includeCaseRows: true,
    includeStudentDetails: true,
  });
  const first = report.reviewers.find((item) => item.id === 'r1');
  assert.equal(first.workloadPoints, 5);
  assert.equal(first.name, 'Reviewer One');
  assert.equal(first.atWarningThreshold, true);
  assert.equal(report.cases.find((item) => item.caseId === '=urgent').studentName, 'Student One');
});

test('reports priority and status totals without emitting case rows by default', () => {
  const report = reportCasebookWorkload(startingBook(), reviewers);
  assert.deepEqual(report.byPriority, [{ key: 'high', total: 1 }, { key: 'review', total: 3 }, { key: 'urgent', total: 1 }]);
  assert.deepEqual(report.byStatus, [{ key: 'new', total: 5 }]);
  assert.equal('cases' in report, false);
});

test('exports aggregate, reviewer and case sections with spreadsheet-safe cells', () => {
  const report = reportCasebookWorkload(startingBook(), reviewers, { includeReviewerNames: true, includeCaseRows: true,
    includeStudentDetails: true });
  assert.match(casebookWorkloadToCsv(report, 'summary'), /orphanedAssignments/);
  assert.match(casebookWorkloadToCsv(report), /Reviewer One/);
  assert.match(casebookWorkloadToCsv(report, 'priorities'), /urgent/);
  assert.match(casebookWorkloadToCsv(report, 'statuses'), /new/);
  assert.match(casebookWorkloadToCsv(report, 'cases'), /Student One/);
  assert.match(casebookWorkloadToCsv(report, 'cases'), /'=urgent/);
  assert.throws(() => casebookWorkloadToCsv(reportCasebookWorkload(startingBook(), reviewers), 'cases'), /not enabled/);
  assert.throws(() => casebookWorkloadToCsv(report, 'other'), /section/);
});

test('validates reviewer capacities, duplicate IDs, and detail limits', () => {
  const source = startingBook();
  assert.throws(() => reportCasebookWorkload(source, [{ id: 'r', name: 'One', capacityCases: -1, capacityPoints: 1 }]), /capacityCases/);
  assert.throws(() => reportCasebookWorkload(source, [
    { id: 'r', name: 'One', capacityCases: 1, capacityPoints: 1 },
    { id: 'r', name: 'Two', capacityCases: 1, capacityPoints: 1 },
  ]), /duplicate reviewer/);
  assert.throws(() => reportCasebookWorkload(source, reviewers, { includeCaseRows: true, maximumCaseRows: 2 }), /exceed/);
  assert.throws(() => reportCasebookWorkload(source, reviewers, { utilizationWarningPercent: 101 }), /percentage/);
  assert.throws(() => reportCasebookWorkload(source, reviewers, { includeStudentDetails: 'yes' }), /boolean/);
});
