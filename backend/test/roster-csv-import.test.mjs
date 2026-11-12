import test from 'node:test';
import assert from 'node:assert/strict';
import { importRosterCsv } from '../roster-csv-import.mjs';
import { normalizeRoster } from '../roster-reconciliation.mjs';

test('imports reordered columns, quoted values and normalized email', () => {
  const result = importRosterCsv('\uFEFFemail,name,id,extra\r\nA@EXAMPLE.COM,"An, Nguyen", A ,x\r\n');
  assert.deepEqual(result, { students: [{ id: 'A', name: 'An, Nguyen', email: 'a@example.com' }], errors: [] });
  assert.deepEqual(normalizeRoster(result.students), result.students);
});

test('reports row errors with physical line numbers and accepted-row duplicates', () => {
  const csv = ['id,name,email', 'A,"An\nNguyen",a@example.com', 'A,Other,b@example.com',
    'B,Other,A@EXAMPLE.COM', 'B,,b@example.com', 'B,Other,bad', 'B,Other',
    'B,Other,b@example.com'].join('\n');
  const result = importRosterCsv(csv);
  assert.deepEqual(result.errors, [
    { line: 4, code: 'duplicate_id', firstLine: 2 },
    { line: 5, code: 'duplicate_email', firstLine: 2 },
    { line: 6, code: 'missing_field' },
    { line: 7, code: 'invalid_email' },
    { line: 8, code: 'column_count' },
  ]);
  assert.deepEqual(result.students.map((student) => student.id), ['A', 'B']);
});

test('rejects invalid headers and malformed CSV', () => {
  assert.throws(() => importRosterCsv(''), /header/);
  assert.throws(() => importRosterCsv('id,id,email'), /duplicate/);
  assert.throws(() => importRosterCsv('id,name'), /requires/);
  assert.throws(() => importRosterCsv('id,name,email\n"broken'), /unclosed/);
  assert.deepEqual(importRosterCsv('id,name,email\n'), { students: [], errors: [] });
});
