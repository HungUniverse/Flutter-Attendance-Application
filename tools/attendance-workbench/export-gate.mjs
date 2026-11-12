import { attendanceQueryToCsv, queryAttendanceSnapshot } from './snapshot-query.mjs';
import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-governed-export-plan';
const VERSION = 1;
const RECIPIENTS = new Set(['internal', 'partner', 'external', 'public']);
const MODES = new Set(['records', 'aggregate']);
const FIELDS = new Set(['studentId', 'studentName', 'studentEmail', 'sessionId', 'status']);
const GROUP_FIELDS = new Set(['sessionId', 'status']);
const MAX_ROWS = 10_000;
const MAX_AGGREGATE_GROUPS = 10_000;

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 256) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function integer(value, field, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  return value;
}

function timestamp(value, field) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) || !Number.isFinite(Date.parse(value))) {
    throw new TypeError(`${field} must be an ISO timestamp with an explicit UTC offset`);
  }
  return new Date(value).toISOString();
}

function idList(value, field, known, maximum) {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value) || value.length > maximum) throw new RangeError(`${field} must be an array with at most ${maximum} IDs`);
  const result = value.map((entry, index) => text(entry, `${field}[${index}]`, 256));
  if (new Set(result).size !== result.length) throw new TypeError(`${field} contains duplicate IDs`);
  const unknown = result.filter((entry) => !known.has(entry));
  if (unknown.length) throw new TypeError(`${field} contains unknown ID: ${unknown[0]}`);
  return result;
}

function normalizePolicy(value) {
  const policy = object(value, 'export policy');
  const recipients = policy.allowedRecipients;
  const purposes = policy.allowedPurposes;
  const fields = policy.allowedFields;
  if (!Array.isArray(recipients) || !recipients.length || recipients.some((item) => !RECIPIENTS.has(item)) || new Set(recipients).size !== recipients.length) {
    throw new TypeError('allowedRecipients must contain unique supported recipient types');
  }
  if (!Array.isArray(purposes) || !purposes.length || purposes.length > 100) throw new RangeError('allowedPurposes must contain 1 to 100 values');
  const normalizedPurposes = purposes.map((item, index) => text(item, `allowedPurposes[${index}]`, 120));
  if (new Set(normalizedPurposes).size !== normalizedPurposes.length) throw new TypeError('allowedPurposes contains duplicates');
  if (!Array.isArray(fields) || !fields.length || fields.some((item) => !FIELDS.has(item)) || new Set(fields).size !== fields.length) {
    throw new TypeError('allowedFields must contain unique supported fields');
  }
  const minGroupSize = integer(policy.minimumAggregateGroupSize ?? 5, 'minimumAggregateGroupSize', 2, 10_000);
  const maxRows = integer(policy.maximumRows ?? 1_000, 'maximumRows', 1, MAX_ROWS);
  const maxGroups = integer(policy.maximumAggregateGroups ?? 1_000, 'maximumAggregateGroups', 1, MAX_AGGREGATE_GROUPS);
  const maxValidityDays = integer(policy.maximumValidityDays ?? 30, 'maximumValidityDays', 1, 3650);
  if (policy.requiresApproval !== undefined && typeof policy.requiresApproval !== 'boolean') throw new TypeError('requiresApproval must be a boolean');
  return { id: text(policy.id, 'export policy ID', 120), allowedRecipients: [...recipients], allowedPurposes: normalizedPurposes,
    allowedFields: [...fields], minimumAggregateGroupSize: minGroupSize, maximumRows: maxRows,
    maximumAggregateGroups: maxGroups, maximumValidityDays: maxValidityDays, requiresApproval: policy.requiresApproval === true };
}

function normalizeRequest(value, snapshot) {
  const request = object(value, 'export request');
  const recipientType = text(request.recipientType, 'recipientType', 20);
  if (!RECIPIENTS.has(recipientType)) throw new TypeError('recipientType is unsupported');
  const mode = text(request.mode, 'mode', 20);
  if (!MODES.has(mode)) throw new TypeError('mode must be records or aggregate');
  const requestedAt = timestamp(request.requestedAt, 'requestedAt');
  const validUntil = timestamp(request.validUntil, 'validUntil');
  if (Date.parse(validUntil) <= Date.parse(requestedAt)) throw new RangeError('validUntil must be after requestedAt');
  const fields = request.fields ?? ['studentId', 'sessionId', 'status'];
  if (!Array.isArray(fields) || fields.length < 1 || fields.length > FIELDS.size || fields.some((field) => !FIELDS.has(field)) || new Set(fields).size !== fields.length) {
    throw new TypeError('fields must contain 1 to 5 unique supported fields');
  }
  const groupBy = request.groupBy ?? [];
  if (!Array.isArray(groupBy) || groupBy.length > 2 || groupBy.some((field) => !GROUP_FIELDS.has(field)) || new Set(groupBy).size !== groupBy.length) {
    throw new TypeError('groupBy must contain up to 2 unique aggregate-safe fields');
  }
  if (mode === 'aggregate' && groupBy.length === 0) throw new TypeError('aggregate mode requires at least one groupBy field');
  if (mode === 'records' && groupBy.length) throw new TypeError('records mode cannot use groupBy');
  const includeUnrecorded = request.includeUnrecorded ?? true;
  if (typeof includeUnrecorded !== 'boolean') throw new TypeError('includeUnrecorded must be a boolean');
  const statuses = request.statuses ?? null;
  if (statuses !== null && (!Array.isArray(statuses) || statuses.length < 1 || statuses.length > 3 ||
      statuses.some((status) => !['present', 'absent', 'missing'].includes(status)) || new Set(statuses).size !== statuses.length)) {
    throw new TypeError('statuses must contain unique present, absent or missing values');
  }
  return {
    id: text(request.id, 'request ID', 120),
    recipient: text(request.recipient, 'recipient', 200),
    recipientType,
    purpose: text(request.purpose, 'purpose', 300),
    requestedAt,
    validUntil,
    mode,
    fields: [...fields],
    groupBy: [...groupBy],
    studentIds: idList(request.studentIds, 'studentIds', new Set(snapshot.roster.map((student) => student.id)), 100_000),
    sessionIds: idList(request.sessionIds, 'sessionIds', new Set(snapshot.sessionIds), 10_000),
    statuses: statuses === null ? null : [...statuses],
    includeUnrecorded,
  };
}

function queryForRequest(snapshot, request, policy) {
  if (request.studentIds?.length === 0 || request.sessionIds?.length === 0) {
    return queryAttendanceSnapshot(createAttendanceSnapshot([], [], []), {
      columns: request.mode === 'records' ? request.fields : ['studentId', 'sessionId', 'status'],
      groupBy: request.groupBy, minimumGroupSize: policy.minimumAggregateGroupSize,
      includeUnrecorded: request.includeUnrecorded, maxMatches: 1,
    });
  }
  const filters = [];
  if (request.studentIds !== null) filters.push({ field: 'studentId', op: 'in', value: request.studentIds.length ? request.studentIds : ['__no_such_student__'] });
  if (request.sessionIds !== null) filters.push({ field: 'sessionId', op: 'in', value: request.sessionIds.length ? request.sessionIds : ['__no_such_session__'] });
  if (request.statuses !== null) {
    filters.push({ field: 'status', op: 'in', value: request.statuses });
  }
  const where = filters.length === 0 ? null : filters.length === 1 ? filters[0] : { all: filters };
  const columns = request.mode === 'records' ? request.fields : ['studentId', 'sessionId', 'status'];
  return queryAttendanceSnapshot(snapshot, {
    where, columns, includeUnrecorded: request.includeUnrecorded,
    groupBy: request.groupBy, minimumGroupSize: policy.minimumAggregateGroupSize,
    maxMatches: 250_000, pageSize: Math.min(500, policy.maximumRows),
  });
}

function issuesFor(policy, request, query, now) {
  const issues = [];
  const deny = (code, message) => issues.push({ code, blocking: true, message });
  const review = (code, message) => issues.push({ code, blocking: false, message });
  if (!policy.allowedRecipients.includes(request.recipientType)) deny('recipient_not_allowed', 'The recipient type is not allowed by the supplied policy.');
  if (!policy.allowedPurposes.includes(request.purpose)) deny('purpose_not_allowed', 'The stated purpose is not allowed by the supplied policy.');
  const requestedFields = request.mode === 'records' ? request.fields : request.groupBy;
  for (const field of requestedFields) if (!policy.allowedFields.includes(field)) deny('field_not_allowed', `Requested field ${field} is not allowed by the supplied policy.`);
  if (request.mode === 'records' && ['external', 'public'].includes(request.recipientType)) {
    review('external_record_export', 'External record-level exports require a human approval.');
  }
  if (policy.requiresApproval) review('policy_requires_approval', 'The supplied policy requires a human approval.');
  const validityDays = Math.ceil((Date.parse(request.validUntil) - Date.parse(request.requestedAt)) / 86_400_000);
  if (validityDays > policy.maximumValidityDays) deny('validity_exceeds_policy', 'The requested validity period exceeds the policy limit.');
  if (Date.parse(now) > Date.parse(request.validUntil)) deny('request_expired', 'The request has already expired.');
  if (Date.parse(now) < Date.parse(request.requestedAt)) deny('request_not_started', 'The request validity window has not started.');
  if (query.summary.matchedRows > policy.maximumRows) deny('row_limit_exceeded', 'The selected scope exceeds the policy row limit.');
  if (request.mode === 'aggregate' && query.groups.length > policy.maximumAggregateGroups) deny('group_limit_exceeded', 'The aggregate has more groups than the policy permits.');
  if (request.mode === 'aggregate' && !['internal', 'partner', 'external', 'public'].includes(request.recipientType)) deny('invalid_aggregate_recipient', 'The recipient type cannot receive aggregates.');
  return issues;
}

function collectPages(snapshot, request, policy, first) {
  if (first.summary.matchedRows > policy.maximumRows) return null;
  if (request.mode === 'aggregate') return first.groups;
  const rows = [...first.rows];
  for (let page = 2; page <= first.summary.totalPages; page++) {
    const next = queryAttendanceSnapshot(snapshot, {
      where: first.query.where, columns: request.fields, includeUnrecorded: request.includeUnrecorded,
      page, pageSize: Math.min(500, policy.maximumRows), maxMatches: policy.maximumRows,
    });
    rows.push(...next.rows);
  }
  return rows;
}

/** Evaluate a local export request against a caller-supplied least-privilege policy. */
export function planGovernedExport(snapshotValue, policyValue, requestValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const policy = normalizePolicy(policyValue);
  const request = normalizeRequest(requestValue, snapshot);
  const options = object(optionsValue, 'export evaluation options');
  const now = timestamp(options.asOf ?? new Date().toISOString(), 'asOf');
  const query = queryForRequest(snapshot, request, policy);
  const issues = issuesFor(policy, request, query, now);
  const blocking = issues.some((issue) => issue.blocking);
  const approvalNeeded = issues.some((issue) => issue.code === 'external_record_export' || issue.code === 'policy_requires_approval');
  const status = blocking ? 'rejected' : approvalNeeded ? 'needs_approval' : 'ready';
  const rows = status === 'ready' ? collectPages(snapshot, request, policy, query) : null;
  return {
    format: FORMAT,
    version: VERSION,
    policyId: policy.id,
    evaluatedAt: now,
    request: { ...request, statuses: request.statuses === null ? null : [...request.statuses] },
    status,
    issues,
    summary: { matchedRows: query.summary.matchedRows, recordedRows: query.summary.recordedRows,
      suppressedGroups: query.groups?.filter((group) => group.suppressed).length ?? 0,
      outputRows: rows?.length ?? 0, validityDays: Math.ceil((Date.parse(request.validUntil) - Date.parse(request.requestedAt)) / 86_400_000),
      fields: request.mode === 'records' ? [...request.fields] : [...request.groupBy] },
    payload: status === 'ready' ? { mode: request.mode, rows: request.mode === 'records' ? rows : null,
      groups: request.mode === 'aggregate' ? rows : null } : null,
    approval: null,
    notice: 'This plan only returns an in-memory minimized preview. It never writes a file, sends data, or changes the source snapshot.',
  };
}

/** Release a held preview after a named reviewer records an explicit approval. */
export function approveGovernedExport(snapshotValue, policyValue, requestValue, approvalValue, optionsValue = {}) {
  const approval = object(approvalValue, 'export approval');
  const actor = text(approval.actor, 'approval actor', 120);
  const reason = text(approval.reason, 'approval reason', 1_000);
  const at = timestamp(approval.at, 'approval timestamp');
  const requestedAt = timestamp(requestValue?.requestedAt, 'requestedAt');
  const validUntil = timestamp(requestValue?.validUntil, 'validUntil');
  if (Date.parse(validUntil) <= Date.parse(requestedAt)) throw new RangeError('validUntil must be after requestedAt');
  if (Date.parse(at) < Date.parse(requestedAt) || Date.parse(at) > Date.parse(validUntil)) {
    throw new RangeError('approval timestamp must fall within the request validity window');
  }
  const plan = planGovernedExport(snapshotValue, policyValue, requestValue, { ...optionsValue, asOf: at });
  if (plan.status !== 'needs_approval') throw new Error(`export request is ${plan.status} and cannot be approved`);
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const policy = normalizePolicy(policyValue);
  const query = queryForRequest(snapshot, plan.request, policy);
  const payloadRows = collectPages(snapshot, plan.request, policy, query);
  if (!payloadRows) throw new Error('export request exceeds the policy row limit');
  return { ...plan, status: 'ready', payload: { mode: plan.request.mode,
    rows: plan.request.mode === 'records' ? payloadRows : null, groups: plan.request.mode === 'aggregate' ? payloadRows : null },
  approval: { actor, reason, at } };
}

/** Export an approved payload using only fields that were explicitly requested. */
export function governedExportToCsv(planValue) {
  const plan = object(planValue, 'governed export plan');
  if (plan.format !== FORMAT || plan.version !== VERSION) throw new TypeError('invalid governed export plan');
  if (plan.status !== 'ready' || !plan.payload) throw new TypeError('export payload is unavailable until the request is approved');
  if (plan.payload.mode === 'records') return attendanceQueryToCsv({ format: 'attendance-snapshot-query', version: 1,
    query: { columns: plan.request.fields }, rows: plan.payload.rows });
  if (plan.payload.mode === 'aggregate') {
    const headers = [...plan.request.groupBy, 'studentCount', 'sessionCount', 'cellCount', 'present', 'absent', 'missing', 'attendanceRate', 'coverage', 'suppressed'];
    const cell = (value) => {
      let textValue = value === undefined || value === null ? '' : String(value);
      if (/^[\t\r\n ]*[=+\-@]/.test(textValue)) textValue = `'${textValue}`;
      return `"${textValue.replaceAll('"', '""')}"`;
    };
    return [headers, ...plan.payload.groups.map((row) => headers.map((header) => row[header]))]
      .map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  }
  throw new TypeError('governed export payload mode is unsupported');
}
