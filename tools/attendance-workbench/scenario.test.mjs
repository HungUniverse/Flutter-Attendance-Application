import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { createScenario, evaluateScenario, parseScenario, removeScenarioChange,
  scenarioToCsv, serializeScenario, setScenarioChange } from './scenario.mjs';

const snapshot = createAttendanceSnapshot([
  { id: 'A', name: 'An, "Minh"', email: 'a@example.test' },
  { id: 'B', name: 'Bình', email: 'b@example.test' },
], ['s1', 's2'], [
  { studentId: 'A', sessionId: 's1', status: 'present' },
  { studentId: 'A', sessionId: 's2', status: 'absent' },
  { studentId: 'B', sessionId: 's1', status: 'absent' },
]);

test('creates a validated independent baseline and serializes a stable scenario', () => {
  const scenario = createScenario(snapshot, { title: 'Review', description: 'Test corrections',
    policy: { minimumRate: 0.5, maximumAbsences: 1 } });
  assert.equal(scenario.schemaVersion, 1);
  assert.equal(scenario.title, 'Review');
  assert.deepEqual(scenario.baseline, snapshot);
  assert.deepEqual(scenario.changes, []);
  assert.deepEqual(parseScenario(serializeScenario(scenario)), scenario);
  assert.equal(snapshot.records.length, 3);
});

test('sets, replaces and clears proposed present, absent and missing values', () => {
  let scenario = createScenario(snapshot);
  scenario = setScenarioChange(scenario, 'B', 's1', 'present');
  scenario = setScenarioChange(scenario, 'B', 's2', 'present');
  assert.deepEqual(scenario.changes, [
    { studentId: 'B', sessionId: 's1', expected: 'absent', status: 'present' },
    { studentId: 'B', sessionId: 's2', expected: null, status: 'present' },
  ]);
  scenario = setScenarioChange(scenario, 'B', 's2', 'absent');
  assert.equal(scenario.changes[1].status, 'absent');
  scenario = setScenarioChange(scenario, 'B', 's2', 'missing');
  assert.equal(scenario.changes.length, 1);
  scenario = setScenarioChange(scenario, 'A', 's1', 'missing');
  assert.equal(scenario.changes[1].expected, 'present');
  scenario = removeScenarioChange(scenario, 'B', 's1');
  assert.equal(scenario.changes.length, 1);
  assert.throws(() => setScenarioChange(scenario, 'unknown', 's1', 'present'), /unknown student/);
});

test('evaluates aggregate and per-student impact without changing the baseline', () => {
  const scenario = setScenarioChange(setScenarioChange(createScenario(snapshot, {
    policy: { minimumRate: 0.5, maximumAbsences: 1 },
  }), 'B', 's1', 'present'), 'B', 's2', 'present');
  const result = evaluateScenario(scenario);
  assert.equal(result.ok, true);
  assert.equal(result.delta.present, 2);
  assert.equal(result.delta.absent, -1);
  assert.equal(result.delta.missing, -1);
  assert.equal(result.after.attendanceRate, 0.75);
  assert.equal(result.delta.newlyPassing, 1);
  assert.equal(result.students.find((item) => item.student.id === 'B').policyAfter, 'pass');
  assert.equal(scenario.baseline.records.length, 3);
  assert.equal(result.snapshot.records.length, 4);
});

test('detects changed source cells as conflicts and applies no partial changes', () => {
  const scenario = setScenarioChange(createScenario(snapshot), 'B', 's1', 'present');
  const changed = createAttendanceSnapshot(snapshot.roster, snapshot.sessionIds, [
    ...snapshot.records.filter((record) => record.studentId !== 'B'),
    { studentId: 'B', sessionId: 's1', status: 'present' },
  ]);
  const result = evaluateScenario(scenario, changed);
  assert.equal(result.ok, false);
  assert.deepEqual(result.conflicts.map((item) => [item.expected, item.actual, item.proposed]), [['absent', 'present', 'present']]);
  assert.equal('snapshot' in result, false);
});

test('blocks evaluation when a scenario target was removed from the current roster', () => {
  const scenario = setScenarioChange(createScenario(snapshot), 'B', 's1', 'present');
  const current = createAttendanceSnapshot(snapshot.roster.filter((student) => student.id !== 'B'),
    snapshot.sessionIds, snapshot.records.filter((record) => record.studentId !== 'B'));
  const result = evaluateScenario(scenario, current);
  assert.equal(result.ok, false);
  assert.equal(result.conflicts[0].reason, 'student_removed');
});

test('rejects invalid policies, stale expectations, duplicate cells and unknown versions', () => {
  assert.throws(() => createScenario(snapshot, { policy: { minimumRate: 2, maximumAbsences: 0 } }), /minimumRate/);
  const scenario = setScenarioChange(createScenario(snapshot), 'B', 's1', 'present');
  assert.throws(() => parseScenario({ ...scenario, changes: [...scenario.changes, scenario.changes[0]] }), /duplicate/);
  assert.throws(() => parseScenario({ ...scenario, changes: [{ ...scenario.changes[0], expected: null }] }), /baseline/);
  assert.throws(() => parseScenario({ ...scenario, schemaVersion: 9 }), /unsupported/);
});

test('exports an escaped CSV row for each proposed change', () => {
  const result = evaluateScenario(setScenarioChange(createScenario(snapshot), 'A', 's2', 'present'));
  const csv = scenarioToCsv(result);
  assert.match(csv, /"studentName"/);
  assert.match(csv, /"An, ""Minh"""/);
  assert.match(csv, /"s2","absent","present"/);
  assert.throws(() => scenarioToCsv({ ok: false, changes: [] }), /successful/);
});

test('protects formula-like student names in scenario CSV exports', () => {
  const risky = createAttendanceSnapshot([{ id: 'A', name: '=HYPERLINK("x")', email: 'a@example.test' }], ['s1'], []);
  const scenario = setScenarioChange(createScenario(risky), 'A', 's1', 'present');
  assert.match(scenarioToCsv(evaluateScenario(scenario)), /"'=HYPERLINK/);
});
