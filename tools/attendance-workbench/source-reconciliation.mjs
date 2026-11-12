import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-source-reconciliation';
const VERSION = 1;
const IDENTITY_POLICIES = new Set(['require-decision', 'prefer-priority']);
const RECORD_POLICIES = new Set(['require-decision', 'prefer-priority', 'prefer-present', 'prefer-absent']);
const FIELDS = ['name', 'email'];

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 256) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${field} must be non-empty text no longer than ${maximum} characters`);
  }
  return value.trim();
}

function nonNegative(value, field, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < 0 || value > maximum) {
    throw new RangeError(`${field} must be a non-negative safe integer${maximum < Number.MAX_SAFE_INTEGER ? ` up to ${maximum}` : ''}`);
  }
  return value;
}

function boolean(value, field, fallback = false) {
  if (value === undefined) return fallback;
  if (typeof value !== 'boolean') throw new TypeError(`${field} must be a boolean`);
  return value;
}

function stableId(value) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36).toUpperCase().padStart(7, '0');
}

function mappingKey(sourceId, inputId) {
  return `${sourceId}\u0000${inputId}`;
}

function normalizedIdentity(value, field) {
  const normalized = String(value ?? '').normalize('NFKC').trim().replace(/\s+/g, ' ');
  return field === 'email' ? normalized.toLowerCase() : normalized.toLocaleLowerCase('vi');
}

function normalizeSources(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 50) {
    throw new RangeError('sources must contain from 1 to 50 entries');
  }
  const seen = new Set();
  return value.map((entry, index) => {
    object(entry, `sources[${index}]`);
    const id = text(entry.id, `sources[${index}].id`, 64);
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id)) throw new TypeError(`sources[${index}].id must use letters, numbers, dot, underscore or hyphen`);
    if (seen.has(id)) throw new TypeError(`duplicate source id: ${id}`);
    seen.add(id);
    const priority = nonNegative(entry.priority ?? 0, `sources[${index}].priority`, 1_000_000);
    const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(entry.snapshot));
    return { id, label: text(entry.label ?? id, `sources[${index}].label`, 160), priority, snapshot };
  });
}

function normalizeMappings(value, field, sourceIds, inputKey, targetKey) {
  if (value === undefined) return new Map();
  if (!Array.isArray(value) || value.length > 1_000_000) throw new RangeError(`${field} must be an array with at most 1000000 mappings`);
  const mapping = new Map();
  for (let index = 0; index < value.length; index++) {
    const entry = object(value[index], `${field}[${index}]`);
    const sourceId = text(entry.sourceId, `${field}[${index}].sourceId`, 64);
    if (!sourceIds.has(sourceId)) throw new TypeError(`${field}[${index}] refers to unknown source ${sourceId}`);
    const from = text(entry[inputKey], `${field}[${index}].${inputKey}`);
    const to = text(entry[targetKey], `${field}[${index}].${targetKey}`);
    const key = mappingKey(sourceId, from);
    if (mapping.has(key)) throw new TypeError(`${field} contains a duplicate mapping for ${sourceId}/${from}`);
    mapping.set(key, to);
  }
  return mapping;
}

function normalizeTargetRoster(value) {
  if (value === undefined) return null;
  if (!Array.isArray(value) || value.length > 250_000) throw new RangeError('targetRoster must be an array with at most 250000 students');
  const ids = new Set();
  return value.map((entry, index) => {
    object(entry, `targetRoster[${index}]`);
    const student = {
      id: text(entry.id, `targetRoster[${index}].id`),
      name: text(entry.name, `targetRoster[${index}].name`),
      email: text(entry.email, `targetRoster[${index}].email`),
    };
    if (ids.has(student.id)) throw new TypeError(`targetRoster contains duplicate student ID ${student.id}`);
    ids.add(student.id);
    return student;
  });
}

function normalizeTargetSessions(value) {
  if (value === undefined) return null;
  if (!Array.isArray(value) || value.length > 500) throw new RangeError('targetSessionIds must be an array with at most 500 session IDs');
  const ids = value.map((id, index) => text(id, `targetSessionIds[${index}]`));
  if (new Set(ids).size !== ids.length) throw new TypeError('targetSessionIds must be unique');
  return ids;
}

function normalizeResolutions(value, sourceIds) {
  if (value === undefined) return new Map();
  if (!Array.isArray(value) || value.length > 1_000_000) throw new RangeError('resolutions must be an array with at most 1000000 entries');
  const resolutions = new Map();
  for (let index = 0; index < value.length; index++) {
    const entry = object(value[index], `resolutions[${index}]`);
    const conflictId = text(entry.conflictId, `resolutions[${index}].conflictId`, 64);
    if (resolutions.has(conflictId)) throw new TypeError(`duplicate resolution for conflict ${conflictId}`);
    const sourceId = entry.sourceId === undefined ? null : text(entry.sourceId, `resolutions[${index}].sourceId`, 64);
    if (sourceId && !sourceIds.has(sourceId)) throw new TypeError(`resolution refers to unknown source ${sourceId}`);
    const valueChoice = entry.value === undefined ? null : text(entry.value, `resolutions[${index}].value`, 256);
    if (Boolean(sourceId) === Boolean(valueChoice)) throw new TypeError(`resolution ${conflictId} must contain exactly one of sourceId or value`);
    resolutions.set(conflictId, { sourceId, value: valueChoice, used: false });
  }
  return resolutions;
}

function compareSources(left, right) {
  return right.priority - left.priority || left.id.localeCompare(right.id);
}

function distinctCandidates(candidates, field) {
  const unique = new Map();
  for (const candidate of candidates) {
    const identity = normalizedIdentity(candidate.value, field);
    if (!unique.has(identity)) unique.set(identity, candidate);
  }
  return [...unique.values()];
}

function buildConflict(kind, target, candidates, field = null) {
  const valueSignature = candidates.map((candidate) => `${candidate.sourceId}:${candidate.value}`).sort().join('|');
  const conflictId = `${kind}-${stableId(`${target}\u0000${field ?? ''}\u0000${valueSignature}`)}`;
  return {
    conflictId,
    kind,
    target,
    ...(field ? { field } : {}),
    candidates: candidates.map((candidate) => ({ sourceId: candidate.sourceId, value: candidate.value })),
    status: 'unresolved',
    selectedValue: null,
    selectedSourceId: null,
  };
}

function resolveConflict(conflict, candidates, resolutions, preferredSourceId = null) {
  const resolution = resolutions.get(conflict.conflictId);
  if (resolution) {
    resolution.used = true;
    const selected = resolution.sourceId
      ? candidates.find((candidate) => candidate.sourceId === resolution.sourceId)
      : candidates.find((candidate) => candidate.value === resolution.value);
    if (!selected) throw new TypeError(`resolution for ${conflict.conflictId} does not match a candidate`);
    conflict.status = 'resolved';
    conflict.selectedValue = selected.value;
    conflict.selectedSourceId = selected.sourceId;
    return selected;
  }
  if (preferredSourceId) {
    const preferred = candidates.find((candidate) => candidate.sourceId === preferredSourceId);
    if (preferred) {
      conflict.status = 'resolved';
      conflict.selectedValue = preferred.value;
      conflict.selectedSourceId = preferred.sourceId;
      return preferred;
    }
  }
  return null;
}

function chooseByPriority(conflict, candidates, sources, resolutions) {
  const explicit = resolveConflict(conflict, candidates, resolutions);
  if (explicit) return explicit;
  const ranked = [...candidates].sort((left, right) => compareSources(sources.get(left.sourceId), sources.get(right.sourceId)));
  const selected = ranked[0] ?? null;
  if (selected) {
    conflict.status = 'resolved';
    conflict.selectedValue = selected.value;
    conflict.selectedSourceId = selected.sourceId;
  }
  return selected;
}

function resolveIdentity(targetId, field, entries, options, conflicts, issues) {
  const candidates = distinctCandidates([...entries].sort((left, right) => compareSources(
    options.sourcesById.get(left.sourceId), options.sourcesById.get(right.sourceId))).map((entry) => ({
      sourceId: entry.sourceId, value: entry.student[field], priority: entry.priority,
    })), field)
    .sort((left, right) => compareSources({ id: left.sourceId, priority: left.priority }, { id: right.sourceId, priority: right.priority }));
  if (options.targetRosterById?.has(targetId)) {
    const target = options.targetRosterById.get(targetId)[field];
    const differs = candidates.some((candidate) => normalizedIdentity(candidate.value, field) !== normalizedIdentity(target, field));
    if (differs) {
      const conflict = buildConflict('identity', targetId, [{ sourceId: 'target-roster', value: target }, ...candidates], field);
      conflict.status = 'resolved';
      conflict.selectedValue = target;
      conflict.selectedSourceId = 'target-roster';
      conflicts.push(conflict);
    }
    return target;
  }
  if (!candidates.length) {
    issues.push({ code: 'identity_missing', target: targetId, field, blocking: true });
    return '';
  }
  if (candidates.length === 1) return candidates[0].value;
  const conflict = buildConflict('identity', targetId, candidates, field);
  let selected = null;
  if (options.identityConflictPolicy === 'prefer-priority') selected = chooseByPriority(conflict, candidates, options.sourcesById, options.resolutions);
  else selected = resolveConflict(conflict, candidates, options.resolutions);
  if (!selected) issues.push({ code: 'identity_conflict_unresolved', target: targetId, field, conflictId: conflict.conflictId, blocking: true });
  conflicts.push(conflict);
  return selected?.value ?? candidates[0].value;
}

function resolveRecordConflict(key, candidates, options, conflicts, issues) {
  const uniqueStatuses = [...new Set(candidates.map((candidate) => candidate.status))];
  if (uniqueStatuses.length === 1) {
    const chosen = [...candidates].sort((left, right) => compareSources(options.sourcesById.get(left.sourceId), options.sourcesById.get(right.sourceId)))[0];
    return { status: chosen.status, sourceId: chosen.sourceId, duplicateCount: candidates.length };
  }
  const conflict = buildConflict('record', key, candidates.map(({ sourceId, status }) => ({ sourceId, value: status })));
  let selected = null;
  const explicit = resolveConflict(conflict, candidates.map((candidate) => ({ sourceId: candidate.sourceId, value: candidate.status })), options.resolutions);
  if (explicit) selected = { sourceId: explicit.sourceId, status: explicit.value };
  else if (options.recordConflictPolicy === 'prefer-priority') {
    const ranked = [...candidates].sort((left, right) => compareSources(options.sourcesById.get(left.sourceId), options.sourcesById.get(right.sourceId)));
    selected = { sourceId: ranked[0].sourceId, status: ranked[0].status };
  } else if (options.recordConflictPolicy === 'prefer-present' && uniqueStatuses.includes('present')) {
    const selectedCandidate = candidates.find((candidate) => candidate.status === 'present');
    selected = { sourceId: selectedCandidate.sourceId, status: 'present' };
  } else if (options.recordConflictPolicy === 'prefer-absent' && uniqueStatuses.includes('absent')) {
    const selectedCandidate = candidates.find((candidate) => candidate.status === 'absent');
    selected = { sourceId: selectedCandidate.sourceId, status: 'absent' };
  }
  if (selected) {
    conflict.status = 'resolved';
    conflict.selectedValue = selected.status;
    conflict.selectedSourceId = selected.sourceId;
  } else {
    issues.push({ code: 'record_conflict_unresolved', target: key, conflictId: conflict.conflictId, blocking: true });
  }
  conflicts.push(conflict);
  return { ...selected, duplicateCount: candidates.length };
}

function normalizeOptions(value, sources) {
  const options = object(value, 'reconciliation options');
  const sourceIds = new Set(sources.map((source) => source.id));
  const targetRoster = normalizeTargetRoster(options.targetRoster);
  const targetRosterById = targetRoster ? new Map(targetRoster.map((student) => [student.id, student])) : null;
  const targetSessionIds = normalizeTargetSessions(options.targetSessionIds);
  const sourceIdsById = new Map(sources.map((source) => [source.id, source]));
  const identityConflictPolicy = options.identityConflictPolicy ?? 'require-decision';
  if (!IDENTITY_POLICIES.has(identityConflictPolicy)) throw new TypeError('identityConflictPolicy must be require-decision or prefer-priority');
  const recordConflictPolicy = options.recordConflictPolicy ?? 'require-decision';
  if (!RECORD_POLICIES.has(recordConflictPolicy)) throw new TypeError('recordConflictPolicy must be a supported record conflict policy');
  if (options.duplicatePolicy !== undefined && options.duplicatePolicy !== 'count-agreeing') {
    throw new TypeError('duplicatePolicy must be count-agreeing');
  }
  const minimumAgreement = nonNegative(options.minimumAgreement ?? 1, 'minimumAgreement', 50);
  if (minimumAgreement < 1) throw new RangeError('minimumAgreement must be at least 1');
  return {
    studentMappings: normalizeMappings(options.studentMappings, 'studentMappings', sourceIds, 'sourceStudentId', 'targetStudentId'),
    sessionMappings: normalizeMappings(options.sessionMappings, 'sessionMappings', sourceIds, 'sourceSessionId', 'targetSessionId'),
    targetRoster,
    targetRosterById,
    targetSessionIds,
    sourcesById: sourceIdsById,
    identityConflictPolicy,
    recordConflictPolicy,
    minimumAgreement,
    resolutions: normalizeResolutions(options.resolutions, sourceIds),
    includeSnapshot: boolean(options.includeSnapshot, 'includeSnapshot'),
    includeProvenance: boolean(options.includeProvenance, 'includeProvenance'),
    maximumProvenanceRows: nonNegative(options.maximumProvenanceRows ?? 100_000, 'maximumProvenanceRows', 250_000),
  };
}

function sourceSessionMap(source, mappings, targetSessionIds, issues) {
  const mapped = new Map();
  for (const sourceSessionId of source.snapshot.sessionIds) {
    const targetSessionId = mappings.get(mappingKey(source.id, sourceSessionId)) ?? sourceSessionId;
    if (targetSessionIds && !targetSessionIds.includes(targetSessionId)) {
      issues.push({ code: 'session_outside_target', sourceId: source.id, sourceSessionId, targetSessionId, blocking: true });
      continue;
    }
    mapped.set(sourceSessionId, targetSessionId);
  }
  return mapped;
}

function sourceStudentMap(source, mappings, targetRosterById, issues) {
  const mapped = new Map();
  for (const student of source.snapshot.roster) {
    const targetStudentId = mappings.get(mappingKey(source.id, student.id)) ?? student.id;
    if (targetRosterById && !targetRosterById.has(targetStudentId)) {
      issues.push({ code: 'student_outside_target', sourceId: source.id, sourceStudentId: student.id, targetStudentId, blocking: true });
      continue;
    }
    mapped.set(student.id, { targetStudentId, student });
  }
  return mapped;
}

function safeSnapshot(roster, sessionIds, records, issues) {
  try {
    return createAttendanceSnapshot(roster, sessionIds, records);
  } catch (error) {
    issues.push({ code: 'merged_snapshot_invalid', message: error.message, blocking: true });
    return null;
  }
}

/**
 * Prepare a deterministic, auditable merge of multiple validated snapshots.
 * Exact duplicate cells are counted; differing identities or attendance
 * states require explicit resolution unless a preference policy was selected.
 * This function has no filesystem, network, server or application side effects.
 */
export function reconcileAttendanceSources(sourceValues, optionsValue = {}) {
  const sources = normalizeSources(sourceValues);
  const options = normalizeOptions(optionsValue, sources);
  const issues = [];
  const conflicts = [];
  const identityCandidates = new Map();
  const recordCandidates = new Map();
  const provenance = [];
  const sessionIds = new Set(options.targetSessionIds ?? []);
  const targetStudentIds = new Set(options.targetRoster?.map((student) => student.id) ?? []);
  const sourceMaps = new Map();

  for (const source of sources) {
    const studentMap = sourceStudentMap(source, options.studentMappings, options.targetRosterById, issues);
    const sessionMap = sourceSessionMap(source, options.sessionMappings, options.targetSessionIds, issues);
    sourceMaps.set(source.id, { students: studentMap, sessions: sessionMap });
    for (const { targetStudentId, student } of studentMap.values()) {
      targetStudentIds.add(targetStudentId);
      if (!identityCandidates.has(targetStudentId)) identityCandidates.set(targetStudentId, []);
      identityCandidates.get(targetStudentId).push({ sourceId: source.id, priority: source.priority, student });
    }
    for (const targetSessionId of sessionMap.values()) sessionIds.add(targetSessionId);
    for (const record of source.snapshot.records) {
      const student = studentMap.get(record.studentId);
      const sessionId = sessionMap.get(record.sessionId);
      if (!student || !sessionId) continue;
      const key = JSON.stringify([student.targetStudentId, sessionId]);
      if (!recordCandidates.has(key)) recordCandidates.set(key, []);
      recordCandidates.get(key).push({ sourceId: source.id, priority: source.priority, studentId: student.targetStudentId,
        sessionId, status: record.status, sourceStudentId: record.studentId, sourceSessionId: record.sessionId });
    }
  }

  for (const [key, targetStudentId] of options.studentMappings) {
    const [sourceId, sourceStudentId] = key.split('\u0000');
    if (!sourceMaps.get(sourceId)?.students.has(sourceStudentId)) {
      issues.push({ code: 'unused_student_mapping', sourceId, sourceStudentId, targetStudentId, blocking: true });
    }
  }
  for (const [key, targetSessionId] of options.sessionMappings) {
    const [sourceId, sourceSessionId] = key.split('\u0000');
    if (!sourceMaps.get(sourceId)?.sessions.has(sourceSessionId)) {
      issues.push({ code: 'unused_session_mapping', sourceId, sourceSessionId, targetSessionId, blocking: true });
    }
  }

  if (options.targetRoster) for (const student of options.targetRoster) targetStudentIds.add(student.id);
  const orderedSources = [...sources].sort(compareSources);
  const orderedRosterIds = [...targetStudentIds].sort((left, right) => left.localeCompare(right));
  const roster = [];
  for (const targetStudentId of orderedRosterIds) {
    const entries = identityCandidates.get(targetStudentId) ?? [];
    const student = { id: targetStudentId };
    for (const field of FIELDS) student[field] = resolveIdentity(targetStudentId, field, entries, options, conflicts, issues);
    if (student.name && student.email) roster.push(student);
  }
  const orderedSessionIds = [...sessionIds].sort((left, right) => left.localeCompare(right));
  const selectedRecords = [];
  const sortedCellKeys = [...recordCandidates.keys()].sort();
  for (const key of sortedCellKeys) {
    const candidates = recordCandidates.get(key).sort((left, right) => compareSources(options.sourcesById.get(left.sourceId), options.sourcesById.get(right.sourceId)));
    const resolution = resolveRecordConflict(key, candidates, options, conflicts, issues);
    if (!resolution?.status) continue;
    selectedRecords.push({ studentId: candidates[0].studentId, sessionId: candidates[0].sessionId, status: resolution.status });
    if (options.includeProvenance && provenance.length < options.maximumProvenanceRows) {
      provenance.push({ studentId: candidates[0].studentId, sessionId: candidates[0].sessionId,
        status: resolution.status, selectedSourceId: resolution.sourceId, duplicateCount: resolution.duplicateCount,
        sourceIds: candidates.map((candidate) => candidate.sourceId) });
    }
  }

  for (const [conflictId, resolution] of options.resolutions) {
    if (!resolution.used) issues.push({ code: 'stale_resolution', conflictId, blocking: true });
  }

  const targetOrder = options.targetRoster?.map((student) => student.id) ?? orderedRosterIds;
  const targetSessionOrder = options.targetSessionIds ?? orderedSessionIds;
  const orderedOutputRoster = targetOrder.map((id) => roster.find((student) => student.id === id)).filter(Boolean);
  const outputRecords = selectedRecords.filter((record) => orderedOutputRoster.some((student) => student.id === record.studentId) &&
    targetSessionOrder.includes(record.sessionId));
  const blockingIssues = issues.filter((issue) => issue.blocking);
  const unresolved = conflicts.filter((conflict) => conflict.status !== 'resolved');
  const enoughAgreement = sources.length >= options.minimumAgreement;
  if (!enoughAgreement) issues.push({ code: 'insufficient_source_agreement', required: options.minimumAgreement,
    available: sources.length, blocking: true });
  let snapshot = null;
  if (!unresolved.length && !blockingIssues.length && enoughAgreement) {
    snapshot = safeSnapshot(orderedOutputRoster, targetSessionOrder, outputRecords, issues);
  }
  const sourceSummary = sources.map((source) => ({ id: source.id, label: source.label, priority: source.priority,
    students: source.snapshot.roster.length, sessions: source.snapshot.sessionIds.length, records: source.snapshot.records.length }));
  const summary = {
    sources: sources.length,
    targetStudents: targetStudentIds.size,
    targetSessions: targetSessionOrder.length,
    candidateCells: recordCandidates.size,
    selectedRecords: outputRecords.length,
    conflicts: conflicts.length,
    unresolvedConflicts: unresolved.length,
    blockingIssues: issues.filter((issue) => issue.blocking).length,
    agreeingDuplicateCells: [...recordCandidates.values()].filter((candidates) => candidates.length > 1 &&
      new Set(candidates.map((candidate) => candidate.status)).size === 1).length,
    provenanceRows: provenance.length,
    provenanceTruncated: options.includeProvenance && outputRecords.length > options.maximumProvenanceRows,
    ready: Boolean(snapshot),
  };
  return {
    format: FORMAT,
    version: VERSION,
    settings: {
      identityConflictPolicy: options.identityConflictPolicy,
      recordConflictPolicy: options.recordConflictPolicy,
      minimumAgreement: options.minimumAgreement,
      targetRosterProvided: Boolean(options.targetRoster),
      targetSessionsProvided: Boolean(options.targetSessionIds),
      includeSnapshot: options.includeSnapshot,
      includeProvenance: options.includeProvenance,
    },
    sources: sourceSummary,
    summary,
    conflicts,
    issues,
    ...(options.includeProvenance ? { provenance } : {}),
    ...(options.includeSnapshot && snapshot ? { snapshot } : {}),
    notice: 'This is a local merge proposal. Resolve every conflict and inspect the merged copy before saving or using it.',
  };
}

function csvCell(value) {
  let cell = String(value ?? '');
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

function csv(headers, rows) {
  return [headers, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}

/** Export either conflicts or selected source provenance as spreadsheet-safe CSV. */
export function reconciliationToCsv(planValue, section = 'conflicts') {
  const plan = object(planValue, 'reconciliation plan');
  if (plan.format !== FORMAT || plan.version !== VERSION) throw new TypeError('invalid reconciliation plan');
  if (section === 'conflicts') {
    return csv(['conflictId', 'kind', 'target', 'field', 'status', 'selectedValue', 'selectedSourceId', 'candidateSources', 'candidateValues'],
      plan.conflicts.map((conflict) => [conflict.conflictId, conflict.kind, conflict.target, conflict.field,
        conflict.status, conflict.selectedValue, conflict.selectedSourceId,
        conflict.candidates.map((candidate) => candidate.sourceId).join('|'),
        conflict.candidates.map((candidate) => candidate.value).join('|')]));
  }
  if (section === 'provenance') {
    if (!Array.isArray(plan.provenance)) throw new TypeError('provenance was not included in this plan');
    return csv(['studentId', 'sessionId', 'status', 'selectedSourceId', 'duplicateCount', 'sourceIds'],
      plan.provenance.map((row) => [row.studentId, row.sessionId, row.status, row.selectedSourceId,
        row.duplicateCount, row.sourceIds.join('|')]));
  }
  if (section === 'issues') {
    return csv(['code', 'blocking', 'sourceId', 'target', 'field', 'conflictId', 'message'], plan.issues.map((issue) => [
      issue.code, issue.blocking, issue.sourceId, issue.target, issue.field, issue.conflictId, issue.message,
    ]));
  }
  throw new TypeError('section must be conflicts, provenance or issues');
}

/** Construct a compact, stable summary without returning snapshot contents. */
export function summarizeReconciliation(planValue) {
  const plan = object(planValue, 'reconciliation plan');
  if (plan.format !== FORMAT || plan.version !== VERSION || !plan.summary) throw new TypeError('invalid reconciliation plan');
  return {
    format: plan.format,
    version: plan.version,
    settings: structuredClone(plan.settings),
    sources: structuredClone(plan.sources),
    summary: structuredClone(plan.summary),
    conflictsByKind: plan.conflicts.reduce((counts, conflict) => {
      counts[conflict.kind] = (counts[conflict.kind] ?? 0) + 1;
      return counts;
    }, {}),
    unresolvedConflictIds: plan.conflicts.filter((conflict) => conflict.status !== 'resolved').map((conflict) => conflict.conflictId),
    issuesByCode: plan.issues.reduce((counts, issue) => {
      counts[issue.code] = (counts[issue.code] ?? 0) + 1;
      return counts;
    }, {}),
    containsSnapshot: Object.hasOwn(plan, 'snapshot'),
  };
}
