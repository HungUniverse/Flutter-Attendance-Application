import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-exemption-ledger';
const VERSION = 1;
const TYPES = new Set(['excused_absence', 'official_closure', 'makeup_credit', 'duplicate_cleanup']);
const EFFECTS = new Set(['exclude', 'present_credit']);
const STATES = new Set(['pending', 'in_review', 'needs_evidence', 'approved', 'rejected', 'withdrawn', 'revoked']);
const TRANSITIONS = Object.freeze({
  pending: new Set(['in_review', 'needs_evidence', 'rejected', 'withdrawn']),
  in_review: new Set(['needs_evidence', 'approved', 'rejected', 'withdrawn']),
  needs_evidence: new Set(['pending', 'in_review', 'rejected', 'withdrawn']),
  approved: new Set(['revoked']),
  rejected: new Set(['in_review', 'withdrawn']),
  withdrawn: new Set(),
  revoked: new Set(),
});
const STATUSES = new Set(['present', 'absent', 'missing']);
const MAX_ENTRIES = 50_000;

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
  if (typeof source !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(source) || !Number.isFinite(Date.parse(source))) {
    throw new TypeError(`${field} must be an ISO timestamp with an explicit UTC offset`);
  }
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

function snapshotStatus(snapshot, studentId, sessionId) {
  return snapshot.records.find((record) => record.studentId === studentId && record.sessionId === sessionId)?.status ?? null;
}

function statusValue(value, field) {
  if (value === null) return null;
  if (!STATUSES.has(value)) throw new TypeError(`${field} must be present, absent, missing or null`);
  return value;
}

function expectedEffect(type, effect) {
  const expected = type === 'makeup_credit' ? 'present_credit' : 'exclude';
  if (effect !== expected) throw new TypeError(`${type} must use the ${expected} effect`);
}

function normalizeEvidence(value, field) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 10) throw new RangeError(`${field} must contain at most 10 evidence references`);
  return value.map((entry, index) => {
    object(entry, `${field}[${index}]`);
    const sha256 = optionalText(entry.sha256, `${field}[${index}].sha256`, 64);
    if (sha256 && !/^[a-f0-9]{64}$/i.test(sha256)) throw new TypeError(`${field}[${index}].sha256 must be a SHA-256 hex digest`);
    return { label: text(entry.label, `${field}[${index}].label`, 160),
      referenceId: optionalText(entry.referenceId, `${field}[${index}].referenceId`, 256), sha256,
      receivedAt: timestamp(entry.receivedAt, `${field}[${index}].receivedAt`) };
  });
}

function normalizeEvent(event, index) {
  object(event, `events[${index}]`);
  if (event.sequence !== index + 1) throw new TypeError('event sequences must be consecutive and start at 1');
  if (!['created', 'status', 'note', 'evidence'].includes(event.type)) throw new TypeError(`invalid exemption event type: ${event.type}`);
  return { sequence: index + 1, type: event.type, at: timestamp(event.at, `events[${index}].at`),
    actor: optionalText(event.actor, `events[${index}].actor`, 120),
    from: optionalText(event.from, `events[${index}].from`, 32), to: optionalText(event.to, `events[${index}].to`, 32),
    note: event.note === null || event.note === undefined ? null : text(event.note, `events[${index}].note`, 2_000),
    evidenceCount: integer(event.evidenceCount ?? 0, `events[${index}].evidenceCount`, 0, 10) };
}

function normalizeEntry(entry, index, students, sessions) {
  object(entry, `entries[${index}]`);
  const id = text(entry.id, `entries[${index}].id`, 120);
  const studentId = optionalText(entry.studentId, `entries[${index}].studentId`, 256);
  const sessionId = text(entry.sessionId, `entries[${index}].sessionId`);
  if (!sessions.has(sessionId)) throw new TypeError(`exemption ${id} refers to an unknown session`);
  if (studentId !== null && !students.has(studentId)) throw new TypeError(`exemption ${id} refers to an unknown student`);
  const type = text(entry.type, `entries[${index}].type`, 40);
  if (!TYPES.has(type)) throw new TypeError(`exemption ${id} has an unsupported type`);
  if (studentId === null && type !== 'official_closure') throw new TypeError(`session-wide exemption ${id} must be an official_closure`);
  const effect = text(entry.effect, `entries[${index}].effect`, 32);
  if (!EFFECTS.has(effect)) throw new TypeError(`exemption ${id} has an unsupported effect`);
  expectedEffect(type, effect);
  const expectedStatus = statusValue(entry.expectedStatus, `entries[${index}].expectedStatus`);
  if (studentId === null && expectedStatus !== null) throw new TypeError(`session-wide exemption ${id} must not have an expectedStatus`);
  if (type === 'excused_absence' && expectedStatus !== 'absent') throw new TypeError(`excused absence ${id} must target an absent result`);
  if (type === 'makeup_credit' && expectedStatus === 'present') throw new TypeError(`make-up credit ${id} cannot replace an already-present result`);
  if (!STATES.has(entry.state)) throw new TypeError(`exemption ${id} has an unsupported state`);
  if (!Array.isArray(entry.events) || entry.events.length < 1 || entry.events.length > 1_000 || entry.revision !== entry.events.length) {
    throw new RangeError(`exemption ${id} must have between 1 and 1000 events matching its revision`);
  }
  return { id, studentId, sessionId, type, effect, expectedStatus,
    reason: text(entry.reason, `entries[${index}].reason`, 1_000), state: entry.state,
    createdAt: timestamp(entry.createdAt, `entries[${index}].createdAt`),
    updatedAt: timestamp(entry.updatedAt, `entries[${index}].updatedAt`),
    evidence: normalizeEvidence(entry.evidence, `entries[${index}].evidence`),
    events: entry.events.map((event, eventIndex) => normalizeEvent(event, eventIndex)), revision: entry.revision };
}

function normalizeLedger(value) {
  object(value, 'exemption ledger');
  if (value.format !== FORMAT || value.version !== VERSION) throw new TypeError('unsupported exemption ledger format or version');
  const snapshot = parseAttendanceSnapshot(value.sourceSnapshot);
  if (value.sourceFingerprint !== fingerprint(snapshot)) throw new TypeError('exemption ledger source fingerprint does not match its embedded snapshot');
  if (!Array.isArray(value.entries) || value.entries.length > MAX_ENTRIES) throw new RangeError(`ledger must contain at most ${MAX_ENTRIES} entries`);
  const students = new Set(snapshot.roster.map((student) => student.id));
  const sessions = new Set(snapshot.sessionIds);
  const entries = value.entries.map((entry, index) => normalizeEntry(entry, index, students, sessions));
  const ids = new Set();
  const targets = new Set();
  for (const entry of entries) {
    if (ids.has(entry.id)) throw new TypeError(`duplicate exemption ID: ${entry.id}`);
    ids.add(entry.id);
    const key = cellKey(entry.studentId ?? '*', entry.sessionId);
    if (targets.has(key)) throw new TypeError(`duplicate exemption target: ${entry.studentId ?? '*'}/${entry.sessionId}`);
    targets.add(key);
  }
  return { format: FORMAT, version: VERSION, id: text(value.id, 'ledger ID', 120), revision: integer(value.revision, 'ledger revision', 1),
    createdAt: timestamp(value.createdAt, 'createdAt'), updatedAt: timestamp(value.updatedAt, 'updatedAt'),
    sourceFingerprint: text(value.sourceFingerprint, 'sourceFingerprint', 120),
    sourceSnapshot: serializeAttendanceSnapshot(snapshot), entries };
}

function eventFor(entry, type, options = {}) {
  return { sequence: entry.events.length + 1, type, at: timestamp(options.at, 'event timestamp'),
    actor: optionalText(options.actor, 'actor', 120), from: optionalText(options.from, 'event from', 32),
    to: optionalText(options.to, 'event to', 32), note: options.note ?? null, evidenceCount: options.evidenceCount ?? 0 };
}

/** Parse and validate a serialized exception ledger. */
export function parseExemptionLedger(value) {
  if (typeof value === 'string') {
    try { value = JSON.parse(value); }
    catch { throw new TypeError('exemption ledger must contain valid JSON'); }
  }
  return normalizeLedger(value);
}

/** Create a review ledger from explicit exception proposals and a fixed baseline. */
export function createExemptionLedger(snapshotValue, proposalsValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = object(optionsValue, 'ledger options');
  if (!Array.isArray(proposalsValue) || proposalsValue.length > MAX_ENTRIES) throw new RangeError(`proposals must contain at most ${MAX_ENTRIES} entries`);
  const students = new Set(snapshot.roster.map((student) => student.id));
  const sessions = new Set(snapshot.sessionIds);
  const createdAt = timestamp(options.createdAt, 'createdAt');
  const actor = optionalText(options.actor, 'actor', 120) ?? 'local requester';
  const targets = new Set();
  const entries = proposalsValue.map((proposal, index) => {
    object(proposal, `proposals[${index}]`);
    const studentId = optionalText(proposal.studentId, `proposals[${index}].studentId`, 256);
    const sessionId = text(proposal.sessionId, `proposals[${index}].sessionId`);
    if (!sessions.has(sessionId)) throw new TypeError(`proposal ${index} refers to an unknown session`);
    if (studentId !== null && !students.has(studentId)) throw new TypeError(`proposal ${index} refers to an unknown student`);
    const type = text(proposal.type, `proposals[${index}].type`, 40);
    if (!TYPES.has(type)) throw new TypeError(`proposal ${index} has an unsupported type`);
    if (studentId === null && type !== 'official_closure') throw new TypeError(`session-wide proposal ${index} must be an official_closure`);
    const effect = text(proposal.effect, `proposals[${index}].effect`, 32);
    if (!EFFECTS.has(effect)) throw new TypeError(`proposal ${index} has an unsupported effect`);
    expectedEffect(type, effect);
    const actual = studentId === null ? null : snapshotStatus(snapshot, studentId, sessionId);
    const expectedStatus = statusValue(proposal.expectedStatus, `proposals[${index}].expectedStatus`);
    if (actual !== expectedStatus) throw new Error(`proposal ${index} expected ${expectedStatus} but snapshot contains ${actual}`);
    if (type === 'excused_absence' && expectedStatus !== 'absent') throw new TypeError(`proposal ${index} must target an absent result`);
    if (type === 'makeup_credit' && expectedStatus === 'present') throw new TypeError(`proposal ${index} cannot replace an already-present result`);
    const targetKey = cellKey(studentId ?? '*', sessionId);
    if (targets.has(targetKey)) throw new TypeError(`duplicate exemption target: ${studentId ?? '*'}/${sessionId}`);
    targets.add(targetKey);
    const id = text(proposal.id ?? `exemption-${stableId(JSON.stringify([studentId, sessionId, type]))}`, `proposals[${index}].id`, 120);
    const entry = { id, studentId, sessionId, type, effect, expectedStatus,
      reason: text(proposal.reason, `proposals[${index}].reason`, 1_000), state: 'pending',
      createdAt, updatedAt: createdAt, evidence: normalizeEvidence(proposal.evidence, `proposals[${index}].evidence`), events: [], revision: 0 };
    entry.events.push(eventFor(entry, 'created', { actor, at: createdAt, from: expectedStatus, to: effect, evidenceCount: entry.evidence.length }));
    entry.revision = entry.events.length;
    return entry;
  });
  const ledgerId = text(options.id ?? `exemptions-${stableId(createdAt)}`, 'ledger ID', 120);
  return normalizeLedger({ format: FORMAT, version: VERSION, id: ledgerId, revision: 1, createdAt, updatedAt: createdAt,
    sourceFingerprint: fingerprint(snapshot), sourceSnapshot: serializeAttendanceSnapshot(snapshot), entries });
}

/** Append a reviewer decision or evidence update with a per-entry optimistic revision. */
export function updateExemption(ledgerValue, entryIdValue, actionValue, optionsValue = {}) {
  const ledger = parseExemptionLedger(ledgerValue);
  const entryId = text(entryIdValue, 'exemption ID', 120);
  const action = object(actionValue, 'exemption action');
  const options = object(optionsValue, 'update options');
  const entry = ledger.entries.find((candidate) => candidate.id === entryId);
  if (!entry) throw new TypeError(`unknown exemption ID: ${entryId}`);
  if (integer(options.expectedRevision, 'expectedRevision', 1) !== entry.revision) throw new Error('stale exemption revision');
  const actor = optionalText(options.actor, 'actor', 120) ?? 'local reviewer';
  const at = timestamp(options.at, 'update timestamp');
  const events = [];
  if (Object.hasOwn(action, 'state')) {
    const next = text(action.state, 'state', 32);
    if (!STATES.has(next)) throw new TypeError(`unsupported exemption state: ${next}`);
    if (next === entry.state) throw new TypeError('exemption state is unchanged');
    if (!TRANSITIONS[entry.state]?.has(next)) throw new TypeError(`exemption cannot move from ${entry.state} to ${next}`);
    events.push(eventFor(entry, 'status', { actor, at, from: entry.state, to: next }));
    entry.state = next;
  }
  if (Object.hasOwn(action, 'note')) events.push(eventFor(entry, 'note', { actor, at, note: text(action.note, 'note', 2_000) }));
  if (Object.hasOwn(action, 'evidence')) {
    const evidence = normalizeEvidence(action.evidence, 'evidence');
    if (!evidence.length) throw new TypeError('evidence update must add at least one reference');
    entry.evidence.push(...evidence);
    if (entry.evidence.length > 10) throw new RangeError('exemption evidence may contain at most 10 references');
    events.push(eventFor(entry, 'evidence', { actor, at, evidenceCount: evidence.length }));
  }
  if (!events.length) throw new TypeError('exemption action must change state, add a note or add evidence');
  events.forEach((event, index) => { event.sequence = entry.events.length + index + 1; });
  entry.events.push(...events);
  entry.revision = entry.events.length;
  entry.updatedAt = at;
  ledger.revision++;
  ledger.updatedAt = at;
  return normalizeLedger(ledger);
}

function recordMap(snapshot) {
  return new Map(snapshot.records.map((record) => [cellKey(record.studentId, record.sessionId), record.status]));
}

function summarizeRows(rows) {
  const eligible = rows.filter((row) => row.eligible);
  const present = eligible.filter((row) => row.effectiveStatus === 'present').length;
  const absent = eligible.filter((row) => row.effectiveStatus === 'absent').length;
  const missing = eligible.filter((row) => row.effectiveStatus === 'missing').length;
  const excluded = rows.length - eligible.length;
  const recorded = present + absent;
  return { expected: eligible.length, present, absent, missing, excluded, recorded,
    coverage: eligible.length ? recorded / eligible.length : null,
    attendanceRate: recorded ? present / recorded : null,
    totalCells: rows.length };
}

/** Evaluate approved exceptions as a separate analytics overlay without changing attendance records. */
export function evaluateExemptionLedger(ledgerValue, currentSnapshotValue) {
  const ledger = parseExemptionLedger(ledgerValue);
  const current = parseAttendanceSnapshot(serializeAttendanceSnapshot(currentSnapshotValue));
  const source = parseAttendanceSnapshot(ledger.sourceSnapshot);
  const layoutChanged = JSON.stringify(current.roster.map((student) => student.id)) !== JSON.stringify(source.roster.map((student) => student.id)) ||
    JSON.stringify(current.sessionIds) !== JSON.stringify(source.sessionIds);
  const actuals = recordMap(current);
  const approved = ledger.entries.filter((entry) => entry.state === 'approved');
  const stale = [];
  const targets = new Map();
  for (const entry of approved) {
    if (entry.studentId !== null) {
      const actual = actuals.get(cellKey(entry.studentId, entry.sessionId)) ?? null;
      if (actual !== entry.expectedStatus) stale.push({ id: entry.id, code: 'expected_status_changed', studentId: entry.studentId,
        sessionId: entry.sessionId, expectedStatus: entry.expectedStatus, actualStatus: actual });
    }
    const key = cellKey(entry.studentId ?? '*', entry.sessionId);
    if (!targets.has(key)) targets.set(key, []);
    targets.get(key).push(entry);
  }
  const conflicts = [];
  for (const entry of approved) if (entry.studentId !== null) {
    const broad = targets.get(cellKey('*', entry.sessionId)) ?? [];
    if (broad.length) conflicts.push({ code: 'session_closure_overlaps_student_exception', sessionId: entry.sessionId,
      studentId: entry.studentId, entryIds: [...broad.map((item) => item.id), entry.id] });
  }
  if (layoutChanged) return { format: 'attendance-exemption-evaluation', version: VERSION, ok: false, ledgerId: ledger.id,
    ledgerRevision: ledger.revision, sourceFingerprint: ledger.sourceFingerprint, currentFingerprint: fingerprint(current), layoutChanged,
    summary: { entries: ledger.entries.length, approved: approved.length, stale: stale.length, conflicts: conflicts.length },
    stale, conflicts, classSummary: null, students: null, sessions: null,
    notice: 'The roster or session layout differs from the ledger baseline; no adjusted report was produced.' };
  if (stale.length || conflicts.length) return { format: 'attendance-exemption-evaluation', version: VERSION, ok: false, ledgerId: ledger.id,
    ledgerRevision: ledger.revision, sourceFingerprint: ledger.sourceFingerprint, currentFingerprint: fingerprint(current), layoutChanged,
    summary: { entries: ledger.entries.length, approved: approved.length, stale: stale.length, conflicts: conflicts.length },
    stale, conflicts, classSummary: null, students: null, sessions: null,
    notice: 'At least one approved exception is stale or overlaps a session-wide closure; no adjusted report was produced.' };

  const byCell = new Map(approved.filter((entry) => entry.studentId !== null).map((entry) => [cellKey(entry.studentId, entry.sessionId), entry]));
  const closures = new Map(approved.filter((entry) => entry.studentId === null).map((entry) => [entry.sessionId, entry]));
  const studentRows = [];
  const sessionRows = [];
  const allCells = [];
  for (const student of current.roster) {
    const cells = [];
    for (const sessionId of current.sessionIds) {
      const raw = actuals.get(cellKey(student.id, sessionId)) ?? 'missing';
      const exception = byCell.get(cellKey(student.id, sessionId)) ?? closures.get(sessionId) ?? null;
      const eligible = exception?.effect !== 'exclude';
      const effectiveStatus = exception?.effect === 'present_credit' ? 'present' : raw;
      const cell = { studentId: student.id, sessionId, rawStatus: raw, effectiveStatus, eligible,
        exceptionId: exception?.id ?? null, exceptionType: exception?.type ?? null };
      cells.push(cell);
      allCells.push(cell);
    }
    studentRows.push({ studentId: student.id, studentName: student.name, ...summarizeRows(cells) });
  }
  for (const sessionId of current.sessionIds) {
    const cells = allCells.filter((cell) => cell.sessionId === sessionId);
    sessionRows.push({ sessionId, ...summarizeRows(cells) });
  }
  const classSummary = summarizeRows(allCells);
  return { format: 'attendance-exemption-evaluation', version: VERSION, ok: true, ledgerId: ledger.id,
    ledgerRevision: ledger.revision, sourceFingerprint: ledger.sourceFingerprint, currentFingerprint: fingerprint(current), layoutChanged: false,
    summary: { entries: ledger.entries.length, approved: approved.length, pending: ledger.entries.filter((entry) => entry.state === 'pending').length,
      stale: 0, conflicts: 0, appliedExclusions: approved.filter((entry) => entry.effect === 'exclude').length,
      makeupCredits: approved.filter((entry) => entry.effect === 'present_credit').length },
    classSummary, students: studentRows, sessions: sessionRows,
    notice: 'Exceptions change only this report overlay. Raw attendance statuses and the source snapshot are unchanged.' };
}

/** Return a summary that omits reviewer notes and evidence references. */
export function summarizeExemptionLedger(ledgerValue) {
  const ledger = parseExemptionLedger(ledgerValue);
  const byState = {};
  const byType = {};
  for (const entry of ledger.entries) {
    byState[entry.state] = (byState[entry.state] ?? 0) + 1;
    byType[entry.type] = (byType[entry.type] ?? 0) + 1;
  }
  return { ledgerId: ledger.id, revision: ledger.revision, updatedAt: ledger.updatedAt, sourceFingerprint: ledger.sourceFingerprint,
    summary: { entries: ledger.entries.length, byState, byType } };
}

/** Serialize ledger JSON for a caller-selected path. */
export function serializeExemptionLedger(ledgerValue) {
  return `${JSON.stringify(parseExemptionLedger(ledgerValue), null, 2)}\n`;
}

/** Export a decision-safe case inventory or a validated adjusted summary. */
export function exemptionToCsv(value, section = 'entries') {
  const objectValue = object(value, 'exemption export');
  const cell = (valueCell) => {
    let source = valueCell === null || valueCell === undefined ? '' : String(valueCell);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (objectValue.format === FORMAT && objectValue.version === VERSION) {
    const ledger = parseExemptionLedger(objectValue);
    if (section !== 'entries') throw new TypeError('ledger CSV section must be entries');
    return csv(['id', 'studentId', 'sessionId', 'type', 'effect', 'expectedStatus', 'reason', 'state', 'evidenceCount', 'revision'],
      ledger.entries.map((entry) => [entry.id, entry.studentId, entry.sessionId, entry.type, entry.effect,
        entry.expectedStatus, entry.reason, entry.state, entry.evidence.length, entry.revision]));
  }
  if (objectValue.format !== 'attendance-exemption-evaluation' || objectValue.version !== VERSION || objectValue.ok !== true) {
    throw new TypeError('invalid or blocked exemption evaluation');
  }
  if (section === 'students') return csv(['studentId', 'studentName', 'expected', 'present', 'absent', 'missing', 'excluded', 'recorded', 'coverage', 'attendanceRate'],
    objectValue.students.map((row) => [row.studentId, row.studentName, row.expected, row.present, row.absent, row.missing,
      row.excluded, row.recorded, row.coverage, row.attendanceRate]));
  if (section === 'sessions') return csv(['sessionId', 'expected', 'present', 'absent', 'missing', 'excluded', 'recorded', 'coverage', 'attendanceRate'],
    objectValue.sessions.map((row) => [row.sessionId, row.expected, row.present, row.absent, row.missing,
      row.excluded, row.recorded, row.coverage, row.attendanceRate]));
  if (section === 'class') return csv(['expected', 'present', 'absent', 'missing', 'excluded', 'recorded', 'coverage', 'attendanceRate'], [[
    objectValue.classSummary.expected, objectValue.classSummary.present, objectValue.classSummary.absent,
    objectValue.classSummary.missing, objectValue.classSummary.excluded, objectValue.classSummary.recorded,
    objectValue.classSummary.coverage, objectValue.classSummary.attendanceRate,
  ]]);
  throw new TypeError('evaluation CSV section must be students, sessions or class');
}
