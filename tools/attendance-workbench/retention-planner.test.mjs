import test from 'node:test';
import assert from 'node:assert/strict';
import { buildRetentionPlan, retentionPlanToCsv } from './retention-planner.mjs';

const asOf = '2026-11-13T12:00:00Z';

function item(id, options = {}) {
  return { id, kind: 'snapshot', classification: 'restricted', createdAt: '2025-01-01T12:00:00Z',
    lastAccessedAt: '2026-10-01T12:00:00Z', owner: 'data-steward', sizeBytes: 2048,
    dataCategories: ['student_id', 'attendance'], tags: [], ...options };
}

const policies = [
  { id: 'snapshots', kind: 'snapshot', retentionDays: 365, reviewWindowDays: 30, action: 'delete', priority: 10 },
  { id: 'exports', kind: 'export', classification: 'confidential', retentionDays: 180, reviewWindowDays: 30,
    action: 'redact', priority: 5, description: 'Remove expired personal identifiers after review.' },
  { id: 'temporary', tagsAny: ['temporary'], retentionDays: 60, reviewWindowDays: 30, action: 'review', priority: 1 },
];

test('plans metadata-only outcomes for current, expiring, expired and held records', () => {
  const inventory = [
    item('old-snapshot'),
    item('recent-export', { kind: 'export', classification: 'confidential', createdAt: '2026-10-20T12:00:00Z' }),
    item('expiring-snapshot', { createdAt: '2025-12-01T12:00:00Z' }),
    item('held-snapshot', { legalHold: true }),
    item('temporary-data', { kind: 'temp', classification: 'internal', tags: ['temporary'], createdAt: '2026-10-01T12:00:00Z' }),
    item('unmatched', { kind: 'unknown', classification: 'public' }),
  ];
  const before = JSON.stringify(inventory);
  const plan = buildRetentionPlan(inventory, policies, { asOf });
  assert.equal(plan.format, 'attendance-retention-plan');
  assert.equal(plan.version, 1);
  assert.equal(plan.summary.items, 6);
  assert.equal(plan.summary.due, 4);
  assert.equal(plan.summary.legalHold, 1);
  assert.equal(plan.summary.policyGaps, 1);
  assert.equal(plan.entries.find((entry) => entry.id === 'old-snapshot').disposition, 'delete');
  assert.equal(plan.entries.find((entry) => entry.id === 'old-snapshot').reasonCode, 'retention_period_expired');
  assert.equal(plan.entries.find((entry) => entry.id === 'recent-export').disposition, 'retain');
  assert.equal(plan.entries.find((entry) => entry.id === 'expiring-snapshot').reasonCode, 'expiry_review_window');
  assert.equal(plan.entries.find((entry) => entry.id === 'held-snapshot').disposition, 'retain');
  assert.equal(plan.entries.find((entry) => entry.id === 'held-snapshot').requiresApproval, true);
  assert.equal(plan.entries.find((entry) => entry.id === 'unmatched').reasonCode, 'no_matching_policy');
  assert.equal(JSON.stringify(inventory), before);
  assert.match(plan.notice, /no deletion/);
});

test('uses priority then specificity and reports conflicting same-rank rules', () => {
  const candidate = item('tagged', { tags: ['temporary'] });
  const lowPrioritySpecific = { id: 'specific', kind: 'snapshot', retentionDays: 900, action: 'retain', priority: 1 };
  const highPriorityGeneral = { id: 'general', classification: 'restricted', retentionDays: 30, action: 'review', priority: 2 };
  const picked = buildRetentionPlan([candidate], [lowPrioritySpecific, highPriorityGeneral], { asOf });
  assert.equal(picked.entries[0].policyId, 'general');
  const conflict = buildRetentionPlan([candidate], [
    { id: 'rule-a', kind: 'snapshot', retentionDays: 20, action: 'delete', priority: 2 },
    { id: 'rule-b', kind: 'snapshot', retentionDays: 40, action: 'retain', priority: 2 },
  ], { asOf });
  assert.equal(conflict.entries[0].reasonCode, 'conflicting_policy_rules');
  assert.deepEqual(conflict.entries[0].ambiguousPolicyIds, ['rule-a', 'rule-b']);
});

test('requires current metadata for a temporary override and legal holds take precedence', () => {
  const override = item('temporary-override', { override: { action: 'retain', reason: 'Audit still open',
    expiresAt: '2026-12-01T00:00:00Z', approver: 'manager@example.test' } });
  const active = buildRetentionPlan([override], policies, { asOf });
  assert.equal(active.entries[0].disposition, 'retain');
  assert.equal(active.entries[0].reasonCode, 'approved_temporary_override');
  assert.equal(active.entries[0].overrideActive, true);
  const expired = buildRetentionPlan([{ ...override, override: { ...override.override, expiresAt: '2026-11-01T00:00:00Z' } }], policies, { asOf });
  assert.equal(expired.entries[0].reasonCode, 'retention_period_expired');
  const held = buildRetentionPlan([{ ...override, legalHold: true }], policies, { asOf });
  assert.equal(held.entries[0].reasonCode, 'legal_hold');
  assert.equal(held.entries[0].overrideActive, false);
});

test('reports immutable inventory summaries by kind and handles empty inventories', () => {
  const plan = buildRetentionPlan([item('one'), item('two', { kind: 'export', classification: 'confidential' })], policies, { asOf });
  assert.deepEqual(plan.byKind.map((row) => row.kind), ['export', 'snapshot']);
  assert.equal(plan.byKind.find((row) => row.kind === 'snapshot').items, 1);
  assert.equal(plan.byKind.find((row) => row.kind === 'export').containsRestricted, 0);
  assert.equal(buildRetentionPlan([], policies, { asOf }).summary.items, 0);
  assert.equal(buildRetentionPlan([], [], { asOf }).summary.due, 0);
});

test('exports metadata rows and aggregates as formula-safe CSV', () => {
  const plan = buildRetentionPlan([item('=danger', { owner: '+owner', tags: ['temporary'] })], policies, { asOf });
  assert.match(retentionPlanToCsv(plan, 'summary'), /"asOf","items","due"/);
  assert.match(retentionPlanToCsv(plan, 'kinds'), /"kind","items","due"/);
  const entries = retentionPlanToCsv(plan);
  assert.match(entries, /"'=danger"/);
  assert.match(entries, /"'\+owner"/);
  assert.throws(() => retentionPlanToCsv({ format: 'wrong', version: 1, entries: [] }), /invalid retention plan/);
  assert.throws(() => retentionPlanToCsv(plan, 'raw'), /section must be/);
});

test('validates inventory, policies, timestamps, holds, overrides and category bounds', () => {
  assert.throws(() => buildRetentionPlan(null, policies, { asOf }), /inventory must be an array/);
  assert.throws(() => buildRetentionPlan([item('same'), item('same')], policies, { asOf }), /duplicate inventory item ID/);
  assert.throws(() => buildRetentionPlan([item('bad-class', { classification: 'secret' })], policies, { asOf }), /classification is unsupported/);
  assert.throws(() => buildRetentionPlan([item('bad-date', { createdAt: '2026-02-30' })], policies, { asOf }), /ISO date or timestamp/);
  assert.throws(() => buildRetentionPlan([item('bad-hold', { legalHold: 'yes' })], policies, { asOf }), /must be a boolean/);
  assert.throws(() => buildRetentionPlan([item('bad-size', { sizeBytes: -1 })], policies, { asOf }), /from 0 to/);
  assert.throws(() => buildRetentionPlan([item('bad-category', { dataCategories: ['password'] })], policies, { asOf }), /recognized data categories/);
  assert.throws(() => buildRetentionPlan([item('bad-override', { override: { action: 'ignore', reason: 'x', expiresAt: asOf } })], policies, { asOf }), /action is unsupported/);
  assert.throws(() => buildRetentionPlan([item('bad-override', { override: { action: 'retain', reason: 'x', expiresAt: asOf } })], policies, { asOf }), /approver/);
  assert.throws(() => buildRetentionPlan([], [{ id: 'all', retentionDays: 30, action: 'retain' }], { asOf }), /must match a kind/);
  assert.throws(() => buildRetentionPlan([], [{ id: 'bad', kind: 'snapshot', retentionDays: -1, action: 'delete' }], { asOf }), /from 0 to/);
  assert.throws(() => buildRetentionPlan([], [{ id: 'bad', kind: 'snapshot', retentionDays: 30, action: 'archive' }], { asOf }), /action is unsupported/);
  assert.throws(() => buildRetentionPlan([], policies, { asOf: 'not-a-date' }), /explicit UTC offset/);
});

test('keeps inventory and policy counts within documented bounds', () => {
  assert.throws(() => buildRetentionPlan(Array.from({ length: 100_001 }, (_, index) => item(`I${index}`)), [], { asOf }), /at most 100000 items/);
  assert.throws(() => buildRetentionPlan([], Array.from({ length: 501 }, (_, index) => ({ id: `P${index}`, kind: 'snapshot', retentionDays: 30, action: 'review' })), { asOf }), /at most 500 rules/);
});
