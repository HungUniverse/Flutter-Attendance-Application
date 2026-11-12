import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-correction-review';
const VERSION = 1;
const CASE_STATUSES = new Set(['submitted', 'in_review', 'needs_evidence', 'approved', 'rejected', 'withdrawn', 'applied']);
const TRANSITIONS = Object.freeze({
  submitted: new Set(['in_review', 'needs_evidence', 'rejected', 'withdrawn']),
  in_review: new Set(['needs_evidence', 'approved', 'rejected', 'withdrawn']),
  needs_evidence: new Set(['submitted', 'in_review', 'approved', 'rejected', 'withdrawn']),
  approved: new Set(['in_review', 'withdrawn', 'applied']),
  rejected: new Set(['in_review', 'withdrawn']),
  withdrawn: new Set(),
  applied: new Set(),
});
const REASONS = new Set(['incorrect_status', 'not_recorded', 'duplicate_entry', 'source_correction', 'other']);
const ATTENDANCE = new Set(['present', 'absent', 'missing']);

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 256) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function optionalText(value, field, maximum = 256) {
  return value === undefined || value === null || value === '' ? null : text(value, field, maximum);
}

function integer(value, field, minimum, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  return value;
}

function timestamp(value, field) {
  const source = value ?? new Date().toISOString();
  if (typeof source !== 'string' || !Number.isFinite(Date.parse(source))) throw new TypeError(`${field} must be a valid timestamp`);
  return new Date(source).toISOString();
}

function stableId(value) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36).toUpperCase().padStart(7, '0');
}

function fingerprint(snapshot) {
  return `snapshot-${stableId(serializeAttendanceSnapshot(snapshot))}`;
}

function cellKey(studentId, sessionId) {
  return JSON.stringify([studentId, sessionId]);
}

function currentCell(snapshot, studentId, sessionId) {
  return snapshot.records.find((record) => record.studentId === studentId && record.sessionId === sessionId)?.status ?? null;
}

function normalizeEvidence(value, field) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 10) throw new RangeError(`${field} must be an array with at most 10 references`);
  return value.map((entry, index) => {
    object(entry, `${field}[${index}]`);
    const reference = {
      label: text(entry.label, `${field}[${index}].label`, 160),
      receivedAt: timestamp(entry.receivedAt, `${field}[${index}].receivedAt`),
      referenceId: optionalText(entry.referenceId, `${field}[${index}].referenceId`, 256),
      sha256: optionalText(entry.sha256, `${field}[${index}].sha256`, 64),
    };
    if (reference.sha256 && !/^[a-f0-9]{64}$/i.test(reference.sha256)) throw new TypeError(`${field}[${index}].sha256 must be a SHA-256 hex digest`);
    return reference;
  });
}

function normalizeCaseEvent(event, index) {
  object(event, `events[${index}]`);
  if (event.sequence !== index + 1) throw new TypeError('case event sequences must be consecutive and start at 1');
  const allowed = new Set(['created', 'status', 'note', 'evidence', 'applied']);
  if (!allowed.has(event.type)) throw new TypeError(`invalid correction event type: ${event.type}`);
  return {
    sequence: index + 1,
    type: event.type,
    at: timestamp(event.at, `events[${index}].at`),
    actor: optionalText(event.actor, `events[${index}].actor`, 80),
    from: optionalText(event.from, `events[${index}].from`, 40),
    to: optionalText(event.to, `events[${index}].to`, 40),
    note: event.note === undefined || event.note === null ? null : text(event.note, `events[${index}].note`, 2_000),
    evidenceCount: integer(event.evidenceCount ?? 0, `events[${index}].evidenceCount`, 0, 10),
  };
}

function normalizeCorrectionCase(item, index, rosterById, sessions) {
  object(item, `cases[${index}]`);
  const caseId = text(item.caseId, `cases[${index}].caseId`, 120);
  const studentId = text(item.studentId, `cases[${index}].studentId`);
  const sessionId = text(item.sessionId, `cases[${index}].sessionId`);
  if (!rosterById.has(studentId)) throw new TypeError(`case ${caseId} refers to an unknown student`);
  if (!sessions.has(sessionId)) throw new TypeError(`case ${caseId} refers to an unknown session`);
  if (!CASE_STATUSES.has(item.status)) throw new TypeError(`invalid correction status: ${item.status}`);
  if (!ATTENDANCE.has(item.expectedStatus) && item.expectedStatus !== null) throw new TypeError(`invalid expected attendance status for ${caseId}`);
  if (!ATTENDANCE.has(item.proposedStatus)) throw new TypeError(`invalid proposed attendance status for ${caseId}`);
  if (!REASONS.has(item.reasonCode)) throw new TypeError(`invalid correction reason code: ${item.reasonCode}`);
  if (!Array.isArray(item.events) || item.events.length < 1 || item.events.length > 1000 || item.revision !== item.events.length) {
    throw new RangeError(`case ${caseId} must have between 1 and 1000 events matching its revision`);
  }
  const key = cellKey(studentId, sessionId);
  const rosterStudent = rosterById.get(studentId);
  return {
    caseId,
    studentId,
    studentName: rosterStudent.name,
    sessionId,
    expectedStatus: item.expectedStatus,
    proposedStatus: item.proposedStatus,
    reasonCode: item.reasonCode,
    reasonText: optionalText(item.reasonText, `cases[${index}].reasonText`, 1000),
    status: item.status,
    stale: item.stale === true,
    revision: item.revision,
    evidence: normalizeEvidence(item.evidence, `cases[${index}].evidence`),
    events: item.events.map(normalizeCaseEvent),
    _cellKey: key,
  };
}

function bookShape(value) {
  object(value, 'correction review');
  if (value.format !== FORMAT || value.version !== VERSION) throw new TypeError('unsupported correction review format or version');
  const snapshot = parseAttendanceSnapshot(value.sourceSnapshot);
  if (!Array.isArray(value.cases) || value.cases.length > 50_000) throw new RangeError('correction review must contain at most 50000 cases');
  const rosterById = new Map(snapshot.roster.map((student) => [student.id, student]));
  const sessions = new Set(snapshot.sessionIds);
  const cases = value.cases.map((item, index) => normalizeCorrectionCase(item, index, rosterById, sessions));
  const caseIds = new Set();
  const cells = new Set();
  for (const item of cases) {
    if (caseIds.has(item.caseId)) throw new TypeError(`duplicate correction case ID: ${item.caseId}`);
    if (cells.has(item._cellKey)) throw new TypeError(`duplicate correction target cell: ${item.studentId}/${item.sessionId}`);
    caseIds.add(item.caseId);
    cells.add(item._cellKey);
    delete item._cellKey;
  }
  return {
    format: FORMAT,
    version: VERSION,
    id: text(value.id, 'correction review ID', 120),
    revision: integer(value.revision, 'review revision', 1),
    createdAt: timestamp(value.createdAt, 'createdAt'),
    updatedAt: timestamp(value.updatedAt, 'updatedAt'),
    sourceFingerprint: text(value.sourceFingerprint, 'sourceFingerprint', 120),
    sourceSnapshot: serializeAttendanceSnapshot(snapshot),
    cases,
  };
}

/** Parse a local correction-review ledger and verify its embedded baseline. */
export function parseCorrectionReview(value) {
  if (typeof value === 'string') {
    try { value = JSON.parse(value); }
    catch { throw new TypeError('correction review must contain valid JSON'); }
  }
  return bookShape(value);
}

function eventFor(item, type, options = {}) {
  return { sequence: item.events.length + 1, type, at: timestamp(options.at, 'event timestamp'),
    actor: optionalText(options.actor, 'actor', 80), from: optionalText(options.from, 'event from', 40),
    to: optionalText(options.to, 'event to', 40), note: options.note ?? null, evidenceCount: options.evidenceCount ?? 0 };
}

function caseId(studentId, sessionId) {
  return `correction-${stableId(JSON.stringify([studentId, sessionId]))}`;
}

/** Create review cases from explicit proposed cell corrections. */
export function createCorrectionReview(snapshotValue, proposalsValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = object(optionsValue, 'correction review options');
  if (!Array.isArray(proposalsValue) || proposalsValue.length > 50_000) throw new RangeError('proposals must be an array with at most 50000 entries');
  const rosterById = new Map(snapshot.roster.map((student) => [student.id, student]));
  const sessions = new Set(snapshot.sessionIds);
  const seenCells = new Set();
  const createdAt = timestamp(options.createdAt, 'createdAt');
  const actor = optionalText(options.actor, 'actor', 80) ?? 'local requester';
  const cases = proposalsValue.map((proposal, index) => {
    object(proposal, `proposals[${index}]`);
    const studentId = text(proposal.studentId, `proposals[${index}].studentId`);
    const sessionId = text(proposal.sessionId, `proposals[${index}].sessionId`);
    if (!rosterById.has(studentId)) throw new TypeError(`proposal ${index} refers to an unknown student`);
    if (!sessions.has(sessionId)) throw new TypeError(`proposal ${index} refers to an unknown session`);
    const key = cellKey(studentId, sessionId);
    if (seenCells.has(key)) throw new TypeError(`duplicate correction target cell: ${studentId}/${sessionId}`);
    seenCells.add(key);
    const expectedStatus = proposal.expectedStatus;
    if (expectedStatus !== null && !ATTENDANCE.has(expectedStatus)) throw new TypeError(`proposal ${index} has an invalid expectedStatus`);
    const actualStatus = currentCell(snapshot, studentId, sessionId);
    if (actualStatus !== expectedStatus) throw new Error(`proposal ${index} expected status ${expectedStatus} but snapshot has ${actualStatus}`);
    const proposedStatus = text(proposal.proposedStatus, `proposals[${index}].proposedStatus`, 16);
    if (!ATTENDANCE.has(proposedStatus)) throw new TypeError(`proposal ${index} has an invalid proposedStatus`);
    if (proposedStatus === expectedStatus) throw new TypeError(`proposal ${index} does not change the current status`);
    const reasonCode = text(proposal.reasonCode, `proposals[${index}].reasonCode`, 40);
    if (!REASONS.has(reasonCode)) throw new TypeError(`proposal ${index} has an invalid reasonCode`);
    const item = {
      caseId: caseId(studentId, sessionId), studentId, studentName: rosterById.get(studentId).name, sessionId,
      expectedStatus, proposedStatus, reasonCode,
      reasonText: optionalText(proposal.reasonText, `proposals[${index}].reasonText`, 1000),
      status: 'submitted', stale: false, revision: 0, evidence: normalizeEvidence(proposal.evidence, `proposals[${index}].evidence`), events: [],
    };
    item.events.push(eventFor(item, 'created', { actor, at: createdAt, from: expectedStatus, to: proposedStatus,
      evidenceCount: item.evidence.length }));
    item.revision = item.events.length;
    return item;
  });
  return bookShape({ format: FORMAT, version: VERSION, id: text(options.id ?? `correction-review-${stableId(createdAt)}`, 'review ID', 120),
    revision: 1, createdAt, updatedAt: createdAt, sourceFingerprint: fingerprint(snapshot),
    sourceSnapshot: serializeAttendanceSnapshot(snapshot), cases });
}

/** Append a reviewer status, note or evidence update using optimistic revision checks. */
export function updateCorrectionCase(reviewValue, caseIdValue, actionValue, optionsValue = {}) {
  const review = parseCorrectionReview(reviewValue);
  const caseIdValueText = text(caseIdValue, 'caseId', 120);
  const action = object(actionValue, 'correction action');
  const options = object(optionsValue, 'update options');
  const item = review.cases.find((entry) => entry.caseId === caseIdValueText);
  if (!item) throw new TypeError(`unknown correction case: ${caseIdValueText}`);
  if (integer(options.expectedRevision, 'expectedRevision', 1) !== item.revision) {
    throw new Error(`stale correction revision: expected ${options.expectedRevision}, actual ${item.revision}`);
  }
  const actor = optionalText(options.actor, 'actor', 80) ?? 'local reviewer';
  const at = timestamp(options.at, 'update timestamp');
  const events = [];
  if (Object.hasOwn(action, 'status')) {
    const next = text(action.status, 'status', 32);
    if (!CASE_STATUSES.has(next) || next === 'applied') throw new TypeError(`invalid reviewer-selected status: ${next}`);
    if (next === item.status) throw new TypeError('case status is unchanged');
    if (!TRANSITIONS[item.status]?.has(next)) throw new TypeError(`correction cannot move from ${item.status} to ${next}`);
    events.push(eventFor(item, 'status', { actor, at, from: item.status, to: next }));
    item.status = next;
  }
  if (Object.hasOwn(action, 'note')) {
    const note = text(action.note, 'note', 2_000);
    events.push(eventFor(item, 'note', { actor, at, note }));
  }
  if (Object.hasOwn(action, 'evidence')) {
    const evidence = normalizeEvidence(action.evidence, 'evidence');
    if (!evidence.length) throw new TypeError('evidence update must add at least one reference');
    item.evidence.push(...evidence);
    if (item.evidence.length > 10) throw new RangeError('case evidence may contain at most 10 references');
    events.push(eventFor(item, 'evidence', { actor, at, evidenceCount: evidence.length }));
  }
  if (!events.length) throw new TypeError('correction action must change status, add a note or add evidence');
  events.forEach((event, index) => { event.sequence = item.events.length + index + 1; });
  item.events.push(...events);
  item.revision = item.events.length;
  review.revision++;
  review.updatedAt = at;
  return bookShape(review);
}

function snapshotCellMap(snapshot) {
  return new Map(snapshot.records.map((record) => [cellKey(record.studentId, record.sessionId), record.status]));
}

/**
 * Apply only approved cases to a new snapshot value. Every expected status is
 * rechecked first; one stale cell blocks the entire batch. No file is written.
 */
export function applyApprovedCorrections(reviewValue, currentSnapshotValue, optionsValue = {}) {
  const review = parseCorrectionReview(reviewValue);
  const current = parseAttendanceSnapshot(serializeAttendanceSnapshot(currentSnapshotValue));
  const options = object(optionsValue, 'apply options');
  if (options.expectedReviewRevision !== undefined && options.expectedReviewRevision !== review.revision) {
    throw new Error(`stale review revision: expected ${options.expectedReviewRevision}, actual ${review.revision}`);
  }
  const source = parseAttendanceSnapshot(review.sourceSnapshot);
  const stale = [];
  if (fingerprint(source) !== review.sourceFingerprint) stale.push({ code: 'embedded_source_fingerprint_mismatch' });
  const currentCells = snapshotCellMap(current);
  const conflicts = [];
  const approved = review.cases.filter((item) => item.status === 'approved');
  for (const item of approved) {
    const actual = currentCells.get(cellKey(item.studentId, item.sessionId)) ?? null;
    if (actual !== item.expectedStatus) conflicts.push({ caseId: item.caseId, studentId: item.studentId,
      sessionId: item.sessionId, expectedStatus: item.expectedStatus, actualStatus: actual });
  }
  const sameLayout = JSON.stringify(current.roster.map((student) => student.id)) === JSON.stringify(source.roster.map((student) => student.id)) &&
    JSON.stringify(current.sessionIds) === JSON.stringify(source.sessionIds);
  if (!sameLayout) stale.push({ code: 'snapshot_roster_or_sessions_changed' });
  if (stale.length || conflicts.length) return { ok: false, applied: 0, stale, conflicts, snapshot: null,
    reviewRevision: review.revision, notice: 'No correction was applied because the baseline changed or an expected cell no longer matches.' };

  const changes = new Map(approved.map((item) => [cellKey(item.studentId, item.sessionId), item.proposedStatus]));
  const records = current.records.filter((record) => !changes.has(cellKey(record.studentId, record.sessionId)));
  for (const item of approved) if (item.proposedStatus !== 'missing') {
    records.push({ studentId: item.studentId, sessionId: item.sessionId, status: item.proposedStatus });
  }
  const snapshot = createAttendanceSnapshot(current.roster, current.sessionIds, records);
  return { ok: true, applied: approved.length, stale: [], conflicts: [], snapshot,
    reviewRevision: review.revision, approvedCaseIds: approved.map((item) => item.caseId),
    snapshotFingerprint: fingerprint(snapshot), notice: 'Corrections are an in-memory copy. Save or use it only after reviewing the output.' };
}

/** Mark case comparisons against a current snapshot without rewriting the review. */
export function auditCorrectionReview(reviewValue, currentSnapshotValue) {
  const review = parseCorrectionReview(reviewValue);
  const current = parseAttendanceSnapshot(serializeAttendanceSnapshot(currentSnapshotValue));
  const source = parseAttendanceSnapshot(review.sourceSnapshot);
  const layoutChanged = JSON.stringify(current.roster.map((student) => student.id)) !== JSON.stringify(source.roster.map((student) => student.id)) ||
    JSON.stringify(current.sessionIds) !== JSON.stringify(source.sessionIds);
  const currentCells = snapshotCellMap(current);
  const findings = [];
  for (const item of review.cases) {
    const actual = currentCells.get(cellKey(item.studentId, item.sessionId)) ?? null;
    const changed = actual !== item.expectedStatus;
    if (changed || layoutChanged) findings.push({ caseId: item.caseId, studentId: item.studentId, sessionId: item.sessionId,
      code: layoutChanged ? 'baseline_layout_changed' : 'expected_status_changed',
      expectedStatus: item.expectedStatus, actualStatus: actual, reviewerStatus: item.status,
      blocksApply: item.status === 'approved' });
  }
  return { format: 'attendance-correction-review-audit', version: 1, reviewId: review.id,
    reviewRevision: review.revision, sourceFingerprint: review.sourceFingerprint,
    currentFingerprint: fingerprint(current), layoutChanged,
    summary: { cases: review.cases.length, approved: review.cases.filter((item) => item.status === 'approved').length,
      stale: findings.length, approvedStale: findings.filter((item) => item.blocksApply).length, valid: findings.length === 0 },
    findings };
}

/** Count cases by review state and reason without exposing names or notes. */
export function summarizeCorrectionReview(reviewValue) {
  const review = parseCorrectionReview(reviewValue);
  const byStatus = {};
  const byReason = {};
  for (const item of review.cases) {
    byStatus[item.status] = (byStatus[item.status] ?? 0) + 1;
    byReason[item.reasonCode] = (byReason[item.reasonCode] ?? 0) + 1;
  }
  return { reviewId: review.id, revision: review.revision, updatedAt: review.updatedAt,
    sourceFingerprint: review.sourceFingerprint, summary: { total: review.cases.length, byStatus, byReason,
      stale: review.cases.filter((item) => item.stale).length } };
}

/** Serialize the review ledger as portable JSON. */
export function serializeCorrectionReview(reviewValue) {
  return `${JSON.stringify(parseCorrectionReview(reviewValue), null, 2)}\n`;
}

function csvCell(value) {
  let cell = String(value ?? '');
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

function csv(headers, rows) {
  return [headers, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}

/** Export current correction cases; reviewer notes require explicit opt-in. */
export function correctionReviewToCsv(reviewValue, optionsValue = {}) {
  const review = parseCorrectionReview(reviewValue);
  const options = object(optionsValue, 'CSV options');
  if (options.includeNotes !== undefined && typeof options.includeNotes !== 'boolean') throw new TypeError('includeNotes must be a boolean');
  const includeNotes = options.includeNotes === true;
  return csv(['caseId', 'studentId', 'studentName', 'sessionId', 'expectedStatus', 'proposedStatus', 'reasonCode',
    'reasonText', 'status', 'evidenceCount', ...(includeNotes ? ['latestNote'] : [])], review.cases.map((item) => {
    const latestNote = [...item.events].reverse().find((event) => event.type === 'note')?.note ?? '';
    return [item.caseId, item.studentId, item.studentName, item.sessionId, item.expectedStatus,
      item.proposedStatus, item.reasonCode, item.reasonText, item.status, item.evidence.length,
      ...(includeNotes ? [latestNote] : [])];
  }));
}

/** Export review audit findings without evidence references or note contents. */
export function correctionAuditToCsv(auditValue) {
  const audit = object(auditValue, 'correction audit');
  if (audit.format !== 'attendance-correction-review-audit' || audit.version !== 1 || !Array.isArray(audit.findings)) {
    throw new TypeError('invalid correction audit');
  }
  return csv(['caseId', 'studentId', 'sessionId', 'code', 'expectedStatus', 'actualStatus', 'reviewerStatus', 'blocksApply'],
    audit.findings.map((item) => [item.caseId, item.studentId, item.sessionId, item.code,
      item.expectedStatus, item.actualStatus, item.reviewerStatus, item.blocksApply]));
}
