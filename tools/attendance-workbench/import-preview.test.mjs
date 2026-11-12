import test from 'node:test';
import assert from 'node:assert/strict';
import { previewAttendanceImport } from './import-preview.mjs';

const validInput = {
  rosterCsv: 'id,name,email\nA,An,a@example.test\nB,Binh,b@example.test\n',
  sessions: '["s1","s2"]',
  attendanceCsv: 'studentId,sessionId,status\nA,s1,present\nB,s1,absent\n',
};

test('previews a complete three-file import and returns an isolated candidate snapshot', () => {
  const preview = previewAttendanceImport(validInput);
  assert.equal(preview.ready, true);
  assert.equal(preview.summary.roster.accepted, 2);
  assert.equal(preview.summary.sessions, 2);
  assert.equal(preview.summary.expected, 4);
  assert.equal(preview.summary.recorded, 2);
  assert.equal(preview.summary.missing, 2);
  assert.equal(preview.summary.coverage, 0.5);
  assert.equal(preview.warnings[0].code, 'incomplete_coverage');
  assert.equal(preview.snapshot.records.length, 2);
  assert.equal(validInput.rosterCsv.startsWith('id,name,email'), true);
});

test('collects row errors across files and withholds a partial snapshot', () => {
  const preview = previewAttendanceImport({
    rosterCsv: 'id,name,email\nA,An,invalid\nA,Another,a@example.test\nA,Third,third@example.test\n',
    sessions: ['s1'],
    attendanceCsv: 'studentId,sessionId,status\nA,s1,present\nB,s2,unknown\n',
  });
  assert.equal(preview.ready, false);
  assert.equal(preview.snapshot, null);
  assert.ok(preview.errors.some((item) => item.source === 'roster' && item.line === 2 && item.code === 'invalid_email'));
  assert.ok(preview.errors.some((item) => item.source === 'roster' && item.code === 'duplicate_id'));
  assert.ok(preview.errors.some((item) => item.source === 'attendance' && item.code === 'invalid_status'));
});

test('rejects attendance references outside the accepted roster or schedule', () => {
  const preview = previewAttendanceImport({ ...validInput,
    attendanceCsv: 'studentId,sessionId,status\nUnknown,other,present\n' });
  assert.equal(preview.ready, false);
  assert.equal(preview.snapshot, null);
  assert.ok(preview.errors.some((item) => item.code === 'unknown_student'));
  assert.ok(preview.errors.some((item) => item.code === 'unknown_session'));
  assert.deepEqual([preview.summary.attendance.accepted, preview.summary.attendance.rejected], [0, 1]);
});

test('turns malformed headers and invalid schedule JSON into actionable preview errors', () => {
  const preview = previewAttendanceImport({
    rosterCsv: 'name,email\nAn,a@example.test\n',
    sessions: '{not json',
    attendanceCsv: 'studentId,sessionId,status\n',
  });
  assert.equal(preview.ready, false);
  assert.equal(preview.snapshot, null);
  assert.ok(preview.errors.some((item) => item.source === 'roster' && item.code === 'invalid_csv'));
  assert.ok(preview.errors.some((item) => item.source === 'sessions' && item.code === 'invalid_sessions'));
});

test('rejects duplicate session IDs instead of building an ambiguous preview', () => {
  const preview = previewAttendanceImport({ ...validInput, sessions: ['s1', 's1'] });
  assert.equal(preview.ready, false);
  assert.ok(preview.errors.some((item) => item.source === 'sessions' && item.message.includes('unique')));
});
