const FORMAT = 'attendance-retention-plan';
const VERSION = 1;
const CLASSIFICATIONS = new Set(['public', 'internal', 'confidential', 'restricted']);
const ACTIONS = new Set(['retain', 'review', 'redact', 'delete']);
const CATEGORIES = new Set(['student_name', 'student_id', 'email', 'attendance', 'review_note', 'evidence_reference', 'schedule', 'other']);
const MAX_ITEMS = 100_000;
const MAX_POLICIES = 500;

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 256) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  }
  return value.trim();
}

function optionalText(value, field, maximum = 256) {
  return value === undefined || value === null || value === '' ? null : text(value, field, maximum);
}

function integer(value, field, minimum, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}

function timestamp(value, field, optional = false) {
  if (optional && (value === undefined || value === null || value === '')) return null;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2}))?$/.test(value) ||
      !Number.isFinite(Date.parse(value)) || new Date(`${value.slice(0, 10)}T00:00:00.000Z`).toISOString().slice(0, 10) !== value.slice(0, 10)) {
    throw new TypeError(`${field} must be an ISO date or timestamp with an explicit UTC offset`);
  }
  return new Date(value.length === 10 ? `${value}T00:00:00.000Z` : value).toISOString();
}

function normalizeCategories(value, field) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > CATEGORIES.size || value.some((category) => !CATEGORIES.has(category)) ||
      new Set(value).size !== value.length) throw new TypeError(`${field} must contain unique recognized data categories`);
  return [...value].sort();
}

function normalizeTags(value, field) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 30) throw new RangeError(`${field} must contain at most 30 tags`);
  const tags = value.map((tag, index) => text(tag, `${field}[${index}]`, 80));
  if (new Set(tags).size !== tags.length) throw new TypeError(`${field} contains duplicate tags`);
  return tags.sort((left, right) => left.localeCompare(right));
}

function normalizeInventory(value) {
  if (!Array.isArray(value) || value.length > MAX_ITEMS) throw new RangeError(`inventory must be an array with at most ${MAX_ITEMS} items`);
  const ids = new Set();
  return value.map((entry, index) => {
    object(entry, `inventory[${index}]`);
    const id = text(entry.id, `inventory[${index}].id`, 120);
    if (ids.has(id)) throw new TypeError(`duplicate inventory item ID: ${id}`);
    ids.add(id);
    if (!CLASSIFICATIONS.has(entry.classification)) throw new TypeError(`inventory[${index}].classification is unsupported`);
    if (entry.legalHold !== undefined && typeof entry.legalHold !== 'boolean') throw new TypeError(`inventory[${index}].legalHold must be a boolean`);
    return {
      id,
      kind: text(entry.kind, `inventory[${index}].kind`, 80),
      classification: entry.classification,
      createdAt: timestamp(entry.createdAt, `inventory[${index}].createdAt`),
      lastAccessedAt: timestamp(entry.lastAccessedAt, `inventory[${index}].lastAccessedAt`, true),
      owner: optionalText(entry.owner, `inventory[${index}].owner`, 120),
      sizeBytes: entry.sizeBytes === undefined ? null : integer(entry.sizeBytes, `inventory[${index}].sizeBytes`, 0, 10_000_000_000_000),
      dataCategories: normalizeCategories(entry.dataCategories, `inventory[${index}].dataCategories`),
      tags: normalizeTags(entry.tags, `inventory[${index}].tags`),
      legalHold: entry.legalHold === true,
      override: entry.override === undefined ? null : normalizeOverride(entry.override, `inventory[${index}].override`),
    };
  });
}

function normalizeOverride(value, field) {
  object(value, field);
  const action = text(value.action, `${field}.action`, 20);
  if (!ACTIONS.has(action)) throw new TypeError(`${field}.action is unsupported`);
  return {
    action,
    reason: text(value.reason, `${field}.reason`, 1_000),
    expiresAt: timestamp(value.expiresAt, `${field}.expiresAt`),
    approver: text(value.approver, `${field}.approver`, 120),
  };
}

function normalizePolicies(value) {
  if (!Array.isArray(value) || value.length > MAX_POLICIES) throw new RangeError(`policies must be an array with at most ${MAX_POLICIES} rules`);
  const ids = new Set();
  return value.map((entry, index) => {
    object(entry, `policies[${index}]`);
    const id = text(entry.id, `policies[${index}].id`, 120);
    if (ids.has(id)) throw new TypeError(`duplicate policy ID: ${id}`);
    ids.add(id);
    const action = text(entry.action, `policies[${index}].action`, 20);
    if (!ACTIONS.has(action)) throw new TypeError(`policies[${index}].action is unsupported`);
    if (entry.kind === undefined && entry.classification === undefined && (!Array.isArray(entry.tagsAny) || !entry.tagsAny.length)) {
      throw new TypeError(`policies[${index}] must match a kind, classification or tag`);
    }
    if (entry.classification !== undefined && !CLASSIFICATIONS.has(entry.classification)) throw new TypeError(`policies[${index}].classification is unsupported`);
    return {
      id,
      kind: optionalText(entry.kind, `policies[${index}].kind`, 80),
      classification: entry.classification ?? null,
      tagsAny: normalizeTags(entry.tagsAny, `policies[${index}].tagsAny`),
      retentionDays: integer(entry.retentionDays, `policies[${index}].retentionDays`, 0, 36_500),
      reviewWindowDays: integer(entry.reviewWindowDays ?? 30, `policies[${index}].reviewWindowDays`, 0, 3_650),
      action,
      priority: integer(entry.priority ?? 0, `policies[${index}].priority`, 0, 1_000_000),
      description: optionalText(entry.description, `policies[${index}].description`, 500),
    };
  });
}

function matches(policy, item) {
  if (policy.kind && policy.kind !== item.kind) return false;
  if (policy.classification && policy.classification !== item.classification) return false;
  if (policy.tagsAny.length && !policy.tagsAny.some((tag) => item.tags.includes(tag))) return false;
  return true;
}

function specificity(policy) {
  return Number(Boolean(policy.kind)) + Number(Boolean(policy.classification)) + Number(policy.tagsAny.length > 0);
}

function selectPolicy(policies, item) {
  const candidates = policies.filter((policy) => matches(policy, item));
  if (!candidates.length) return { selected: null, ambiguous: [] };
  candidates.sort((left, right) => right.priority - left.priority || specificity(right) - specificity(left) || left.id.localeCompare(right.id));
  const first = candidates[0];
  const tied = candidates.filter((policy) => policy.priority === first.priority && specificity(policy) === specificity(first));
  if (new Set(tied.map((policy) => `${policy.retentionDays}/${policy.reviewWindowDays}/${policy.action}`)).size > 1) {
    return { selected: null, ambiguous: tied.map((policy) => policy.id) };
  }
  return { selected: first, ambiguous: [] };
}

function daysBetween(start, end) {
  return Math.floor((Date.parse(end) - Date.parse(start)) / 86_400_000);
}

function addDays(value, amount) {
  return new Date(Date.parse(value) + amount * 86_400_000).toISOString();
}

function evaluateItem(item, policies, asOf) {
  const selected = selectPolicy(policies, item);
  const ageDays = Math.max(0, daysBetween(item.createdAt, asOf));
  const inactiveDays = item.lastAccessedAt ? Math.max(0, daysBetween(item.lastAccessedAt, asOf)) : null;
  const common = { id: item.id, kind: item.kind, classification: item.classification, owner: item.owner,
    sizeBytes: item.sizeBytes, dataCategories: item.dataCategories, ageDays, inactiveDays,
    legalHold: item.legalHold, policyId: selected.selected?.id ?? null, ambiguousPolicyIds: selected.ambiguous };
  if (item.legalHold) return { ...common, disposition: 'retain', reasonCode: 'legal_hold', actionDue: false,
    requiresApproval: true, expiryAt: null, overrideActive: false };
  if (item.override && Date.parse(item.override.expiresAt) >= Date.parse(asOf)) {
    return { ...common, disposition: item.override.action, reasonCode: 'approved_temporary_override', actionDue: false,
      requiresApproval: true, expiryAt: selected.selected ? addDays(item.createdAt, selected.selected.retentionDays) : null,
      overrideActive: true, overrideReason: item.override.reason, overrideApprover: item.override.approver,
      overrideExpiresAt: item.override.expiresAt };
  }
  if (selected.ambiguous.length) return { ...common, disposition: 'review', reasonCode: 'conflicting_policy_rules', actionDue: true,
    requiresApproval: true, expiryAt: null, overrideActive: false };
  if (!selected.selected) return { ...common, disposition: 'review', reasonCode: 'no_matching_policy', actionDue: true,
    requiresApproval: true, expiryAt: null, overrideActive: false };
  const policy = selected.selected;
  const expiryAt = addDays(item.createdAt, policy.retentionDays);
  const daysUntilExpiry = daysBetween(asOf, expiryAt);
  if (daysUntilExpiry < 0) return { ...common, disposition: policy.action, reasonCode: 'retention_period_expired', actionDue: true,
    requiresApproval: true, expiryAt, daysUntilExpiry, overrideActive: false };
  if (daysUntilExpiry <= policy.reviewWindowDays) return { ...common, disposition: 'review', reasonCode: 'expiry_review_window', actionDue: true,
    requiresApproval: true, expiryAt, daysUntilExpiry, overrideActive: false };
  return { ...common, disposition: 'retain', reasonCode: 'within_retention_period', actionDue: false,
    requiresApproval: false, expiryAt, daysUntilExpiry, overrideActive: false };
}

function dispositionCounts(rows) {
  const counts = {};
  for (const row of rows) counts[row.disposition] = (counts[row.disposition] ?? 0) + 1;
  return counts;
}

/** Build a metadata-only retention review; it never reads, deletes or rewrites files. */
export function buildRetentionPlan(inventoryValue, policiesValue, optionsValue = {}) {
  const options = object(optionsValue, 'retention options');
  const asOf = timestamp(options.asOf ?? new Date().toISOString(), 'asOf');
  const inventory = normalizeInventory(inventoryValue);
  const policies = normalizePolicies(policiesValue);
  const entries = inventory.map((item) => evaluateItem(item, policies, asOf));
  const sizeBytes = entries.reduce((sum, entry) => sum + BigInt(entry.sizeBytes ?? 0), 0n);
  if (sizeBytes > BigInt(Number.MAX_SAFE_INTEGER)) throw new RangeError('inventory sizeBytes total exceeds the safe integer range');
  const due = entries.filter((entry) => entry.actionDue);
  const byKind = new Map();
  for (const entry of entries) {
    if (!byKind.has(entry.kind)) byKind.set(entry.kind, []);
    byKind.get(entry.kind).push(entry);
  }
  const summaryByKind = [...byKind].sort(([left], [right]) => left.localeCompare(right)).map(([kind, rows]) => ({
    kind, items: rows.length, due: rows.filter((row) => row.actionDue).length,
    byDisposition: dispositionCounts(rows), containsRestricted: rows.filter((row) => row.classification === 'restricted').length,
  }));
  return {
    format: FORMAT,
    version: VERSION,
    asOf,
    summary: { items: entries.length, due: due.length, requiresApproval: entries.filter((entry) => entry.requiresApproval).length,
      legalHold: entries.filter((entry) => entry.reasonCode === 'legal_hold').length,
      policyGaps: entries.filter((entry) => entry.reasonCode === 'no_matching_policy').length,
      ambiguousPolicies: entries.filter((entry) => entry.reasonCode === 'conflicting_policy_rules').length,
      byDisposition: dispositionCounts(entries), sizeBytes: Number(sizeBytes) },
    byKind: summaryByKind,
    entries,
    notice: 'This is a planning report from supplied metadata. It performs no deletion, redaction, file access, or policy enforcement.',
  };
}

/** Export a compact aggregate or a metadata-only inventory section as CSV. */
export function retentionPlanToCsv(planValue, section = 'entries') {
  const plan = object(planValue, 'retention plan');
  if (plan.format !== FORMAT || plan.version !== VERSION || !Array.isArray(plan.entries)) throw new TypeError('invalid retention plan');
  const cell = (value) => {
    let textValue = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(textValue)) textValue = `'${textValue}`;
    return `"${textValue.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (section === 'summary') return csv(['asOf', 'items', 'due', 'requiresApproval', 'legalHold', 'policyGaps', 'ambiguousPolicies', 'sizeBytes'], [[
    plan.asOf, plan.summary.items, plan.summary.due, plan.summary.requiresApproval, plan.summary.legalHold,
    plan.summary.policyGaps, plan.summary.ambiguousPolicies, plan.summary.sizeBytes,
  ]]);
  if (section === 'kinds') return csv(['kind', 'items', 'due', 'containsRestricted', 'byDisposition'], plan.byKind.map((item) => [
    item.kind, item.items, item.due, item.containsRestricted, JSON.stringify(item.byDisposition),
  ]));
  if (section === 'entries') return csv(['id', 'kind', 'classification', 'owner', 'sizeBytes', 'dataCategories', 'ageDays',
    'inactiveDays', 'disposition', 'reasonCode', 'policyId', 'expiryAt', 'daysUntilExpiry', 'legalHold', 'requiresApproval'],
  plan.entries.map((entry) => [entry.id, entry.kind, entry.classification, entry.owner, entry.sizeBytes,
    entry.dataCategories.join('|'), entry.ageDays, entry.inactiveDays, entry.disposition, entry.reasonCode,
    entry.policyId, entry.expiryAt, entry.daysUntilExpiry, entry.legalHold, entry.requiresApproval]));
  throw new TypeError('section must be entries, kinds or summary');
}
