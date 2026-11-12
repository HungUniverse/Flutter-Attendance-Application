import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mappedImportIssuesToCsv,
  parseDelimitedCsv,
  previewMappedImport,
  suggestHeaderMapping,
} from './import-studio.mjs';

const sessions = ['D1', 'D2'];
const roster = 'MSSV;Họ và tên;Email sinh viên\nA001;Nguyễn An;an@example.test\nB002;Bình Trần;binh@example.test\n';
const attendance = 'Mã sinh viên|Buổi học|Trạng thái\nA001|D1|Có mặt\nB002|D1|Vắng\n';

test('parses BOM, escaped quotes, quoted line breaks, empty fields and physical line numbers', () => {
  const parsed = parseDelimitedCsv('\uFEFFname;notes;extra\r\n"Maya; Ann";"line one\r\nline two";"say ""hi"""\r\nA;;\r\n');
  assert.equal(parsed.delimiter, ';');
  assert.deepEqual(parsed.rows, [
    { line: 1, fields: ['name', 'notes', 'extra'] },
    { line: 2, fields: ['Maya; Ann', 'line one\r\nline two', 'say "hi"'] },
    { line: 4, fields: ['A', '', ''] },
  ]);
});

test('supports explicit and automatic delimiters while rejecting malformed quoting', () => {
  assert.equal(parseDelimitedCsv('id,name,email\nA,An,a@example.test').delimiter, ',');
  assert.equal(parseDelimitedCsv('id\tname\temail\nA\tAn\ta@example.test').delimiter, '\t');
  assert.equal(parseDelimitedCsv('id|name\nA|An', { delimiter: '|' }).rows.length, 2);
  assert.throws(() => parseDelimitedCsv('id,name\nA,"An"oops'), /after closing quote/);
  assert.throws(() => parseDelimitedCsv('id,name\nA,"An'), /unclosed quoted/);
  assert.throws(() => parseDelimitedCsv('a,b', { delimiter: ':' }), /delimiter/);
  assert.throws(() => parseDelimitedCsv('a,b', null), /options/);
});

test('suggests Vietnamese and English field aliases without exposing row values', () => {
  const suggested = suggestHeaderMapping(['MSSV', 'Họ và tên', 'Email sinh viên'], 'roster');
  assert.equal(suggested.ready, true);
  assert.deepEqual(suggested.mapping, { id: 'MSSV', name: 'Họ và tên', email: 'Email sinh viên' });
  assert.ok(suggested.fields.every((field) => field.status === 'matched'));
  assert.deepEqual(suggestHeaderMapping(['Student ID', 'Full Name', 'Email'], 'roster').mapping,
    { id: 'Student ID', name: 'Full Name', email: 'Email' });
  assert.throws(() => suggestHeaderMapping(['x'], 'unknown'), /kind/);
});

test('requests explicit choices when header aliases are ambiguous and allows manual resolution', () => {
  const headers = ['Student ID', 'Student Number', 'Full Name', 'Email'];
  const suggested = suggestHeaderMapping(headers, 'roster');
  assert.equal(suggested.ready, false);
  assert.equal(suggested.fields.find((field) => field.field === 'id').status, 'ambiguous');
  const preview = previewMappedImport({
    rosterCsv: 'Student ID,Student Number,Full Name,Email\nold,A001,An,a@example.test\n',
    attendanceCsv: 'Student,Session,State\nA001,D1,P\n', sessions: ['D1'],
    rosterOptions: { mapping: { id: 'Student Number', name: 'Full Name', email: 'Email' } },
    attendanceOptions: { mapping: { studentId: 'Student', sessionId: 'Session', status: 'State' }, statusAliases: { present: ['P'] } },
  });
  assert.equal(preview.ready, true);
  assert.equal(preview.snapshot.roster[0].id, 'A001');
  assert.equal(preview.snapshot.records[0].status, 'present');
});

test('keeps an incomplete mapping as a preview error and withholds a candidate snapshot', () => {
  const preview = previewMappedImport({
    rosterCsv: 'Student IDd,Full Namee,Email\nA,An,a@example.test\n',
    attendanceCsv: 'Person,Meeting,Result\nA,D1,here\n', sessions: ['D1'],
  });
  assert.equal(preview.ready, false);
  assert.equal(preview.snapshot, null);
  assert.ok(preview.errors.some((issue) => issue.source === 'roster' && issue.code === 'missing_header'));
  assert.ok(preview.errors.some((issue) => issue.source === 'attendance' && issue.code === 'missing_header'));
  assert.ok(preview.mappings.roster.fields.some((field) => field.status === 'suggested'));
});

test('imports mixed delimiters, localized statuses and explicitly missing outcomes', () => {
  const preview = previewMappedImport({
    rosterCsv: roster,
    attendanceCsv: 'Student ID|Session ID|Status\nA001|D1|Có mặt\nA001|D2|chưa ghi\nB002|D1|nghỉ học\nB002|D2|\n',
    sessions,
  });
  assert.equal(preview.ready, true);
  assert.equal(preview.delimiters.roster, ';');
  assert.equal(preview.delimiters.attendance, '|');
  assert.deepEqual(preview.snapshot.records, [
    { studentId: 'A001', sessionId: 'D1', status: 'present' },
    { studentId: 'B002', sessionId: 'D1', status: 'absent' },
  ]);
  assert.equal(preview.summary.attendance.explicitMissing, 2);
  assert.equal(preview.summary.missing, 2);
  assert.equal(preview.summary.coverage, 0.5);
  assert.ok(preview.warnings.some((issue) => issue.code === 'unrecorded_rows'));
});

test('uses custom status vocabulary and rejects ambiguous status aliases', () => {
  const mapped = previewMappedImport({ rosterCsv: 'id,name,email\nA,An,a@example.test\n',
    attendanceCsv: 'studentId,sessionId,status\nA,D1,P\n', sessions: ['D1'],
    attendanceOptions: { statusAliases: { present: ['P'] } } });
  assert.equal(mapped.snapshot.records[0].status, 'present');
  const ambiguous = previewMappedImport({ rosterCsv: 'id,name,email\nA,An,a@example.test\n',
    attendanceCsv: 'studentId,sessionId,status\nA,D1,X\n', sessions: ['D1'],
    attendanceOptions: { statusAliases: { present: ['X'], absent: ['X'] } } });
  assert.equal(ambiguous.ready, false);
  assert.equal(ambiguous.errors[0].code, 'ambiguous_status');
});

test('rejects duplicate roster identities by default and supports explicit first-row choice', () => {
  const source = 'id,name,email\nA,An,a@example.test\nA,Other,a@example.test\n';
  const rejected = previewMappedImport({ rosterCsv: source, attendanceCsv: 'studentId,sessionId,status\nA,D1,present\n', sessions: ['D1'] });
  assert.equal(rejected.ready, false);
  assert.equal(rejected.errors[0].code, 'duplicate_id');
  const first = previewMappedImport({ rosterCsv: source, attendanceCsv: 'studentId,sessionId,status\nA,D1,present\n', sessions: ['D1'],
    rosterOptions: { duplicatePolicy: 'first' } });
  assert.equal(first.ready, true);
  assert.equal(first.snapshot.roster[0].name, 'An');
  assert.ok(first.warnings.some((issue) => issue.code === 'duplicate_skipped'));
  assert.throws(() => previewMappedImport({ rosterCsv: source, attendanceCsv: 'id,sessionId,status\nA,D1,present', sessions: ['D1'],
    rosterOptions: { duplicatePolicy: 'ignore' } }), /reject, first or last/);
});

test('resolves duplicate attendance cells with an explicit policy and tracks source lines', () => {
  const source = 'studentId,sessionId,status\nA,D1,present\nA,D1,absent\n';
  const rejected = previewMappedImport({ rosterCsv: 'id,name,email\nA,An,a@example.test\n', attendanceCsv: source, sessions: ['D1'] });
  assert.equal(rejected.ready, false);
  assert.equal(rejected.errors[0].line, 3);
  const first = previewMappedImport({ rosterCsv: 'id,name,email\nA,An,a@example.test\n', attendanceCsv: source, sessions: ['D1'],
    attendanceOptions: { duplicatePolicy: 'first' } });
  const last = previewMappedImport({ rosterCsv: 'id,name,email\nA,An,a@example.test\n', attendanceCsv: source, sessions: ['D1'],
    attendanceOptions: { duplicatePolicy: 'last' } });
  assert.equal(first.snapshot.records[0].status, 'present');
  assert.equal(last.snapshot.records[0].status, 'absent');
  assert.equal(last.warnings[0].code, 'duplicate_replaced');
});

test('rejects ragged rows, unknown references and malformed sessions without partial snapshots', () => {
  const preview = previewMappedImport({
    rosterCsv: 'id,name,email\nA,An,a@example.test\nB,Bin\n',
    attendanceCsv: 'studentId,sessionId,status\nA,D1,present\nUNKNOWN,D3,absent\n',
    sessions,
  });
  assert.equal(preview.ready, false);
  assert.equal(preview.snapshot, null);
  assert.ok(preview.errors.some((issue) => issue.code === 'column_count' && issue.line === 3));
  assert.ok(preview.errors.some((issue) => issue.code === 'unknown_student'));
  assert.ok(preview.errors.some((issue) => issue.code === 'unknown_session'));
  assert.throws(() => previewMappedImport({ rosterCsv: '', attendanceCsv: '', sessions: ['D1', 'D1'] }), /unique/);
});

test('exports safe issue CSV without including student or source-cell values', () => {
  const preview = previewMappedImport({ rosterCsv: 'id,name,email\nA,An,a@example.test\n',
    attendanceCsv: 'studentId,sessionId,status\nA,D1,unexpected\n', sessions: ['D1'] });
  const csv = mappedImportIssuesToCsv(preview);
  assert.match(csv, /"error","attendance","2","invalid_status"/);
  assert.doesNotMatch(csv, /a@example\.test|unexpected|\nA,/);
  assert.throws(() => mappedImportIssuesToCsv({ version: 2 }), /invalid/);
});

test('validates dimensions, mapping options, status aliases and row sizes', () => {
  const goodRoster = 'id,name,email\nA,An,a@example.test\n';
  const goodAttendance = 'studentId,sessionId,status\nA,D1,present\n';
  assert.throws(() => previewMappedImport({ rosterCsv: goodRoster, attendanceCsv: goodAttendance, sessions: ['D1'], rosterOptions: null }), /rosterOptions/);
  assert.throws(() => previewMappedImport({ rosterCsv: goodRoster, attendanceCsv: goodAttendance, sessions: ['D1'],
    attendanceOptions: { statusAliases: { unknown: ['X'] } } }), /unknown status alias group/);
  assert.throws(() => previewMappedImport({ rosterCsv: goodRoster, attendanceCsv: goodAttendance, sessions: ['D1'],
    rosterOptions: { mapping: { id: 'absent' } } }), /existing CSV header/);
  assert.throws(() => previewMappedImport({ rosterCsv: `${'a'.repeat(20_000_001)}`, attendanceCsv: goodAttendance, sessions: ['D1'] }), /characters/);
});

