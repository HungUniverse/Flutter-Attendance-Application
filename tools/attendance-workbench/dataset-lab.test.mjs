import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import {
  generateSyntheticDataset,
  listSyntheticProfiles,
  parseSyntheticDataset,
  serializeSyntheticDataset,
  summarizeDatasetSnapshot,
  syntheticDatasetLimits,
} from './dataset-lab.mjs';

test('generates deterministic, schema-valid snapshots from the same string or numeric seed', () => {
  const first = generateSyntheticDataset({ students: 12, sessions: 9, seed: 'course-check-7' });
  const again = generateSyntheticDataset({ students: 12, sessions: 9, seed: 'course-check-7' });
  const numeric = generateSyntheticDataset({ students: 12, sessions: 9, seed: 42 });
  const numericText = generateSyntheticDataset({ students: 12, sessions: 9, seed: '42' });

  assert.deepEqual(first, again);
  assert.deepEqual(numeric, numericText);
  assert.notEqual(first.manifest.fingerprint, numeric.manifest.fingerprint);
  assert.equal(first.snapshot.roster.length, 12);
  assert.equal(first.snapshot.sessionIds.length, 9);
  assert.ok(first.snapshot.roster.every((student) => student.email.endsWith('@example.invalid')));
  assert.doesNotThrow(() => createAttendanceSnapshot(first.snapshot.roster, first.snapshot.sessionIds, first.snapshot.records));
});

test('creates a stable profile mix and reports counts by profile, group and session', () => {
  const { manifest } = generateSyntheticDataset({
    students: 8, sessions: 5, seed: 2,
    profileMix: { steady: 1, improving: 1 }, groupCount: 3,
  });
  assert.equal(manifest.profileCounts.steady + manifest.profileCounts.improving, 8);
  assert.equal(manifest.profileCounts.declining, 0);
  assert.equal(manifest.byProfile.steady.students, manifest.profileCounts.steady);
  assert.equal(manifest.bySession.length, 5);
  assert.deepEqual([...new Set(manifest.students.map((student) => student.group))], ['NHOM-01', 'NHOM-02', 'NHOM-03']);
  assert.ok(manifest.students.every((student) => ['steady', 'improving'].includes(student.profile)));
});

test('trend profiles improve or decline across a sufficiently large reproducible cohort', () => {
  const improving = generateSyntheticDataset({ students: 160, sessions: 20, seed: 'trend-a', missingRate: 0,
    streakiness: 0, profileMix: { improving: 1 } }).snapshot;
  const declining = generateSyntheticDataset({ students: 160, sessions: 20, seed: 'trend-b', missingRate: 0,
    streakiness: 0, profileMix: { declining: 1 } }).snapshot;
  const firstRate = (snapshot) => snapshot.records.filter((record) => record.sessionId.endsWith('01') && record.status === 'present').length / snapshot.roster.length;
  const lastRate = (snapshot) => snapshot.records.filter((record) => record.sessionId.endsWith('20') && record.status === 'present').length / snapshot.roster.length;
  assert.ok(lastRate(improving) > firstRate(improving) + 0.25);
  assert.ok(firstRate(declining) > lastRate(declining) + 0.25);
});

test('allows fully-present and fully-absent profile fixtures without unexpected statuses', () => {
  const perfect = generateSyntheticDataset({ students: 4, sessions: 7, missingRate: 0, streakiness: 0, profileMix: { perfect: 1 } });
  const rare = generateSyntheticDataset({ students: 4, sessions: 7, missingRate: 0, streakiness: 0, profileMix: { rare: 1 } });
  assert.equal(perfect.snapshot.records.filter((record) => record.status === 'absent').length, 0);
  assert.ok(rare.snapshot.records.filter((record) => record.status === 'present').length < rare.snapshot.records.length * 0.25);
});

test('missingness patterns target early, recent and per-student blocks separately', () => {
  const early = generateSyntheticDataset({ students: 3, sessions: 10, seed: 8, missingRate: 0.3, missingPattern: 'early' }).snapshot;
  const recent = generateSyntheticDataset({ students: 3, sessions: 10, seed: 8, missingRate: 0.3, missingPattern: 'recent' }).snapshot;
  const blocks = generateSyntheticDataset({ students: 30, sessions: 12, seed: 8, missingRate: 0.25, missingPattern: 'blocks' }).snapshot;
  const missingBySession = (snapshot) => snapshot.sessionIds.map((sessionId) =>
    snapshot.roster.length - snapshot.records.filter((record) => record.sessionId === sessionId).length);
  assert.deepEqual(missingBySession(early).slice(0, 3), [3, 3, 3]);
  assert.deepEqual(missingBySession(recent).slice(-3), [3, 3, 3]);
  const missingSessionsByStudent = blocks.roster.map((student) => blocks.records.filter((record) => record.studentId === student.id).length);
  assert.ok(missingSessionsByStudent.some((count) => count <= 9));
});

test('creates targeted unrecorded students when the synthetic profile requests it', () => {
  const { snapshot, manifest } = generateSyntheticDataset({ students: 12, sessions: 10, seed: 22,
    missingRate: 0.1, profileMix: { unrecorded: 1 } });
  assert.equal(manifest.profileCounts.unrecorded, 12);
  assert.ok(snapshot.records.length < 12 * 10 * 0.75);
});

test('serializes and validates an envelope while detecting changed snapshot data', () => {
  const dataset = generateSyntheticDataset({ students: 7, sessions: 4, seed: 3 });
  const serialized = serializeSyntheticDataset(dataset);
  const loaded = parseSyntheticDataset(serialized);
  assert.deepEqual(loaded, dataset);
  const modified = JSON.parse(serialized);
  modified.snapshot.roster[0].name = 'Changed name';
  assert.throws(() => parseSyntheticDataset(modified), /fingerprint/);
  assert.throws(() => parseSyntheticDataset('{'), /valid JSON/);
  assert.throws(() => parseSyntheticDataset({ ...dataset, synthetic: false }), /unsupported/);
});

test('lists known synthetic profiles and derives neutral summaries for ordinary snapshots', () => {
  assert.equal(listSyntheticProfiles().length, 8);
  const snapshot = createAttendanceSnapshot([{ id: 'S1', name: 'A', email: 'a@example.test' }], ['D1', 'D2'], [
    { studentId: 'S1', sessionId: 'D1', status: 'present' },
  ]);
  assert.deepEqual(summarizeDatasetSnapshot(snapshot), {
    students: 1, sessions: 2, expected: 2, recorded: 1, missing: 1, coverage: 0.5,
    present: 1, absent: 0,
    studentRates: [{ studentId: 'S1', present: 1, absent: 0, missing: 1, rate: 1 }],
  });
});

test('rejects unsafe dimensions, profile values, and malformed options', () => {
  const limits = syntheticDatasetLimits();
  assert.throws(() => generateSyntheticDataset({ students: limits.students, sessions: 100 }), /cells/);
  assert.throws(() => generateSyntheticDataset({ students: 0 }), /students/);
  assert.throws(() => generateSyntheticDataset({ sessions: limits.sessions + 1 }), /sessions/);
  assert.throws(() => generateSyntheticDataset({ missingRate: 1 }), /missingRate/);
  assert.throws(() => generateSyntheticDataset({ missingPattern: 'weekday' }), /missingPattern/);
  assert.throws(() => generateSyntheticDataset({ profileMix: { invented: 1 } }), /unknown synthetic profile/);
  assert.throws(() => generateSyntheticDataset({ profileMix: { rare: 0 } }), /positive weight/);
  assert.throws(() => generateSyntheticDataset(null), /options/);
  assert.throws(() => parseSyntheticDataset({ version: 2, synthetic: true }), /unsupported/);
});

