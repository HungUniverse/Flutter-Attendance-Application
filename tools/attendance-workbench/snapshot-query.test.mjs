import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import {
  attendanceQueryDiffToCsv,
  attendanceQueryToCsv,
  compareAttendanceQueryResults,
  queryAttendanceSnapshot,
} from './snapshot-query.mjs';

function sample() {
  return createAttendanceSnapshot([
    { id: 'A', name: 'Alice Example', email: 'alice@example.test' },
    { id: 'B', name: 'Bob Example', email: 'bob@example.test' },
    { id: 'C', name: '=Casey Example', email: 'casey@example.test' },
  ], ['S1', 'S2', 'S3'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'A', sessionId: 'S2', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'present' },
    { studentId: 'C', sessionId: 'S1', status: 'absent' },
    { studentId: 'C', sessionId: 'S3', status: 'absent' },
  ]);
}

test('returns a bounded page with summary statistics and keeps private columns opt-in', () => {
  const input = sample();
  const before = serializeAttendanceSnapshot(input);
  const result = queryAttendanceSnapshot(input, { page: 2, pageSize: 4, sort: [{ field: 'studentId', direction: 'asc' }] });
  assert.equal(result.format, 'attendance-snapshot-query');
  assert.deepEqual(result.query.columns, ['studentId', 'sessionId', 'status']);
  assert.equal(result.summary.scannedCells, 9);
  assert.equal(result.summary.matchedRows, 9);
  assert.equal(result.summary.recordedRows, 6);
  assert.equal(result.summary.present, 3);
  assert.equal(result.summary.absent, 3);
  assert.equal(result.summary.missing, 3);
  assert.equal(result.summary.attendanceRate, 0.5);
  assert.equal(result.summary.coverage, 2 / 3);
  assert.equal(result.summary.totalPages, 3);
  assert.equal(result.summary.hasMore, true);
  assert.equal(Object.hasOwn(result.rows[0], 'studentName'), false);
  assert.equal(serializeAttendanceSnapshot(input), before);
});

test('filters rows with nested all/any/not logic and case-insensitive text operators', () => {
  const result = queryAttendanceSnapshot(sample(), {
    where: { all: [
      { field: 'status', op: 'in', value: ['present', 'absent'] },
      { any: [
        { field: 'studentName', op: 'contains', value: 'ALICE' },
        { not: { field: 'studentEmail', op: 'suffix', value: '@example.test' } },
      ] },
    ] },
    columns: ['studentId', 'studentName', 'sessionId', 'status'],
  });
  assert.equal(result.summary.matchedRows, 2);
  assert.deepEqual(result.rows.map((row) => row.sessionId), ['S1', 'S2']);
  assert.equal(result.rows[0].studentName, 'Alice Example');
});

test('supports each safe text and membership operator with explicit case sensitivity', () => {
  const cases = [
    [{ field: 'studentId', op: 'eq', value: 'A' }, 3],
    [{ field: 'studentId', op: 'neq', value: 'A' }, 6],
    [{ field: 'studentName', op: 'prefix', value: 'alice' }, 3],
    [{ field: 'studentEmail', op: 'contains', value: 'CASEY' }, 3],
    [{ field: 'studentName', op: 'suffix', value: 'Example' }, 9],
    [{ field: 'sessionId', op: 'gt', value: 'S1' }, 6],
    [{ field: 'sessionId', op: 'gte', value: 'S2' }, 6],
    [{ field: 'sessionId', op: 'lt', value: 'S3' }, 6],
    [{ field: 'sessionId', op: 'lte', value: 'S1' }, 3],
    [{ field: 'studentId', op: 'in', value: ['A', 'C'] }, 6],
    [{ field: 'studentId', op: 'notIn', value: ['B'] }, 6],
    [{ field: 'studentId', op: 'eq', value: 'alice' }, 0],
  ];
  for (const [where, count] of cases) {
    assert.equal(queryAttendanceSnapshot(sample(), { where }).summary.matchedRows, count, JSON.stringify(where));
  }
  assert.equal(queryAttendanceSnapshot(sample(), { where: { field: 'studentId', op: 'eq', value: 'a' }, caseSensitive: true }).summary.matchedRows, 0);
  assert.equal(queryAttendanceSnapshot(sample(), { where: { field: 'studentId', op: 'isMissing' } }).summary.matchedRows, 0);
  assert.equal(queryAttendanceSnapshot(sample(), { where: { field: 'status', op: 'isMissing' } }).summary.matchedRows, 3);
  assert.equal(queryAttendanceSnapshot(sample(), { where: { field: 'status', op: 'isPresent' } }).summary.matchedRows, 6);
});

test('excludes missing cells when requested without confusing them with missing roster fields', () => {
  const all = queryAttendanceSnapshot(sample());
  const recorded = queryAttendanceSnapshot(sample(), { includeUnrecorded: false });
  assert.equal(all.summary.matchedRows, 9);
  assert.equal(recorded.summary.matchedRows, 6);
  assert.equal(recorded.summary.missing, 0);
  assert.equal(recorded.rows.some((row) => row.status === 'missing'), false);
  assert.equal(queryAttendanceSnapshot(sample(), { where: { field: 'status', op: 'eq', value: 'missing' } }).summary.matchedRows, 3);
});

test('sorts deterministically and paginates without exposing out-of-page rows', () => {
  const first = queryAttendanceSnapshot(sample(), { sort: [{ field: 'studentId' }, { field: 'sessionId', direction: 'desc' }], page: 1, pageSize: 2 });
  const second = queryAttendanceSnapshot(sample(), { sort: [{ field: 'studentId' }, { field: 'sessionId', direction: 'desc' }], page: 2, pageSize: 2 });
  assert.deepEqual(first.rows.map((row) => [row.studentId, row.sessionId]), [['A', 'S3'], ['A', 'S2']]);
  assert.deepEqual(second.rows.map((row) => [row.studentId, row.sessionId]), [['A', 'S1'], ['B', 'S3']]);
  assert.equal(first.summary.hasMore, true);
  assert.equal(second.summary.hasMore, true);
});

test('groups records by explicit dimensions and suppresses small cells', () => {
  const result = queryAttendanceSnapshot(sample(), { groupBy: ['status'], minimumGroupSize: 3 });
  assert.equal(result.rows, null);
  assert.equal(result.summary.groups, 3);
  const present = result.groups.find((item) => item.status === 'present');
  const absent = result.groups.find((item) => item.status === 'absent');
  const missing = result.groups.find((item) => item.status === 'missing');
  assert.equal(present.suppressed, true);
  assert.equal(present.studentCount, null);
  assert.equal(present.attendanceRate, null);
  assert.equal(absent.suppressed, true);
  assert.equal(missing.suppressed, false);
  assert.equal(missing.studentCount, 3);
  assert.equal(missing.present, 0);
  assert.equal(missing.coverage, 0);
  assert.equal(attendanceQueryToCsv(result, 'groups').includes('"present","","","",""'), true);
});

test('supports group filters, status rollups and zero-record groups', () => {
  const result = queryAttendanceSnapshot(sample(), {
    where: { field: 'studentId', op: 'in', value: ['A', 'B'] },
    groupBy: ['studentId'], minimumGroupSize: 1,
  });
  assert.equal(result.groups.length, 2);
  assert.equal(result.groups[0].studentCount, 1);
  assert.equal(result.groups[0].cellCount, 3);
  assert.equal(result.groups[0].missing, 1);
  assert.equal(result.groups[0].attendanceRate, 1 / 2);
  assert.equal(result.groups[1].coverage, 2 / 3);
});

test('compares changed, added and removed cells by stable student/session identity', () => {
  const before = sample();
  const after = createAttendanceSnapshot([
    { id: 'A', name: 'Alice Example', email: 'alice@example.test' },
    { id: 'C', name: '=Casey Example', email: 'casey@example.test' },
    { id: 'D', name: 'Dana Example', email: 'dana@example.test' },
  ], ['S1', 'S2', 'S3'], [
    { studentId: 'A', sessionId: 'S1', status: 'absent' },
    { studentId: 'A', sessionId: 'S2', status: 'absent' },
    { studentId: 'C', sessionId: 'S1', status: 'absent' },
    { studentId: 'C', sessionId: 'S3', status: 'absent' },
    { studentId: 'D', sessionId: 'S1', status: 'present' },
  ]);
  const diff = compareAttendanceQueryResults(before, after);
  assert.deepEqual(diff.summary, { beforeMatched: 9, afterMatched: 9, added: 3, removed: 3, changed: 1, unchanged: 5 });
  assert.deepEqual(diff.changed[0].fields, ['status']);
  assert.equal(diff.changed[0].before.status, 'present');
  assert.equal(diff.changed[0].after.status, 'absent');
  assert.equal(diff.added[0].after.studentId, 'D');
  assert.equal(diff.removed[0].before.studentId, 'B');
  assert.match(attendanceQueryDiffToCsv(diff, 'changed'), /"fields","studentId","sessionId","beforeStatus"/);
  assert.match(attendanceQueryDiffToCsv(diff, 'added'), /"studentId","sessionId","status"/);
});

test('reports roster identity edits as changed fields', () => {
  const before = sample();
  const after = createAttendanceSnapshot([
    { id: 'A', name: 'Alice Revised', email: 'alice@example.test' },
    { id: 'B', name: 'Bob Example', email: 'bob@example.test' },
    { id: 'C', name: '=Casey Example', email: 'casey@example.test' },
  ], before.sessionIds, before.records);
  const diff = compareAttendanceQueryResults(before, after);
  assert.ok(diff.changed.some((item) => item.before.studentId === 'A' && item.fields.includes('studentName')));
});

test('exports only opted-in columns and protects spreadsheet formula prefixes', () => {
  const result = queryAttendanceSnapshot(sample(), { columns: ['studentId', 'studentName', 'studentEmail', 'sessionId', 'status'] });
  const csv = attendanceQueryToCsv(result);
  assert.match(csv, /"studentId","studentName","studentEmail","sessionId","status"/);
  assert.match(csv, /"C","'=Casey Example","casey@example\.test"/);
  const privateSafe = queryAttendanceSnapshot(sample());
  assert.equal(attendanceQueryToCsv(privateSafe).includes('Alice Example'), false);
  assert.throws(() => attendanceQueryToCsv({ format: 'wrong', version: 1 }), /invalid/);
  assert.throws(() => attendanceQueryToCsv(result, 'groups'), /unavailable/);
  assert.throws(() => attendanceQueryDiffToCsv({ format: 'wrong', version: 1 }), /invalid/);
  assert.throws(() => attendanceQueryDiffToCsv(compareAttendanceQueryResults(sample(), sample()), 'raw'), /section must be/);
});

test('validates fields, operators, value types, options, and the query AST before scanning', () => {
  assert.throws(() => queryAttendanceSnapshot(null), /snapshot must be an object/);
  assert.throws(() => queryAttendanceSnapshot(sample(), null), /query must be an object/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { unboundedSql: 'select *' }), /unsupported field/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { columns: [] }), /columns must contain/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { columns: ['status', 'status'] }), /unique supported fields/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { sort: [{ field: 'password' }] }), /unsupported/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { sort: [{ field: 'status', direction: 'sideways' }] }), /must be asc or desc/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { sort: [{ field: 'status' }, { field: 'status' }] }), /must be unique/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { includeUnrecorded: 'yes' }), /must be a boolean/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { page: 0 }), /from 1 to/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { pageSize: 501 }), /from 1 to 500/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { maxMatches: 2 }), /matched 9 rows/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: { field: 'password', op: 'eq', value: 'x' } }), /unsupported query field/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: { field: 'status', op: 'contains', value: 'present' } }), /only supported on text fields/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: { field: 'status', op: 'eq', value: 'late' } }), /present, absent or missing/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: { field: 'studentId', op: 'in', value: [] } }), /1 to 100 entries/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: { field: 'studentId', op: 'isMissing', value: true } }), /does not accept a value/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: { field: 'studentId', op: 'execute', value: 'x' } }), /unsupported query operator/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: { all: [] } }), /1 to 50 expressions/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { groupBy: ['status', 'status'] }), /unique supported fields/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { groupBy: ['status'], page: 2 }), /do not support page offsets/);
});

test('caps expression depth and rejects unsafe executable or malformed expressions', () => {
  let deep = { field: 'studentId', op: 'eq', value: 'A' };
  for (let index = 0; index < 9; index++) deep = { not: deep };
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: deep }), /nesting must not exceed/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: { field: 'studentId', op: 'eq', value: 'A', script: 'globalThis.pwned=true' } }), /unsupported field/);
  assert.throws(() => queryAttendanceSnapshot(sample(), { where: [{ field: 'studentId', op: 'eq', value: 'A' }] }), /where expression must be an object/);
});

test('rejects query comparisons when a snapshot exceeds the bounded result allowance', () => {
  assert.throws(() => compareAttendanceQueryResults(sample(), sample(), { maxMatches: 2 }), /matched 9 rows/);
});
