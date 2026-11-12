import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { createSnapshotContract, parseSnapshotContract, serializeSnapshotContract, snapshotContractToCsv,
  validateSnapshotContract } from './snapshot-contract.mjs';

function sample() {
  return createAttendanceSnapshot([
    { id: 'A', name: 'An Nguyen', email: 'an@example.test' },
    { id: 'B', name: 'Binh Tran', email: 'binh@example.test' },
  ], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
  ]);
}

const contract = () => createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1,
  id: 'term-contract', title: 'Term snapshot acceptance', revision: 3, note: 'Use before publishing reviewed data.',
  checks: [
    { id: 'student-min', type: 'min_students', value: 2 },
    { id: 'student-max', type: 'max_students', value: 4 },
    { id: 'session-min', type: 'min_sessions', value: 2 },
    { id: 'session-max', type: 'max_sessions', value: 4 },
    { id: 'record-min', type: 'min_records', value: 2 },
    { id: 'record-max', type: 'max_records', value: 4 },
    { id: 'coverage', type: 'minimum_coverage', value: 0.5 },
    { id: 'missing-max', type: 'maximum_missing', value: 2 },
    { id: 'missing-student-max', type: 'maximum_missing_per_student', value: 1 },
    { id: 'required-a', type: 'require_student', studentId: 'A' },
    { id: 'required-s2', type: 'require_session', sessionId: 'S2' },
    { id: 'order', type: 'exact_session_order', sessionIds: ['S1', 'S2'] },
    { id: 'cell', type: 'cell_status', studentId: 'A', sessionId: 'S1', status: 'absent' },
    { id: 'missing-cell', type: 'cell_status', studentId: 'A', sessionId: 'S2', status: 'missing' },
    { id: 'absence-rate', type: 'maximum_absence_rate', value: 1 },
    { id: 'identities', type: 'no_placeholder_identity' },
  ] });

test('validates dimensions, coverage, missing cells, identity and explicit result requirements', () => {
  const source = sample();
  const before = serializeAttendanceSnapshot(source);
  const report = validateSnapshotContract(source, contract());
  assert.equal(report.format, 'attendance-snapshot-contract-report');
  assert.equal(report.contractId, 'term-contract');
  assert.equal(report.contractRevision, 3);
  assert.equal(report.accepted, true, JSON.stringify(report.results.filter((result) => !result.passed)));
  assert.equal(report.summary.checks, 16);
  assert.equal(report.summary.passed, 16);
  assert.equal(report.summary.records, 2);
  assert.equal(report.summary.expectedCells, 4);
  assert.equal(report.snapshotFingerprint.startsWith('snapshot-'), true);
  assert.equal(serializeAttendanceSnapshot(source), before);
});

test('rejects a contract when any error check fails but preserves warning-only failures', () => {
  const source = sample();
  const failing = createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1,
    id: 'strict', title: 'Strict', revision: 1, checks: [
      { id: 'coverage', type: 'minimum_coverage', value: 0.75 },
      { id: 'minimum-size', type: 'min_students', value: 3, severity: 'warning' },
    ] });
  const report = validateSnapshotContract(source, failing);
  assert.equal(report.accepted, false);
  assert.equal(report.summary.failed, 2);
  assert.equal(report.summary.errors, 1);
  assert.equal(report.summary.warnings, 1);
  assert.equal(report.results[0].actual, 0.5);
  const warningOnly = createSnapshotContract({ ...failing, checks: [{ id: 'warning', type: 'min_students', value: 3, severity: 'warning' }] });
  const warningReport = validateSnapshotContract(source, warningOnly);
  assert.equal(warningReport.accepted, true);
  assert.equal(warningReport.summary.warnings, 1);
});

test('detects session-order changes, absent expected students, wrong cell values and placeholders', () => {
  const source = createAttendanceSnapshot([
    { id: 'A', name: 'Unknown', email: 'unknown@example.test' },
    { id: 'B', name: 'Binh Tran', email: 'binh@example.test' },
  ], ['S2', 'S1'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
  ]);
  const checks = createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1, id: 'identity',
    title: 'Identity checks', revision: 1, checks: [
      { id: 'order', type: 'exact_session_order', sessionIds: ['S1', 'S2'] },
      { id: 'student', type: 'require_student', studentId: 'MISSING' },
      { id: 'cell', type: 'cell_status', studentId: 'A', sessionId: 'S2', status: 'absent' },
      { id: 'identity', type: 'no_placeholder_identity' },
    ] });
  const report = validateSnapshotContract(source, checks);
  assert.equal(report.accepted, false);
  assert.equal(report.results[0].actual.join(','), 'S2,S1');
  assert.equal(report.results[1].actual, false);
  assert.equal(report.results[2].actual, 'missing');
  assert.equal(report.results[3].details.length, 2);
  assert.deepEqual(report.results[3].details[0], { studentId: 'A', field: 'name' });
  assert.deepEqual(report.results[3].details[1], { studentId: 'A', field: 'email' });
});

test('round trips serialized contract JSON and rejects malformed contracts', () => {
  const value = contract();
  assert.deepEqual(parseSnapshotContract(serializeSnapshotContract(value)), value);
  assert.throws(() => parseSnapshotContract('{bad'), /valid JSON/);
  assert.throws(() => parseSnapshotContract({ ...value, version: 2 }), /unsupported/);
  assert.throws(() => createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1,
    id: 'bad', title: 'Bad', revision: 1, checks: [] }), /1 to 500 checks/);
  assert.throws(() => createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1,
    id: 'bad', title: 'Bad', revision: 1, checks: [{ id: 'x', type: 'eval', value: 'true' }] }), /unsupported/);
  assert.throws(() => createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1,
    id: 'bad', title: 'Bad', revision: 1, checks: [
      { id: 'same', type: 'min_students', value: 1 }, { id: 'same', type: 'max_students', value: 2 },
    ] }), /check IDs must be unique/);
});

test('exports checks and run summaries as spreadsheet-safe CSV', () => {
  const value = createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1, id: 'csv', title: '=Sensitive title',
    revision: 1, checks: [{ id: 'coverage', type: 'minimum_coverage', value: 0.75, label: '=Check coverage' }] });
  const report = validateSnapshotContract(sample(), value);
  assert.match(snapshotContractToCsv(report, 'checks'), /"checkId","type","label","severity"/);
  assert.match(snapshotContractToCsv(report, 'checks'), /'=Check coverage/);
  assert.match(snapshotContractToCsv(report, 'summary'), /"contractId","contractRevision","snapshotFingerprint"/);
  assert.throws(() => snapshotContractToCsv({ format: 'wrong', version: 1, results: [] }), /invalid/);
  assert.throws(() => snapshotContractToCsv(report, 'raw'), /section must be/);
});

test('handles empty snapshots and validates check-specific values', () => {
  const empty = createAttendanceSnapshot([], [], []);
  const emptyContract = createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1,
    id: 'empty', title: 'Empty snapshot', revision: 1, checks: [
      { id: 'min', type: 'minimum_coverage', value: 0.1 },
      { id: 'identities', type: 'no_placeholder_identity' },
      { id: 'missing', type: 'maximum_missing_per_student', value: 0 },
    ] });
  const report = validateSnapshotContract(empty, emptyContract);
  assert.equal(report.accepted, false);
  assert.equal(report.results[0].actual, null);
  assert.equal(report.results[1].passed, true);
  assert.equal(report.results[2].actual, 0);
  assert.throws(() => createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1, id: 'x', title: 'X', revision: 1,
    checks: [{ id: 'x', type: 'minimum_coverage', value: 2 }] }), /fraction from 0 to 1/);
  assert.throws(() => createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1, id: 'x', title: 'X', revision: 1,
    checks: [{ id: 'x', type: 'cell_status', studentId: 'A', sessionId: 'S1', status: 'late' }] }), /unsupported/);
  assert.throws(() => createSnapshotContract({ format: 'attendance-snapshot-contract', version: 1, id: 'x', title: 'X', revision: 1,
    checks: [{ id: 'x', type: 'no_placeholder_identity', checkNames: false, checkEmails: false }] }), /names, emails or both/);
});
