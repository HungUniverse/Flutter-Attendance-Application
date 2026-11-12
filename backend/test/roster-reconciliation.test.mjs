import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeEmail, normalizeRoster, compareRosters, findSharedStudents,
  matchEmails, searchRoster, chunkRoster } from '../roster-reconciliation.mjs';

const roster = [
  { id: 'SV1', name: 'An Nguyen', email: ' An@example.com ' },
  { id: 'SV2', name: 'Binh Tran', email: 'binh@example.com' },
];

test('normalizes emails and refuses malformed values', () => {
  assert.equal(normalizeEmail(' A@Example.com '), 'a@example.com');
  for (const value of ['', 'a', 'a@@example.com', 'a@x']) assert.throws(() => normalizeEmail(value));
});

test('validates both student ID and case-insensitive email uniqueness', () => {
  assert.equal(normalizeRoster(roster)[0].email, 'an@example.com');
  assert.equal(roster[0].email, ' An@example.com ');
  assert.throws(() => normalizeRoster([roster[0], { ...roster[1], id: ' SV1 ' }]), /duplicate student id/);
  assert.throws(() => normalizeRoster([roster[0], { ...roster[1], email: 'AN@example.com' }]), /duplicate email/);
});

test('compares roster membership and changed fields by ID', () => {
  const next = [{ ...roster[0], name: 'An Le', email: 'an@example.com' },
    { id: 'SV3', name: 'Chi', email: 'chi@example.com' }];
  const result = compareRosters(roster, next);
  assert.deepEqual(result.added.map((s) => s.id), ['SV3']);
  assert.deepEqual(result.removed.map((s) => s.id), ['SV2']);
  assert.deepEqual(result.changed[0].fields, ['name']);
});

test('finds shared students even if names differ', () => {
  assert.deepEqual(findSharedStudents(roster, [{ ...roster[0], name: 'An Le' }]).map((s) => s.id), ['SV1']);
});

test('matches email, searches roster, and chunks in original order', () => {
  assert.deepEqual(matchEmails(roster, ['AN@example.com', 'missing@example.com']).map((r) => r.student?.id ?? null), ['SV1', null]);
  assert.deepEqual(searchRoster(roster, 'BINH').map((s) => s.id), ['SV2']);
  assert.deepEqual(chunkRoster(roster, 1).map((c) => c[0].id), ['SV1', 'SV2']);
  assert.deepEqual(chunkRoster([], 2), []);
  assert.throws(() => chunkRoster(roster, 0), RangeError);
});
