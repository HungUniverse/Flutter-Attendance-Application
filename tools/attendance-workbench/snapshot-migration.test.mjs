import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { planSnapshotMigration, snapshotMigrationToCsv } from './snapshot-migration.mjs';

function sourceSnapshot() {
  return createAttendanceSnapshot([
    { id: 'A', name: 'An Nguyen', email: 'an@example.test' },
    { id: 'B', name: 'Binh Tran', email: 'binh@example.test' },
  ], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'absent' },
    { studentId: 'A', sessionId: 'S2', status: 'present' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'absent' },
  ]);
}

test('plans identity and session re-keying without changing the input snapshot', () => {
  const source = sourceSnapshot();
  const before = serializeAttendanceSnapshot(source);
  const plan = planSnapshotMigration(source, {
    studentMappings: [{ from: 'A', to: 'A001' }],
    sessionMappings: [{ from: 'S1', to: '2026-T1' }], includeSnapshot: true,
  });
  assert.equal(plan.format, 'attendance-snapshot-migration');
  assert.equal(plan.summary.ready, true);
  assert.equal(plan.summary.studentMappings, 1);
  assert.equal(plan.summary.sessionMappings, 1);
  assert.equal(plan.snapshot.roster.find((student) => student.id === 'A001').name, 'An Nguyen');
  assert.equal(plan.snapshot.records.find((record) => record.studentId === 'A001' && record.sessionId === '2026-T1').status, 'absent');
  assert.equal(serializeAttendanceSnapshot(source), before);
});

test('accepts explicit target dimensions and reports additions without fabricating records', () => {
  const source = sourceSnapshot();
  const plan = planSnapshotMigration(source, {
    targetRoster: [...source.roster, { id: 'C', name: 'Chi Le', email: 'chi@example.test' }],
    targetSessionIds: ['S1', 'S2', 'S3'], includeSnapshot: true,
  });
  assert.equal(plan.summary.ready, true);
  assert.equal(plan.summary.studentsAdded, 1);
  assert.equal(plan.summary.sessionsAdded, 1);
  assert.equal(plan.snapshot.roster.length, 3);
  assert.equal(plan.snapshot.sessionIds.length, 3);
  assert.equal(plan.snapshot.records.length, 4);
  assert.equal(plan.snapshot.records.some((record) => record.studentId === 'C'), false);
});

test('blocks removals until each student and session drop is explicitly enabled', () => {
  const source = sourceSnapshot();
  const options = { targetRoster: [source.roster[0]], targetSessionIds: ['S1'], includeSnapshot: true };
  const blocked = planSnapshotMigration(source, options);
  assert.equal(blocked.summary.ready, false);
  assert.equal(Object.hasOwn(blocked, 'snapshot'), false);
  assert.ok(blocked.issues.some((issue) => issue.code === 'students_removed_without_opt_in'));
  assert.ok(blocked.issues.some((issue) => issue.code === 'sessions_removed_without_opt_in'));
  const approved = planSnapshotMigration(source, { ...options, dropUnmappedStudents: true, dropUnmappedSessions: true });
  assert.equal(approved.summary.ready, true);
  assert.equal(approved.summary.studentsRemoved, 1);
  assert.equal(approved.summary.sessionsRemoved, 1);
  assert.equal(approved.summary.omittedRecords, 3);
  assert.equal(approved.snapshot.records.length, 1);
});

test('blocks many-to-one identity merges without an authoritative target identity', () => {
  const source = sourceSnapshot();
  const blocked = planSnapshotMigration(source, { studentMappings: [{ from: 'B', to: 'A' }] });
  assert.equal(blocked.summary.ready, false);
  assert.ok(blocked.issues.some((issue) => issue.code === 'merged_identity_conflict'));
  const targetRoster = [{ id: 'A', name: 'An and Binh', email: 'merged@example.test' }];
  const authorized = planSnapshotMigration(source, { studentMappings: [{ from: 'B', to: 'A' }], targetRoster,
    recordConflictPolicy: 'prefer-present', includeSnapshot: true });
  assert.equal(authorized.summary.ready, true);
  assert.ok(authorized.warnings.some((warning) => warning.code === 'target_identity_authority'));
  assert.equal(authorized.snapshot.roster.length, 1);
  assert.equal(authorized.snapshot.records.find((record) => record.sessionId === 'S1').status, 'present');
  assert.equal(authorized.snapshot.records.find((record) => record.sessionId === 'S2').status, 'present');
});

test('surfaces mapped record conflicts and resolves each by stable ID or explicit policy', () => {
  const source = sourceSnapshot();
  const targetRoster = [{ id: 'MERGED', name: 'Merged student', email: 'merged@example.test' }];
  const base = { studentMappings: [{ from: 'A', to: 'MERGED' }, { from: 'B', to: 'MERGED' }], targetRoster };
  const unresolved = planSnapshotMigration(source, base);
  assert.equal(unresolved.summary.unresolvedConflicts, 2);
  assert.equal(unresolved.summary.ready, false);
  assert.equal(unresolved.conflicts[0].candidateStatuses.length, 2);
  const chosen = planSnapshotMigration(source, { ...base, includeSnapshot: true, conflictResolutions: [
    { conflictId: unresolved.conflicts[0].conflictId, status: 'present' },
    { conflictId: unresolved.conflicts[1].conflictId, status: 'absent' },
  ] });
  assert.equal(chosen.summary.ready, true);
  assert.equal(chosen.snapshot.records.length, 2);
  assert.equal(chosen.snapshot.records[0].status, 'present');
  assert.equal(chosen.snapshot.records[1].status, 'absent');
  const policy = planSnapshotMigration(source, { ...base, recordConflictPolicy: 'prefer-absent' });
  assert.equal(policy.summary.unresolvedConflicts, 0);
  assert.equal(policy.conflicts.every((conflict) => conflict.selectedStatus === 'absent'), true);
});

test('counts agreeing duplicates when distinct source cells map to one target cell', () => {
  const source = createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'an@example.test' }], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'A', sessionId: 'S2', status: 'present' },
  ]);
  const plan = planSnapshotMigration(source, { sessionMappings: [{ from: 'S2', to: 'S1' }], includeSnapshot: true });
  assert.equal(plan.summary.ready, true);
  assert.equal(plan.summary.agreeingDuplicates, 1);
  assert.equal(plan.snapshot.records.length, 1);
  assert.equal(plan.snapshot.records[0].status, 'present');
});

test('rejects stale conflict decisions instead of retaining them silently', () => {
  const source = sourceSnapshot();
  const plan = planSnapshotMigration(source, { recordConflictPolicy: 'prefer-present' });
  const stale = planSnapshotMigration(source, { conflictResolutions: [{ conflictId: 'migration-STALE', status: 'present' }] });
  assert.ok(stale.issues.some((issue) => issue.code === 'stale_conflict_resolution'));
  assert.throws(() => planSnapshotMigration(source, { conflictResolutions: [
    { conflictId: 'same', status: 'present' }, { conflictId: 'same', status: 'absent' },
  ] }), /duplicate conflict resolution/);
  assert.throws(() => planSnapshotMigration(source, { conflictResolutions: [{ conflictId: 'x', status: 'missing' }] }), /must be present or absent/);
});

test('exports safe issue and conflict tables and only exposes records when requested', () => {
  const source = sourceSnapshot();
  const plan = planSnapshotMigration(source, { targetRoster: [], targetSessionIds: [], dropUnmappedStudents: true, dropUnmappedSessions: true });
  assert.match(snapshotMigrationToCsv(plan, 'issues'), /"code","blocking","message"/);
  assert.match(snapshotMigrationToCsv(plan, 'conflicts'), /"conflictId","studentId","sessionId"/);
  assert.throws(() => snapshotMigrationToCsv(plan, 'records'), /snapshot was not included/);
  const ready = planSnapshotMigration(source, { includeSnapshot: true });
  assert.match(snapshotMigrationToCsv(ready, 'records'), /"studentId","sessionId","status"/);
  assert.throws(() => snapshotMigrationToCsv({ format: 'wrong', version: 1 }), /invalid/);
  assert.throws(() => snapshotMigrationToCsv(ready, 'raw'), /section must be/);
});

test('validates mappings, target rosters, target sessions and explicit option types', () => {
  const source = sourceSnapshot();
  assert.throws(() => planSnapshotMigration(null), /snapshot must be an object/);
  assert.throws(() => planSnapshotMigration(source, null), /migration options must be an object/);
  assert.throws(() => planSnapshotMigration(source, { studentMappings: [{ from: 'UNKNOWN', to: 'A' }] }), /unknown source ID/);
  assert.throws(() => planSnapshotMigration(source, { studentMappings: [{ from: 'A', to: 'A1' }, { from: 'A', to: 'A2' }] }), /duplicate source mapping/);
  const missingTarget = planSnapshotMigration(source, { sessionMappings: [{ from: 'S1', to: 'T1' }], targetSessionIds: ['S2'] });
  assert.ok(missingTarget.issues.some((issue) => issue.code === 'session_mapping_target_missing'));
  assert.throws(() => planSnapshotMigration(source, { targetSessionIds: ['S1', 'S1'] }), /duplicate sessions/);
  assert.throws(() => planSnapshotMigration(source, { targetRoster: [
    { id: 'A', name: 'One', email: 'one@example.test' }, { id: 'A', name: 'Two', email: 'two@example.test' },
  ] }), /duplicate student id/);
  assert.throws(() => planSnapshotMigration(source, { dropUnmappedStudents: 'yes' }), /must be booleans/);
  assert.throws(() => planSnapshotMigration(source, { recordConflictPolicy: 'guess' }), /must be strict/);
});
