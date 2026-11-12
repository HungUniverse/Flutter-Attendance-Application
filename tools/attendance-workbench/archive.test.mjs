import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { appendArchiveRevision, archiveToCsv, compareArchiveRevisions, createArchive,
  getArchiveSnapshot, listArchiveRevisions, parseArchive, restoreArchiveRevision, serializeArchive } from './archive.mjs';

const baseline = createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'a@example.test' }], ['1', '2'], [
  { studentId: 'A', sessionId: '1', status: 'present' },
]);
const updated = createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'a@example.test' }], ['1', '2'], [
  { studentId: 'A', sessionId: '1', status: 'present' },
  { studentId: 'A', sessionId: '2', status: 'absent' },
]);

test('creates an immutable root and appends validated snapshot revisions', () => {
  const archive = createArchive(baseline, { title: 'Term', author: 'Registrar', createdAt: '2026-01-01T00:00:00Z' });
  const next = appendArchiveRevision(archive, updated, { message: 'Imported second meeting', author: 'Registrar', createdAt: '2026-01-02T00:00:00Z' });
  assert.equal(archive.revisions.length, 1);
  assert.equal(next.headId, 'r2');
  assert.deepEqual(getArchiveSnapshot(next, 'r1'), baseline);
  assert.deepEqual(getArchiveSnapshot(next, 'r2'), updated);
  assert.deepEqual(parseArchive(serializeArchive(next)), next);
});

test('lists parent lineage, current heads and per-revision change counts', () => {
  const archive = appendArchiveRevision(createArchive(baseline), updated, { message: 'Add result' });
  const [root, revision] = listArchiveRevisions(archive);
  assert.equal(root.branch, true);
  assert.equal(root.isHead, false);
  assert.equal(revision.parentId, root.id);
  assert.equal(revision.isHead, true);
  assert.equal(revision.changes.recordsAdded, 1);
  assert.equal(revision.records, 2);
});

test('supports branches and restores as a new revision without rewriting history', () => {
  const archive = appendArchiveRevision(createArchive(baseline), updated, { message: 'Corrected result' });
  const branchSnapshot = createAttendanceSnapshot(baseline.roster, baseline.sessionIds, [
    { studentId: 'A', sessionId: '1', status: 'absent' },
  ]);
  const branch = appendArchiveRevision(archive, branchSnapshot, { parentId: 'r1', message: 'Alternative correction' });
  assert.equal(branch.headId, 'r3');
  assert.equal(listArchiveRevisions(branch)[0].branch, true);
  const restored = restoreArchiveRevision(branch, 'r2', { message: 'Restore approved state' });
  assert.equal(restored.headId, 'r4');
  assert.equal(restored.revisions.length, 4);
  assert.deepEqual(getArchiveSnapshot(restored, 'r4'), updated);
  assert.equal(restored.revisions.find((item) => item.id === 'r3').snapshot.records[0].status, 'absent');
});

test('compares any two saved revisions and reports missing revision IDs', () => {
  const archive = appendArchiveRevision(createArchive(baseline), updated, { message: 'Add result' });
  const comparison = compareArchiveRevisions(archive, 'r1', 'r2');
  assert.equal(comparison.changes.attendance.added.length, 1);
  assert.equal(comparison.before.id, 'r1');
  assert.throws(() => compareArchiveRevisions(archive, 'missing', 'r2'), /both archive revisions/);
});

test('rejects stale heads, missing parents, invalid graph edges, and duplicate IDs', () => {
  const archive = createArchive(baseline);
  assert.throws(() => appendArchiveRevision(archive, updated, { message: 'x', expectedHeadId: 'old' }), /head changed/);
  assert.throws(() => appendArchiveRevision(archive, updated, { message: 'x', parentId: 'missing' }), /unknown parent/);
  const duplicate = { ...archive, revisions: [...archive.revisions, archive.revisions[0]] };
  assert.throws(() => parseArchive(duplicate), /duplicate revision ID/);
  const cycle = { ...archive, revisions: [{ ...archive.revisions[0], parentId: 'r1' }] };
  assert.throws(() => parseArchive(cycle), /exactly one root/);
});

test('exports a compact formula-safe CSV index without attendance records', () => {
  const archive = createArchive(baseline, { title: 'Test', author: '=Sheet', message: 'Initial "source"' });
  const csv = archiveToCsv(archive);
  assert.match(csv, /"'=Sheet"/);
  assert.match(csv, /"Initial ""source"""/);
  assert.doesNotMatch(csv, /a@example\.test/);
  assert.throws(() => getArchiveSnapshot(archive, 'missing'), /unknown revision/);
});
