import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { buildReportStudio, renderReportStudioHtml, reportStudioToCsv } from './report-studio.mjs';

function snapshot() {
  return createAttendanceSnapshot([
    { id: 'A', name: 'An <Student>', email: 'an@example.test' },
    { id: 'B', name: 'Bình & Co', email: 'binh@example.test' },
    { id: 'C', name: 'Formula =Person', email: 'c@example.test' },
  ], ['S1', 'S2', 'S3', 'S4'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'A', sessionId: 'S2', status: 'present' },
    { studentId: 'A', sessionId: 'S3', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'present' },
    { studentId: 'B', sessionId: 'S3', status: 'present' },
    { studentId: 'B', sessionId: 'S4', status: 'present' },
    { studentId: 'C', sessionId: 'S1', status: 'absent' },
    { studentId: 'C', sessionId: 'S2', status: 'absent' },
  ]);
}

test('builds scoped summaries, student rows and session rows using recorded results only', () => {
  const report = buildReportStudio(snapshot(), { generatedAt: '2026-11-01T12:00:00Z' });
  assert.deepEqual(report.summary, {
    students: 3, studentRows: 3, studentsTruncated: 0, sessions: 4, expected: 12, recorded: 9,
    present: 6, absent: 3, missing: 3, coverage: 0.75, attendanceRate: 2 / 3,
  });
  assert.equal(report.students.find((student) => student.studentId === 'A').attendanceRate, 2 / 3);
  assert.equal(report.sessions[3].missing, 2);
  assert.equal(report.matrix, null);
  assert.equal(report.audit, null);
  assert.equal(report.policy, null);
});

test('filters and sorts students while preserving the requested session order', () => {
  const report = buildReportStudio(snapshot(), { studentIds: ['C', 'A'], sessionIds: ['S3', 'S2'], search: 'An',
    sortBy: 'rateDescending', generatedAt: '2026-11-02T00:00:00Z' });
  assert.equal(report.summary.students, 1);
  assert.equal(report.sessions.length, 2);
  assert.equal(report.sessions[0].sessionId, 'S3');
  assert.equal(report.students[0].studentId, 'A');
  assert.equal(report.summary.expected, 2);
  assert.equal(report.summary.recorded, 2);
  assert.equal(report.summary.coverage, 1);
  assert.throws(() => buildReportStudio(snapshot(), { studentIds: ['missing'] }), /unknown studentIds/);
  assert.throws(() => buildReportStudio(snapshot(), { sessionIds: ['S1', 'S1'] }), /duplicates/);
});

test('redacts identity fields from every section, including quality findings', () => {
  const source = snapshot();
  const report = buildReportStudio(source, { includeStudentNames: false, includeStudentIds: false, includeSessionIds: false,
    includeMatrix: true, includeAudit: true, auditOptions: { maximumMissingPerStudent: 0 },
    generatedAt: '2026-11-01T00:00:00Z' });
  const html = renderReportStudioHtml(report);
  assert.doesNotMatch(html, /An &lt;Student&gt;|Bình &amp; Co|Formula =Person|an@example\.test|S1/);
  assert.doesNotMatch(JSON.stringify(report), /an@example\.test|binh@example\.test/);
  assert.ok(report.audit.findings.every((item) => item.subject === null));
  assert.ok(report.students.every((item) => item.studentId === null && item.studentName === null));
  assert.ok(report.matrix.every((item) => item.studentId === null && item.studentName === null));
});

test('includes policy and audit sections with configured limits and safe messages', () => {
  const report = buildReportStudio(snapshot(), { policy: { minimumRate: 0.75, maximumAbsences: 1 }, includeAudit: true,
    maxFindings: 1, generatedAt: '2026-11-01T00:00:00Z' });
  assert.equal(report.policy.length, 3);
  assert.ok(report.policy.some((item) => item.status === 'undetermined'));
  assert.equal(report.audit.findings.length, 1);
  assert.ok(report.audit.truncated);
  assert.match(renderReportStudioHtml(report), /Policy review/);
  assert.match(renderReportStudioHtml(report), /Data quality findings/);
});

test('limits student and matrix detail while keeping full matching totals', () => {
  const students = buildReportStudio(snapshot(), { maxStudentRows: 1, includeMatrix: true, maxMatrixCells: 4,
    sortBy: 'absentDescending', generatedAt: '2026-11-01T00:00:00Z' });
  assert.equal(students.summary.students, 3);
  assert.equal(students.summary.studentRows, 1);
  assert.equal(students.summary.studentsTruncated, 2);
  assert.equal(students.matrix.length, 1);
  assert.equal(students.students[0].studentId, 'C');
  assert.throws(() => buildReportStudio(snapshot(), { includeMatrix: true, maxMatrixCells: 3 }), /matrix would contain/);
});

test('renders escaped, self-contained HTML with optional sections and print styles', () => {
  const report = buildReportStudio(snapshot(), { title: 'Term <Closeout>', includeMatrix: true,
    generatedAt: '2026-11-01T00:00:00Z' });
  const html = renderReportStudioHtml(report);
  assert.match(html, /Term &lt;Closeout&gt;/);
  assert.match(html, /An &lt;Student&gt;/);
  assert.match(html, /Attendance matrix/);
  assert.match(html, /@media print/);
  assert.doesNotMatch(html, /<script|https?:\/\//i);
  assert.throws(() => renderReportStudioHtml({ version: 2 }), /invalid/);
});

test('exports formula-safe CSV for each requested report section', () => {
  const report = buildReportStudio(snapshot(), { includeMatrix: true, includeAudit: true,
    policy: { minimumRate: 0.8, maximumAbsences: 2 }, generatedAt: '2026-11-01T00:00:00Z' });
  assert.match(reportStudioToCsv(report, 'summary'), /"coverage","0\.75"/);
  assert.match(reportStudioToCsv(report, 'students'), /"A","An <Student>"/);
  assert.match(reportStudioToCsv(report, 'sessions'), /"S1"/);
  assert.match(reportStudioToCsv(report, 'matrix'), /"Present"/);
  assert.match(reportStudioToCsv(report, 'audit'), /"severity","code","subject"/);
  assert.match(reportStudioToCsv(report, 'policy'), /"studentId","studentName","status"/);
  assert.throws(() => reportStudioToCsv(report, 'unknown'), /section must be/);
  const formula = createAttendanceSnapshot([{ id: '=CMD()', name: '=Sheet!', email: 'x@example.test' }], ['S1'], [
    { studentId: '=CMD()', sessionId: 'S1', status: 'present' },
  ]);
  const safe = reportStudioToCsv(buildReportStudio(formula, { generatedAt: '2026-11-01T00:00:00Z' }), 'students');
  assert.match(safe, /"'=CMD/);
  assert.match(safe, /"'=Sheet/);
});

test('validates filter, privacy, policy and output-size options', () => {
  assert.throws(() => buildReportStudio(snapshot(), { minimumRate: 0.9, maximumRate: 0.2 }), /must not exceed/);
  assert.throws(() => buildReportStudio(snapshot(), { studentIds: 'A' }), /must be an array/);
  assert.throws(() => buildReportStudio(snapshot(), { sortBy: 'random' }), /sortBy/);
  assert.throws(() => buildReportStudio(snapshot(), { includeMatrix: 'yes' }), /boolean/);
  assert.throws(() => buildReportStudio(snapshot(), { generatedAt: 'not-a-date' }), /timestamp/);
  assert.throws(() => buildReportStudio(snapshot(), { policy: { minimumRate: 2, maximumAbsences: 1 } }), /minimumRate/);
  assert.throws(() => reportStudioToCsv({}, 'students'), /invalid report/);
});
