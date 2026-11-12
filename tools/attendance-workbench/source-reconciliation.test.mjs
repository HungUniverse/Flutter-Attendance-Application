import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { reconcileAttendanceSources, reconciliationToCsv, summarizeReconciliation } from './source-reconciliation.mjs';

function snapshot(rows, sessions = ['S1', 'S2']) {
  const roster = rows.map(({ id, name, email }) => ({ id, name, email }));
  const records = rows.flatMap(({ id, statuses }) => statuses.flatMap((status, index) => status === 'missing' ? [] : [
    { studentId: id, sessionId: sessions[index], status },
  ]));
  return createAttendanceSnapshot(roster, sessions, records);
}

function source(id, rows, options = {}) {
  return { id, label: options.label ?? id, priority: options.priority ?? 0,
    snapshot: snapshot(rows, options.sessions ?? ['S1', 'S2']) };
}

const baseSources = () => [
  source('morning', [
    { id: 'A', name: 'An Nguyen', email: 'an@example.test', statuses: ['present', 'absent'] },
    { id: 'B', name: 'Binh Tran', email: 'binh@example.test', statuses: ['present', 'present'] },
  ], { priority: 10 }),
  source('evening', [
    { id: 'A', name: 'An Nguyen', email: 'an@example.test', statuses: ['present', 'absent'] },
    { id: 'B', name: 'Binh Tran', email: 'binh@example.test', statuses: ['present', 'absent'] },
  ], { priority: 5 }),
];

test('merges matching sources as an explicit copy and reports agreeing duplicates', () => {
  const inputs = [
    source('morning', [
      { id: 'A', name: 'An Nguyen', email: 'an@example.test', statuses: ['present', 'absent'] },
      { id: 'B', name: 'Binh Tran', email: 'binh@example.test', statuses: ['present', 'present'] },
    ], { priority: 10 }),
    source('evening', [
      { id: 'A', name: 'An Nguyen', email: 'an@example.test', statuses: ['present', 'absent'] },
      { id: 'B', name: 'Binh Tran', email: 'binh@example.test', statuses: ['present', 'present'] },
    ], { priority: 5 }),
  ];
  const before = inputs.map((entry) => serializeAttendanceSnapshot(entry.snapshot));
  const plan = reconcileAttendanceSources(inputs, { includeSnapshot: true, includeProvenance: true });
  assert.equal(plan.format, 'attendance-source-reconciliation');
  assert.equal(plan.summary.ready, true, JSON.stringify(plan.issues));
  assert.equal(plan.summary.sources, 2);
  assert.equal(plan.summary.targetStudents, 2);
  assert.equal(plan.summary.targetSessions, 2);
  assert.equal(plan.summary.selectedRecords, 4);
  assert.equal(plan.summary.agreeingDuplicateCells, 4);
  assert.equal(plan.snapshot.records.find((record) => record.studentId === 'B' && record.sessionId === 'S2').status, 'present');
  assert.equal(plan.provenance.find((item) => item.studentId === 'A' && item.sessionId === 'S1').duplicateCount, 2);
  assert.deepEqual(inputs.map((entry) => serializeAttendanceSnapshot(entry.snapshot)), before);
  assert.equal(plan.sources[0].label, 'morning');
});

test('does not return a merged snapshot while conflicting attendance cells lack a decision', () => {
  const sources = baseSources();
  const plan = reconcileAttendanceSources(sources);
  assert.equal(plan.summary.ready, false);
  assert.equal(Object.hasOwn(plan, 'snapshot'), false);
  assert.equal(plan.summary.unresolvedConflicts, 1);
  assert.equal(plan.conflicts[0].kind, 'record');
  assert.deepEqual(plan.conflicts[0].candidates.map((item) => item.value), ['present', 'absent']);
  assert.ok(plan.issues.some((issue) => issue.code === 'record_conflict_unresolved'));
});

test('resolves a record conflict by conflict ID and reuses stable conflict identifiers', () => {
  const sources = baseSources();
  const first = reconcileAttendanceSources(sources);
  const conflict = first.conflicts[0];
  const resolved = reconcileAttendanceSources([...sources].reverse(), {
    resolutions: [{ conflictId: conflict.conflictId, sourceId: 'evening' }], includeSnapshot: true,
  });
  assert.equal(resolved.summary.ready, true);
  assert.equal(resolved.conflicts[0].conflictId, conflict.conflictId);
  assert.equal(resolved.conflicts[0].selectedSourceId, 'evening');
  assert.equal(resolved.snapshot.records.find((record) => record.studentId === 'B' && record.sessionId === 'S2').status, 'absent');
});

test('applies caller-selected source priorities and never edits any source snapshot', () => {
  const sources = baseSources();
  const input = sources.map(({ snapshot: data }) => serializeAttendanceSnapshot(data));
  const plan = reconcileAttendanceSources(sources, { recordConflictPolicy: 'prefer-priority', includeSnapshot: true });
  assert.equal(plan.summary.ready, true);
  assert.equal(plan.conflicts[0].status, 'resolved');
  assert.equal(plan.conflicts[0].selectedSourceId, 'morning');
  assert.equal(plan.snapshot.records.find((record) => record.studentId === 'B' && record.sessionId === 'S2').status, 'present');
  assert.deepEqual(sources.map(({ snapshot: data }) => serializeAttendanceSnapshot(data)), input);
});

test('supports explicit present and absent preference rules for record conflicts', () => {
  const sources = baseSources();
  const present = reconcileAttendanceSources(sources, { recordConflictPolicy: 'prefer-present', includeSnapshot: true });
  const absent = reconcileAttendanceSources(sources, { recordConflictPolicy: 'prefer-absent', includeSnapshot: true });
  const cell = (plan) => plan.snapshot.records.find((record) => record.studentId === 'B' && record.sessionId === 'S2').status;
  assert.equal(cell(present), 'present');
  assert.equal(cell(absent), 'absent');
  assert.equal(present.conflicts[0].status, 'resolved');
  assert.equal(absent.conflicts[0].status, 'resolved');
});

test('detects identity field disagreements and keeps unresolved identity out of the merged copy', () => {
  const sources = [
    source('one', [{ id: 'A', name: 'An Nguyen', email: 'an@example.test', statuses: ['present', 'missing'] }]),
    source('two', [{ id: 'A', name: 'An N.', email: 'an@example.test', statuses: ['present', 'missing'] }]),
  ];
  const plan = reconcileAttendanceSources(sources);
  assert.equal(plan.summary.ready, false);
  assert.equal(plan.summary.unresolvedConflicts, 1);
  assert.equal(plan.conflicts[0].kind, 'identity');
  assert.equal(plan.conflicts[0].field, 'name');
  assert.equal(Object.hasOwn(plan, 'snapshot'), false);
});

test('resolves identity conflicts by a source or exact candidate value', () => {
  const sources = [
    source('alpha', [{ id: 'A', name: 'Alice', email: 'alice@example.test', statuses: ['present', 'missing'] }]),
    source('beta', [{ id: 'A', name: 'Alice B', email: 'alice@example.test', statuses: ['present', 'missing'] }]),
  ];
  const initial = reconcileAttendanceSources(sources);
  const conflict = initial.conflicts[0];
  const bySource = reconcileAttendanceSources(sources, { resolutions: [{ conflictId: conflict.conflictId, sourceId: 'beta' }], includeSnapshot: true });
  assert.equal(bySource.summary.ready, true);
  assert.equal(bySource.snapshot.roster[0].name, 'Alice B');
  const byValue = reconcileAttendanceSources(sources, { resolutions: [{ conflictId: conflict.conflictId, value: 'Alice' }], includeSnapshot: true });
  assert.equal(byValue.snapshot.roster[0].name, 'Alice');
});

test('chooses identity values from the highest-priority source when explicitly configured', () => {
  const sources = [
    source('old', [{ id: 'A', name: 'Old Name', email: 'a@example.test', statuses: ['present', 'missing'] }], { priority: 1 }),
    source('current', [{ id: 'A', name: 'Current Name', email: 'a@example.test', statuses: ['present', 'missing'] }], { priority: 9 }),
  ];
  const plan = reconcileAttendanceSources(sources, { identityConflictPolicy: 'prefer-priority', includeSnapshot: true });
  assert.equal(plan.summary.ready, true);
  assert.equal(plan.snapshot.roster[0].name, 'Current Name');
  assert.equal(plan.conflicts[0].selectedSourceId, 'current');
});

test('uses an explicit target roster as identity authority and reports mismatching source fields', () => {
  const sources = [source('import', [{ id: 'local-a', name: 'Imported Name', email: 'old@example.test', statuses: ['present', 'missing'] }])];
  const plan = reconcileAttendanceSources(sources, {
    studentMappings: [{ sourceId: 'import', sourceStudentId: 'local-a', targetStudentId: 'A-001' }],
    targetRoster: [{ id: 'A-001', name: 'Official Name', email: 'official@example.test' }],
    includeSnapshot: true,
  });
  assert.equal(plan.summary.ready, true);
  assert.deepEqual(plan.snapshot.roster, [{ id: 'A-001', name: 'Official Name', email: 'official@example.test' }]);
  assert.equal(plan.conflicts.length, 2);
  assert.ok(plan.conflicts.every((conflict) => conflict.status === 'resolved' && conflict.selectedSourceId === 'target-roster'));
});

test('reports source students and sessions that are outside an explicit target', () => {
  const sources = [source('import', [{ id: 'A', name: 'An', email: 'a@example.test', statuses: ['present', 'absent'] }])];
  const plan = reconcileAttendanceSources(sources, {
    targetRoster: [{ id: 'B', name: 'Bao', email: 'b@example.test' }],
    targetSessionIds: ['S1'],
  });
  assert.equal(plan.summary.ready, false);
  assert.ok(plan.issues.some((issue) => issue.code === 'student_outside_target'));
  assert.ok(plan.issues.some((issue) => issue.code === 'session_outside_target'));
  assert.equal(Object.hasOwn(plan, 'snapshot'), false);
});

test('maps source student and session identifiers while preserving target order', () => {
  const sources = [source('import', [
    { id: 'local-2', name: 'Bao', email: 'b@example.test', statuses: ['absent', 'present'] },
    { id: 'local-1', name: 'An', email: 'a@example.test', statuses: ['present', 'absent'] },
  ], { sessions: ['week-one', 'week-two'] })];
  const plan = reconcileAttendanceSources(sources, {
    studentMappings: [
      { sourceId: 'import', sourceStudentId: 'local-1', targetStudentId: 'A' },
      { sourceId: 'import', sourceStudentId: 'local-2', targetStudentId: 'B' },
    ],
    sessionMappings: [
      { sourceId: 'import', sourceSessionId: 'week-one', targetSessionId: 'S1' },
      { sourceId: 'import', sourceSessionId: 'week-two', targetSessionId: 'S2' },
    ],
    targetRoster: [
      { id: 'B', name: 'Bao', email: 'b@example.test' },
      { id: 'A', name: 'An', email: 'a@example.test' },
    ],
    targetSessionIds: ['S2', 'S1'],
    includeSnapshot: true,
  });
  assert.equal(plan.summary.ready, true);
  assert.deepEqual(plan.snapshot.roster.map((student) => student.id), ['B', 'A']);
  assert.deepEqual(plan.snapshot.sessionIds, ['S2', 'S1']);
  assert.equal(plan.snapshot.records.find((record) => record.studentId === 'A' && record.sessionId === 'S1').status, 'present');
});

test('blocks unused stale mappings, unknown IDs and conflicting decisions', () => {
  const sources = [source('one', [{ id: 'A', name: 'An', email: 'a@example.test', statuses: ['present', 'absent'] }])];
  const unused = reconcileAttendanceSources(sources, { studentMappings: [
    { sourceId: 'one', sourceStudentId: 'not-present', targetStudentId: 'A' },
  ] });
  assert.ok(unused.issues.some((issue) => issue.code === 'unused_student_mapping'));
  assert.equal(unused.summary.ready, false);
  assert.throws(() => reconcileAttendanceSources(sources, { sessionMappings: [
    { sourceId: 'missing', sourceSessionId: 'S1', targetSessionId: 'A' },
  ] }), /unknown source/);
  assert.throws(() => reconcileAttendanceSources(sources, { studentMappings: [
    { sourceId: 'one', sourceStudentId: 'A', targetStudentId: 'B' },
    { sourceId: 'one', sourceStudentId: 'A', targetStudentId: 'C' },
  ] }), /duplicate mapping/);
});

test('rejects stale conflict decisions instead of silently ignoring them', () => {
  const sources = [source('one', [{ id: 'A', name: 'An', email: 'a@example.test', statuses: ['present', 'absent'] }])];
  const plan = reconcileAttendanceSources(sources, { resolutions: [{ conflictId: 'record-STALE', sourceId: 'one' }] });
  assert.equal(plan.summary.ready, false);
  assert.ok(plan.issues.some((issue) => issue.code === 'stale_resolution'));
});

test('counts source threshold blockers and exposes only a compact summary by default', () => {
  const sources = [source('one', [{ id: 'A', name: 'An', email: 'a@example.test', statuses: ['present', 'absent'] }])];
  const plan = reconcileAttendanceSources(sources, { minimumAgreement: 2 });
  assert.equal(plan.summary.ready, false);
  assert.ok(plan.issues.some((issue) => issue.code === 'insufficient_source_agreement'));
  assert.equal(Object.hasOwn(plan, 'provenance'), false);
  assert.equal(Object.hasOwn(plan, 'snapshot'), false);
  const summary = summarizeReconciliation(plan);
  assert.deepEqual(summary.conflictsByKind, {});
  assert.equal(summary.containsSnapshot, false);
});

test('limits provenance rows and only adds a snapshot after explicit opt-in', () => {
  const plan = reconcileAttendanceSources(baseSources(), {
    recordConflictPolicy: 'prefer-present', includeProvenance: true, maximumProvenanceRows: 1,
  });
  assert.equal(plan.summary.ready, true);
  assert.equal(Object.hasOwn(plan, 'snapshot'), false);
  assert.equal(plan.provenance.length, 1);
  assert.equal(plan.summary.provenanceTruncated, true);
});

test('exports conflict, issue and provenance CSV with formula-safe cells', () => {
  const sources = [
    source('first', [{ id: 'A', name: '=FORMULA()', email: 'a@example.test', statuses: ['present', 'missing'] }]),
    source('second', [{ id: 'A', name: 'Safe Name', email: 'a@example.test', statuses: ['present', 'missing'] }]),
  ];
  const initial = reconcileAttendanceSources(sources, { includeProvenance: true });
  assert.match(reconciliationToCsv(initial), /"conflictId","kind","target"/);
  assert.match(reconciliationToCsv(initial), /'=FORMULA/);
  assert.match(reconciliationToCsv(initial, 'issues'), /"code","blocking"/);
  assert.match(reconciliationToCsv(initial, 'provenance'), /"studentId","sessionId","status"/);
  assert.throws(() => reconciliationToCsv(initial, 'raw'), /section must be/);
  const noProvenance = reconcileAttendanceSources(sources);
  assert.throws(() => reconciliationToCsv(noProvenance, 'provenance'), /not included/);
});

test('normalizes equivalent identity values without inventing an identity conflict', () => {
  const sources = [
    source('first', [{ id: 'A', name: 'An  Nguyen', email: 'AN@EXAMPLE.TEST', statuses: ['present', 'missing'] }]),
    source('second', [{ id: 'A', name: 'an nguyen', email: 'an@example.test', statuses: ['present', 'missing'] }]),
  ];
  const plan = reconcileAttendanceSources(sources, { identityConflictPolicy: 'prefer-priority', includeSnapshot: true });
  assert.equal(plan.summary.ready, true);
  assert.equal(plan.conflicts.length, 0);
  assert.deepEqual(plan.snapshot.roster[0], { id: 'A', name: 'An  Nguyen', email: 'an@example.test' });
});

test('validates source count, target identity, session order, policies and option types', () => {
  const valid = [source('one', [{ id: 'A', name: 'An', email: 'a@example.test', statuses: ['present', 'absent'] }])];
  assert.throws(() => reconcileAttendanceSources([], {}), /from 1 to 50/);
  assert.throws(() => reconcileAttendanceSources(Array(51).fill(valid[0])), /from 1 to 50/);
  assert.throws(() => reconcileAttendanceSources([valid[0], valid[0]]), /duplicate source id/);
  assert.throws(() => reconcileAttendanceSources(valid, { identityConflictPolicy: 'last' }), /identityConflictPolicy/);
  assert.throws(() => reconcileAttendanceSources(valid, { recordConflictPolicy: 'always-present' }), /record conflict policy/);
  assert.throws(() => reconcileAttendanceSources(valid, { minimumAgreement: 0 }), /at least 1/);
  assert.throws(() => reconcileAttendanceSources(valid, { includeSnapshot: 'yes' }), /must be a boolean/);
  assert.throws(() => reconcileAttendanceSources(valid, { targetRoster: [
    { id: 'A', name: 'An', email: 'a@example.test' }, { id: 'A', name: 'Again', email: 'again@example.test' },
  ] }), /duplicate student ID/);
  assert.throws(() => reconcileAttendanceSources(valid, { targetSessionIds: ['S1', 'S1'] }), /must be unique/);
});

test('validates report types and snapshot schemas before returning a plan', () => {
  assert.throws(() => reconcileAttendanceSources([{}]), /sources\[0\]\.id/);
  assert.throws(() => summarizeReconciliation({ format: 'wrong', version: 1 }), /invalid/);
  assert.throws(() => reconciliationToCsv({ format: 'wrong', version: 1 }), /invalid/);
  assert.match(JSON.stringify(reconcileAttendanceSources(baseSources())), /local merge proposal/);
});
