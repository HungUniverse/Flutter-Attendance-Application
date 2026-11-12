import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCsv, importAttendanceCsv } from '../attendance-csv-import.mjs';
import { attendanceToCsv } from '../attendance-analytics.mjs';

test('parses escaped quotes, commas, multiline values and physical line numbers', () => {
  assert.deepEqual(parseCsv('\uFEFFa,b\r\n"x,""y""\r\nz",q\r\nlast,\r\n'), [
    { line: 1, fields: ['a', 'b'] },
    { line: 2, fields: ['x,"y"\r\nz', 'q'] },
    { line: 4, fields: ['last', ''] },
  ]);
  assert.deepEqual(parseCsv(''), []);
  assert.deepEqual(parseCsv('""'), [{ line: 1, fields: [''] }]);
});

test('rejects malformed quoting rather than guessing row boundaries', () => {
  assert.throws(() => parseCsv('a"b,c'), /unexpected quote/);
  assert.throws(() => parseCsv('"a"b,c'), /after closing quote/);
  assert.throws(() => parseCsv('"a\nb'), /unclosed/);
  assert.throws(() => parseCsv(null), TypeError);
});

test('imports exported records containing commas and quotes', () => {
  const records = [
    { studentId: 'student,"one"', sessionId: 'session 1', status: 'present' },
    { studentId: 'student two', sessionId: 'session 2', status: 'absent' },
  ];
  assert.deepEqual(importAttendanceCsv(attendanceToCsv(records)), { records, errors: [] });
});

test('reports invalid rows and duplicate locations while keeping valid rows', () => {
  const csv = [
    'status,sessionId,studentId,note',
    'present, s1 , A ,ok',
    'absent,s1,A,duplicate',
    'late,s1,B,bad status',
    'present,s2,,missing student',
    'present,s2,C',
    'absent,s2,C,ok',
  ].join('\n');
  const result = importAttendanceCsv(csv);
  assert.deepEqual(result.records, [
    { studentId: 'A', sessionId: 's1', status: 'present' },
    { studentId: 'C', sessionId: 's2', status: 'absent' },
  ]);
  assert.deepEqual(result.errors.map(({ line, code }) => [line, code]), [
    [3, 'duplicate'], [4, 'invalid_status'], [5, 'missing_id'], [6, 'column_count'],
  ]);
  assert.match(result.errors[0].message, /line 2/);
});

test('requires unique headers and the three required columns', () => {
  assert.throws(() => importAttendanceCsv(''), /header/);
  assert.throws(() => importAttendanceCsv('studentId,studentId,status'), /duplicate/);
  assert.throws(() => importAttendanceCsv('studentId,status'), /requires/);
  assert.deepEqual(importAttendanceCsv('studentId,sessionId,status\n'), { records: [], errors: [] });
});
