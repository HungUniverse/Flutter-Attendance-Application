import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { createBundle, putClass, serializeBundle } from './bundle.mjs';
import { appendArchiveRevision, createArchive, serializeArchive } from './archive.mjs';
import { anonymizeArchive, anonymizeBundle, anonymizeSnapshot, anonymizationReport } from './privacy.mjs';

const secret = 'local-demo-key-with-enough-entropy';

function snapshot(suffix = '') {
  return createAttendanceSnapshot([
    { id: `student-a${suffix}`, name: 'Maya Example', email: `maya${suffix}@private.test` },
    { id: `student-b${suffix}`, name: 'Noah Example', email: `noah${suffix}@private.test` },
  ], ['Tuesday 08:00 - Room 4', 'Thursday 10:30 - Room 8'], [
    { studentId: `student-a${suffix}`, sessionId: 'Tuesday 08:00 - Room 4', status: 'present' },
    { studentId: `student-b${suffix}`, sessionId: 'Thursday 10:30 - Room 8', status: 'absent' },
  ]);
}

test('replaces student and session identifiers while preserving attendance and order', () => {
  const source = snapshot();
  const output = anonymizeSnapshot(source, { secret });
  assert.equal(output.roster.length, source.roster.length);
  assert.equal(output.sessionIds.length, source.sessionIds.length);
  assert.deepEqual(output.records.map((record) => record.status), source.records.map((record) => record.status));
  assert.notDeepEqual(output.sessionIds, source.sessionIds);
  assert.ok(output.roster.every((student) => student.name.startsWith('Participant ')));
  assert.ok(output.roster.every((student) => student.email.endsWith('@example.invalid')));
  assert.doesNotMatch(JSON.stringify(output), /Maya Example|maya@private\.test|Tuesday 08:00|student-a/);
});

test('produces the same pseudonyms for a fixed secret and different aliases for a different secret', () => {
  const source = snapshot();
  const first = anonymizeSnapshot(source, { secret });
  const again = anonymizeSnapshot(source, { secret });
  const otherKey = anonymizeSnapshot(source, { secret: 'another-distinct-key-material' });
  assert.deepEqual(first, again);
  assert.notEqual(first.roster[0].id, otherKey.roster[0].id);
  assert.notEqual(first.sessionIds[0], otherKey.sessionIds[0]);
});

test('reuses pseudonyms across multiple classes without leaking bundle names', () => {
  const first = snapshot();
  const second = createAttendanceSnapshot([
    { id: 'student-b', name: 'Noah Example', email: 'noah@private.test' },
    { id: 'student-c', name: 'Iris Example', email: 'iris@private.test' },
  ], ['Tuesday 08:00 - Room 4'], [
    { studentId: 'student-b', sessionId: 'Tuesday 08:00 - Room 4', status: 'absent' },
  ]);
  const sourceBundle = putClass(putClass(createBundle(), 'course-a', 'Protected Systems', first),
    'course-b', 'Private Seminar', second);
  const output = anonymizeBundle(sourceBundle, { secret });
  const firstOutput = output.classes[0].snapshot;
  const secondOutput = output.classes[1].snapshot;
  assert.equal(firstOutput.roster[1].id, secondOutput.roster[0].id);
  assert.equal(firstOutput.roster[1].name, secondOutput.roster[0].name);
  assert.equal(firstOutput.roster[1].email, secondOutput.roster[0].email);
  assert.ok(output.classes.every((entry) => /^CLASS-[A-F0-9]+$/.test(entry.id) && entry.name.startsWith('Class ')));
  assert.doesNotMatch(serializeBundle(output), /Protected Systems|Private Seminar|"student-b"|private\.test/);
});

test('can preserve session labels only when explicitly configured', () => {
  const source = snapshot();
  const output = anonymizeSnapshot(source, { secret, keepSessionIds: true });
  assert.deepEqual(output.sessionIds, source.sessionIds);
  assert.notDeepEqual(output.roster.map((student) => student.id), source.roster.map((student) => student.id));
});

test('anonymizes archive lineage, labels, authors and real dates', () => {
  const original = createArchive(snapshot(), { id: 'teacher-case-77', title: 'Maya attendance appeal',
    author: 'Maya Instructor', message: 'Imported from Maya email', createdAt: '2026-09-01T10:00:00Z' });
  const updated = anonymizeSnapshot(snapshot(), { secret });
  const history = appendArchiveRevision(original, updated, { id: 'teacher-final-review', author: 'Noah Teacher',
    message: 'Noah confirmed Thursday', createdAt: '2026-10-30T11:00:00Z' });
  const result = anonymizeArchive(history, { secret });
  const text = serializeArchive(result);
  assert.equal(result.revisions.length, 2);
  assert.equal(result.revisions[1].parentId, 'r1');
  assert.equal(result.headId, 'r2');
  assert.equal(result.revisions[0].message, 'Revision 1');
  assert.equal(result.revisions[1].author, 'Anonymous');
  assert.ok(result.revisions[0].createdAt.startsWith('2000-01-01'));
  assert.doesNotMatch(text, /Maya attendance appeal|Maya Instructor|Noah Teacher|teacher-final-review|Thursday 10:30|2026-10-30/);
});

test('reports retained identity fields and confirms a valid anonymized snapshot', () => {
  const source = snapshot();
  const output = anonymizeSnapshot(source, { secret });
  const report = anonymizationReport(source, output);
  assert.equal(report.valid, true);
  assert.deepEqual(report.issues, []);
  assert.equal(report.secretIncluded, false);
  assert.ok(report.replacedFields.includes('session IDs'));
  assert.equal(anonymizationReport(source, source).valid, false);
});

test('rejects missing, weak and malformed anonymization options or input data', () => {
  assert.throws(() => anonymizeSnapshot(snapshot()), /options/);
  assert.throws(() => anonymizeSnapshot(snapshot(), { secret: 'short' }), /16 and 4096/);
  assert.throws(() => anonymizeSnapshot(snapshot(), { secret, keepSessionIds: 'yes' }), /boolean/);
  assert.throws(() => anonymizeSnapshot(snapshot(), { secret, studentPrefix: '' }), /studentPrefix/);
  assert.throws(() => anonymizeSnapshot({}, { secret }), /snapshot/);
  assert.throws(() => anonymizeBundle({ classes: [] }, { secret }), /bundle/);
});

