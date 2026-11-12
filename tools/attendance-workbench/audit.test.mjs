import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { auditAttendanceSnapshot, auditToCsv } from './audit.mjs';

test('reports duplicate identities, missing outcomes, low rates and absence streaks deterministically', () => {
  const snapshot = createAttendanceSnapshot([
    { id: 'A', name: 'Nguyễn An', email: 'a@example.test' },
    { id: 'B', name: '  NGUYỄN   AN ', email: 'b@example.test' },
  ], ['1', '2', '3'], [
    { studentId: 'A', sessionId: '1', status: 'absent' },
    { studentId: 'A', sessionId: '2', status: 'absent' },
    { studentId: 'A', sessionId: '3', status: 'absent' },
    { studentId: 'B', sessionId: '1', status: 'present' },
  ]);
  const report = auditAttendanceSnapshot(snapshot, { maximumMissingPerStudent: 1 });
  const codes = report.issues.map((item) => item.code);
  assert.equal(report.summary.total, report.issues.length);
  assert.equal(report.summary.byCode.duplicate_name, 1);
  assert.equal(report.summary.byCode.absence_streak, 1);
  assert.ok(codes.includes('student_missing_results'));
  assert.ok(codes.includes('low_student_rate'));
  assert.deepEqual(report.issues, [...report.issues].sort((a, b) =>
    ({ error: 0, warning: 1, info: 2 })[a.severity] - ({ error: 0, warning: 1, info: 2 })[b.severity] ||
    a.code.localeCompare(b.code) || a.subject.localeCompare(b.subject)));
  assert.equal(snapshot.records.length, 4);
});

test('reports empty datasets and wholly unrecorded sessions', () => {
  const empty = auditAttendanceSnapshot(createAttendanceSnapshot([], [], []));
  assert.deepEqual(empty.issues.map((item) => item.code), ['empty_roster', 'empty_schedule']);
  const noResults = auditAttendanceSnapshot(createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'a@example.test' }], ['1', '2'], []));
  assert.ok(noResults.issues.some((item) => item.code === 'no_recorded_results'));
  assert.equal(noResults.summary.byCode.session_unrecorded, 2);
});

test('accepts caller thresholds and validates option ranges', () => {
  const snapshot = createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'a@example.test' }], ['1', '2'], [
    { studentId: 'A', sessionId: '1', status: 'present' },
    { studentId: 'A', sessionId: '2', status: 'absent' },
  ]);
  const relaxed = auditAttendanceSnapshot(snapshot, { minimumAttendanceRate: 0.4, minimumRecordedSessions: 1,
    maximumMissingPerStudent: 0, absenceStreakLength: 2, lowSessionRate: 0 });
  assert.equal(relaxed.summary.byCode.low_student_rate, undefined);
  assert.equal(relaxed.options.minimumAttendanceRate, 0.4);
  assert.throws(() => auditAttendanceSnapshot(snapshot, { lowSessionRate: 1.1 }), /lowSessionRate/);
  assert.throws(() => auditAttendanceSnapshot(snapshot, { absenceStreakLength: 1 }), /absenceStreakLength/);
});

test('exports concise findings as spreadsheet-safe CSV', () => {
  const snapshot = createAttendanceSnapshot([{ id: '+B1', name: '=HYPERLINK("x")', email: 'a@example.test' }], ['1', '2', '3'], [
    { studentId: '+B1', sessionId: '1', status: 'absent' },
    { studentId: '+B1', sessionId: '2', status: 'absent' },
    { studentId: '+B1', sessionId: '3', status: 'absent' },
  ]);
  const csv = auditToCsv(auditAttendanceSnapshot(snapshot));
  assert.match(csv, /"'=HYPERLINK/);
  assert.match(csv, /"'\+B1/);
  assert.throws(() => auditToCsv({ version: 2, issues: [] }), /invalid audit/);
});
