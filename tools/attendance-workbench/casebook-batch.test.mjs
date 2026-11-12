import test from 'node:test';
import assert from 'node:assert/strict';
import { createCasebook, parseCasebook, serializeCasebook, updateCasebook } from './casebook.mjs';
import { applyCasebookBatch } from './casebook-batch.mjs';

function makeBook() {
  const cases = ['a', 'b', 'c'].map((caseId, index) => ({ caseId, studentId: `s${index}`, studentName: `Student ${index}`,
    priority: 'review', attendanceRate: 0.5, present: 1, absent: 1, missing: 0, reasons: [], suggestedSteps: [] }));
  return createCasebook({ version: 1, snapshotFingerprint: 'fp', generatedFor: { students: 3, sessions: 2, records: 6 },
    summary: { total: 3 }, cases }, { id: 'batch-book', createdAt: '2026-11-01T00:00:00Z' });
}

test('applies multiple independent updates and appends each to the case history', () => {
  const source = makeBook();
  const before = serializeCasebook(source);
  const updated = applyCasebookBatch(source, { expectedBookRevision: 1, actor: 'reviewer', at: '2026-11-02T00:00:00Z',
    operations: [
      { caseId: 'a', expectedRevision: 1, action: { status: 'in_review', assigneeId: 'staff-a' } },
      { caseId: 'b', expectedRevision: 1, action: { status: 'data_needed' } },
    ] });

  assert.equal(updated.revision, 3);
  assert.equal(updated.cases.find((item) => item.caseId === 'a').status, 'in_review');
  assert.equal(updated.cases.find((item) => item.caseId === 'a').assigneeId, 'staff-a');
  assert.equal(updated.cases.find((item) => item.caseId === 'b').status, 'data_needed');
  assert.equal(updated.cases.find((item) => item.caseId === 'c').revision, 1);
  assert.equal(serializeCasebook(source), before);
});

test('checks the book and every case revision before applying anything', () => {
  const source = makeBook();
  const batch = { expectedBookRevision: 1, operations: [
    { caseId: 'a', expectedRevision: 1, action: { status: 'in_review' } },
    { caseId: 'b', expectedRevision: 3, action: { status: 'in_review' } },
  ] };
  const before = serializeCasebook(source);
  assert.throws(() => applyCasebookBatch(source, batch), /stale case revision for b/);
  assert.equal(serializeCasebook(source), before);
  assert.throws(() => applyCasebookBatch(source, { ...batch, expectedBookRevision: 2 }), /stale casebook revision/);
});

test('rejects a later invalid transition without returning a partial casebook', () => {
  const source = makeBook();
  const before = serializeCasebook(source);
  assert.throws(() => applyCasebookBatch(source, { expectedBookRevision: 1, operations: [
    { caseId: 'a', expectedRevision: 1, action: { status: 'in_review' } },
    { caseId: 'b', expectedRevision: 1, action: { status: 'reopened' } },
  ] }), /cannot move from new to reopened/);
  assert.equal(serializeCasebook(source), before);
});

test('rejects duplicate targets, missing cases, empty actions and malformed batches', () => {
  const source = makeBook();
  assert.throws(() => applyCasebookBatch(source, { expectedBookRevision: 1, operations: [
    { caseId: 'a', expectedRevision: 1, action: { status: 'in_review' } },
    { caseId: 'a', expectedRevision: 1, action: { assigneeId: 'staff' } },
  ] }), /more than once/);
  assert.throws(() => applyCasebookBatch(source, { expectedBookRevision: 1, operations: [
    { caseId: 'missing', expectedRevision: 1, action: { status: 'in_review' } },
  ] }), /unknown case ID/);
  assert.throws(() => applyCasebookBatch(source, { expectedBookRevision: 1, operations: [
    { caseId: 'a', expectedRevision: 1, action: {} },
  ] }), /does not change/);
  assert.throws(() => applyCasebookBatch(source, { expectedBookRevision: 1, operations: [] }), /1 to 2000/);
  assert.equal(parseCasebook(source).revision, 1);
});

test('preserves concurrent edits only when the submitted book revision is current', () => {
  const source = makeBook();
  const edited = updateCasebook(source, 'c', { note: 'Changed elsewhere' }, { expectedRevision: 1,
    actor: 'other', at: '2026-11-02T00:00:00Z' });
  assert.throws(() => applyCasebookBatch(edited, { expectedBookRevision: 1, operations: [
    { caseId: 'a', expectedRevision: 1, action: { status: 'in_review' } },
  ] }), /stale casebook revision/);
});
