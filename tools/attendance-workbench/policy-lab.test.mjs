import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { buildPolicyLab, createPolicyGrid, policyLabToCsv } from './policy-lab.mjs';

const candidates = [
  { id: 'baseline', name: 'Current example', minimumRate: 0.5, maximumAbsences: 1 },
  { id: 'strict', name: 'Higher example', minimumRate: 0.75, maximumAbsences: 0 },
];

function snapshotWithMissing() {
  const roster = [
    { id: 'A', name: 'An Example', email: 'an@example.test' },
    { id: 'B', name: 'Bao Example', email: 'bao@example.test' },
    { id: 'C', name: 'Chi Example', email: 'chi@example.test' },
    { id: 'D', name: 'Dung Example', email: 'dung@example.test' },
  ];
  const sessions = ['S1', 'S2', 'S3', 'S4'];
  const pattern = {
    A: ['present', 'present', 'absent', 'missing'],
    B: ['absent', 'absent', 'absent', 'missing'],
    C: ['present', 'present', 'present', 'present'],
    D: ['missing', 'missing', 'missing', 'missing'],
  };
  const records = roster.flatMap((student) => pattern[student.id].flatMap((status, index) => status === 'missing' ? [] : [
    { studentId: student.id, sessionId: sessions[index], status },
  ]));
  return createAttendanceSnapshot(roster, sessions, records);
}

function options(overrides = {}) {
  return { policies: candidates, minimumCohortSize: 2, ...overrides };
}

test('compares explicit policies across four missing-data assumptions without modifying input', () => {
  const source = snapshotWithMissing();
  const before = JSON.stringify(source);
  const result = buildPolicyLab(source, options());
  assert.equal(JSON.stringify(source), before);
  assert.equal(result.format, 'attendance-policy-lab');
  assert.deepEqual(result.settings.missingModes, ['bounded', 'assume-present', 'assume-absent', 'exclude-missing']);
  assert.equal(result.scenarios.length, 8);
  assert.deepEqual(result.generatedFor, { students: 4, sessions: 4, records: 10 });
  assert.equal(result.scenarios.every((scenario) => !Object.hasOwn(scenario, 'students')), true);
  assert.equal(result.scenarios[0].summary.students, 4);
  assert.equal(result.scenarios[0].summary.pass + result.scenarios[0].summary.fail + result.scenarios[0].summary.undetermined, 4);
  assert.match(result.note, /descriptive/);
});

test('bounds uncertain records and shows each assumption separately', () => {
  const result = buildPolicyLab(snapshotWithMissing(), options({ policies: [candidates[0]],
    missingModes: ['bounded', 'assume-present', 'assume-absent', 'exclude-missing'], includeStudentRows: true }));
  const byMode = new Map(result.scenarios.map((scenario) => [scenario.missingMode, scenario]));
  const row = (mode, id = 'A') => byMode.get(mode).students.find((student) => student.studentId === id);
  assert.equal(row('bounded').status, 'undetermined');
  assert.equal(row('bounded').minimumRate, 0.5);
  assert.equal(row('bounded').maximumRate, 0.75);
  assert.equal(row('assume-present').status, 'pass');
  assert.equal(row('assume-present').present, 3);
  assert.equal(row('assume-absent').status, 'fail');
  assert.equal(row('assume-absent').absent, 2);
  assert.equal(row('exclude-missing').status, 'pass');
  assert.equal(row('exclude-missing').denominator, 3);
  assert.equal(row('bounded', 'D').status, 'undetermined');
  assert.equal(row('exclude-missing', 'D').reasons[0], 'no_recorded_results');
});

test('reports an outcome as failed when even the optimistic missing-data bound cannot pass', () => {
  const source = createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'a@example.test' }],
    ['S1', 'S2', 'S3', 'S4'], [
      { studentId: 'A', sessionId: 'S1', status: 'absent' },
      { studentId: 'A', sessionId: 'S2', status: 'absent' },
      { studentId: 'A', sessionId: 'S3', status: 'absent' },
    ]);
  const lab = buildPolicyLab(source, options({ policies: [{ id: 'rule', minimumRate: 0.5, maximumAbsences: 4 }],
    missingModes: ['bounded'], includeStudentRows: true }));
  assert.equal(lab.scenarios[0].students[0].status, 'fail');
  assert.ok(lab.scenarios[0].students[0].reasons.includes('rate_below_minimum'));
});

test('compares alternatives to a selected baseline using outcome transition counts', () => {
  const lab = buildPolicyLab(snapshotWithMissing(), options({ baselinePolicyId: 'baseline', missingModes: ['assume-present', 'assume-absent'] }));
  const strict = lab.scenarios.find((scenario) => scenario.policy.id === 'strict' && scenario.missingMode === 'assume-present');
  assert.equal(strict.comparisonToBaseline.changed, 1);
  assert.equal(strict.comparisonToBaseline.transitions.pass_to_fail, 1);
  assert.equal(Object.values(strict.comparisonToBaseline.transitions).reduce((sum, value) => sum + value, 0), 1);
  assert.equal(strict.comparisonToBaseline.cohorts[0].comparison.changed, 1);
  assert.equal(lab.scenarios.find((scenario) => scenario.policy.id === 'baseline' && scenario.missingMode === 'assume-present')
    .comparisonToBaseline, null);
});

test('summarizes named cohorts and suppresses groups below the configured minimum', () => {
  const lab = buildPolicyLab(snapshotWithMissing(), options({ cohorts: [
    { id: 'north', label: 'North', studentIds: ['A', 'C'] },
    { id: 'small', label: 'Small cohort', studentIds: ['B'] },
  ] }));
  const cohorts = lab.scenarios[0].cohorts;
  assert.deepEqual(cohorts.map(({ id, suppressed }) => [id, suppressed]), [
    ['north', false], ['small', true], ['unassigned', true],
  ]);
  assert.equal(cohorts[0].summary.students, 2);
  assert.equal(cohorts[1].summary, null);
  assert.equal(cohorts[2].summary, null);
  const csv = policyLabToCsv(lab, 'cohorts');
  assert.match(csv, /"small","Small cohort","true","","","",""/);
});

test('suppresses small-cohort policy transition counts and exports aggregate comparisons', () => {
  const lab = buildPolicyLab(snapshotWithMissing(), options({
    missingModes: ['assume-present'],
    cohorts: [
      { id: 'north', label: 'North', studentIds: ['A', 'C'] },
      { id: 'small', label: 'Small cohort', studentIds: ['B'] },
    ],
  }));
  const strict = lab.scenarios.find((scenario) => scenario.policy.id === 'strict');
  assert.equal(strict.comparisonToBaseline.cohorts[0].comparison.changed, 1);
  assert.equal(strict.comparisonToBaseline.cohorts[1].suppressed, true);
  assert.equal(strict.comparisonToBaseline.cohorts[1].comparison, null);
  assert.equal(strict.comparisonToBaseline.cohorts[2].suppressed, true);
  const csv = policyLabToCsv(lab, 'comparisons');
  assert.match(csv, /"scenarioId","missingMode","policyId","cohortId"/);
  assert.match(csv, /"small","Small cohort","true","",""/);
  assert.doesNotMatch(csv, /An Example|Bao Example/);
});

test('rejects unknown students and overlapping cohort assignments', () => {
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ cohorts: [
    { id: 'x', studentIds: ['not-in-roster'] },
  ] })), /unknown student id/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ cohorts: [
    { id: 'x', studentIds: ['A'] }, { id: 'y', studentIds: ['A'] },
  ] })), /more than one cohort/);
});

test('does not include a singleton cohort summary and requires at least two for cohort output', () => {
  const lab = buildPolicyLab(snapshotWithMissing(), options({ cohorts: [{ id: 'one', studentIds: ['A'] }] }));
  assert.equal(lab.scenarios[0].cohorts[0].suppressed, true);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ minimumCohortSize: 1 })), /at least 2/);
});

test('limits and validates explicit student-level exports', () => {
  const withoutRows = buildPolicyLab(snapshotWithMissing(), options());
  assert.throws(() => policyLabToCsv(withoutRows, 'students'), /not enabled/);
  const withRows = buildPolicyLab(snapshotWithMissing(), options({ missingModes: ['bounded'], includeStudentRows: true }));
  assert.match(policyLabToCsv(withRows, 'students'), /"scenarioId","studentId","studentName"/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ includeStudentRows: 'yes' })), /must be a boolean/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ includeStudentRows: true, maximumStudentRows: 3 })), /limited to 3 rows/);
});

test('creates a deterministic policy grid with a bounded number of combinations', () => {
  const grid = createPolicyGrid({ minimumRates: [0.5, 0.75], maximumAbsences: [0, 2], idPrefix: 'term' });
  assert.deepEqual(grid, [
    { id: 'term-r01-a01', name: 'Minimum 50%, at most 0 absences', minimumRate: 0.5, maximumAbsences: 0 },
    { id: 'term-r01-a02', name: 'Minimum 50%, at most 2 absences', minimumRate: 0.5, maximumAbsences: 2 },
    { id: 'term-r02-a01', name: 'Minimum 75%, at most 0 absences', minimumRate: 0.75, maximumAbsences: 0 },
    { id: 'term-r02-a02', name: 'Minimum 75%, at most 2 absences', minimumRate: 0.75, maximumAbsences: 2 },
  ]);
  assert.equal(createPolicyGrid({ minimumRates: [1], maximumAbsences: [0] })[0].id, 'grid-r01-a01');
  assert.throws(() => createPolicyGrid({ minimumRates: Array(9).fill(0.5), maximumAbsences: Array(5).fill(1) }), /at most 40/);
  assert.throws(() => createPolicyGrid({ minimumRates: [0.5, 0.5], maximumAbsences: [1] }), /must be unique/);
  assert.throws(() => createPolicyGrid({ minimumRates: [1.2], maximumAbsences: [1] }), /from 0 to 1/);
});

test('validates candidate policies, missing-data modes, and comparison controls', () => {
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), {}), /policies must contain/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ policies: [candidates[0], candidates[0]] })), /duplicate policy id/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ policies: [{ ...candidates[0], minimumRate: 2 }] })), /from 0 to 1/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ policies: [{ ...candidates[0], maximumAbsences: -1 }] })), /non-negative/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ missingModes: ['impute-by-name'] })), /unsupported missing-data mode/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ missingModes: ['bounded', 'bounded'] })), /duplicate missing-data mode/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ baselinePolicyId: 'absent' })), /identify one/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ policies: Array(41).fill(candidates[0]) })), /1 to 40/);
});

test('validates cohort limits, identifiers, labels, and duplicate ids', () => {
  const source = snapshotWithMissing();
  assert.throws(() => buildPolicyLab(source, options({ cohorts: [{ id: 'x', studentIds: ['A'] }, { id: 'x', studentIds: [] }] })), /duplicate cohort id/);
  assert.throws(() => buildPolicyLab(source, options({ cohorts: [{ id: 'bad space', studentIds: [] }] })), /letters, numbers/);
  assert.throws(() => buildPolicyLab(source, options({ cohorts: 'north' })), /must be an array/);
  assert.throws(() => buildPolicyLab(source, options({ cohorts: Array(101).fill({ id: 'x', studentIds: [] }) })), /at most 100/);
});

test('exports stable formula-safe aggregate and cohort CSV sections', () => {
  const lab = buildPolicyLab(snapshotWithMissing(), options({
    cohorts: [{ id: 'group', label: '=HYPERLINK("bad")', studentIds: ['A', 'B'] }], missingModes: ['bounded'],
  }));
  const summary = policyLabToCsv(lab);
  assert.match(summary, /^"scenarioId","policyId","policyName"/);
  assert.match(summary, /\r\n"baseline--bounded"/);
  const cohort = policyLabToCsv(lab, 'cohorts');
  assert.match(cohort, /'=HYPERLINK/);
  assert.throws(() => policyLabToCsv(lab, 'raw'), /section must be/);
  assert.throws(() => policyLabToCsv({ ...lab, format: 'other' }), /invalid policy lab/);
});

test('marks students with no sessions as undetermined in every mode', () => {
  const source = createAttendanceSnapshot([{ id: 'A', name: 'An', email: 'a@example.test' }], [], []);
  const lab = buildPolicyLab(source, options({ policies: [candidates[0]], includeStudentRows: true }));
  assert.equal(lab.scenarios.length, 4);
  assert.ok(lab.scenarios.every((scenario) => scenario.students[0].status === 'undetermined'));
  assert.ok(lab.scenarios.every((scenario) => scenario.students[0].reasons.includes('no_sessions')));
});

test('applies exact rate and absence boundaries without rounding the decision', () => {
  const source = createAttendanceSnapshot([
    { id: 'A', name: 'All present', email: 'a@example.test' },
    { id: 'B', name: 'Exactly half', email: 'b@example.test' },
  ], ['S1', 'S2'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'A', sessionId: 'S2', status: 'present' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'absent' },
  ]);
  const lab = buildPolicyLab(source, options({
    policies: [
      { id: 'edge', minimumRate: 0.5, maximumAbsences: 1 },
      { id: 'above-edge', minimumRate: 0.500001, maximumAbsences: 0 },
    ], missingModes: ['exclude-missing'], includeStudentRows: true,
  }));
  const exact = lab.scenarios[0].students;
  const strict = lab.scenarios[1].students;
  assert.deepEqual(exact.map((student) => student.status), ['pass', 'pass']);
  assert.deepEqual(strict.map((student) => student.status), ['pass', 'fail']);
  assert.equal(lab.scenarios[1].comparisonToBaseline.transitions.pass_to_fail, 1);
});

test('handles an empty roster with aggregate zeroes and no invented cohort results', () => {
  const source = createAttendanceSnapshot([], [], []);
  const lab = buildPolicyLab(source, options({ policies: [candidates[0]], missingModes: ['bounded'] }));
  assert.deepEqual(lab.generatedFor, { students: 0, sessions: 0, records: 0 });
  assert.equal(lab.scenarios[0].summary.students, 0);
  assert.equal(lab.scenarios[0].summary.passRateAmongDetermined, null);
  assert.equal(lab.scenarios[0].cohorts[0].suppressed, true);
});

test('formula-protects explicitly requested student CSV cells and leaves the snapshot unchanged', () => {
  const source = createAttendanceSnapshot([
    { id: '=CMD()', name: '=HYPERLINK("unsafe")', email: 'safe@example.test' },
  ], ['S1'], [{ studentId: '=CMD()', sessionId: 'S1', status: 'present' }]);
  const before = JSON.stringify(source);
  const lab = buildPolicyLab(source, options({ policies: [candidates[0]], missingModes: ['bounded'], includeStudentRows: true }));
  const csv = policyLabToCsv(lab, 'students');
  assert.match(csv, /'=CMD\(\)/);
  assert.match(csv, /'=HYPERLINK/);
  assert.equal(JSON.stringify(source), before);
});

test('rejects malformed options and invalid row limits before calculating any scenarios', () => {
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), []), /options must be an object/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ minimumCohortSize: 1001 })), /no greater than 1000/);
  assert.throws(() => buildPolicyLab(snapshotWithMissing(), options({ maximumStudentRows: 10_001 })), /no greater than 10000/);
  assert.throws(() => createPolicyGrid({ minimumRates: [0.5], maximumAbsences: [1], idPrefix: 'bad prefix' }), /letters, numbers/);
});
