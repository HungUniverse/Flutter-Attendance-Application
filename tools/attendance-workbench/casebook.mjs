const FORMAT = 'attendance-review-casebook';
const VERSION = 1;
const STATUSES = new Set(['new', 'in_review', 'data_needed', 'resolved', 'dismissed', 'reopened']);
const PRIORITIES = new Set(['urgent', 'high', 'review']);
const EVENT_TYPES = new Set(['created', 'status', 'assigned', 'note', 'refreshed', 'stale']);
const TRANSITIONS = Object.freeze({
  new: new Set(['in_review', 'data_needed', 'resolved', 'dismissed']),
  in_review: new Set(['new', 'data_needed', 'resolved', 'dismissed']),
  data_needed: new Set(['in_review', 'resolved', 'dismissed']),
  resolved: new Set(['reopened']),
  dismissed: new Set(['reopened']),
  reopened: new Set(['in_review', 'data_needed', 'resolved', 'dismissed']),
});

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function requiredText(value, field, maximum = 512) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${field} must be a non-empty string of at most ${maximum} characters`);
  }
  return value.trim();
}

function optionalText(value, field, maximum = 120) {
  if (value === null || value === undefined || value === '') return null;
  return requiredText(value, field, maximum);
}

function timestamp(value, field) {
  const source = value ?? new Date().toISOString();
  if (typeof source !== 'string' || !Number.isFinite(Date.parse(source))) throw new TypeError(`${field} must be a valid timestamp`);
  return new Date(source).toISOString();
}

function normalizeEvent(event, index) {
  object(event, `events[${index}]`);
  if (!Number.isSafeInteger(event.sequence) || event.sequence !== index + 1) throw new TypeError('event sequences must be consecutive and start at 1');
  if (!EVENT_TYPES.has(event.type)) throw new TypeError(`invalid event type: ${event.type}`);
  return {
    sequence: event.sequence,
    type: event.type,
    at: timestamp(event.at, `events[${index}].at`),
    actor: optionalText(event.actor, `events[${index}].actor`, 80),
    from: optionalText(event.from, `events[${index}].from`, 120),
    to: optionalText(event.to, `events[${index}].to`, 120),
    note: event.note === undefined || event.note === null ? null : requiredText(event.note, `events[${index}].note`, 2_000),
  };
}

function normalizeReviewCase(item, index) {
  object(item, `cases[${index}]`);
  if (!STATUSES.has(item.status)) throw new TypeError(`invalid case status: ${item.status}`);
  if (!PRIORITIES.has(item.priority)) throw new TypeError(`invalid case priority: ${item.priority}`);
  if (!Number.isSafeInteger(item.revision) || item.revision < 1) throw new TypeError('case revision must be a positive integer');
  if (!Array.isArray(item.events) || item.events.length !== item.revision || item.events.length > 10_000) {
    throw new RangeError('case events must match its revision and fit within 10000 entries');
  }
  if (!Array.isArray(item.reasons) || !Array.isArray(item.suggestedSteps) || item.suggestedSteps.some((step) => typeof step !== 'string')) {
    throw new TypeError('case reasons and suggestedSteps must be arrays of valid values');
  }
  return {
    caseId: requiredText(item.caseId, `cases[${index}].caseId`, 160),
    studentId: requiredText(item.studentId, `cases[${index}].studentId`, 256),
    studentName: requiredText(item.studentName, `cases[${index}].studentName`, 256),
    priority: item.priority,
    status: item.status,
    assigneeId: optionalText(item.assigneeId, `cases[${index}].assigneeId`, 120),
    attendanceRate: item.attendanceRate === null ? null : normalizeRate(item.attendanceRate),
    present: nonNegative(item.present, 'present'),
    absent: nonNegative(item.absent, 'absent'),
    missing: nonNegative(item.missing, 'missing'),
    reasons: structuredClone(item.reasons),
    suggestedSteps: [...item.suggestedSteps],
    sourceFingerprint: requiredText(item.sourceFingerprint, `cases[${index}].sourceFingerprint`, 120),
    stale: item.stale === true,
    revision: item.revision,
    events: item.events.map(normalizeEvent),
  };
}

function nonNegative(value, field) {
  if (!Number.isSafeInteger(value) || value < 0) throw new RangeError(`${field} must be a non-negative integer`);
  return value;
}

function normalizeRate(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) throw new RangeError('attendanceRate must be null or a number from 0 to 1');
  return value;
}

function bookShape(value) {
  object(value, 'casebook');
  if (value.format !== FORMAT || value.version !== VERSION) throw new TypeError('unsupported casebook format or version');
  if (!Array.isArray(value.cases) || value.cases.length > 50_000) throw new RangeError('casebook must contain at most 50000 cases');
  if (!Number.isSafeInteger(value.revision) || value.revision < 1) throw new TypeError('casebook revision must be a positive integer');
  const cases = value.cases.map(normalizeReviewCase);
  const seen = new Set();
  for (const item of cases) {
    if (seen.has(item.caseId)) throw new TypeError(`duplicate case ID: ${item.caseId}`);
    seen.add(item.caseId);
  }
  return {
    format: FORMAT,
    version: VERSION,
    id: requiredText(value.id, 'casebook ID', 160),
    createdAt: timestamp(value.createdAt, 'createdAt'),
    updatedAt: timestamp(value.updatedAt, 'updatedAt'),
    revision: value.revision,
    sourceFingerprint: requiredText(value.sourceFingerprint, 'sourceFingerprint', 120),
    sourceDimensions: {
      students: nonNegative(value.sourceDimensions?.students, 'sourceDimensions.students'),
      sessions: nonNegative(value.sourceDimensions?.sessions, 'sourceDimensions.sessions'),
      records: nonNegative(value.sourceDimensions?.records, 'sourceDimensions.records'),
    },
    cases,
  };
}

/** Parse and validate a local, versioned review casebook. */
export function parseCasebook(value) {
  if (typeof value === 'string') {
    try { value = JSON.parse(value); }
    catch { throw new TypeError('casebook must contain valid JSON'); }
  }
  return bookShape(value);
}

function validatePlan(plan) {
  object(plan, 'review plan');
  if (plan.version !== 1 || !Array.isArray(plan.cases)) throw new TypeError('invalid review plan');
  if (!plan.generatedFor || !plan.summary) throw new TypeError('review plan is missing its summary');
  const caseIds = new Set();
  for (const item of plan.cases) {
    object(item, 'review case');
    requiredText(item.caseId, 'caseId', 160);
    requiredText(item.studentId, 'studentId', 256);
    requiredText(item.studentName, 'studentName', 256);
    if (!PRIORITIES.has(item.priority)) throw new TypeError('review case has an invalid priority');
    if (!Array.isArray(item.reasons) || !Array.isArray(item.suggestedSteps)) throw new TypeError('review case reasons and suggestedSteps must be arrays');
    if (caseIds.has(item.caseId)) throw new TypeError(`duplicate case ID: ${item.caseId}`);
    caseIds.add(item.caseId);
  }
  return plan;
}

function eventFor(item, type, options = {}) {
  return {
    sequence: options.sequence ?? item.events.length + 1,
    type,
    at: timestamp(options.at, 'event timestamp'),
    actor: optionalText(options.actor, 'actor', 80),
    from: optionalText(options.from, 'event from', 120),
    to: optionalText(options.to, 'event to', 120),
    note: options.note === undefined ? null : requiredText(options.note, 'note', 2_000),
  };
}

function caseFromPlan(item, options = {}) {
  const created = {
    caseId: item.caseId,
    studentId: item.studentId,
    studentName: item.studentName,
    priority: item.priority,
    status: 'new',
    assigneeId: null,
    attendanceRate: item.attendanceRate,
    present: item.present,
    absent: item.absent,
    missing: item.missing,
    reasons: structuredClone(item.reasons),
    suggestedSteps: [...item.suggestedSteps],
    sourceFingerprint: options.sourceFingerprint,
    stale: false,
    revision: 0,
    events: [],
  };
  created.events.push(eventFor(created, 'created', { ...options, to: 'new' }));
  created.revision = created.events.length;
  return created;
}

/** Create a review tracker from a review plan without writing to a datastore. */
export function createCasebook(planValue, optionsValue = {}) {
  const plan = validatePlan(planValue);
  object(optionsValue, 'casebook options');
  const createdAt = timestamp(optionsValue.createdAt, 'createdAt');
  const sourceDimensions = {
    students: nonNegative(plan.generatedFor.students, 'generatedFor.students'),
    sessions: nonNegative(plan.generatedFor.sessions, 'generatedFor.sessions'),
    records: nonNegative(plan.generatedFor.records, 'generatedFor.records'),
  };
  return bookShape({
    format: FORMAT,
    version: VERSION,
    id: optionsValue.id ?? `reviewbook-${plan.snapshotFingerprint}`,
    createdAt,
    updatedAt: createdAt,
    revision: 1,
    sourceFingerprint: plan.snapshotFingerprint,
    sourceDimensions,
    cases: plan.cases.map((item) => caseFromPlan(item, { actor: optionsValue.actor, at: createdAt,
      sourceFingerprint: plan.snapshotFingerprint })),
  });
}

function currentOfTransition(status, next) {
  if (!TRANSITIONS[status]?.has(next)) throw new TypeError(`case cannot move from ${status} to ${next}`);
}

/** Apply an optimistic, append-only status, assignment or note update. */
export function updateCasebook(bookValue, caseIdValue, actionValue, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const caseId = requiredText(caseIdValue, 'caseId', 160);
  const action = object(actionValue, 'action');
  const options = object(optionsValue, 'update options');
  const item = book.cases.find((entry) => entry.caseId === caseId);
  if (!item) throw new TypeError(`unknown case ID: ${caseId}`);
  if (options.expectedRevision !== item.revision) throw new Error(`stale case revision: expected ${options.expectedRevision}, actual ${item.revision}`);
  const events = [];
  const actor = options.actor;
  if (Object.hasOwn(action, 'status')) {
    if (!STATUSES.has(action.status)) throw new TypeError(`invalid case status: ${action.status}`);
    if (action.status !== item.status) {
      currentOfTransition(item.status, action.status);
      events.push(eventFor(item, 'status', { actor, at: options.at, from: item.status, to: action.status,
        sequence: item.events.length + events.length + 1 }));
      item.status = action.status;
    }
  }
  if (Object.hasOwn(action, 'assigneeId')) {
    const assigneeId = optionalText(action.assigneeId, 'assigneeId', 120);
    if (assigneeId !== item.assigneeId) {
      events.push(eventFor(item, 'assigned', { actor, at: options.at, from: item.assigneeId, to: assigneeId,
        sequence: item.events.length + events.length + 1 }));
      item.assigneeId = assigneeId;
    }
  }
  if (Object.hasOwn(action, 'note')) {
    const note = requiredText(action.note, 'note', 2_000);
    events.push(eventFor(item, 'note', { actor, at: options.at, note, sequence: item.events.length + events.length + 1 }));
  }
  if (!events.length) throw new TypeError('action does not change the case');
  item.events.push(...events);
  item.revision = item.events.length;
  book.revision++;
  book.updatedAt = timestamp(options.at, 'updatedAt');
  return bookShape(book);
}

/** Merge a refreshed plan while preserving notes, assignments and status history. */
export function reconcileCasebook(bookValue, planValue, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const plan = validatePlan(planValue);
  const options = object(optionsValue, 'reconciliation options');
  if (options.expectedRevision !== undefined && options.expectedRevision !== book.revision) {
    throw new Error(`stale casebook revision: expected ${options.expectedRevision}, actual ${book.revision}`);
  }
  const at = timestamp(options.at, 'reconciliation timestamp');
  const actor = optionalText(options.actor, 'actor', 80) ?? 'local review';
  const existing = new Map(book.cases.map((item) => [item.caseId, item]));
  const incoming = new Map(plan.cases.map((item) => [item.caseId, item]));
  const merged = [];
  for (const [caseId, planned] of incoming) {
    const current = existing.get(caseId);
    if (!current) {
      merged.push(caseFromPlan(planned, { actor, at, sourceFingerprint: plan.snapshotFingerprint }));
      continue;
    }
    const updatedFacts = {
      studentId: planned.studentId,
      studentName: planned.studentName,
      priority: planned.priority,
      attendanceRate: planned.attendanceRate,
      present: planned.present,
      absent: planned.absent,
      missing: planned.missing,
      reasons: structuredClone(planned.reasons),
      suggestedSteps: [...planned.suggestedSteps],
      sourceFingerprint: plan.snapshotFingerprint,
    };
    const previousSourceFingerprint = current.sourceFingerprint;
    const changed = current.stale || Object.keys(updatedFacts).some((key) =>
      JSON.stringify(current[key]) !== JSON.stringify(updatedFacts[key]));
    Object.assign(current, updatedFacts, { stale: false });
    if (changed) {
      current.events.push(eventFor(current, 'refreshed', { actor, at, from: previousSourceFingerprint, to: plan.snapshotFingerprint }));
      current.revision = current.events.length;
    }
    merged.push(current);
  }
  for (const current of book.cases) {
    if (incoming.has(current.caseId)) continue;
    if (!current.stale) {
      current.stale = true;
      current.events.push(eventFor(current, 'stale', { actor, at, from: book.sourceFingerprint, to: plan.snapshotFingerprint }));
      current.revision = current.events.length;
    }
    current.sourceFingerprint = plan.snapshotFingerprint;
    merged.push(current);
  }
  book.cases = merged;
  book.sourceFingerprint = plan.snapshotFingerprint;
  book.sourceDimensions = {
    students: nonNegative(plan.generatedFor.students, 'generatedFor.students'),
    sessions: nonNegative(plan.generatedFor.sessions, 'generatedFor.sessions'),
    records: nonNegative(plan.generatedFor.records, 'generatedFor.records'),
  };
  book.revision++;
  book.updatedAt = at;
  return bookShape(book);
}

/** Count open, assigned, resolved and stale cases for a compact dashboard. */
export function summarizeCasebook(bookValue) {
  const book = parseCasebook(bookValue);
  const summary = { total: book.cases.length, open: 0, assigned: 0, resolved: 0, dismissed: 0, stale: 0, byPriority: {} };
  for (const item of book.cases) {
    if (item.status === 'resolved') summary.resolved++;
    else if (item.status === 'dismissed') summary.dismissed++;
    else summary.open++;
    if (item.assigneeId) summary.assigned++;
    if (item.stale) summary.stale++;
    summary.byPriority[item.priority] = (summary.byPriority[item.priority] ?? 0) + 1;
  }
  return { revision: book.revision, updatedAt: book.updatedAt, sourceFingerprint: book.sourceFingerprint, summary };
}

/** Serialize a normalized casebook as portable JSON. */
export function serializeCasebook(value) {
  return `${JSON.stringify(parseCasebook(value), null, 2)}\n`;
}

/** Export current case state without exposing its full event history. */
export function casebookToCsv(bookValue, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  object(optionsValue, 'CSV options');
  const includeNotes = optionsValue.includeNotes === true;
  const header = ['caseId', 'studentId', 'studentName', 'priority', 'status', 'assigneeId', 'attendanceRate', 'present', 'absent',
    'missing', 'reasonCodes', 'stale', 'sourceFingerprint', ...(includeNotes ? ['latestNote'] : [])];
  const escape = (value) => {
    let cell = String(value ?? '');
    if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
    return `"${cell.replaceAll('"', '""')}"`;
  };
  const rows = book.cases.map((item) => {
    const latestNote = [...item.events].reverse().find((event) => event.type === 'note')?.note ?? '';
    return [item.caseId, item.studentId, item.studentName, item.priority, item.status, item.assigneeId,
      item.attendanceRate === null ? '' : `${(item.attendanceRate * 100).toFixed(1)}%`, item.present, item.absent, item.missing,
      item.reasons.map((reason) => reason.code).join(';'), item.stale, item.sourceFingerprint,
      ...(includeNotes ? [latestNote] : [])];
  });
  return `${[header, ...rows].map((row) => row.map(escape).join(',')).join('\r\n')}\r\n`;
}

function boundedLimit(value, field, fallback, maximum) {
  const limit = value ?? fallback;
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > maximum) {
    throw new RangeError(`${field} must be an integer from 1 to ${maximum}`);
  }
  return limit;
}

function historyOptions(value) {
  const options = object(value, 'history options');
  const booleanOptions = ['includeStudentDetails', 'includeNotes'];
  for (const name of booleanOptions) {
    if (options[name] !== undefined && typeof options[name] !== 'boolean') throw new TypeError(`${name} must be a boolean`);
  }
  const caseId = options.caseId === undefined ? null : requiredText(options.caseId, 'caseId', 160);
  const actor = options.actor === undefined ? null : requiredText(options.actor, 'actor', 80);
  let types = null;
  if (options.types !== undefined) {
    if (!Array.isArray(options.types) || options.types.length < 1 || options.types.some((type) => !EVENT_TYPES.has(type))) {
      throw new TypeError('types must be a non-empty array of known event types');
    }
    types = new Set(options.types);
  }
  const parseBound = (value, field) => {
    if (value === undefined) return null;
    if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw new TypeError(`${field} must be a valid timestamp`);
    return Date.parse(value);
  };
  const fromAt = parseBound(options.fromAt, 'fromAt');
  const toAt = parseBound(options.toAt, 'toAt');
  if (fromAt !== null && toAt !== null && fromAt > toAt) throw new RangeError('fromAt must not be later than toAt');
  return {
    caseId,
    actor,
    types,
    fromAt,
    toAt,
    includeStudentDetails: options.includeStudentDetails === true,
    includeNotes: options.includeNotes === true,
    limit: boundedLimit(options.limit, 'limit', 1000, 10_000),
  };
}

/** Return an optionally filtered, capped event list in case order and sequence
 * order. Notes and student identity fields require explicit opt-in. */
export function listCasebookEvents(bookValue, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const options = historyOptions(optionsValue);
  const events = [];
  let totalMatches = 0;
  const matchedCases = new Set();
  const byType = {};
  for (const item of book.cases) {
    if (options.caseId && item.caseId !== options.caseId) continue;
    for (const event of item.events) {
      if (options.actor && event.actor !== options.actor) continue;
      if (options.types && !options.types.has(event.type)) continue;
      const time = Date.parse(event.at);
      if (options.fromAt !== null && time < options.fromAt) continue;
      if (options.toAt !== null && time > options.toAt) continue;
      totalMatches++;
      matchedCases.add(item.caseId);
      byType[event.type] = (byType[event.type] ?? 0) + 1;
      if (events.length >= options.limit) continue;
      events.push({
        caseId: item.caseId,
        sequence: event.sequence,
        type: event.type,
        at: event.at,
        actor: event.actor,
        from: event.from,
        to: event.to,
        ...(options.includeStudentDetails ? { studentId: item.studentId, studentName: item.studentName } : {}),
        ...(options.includeNotes ? { note: event.note } : {}),
      });
    }
  }
  return {
    format: 'attendance-casebook-events',
    version: 1,
    casebookId: book.id,
    casebookRevision: book.revision,
    filters: {
      caseId: options.caseId,
      actor: options.actor,
      types: options.types ? [...options.types] : null,
      fromAt: options.fromAt === null ? null : new Date(options.fromAt).toISOString(),
      toAt: options.toAt === null ? null : new Date(options.toAt).toISOString(),
      includeStudentDetails: options.includeStudentDetails,
      includeNotes: options.includeNotes,
      limit: options.limit,
    },
    summary: { totalMatches, matchedCases: matchedCases.size, byType, returned: events.length, truncated: totalMatches > events.length },
    events,
  };
}

function historyCsvCell(value) {
  let cell = String(value ?? '');
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

/** Export a filtered event report. Notes and student details only appear when
 * those fields were explicitly included in listCasebookEvents options. */
export function casebookEventsToCsv(eventsValue) {
  const report = object(eventsValue, 'casebook events');
  if (report.format !== 'attendance-casebook-events' || report.version !== 1 || !Array.isArray(report.events)) {
    throw new TypeError('invalid casebook events report');
  }
  const hasStudentDetails = report.filters?.includeStudentDetails === true;
  const hasNotes = report.filters?.includeNotes === true;
  const header = ['caseId', 'sequence', 'type', 'at', 'actor', 'from', 'to',
    ...(hasStudentDetails ? ['studentId', 'studentName'] : []), ...(hasNotes ? ['note'] : [])];
  const rows = report.events.map((event) => [event.caseId, event.sequence, event.type, event.at, event.actor,
    event.from, event.to, ...(hasStudentDetails ? [event.studentId, event.studentName] : []), ...(hasNotes ? [event.note] : [])]);
  return `${[header, ...rows].map((row) => row.map(historyCsvCell).join(',')).join('\r\n')}\r\n`;
}

/** Check whether the append-only event sequence still agrees with each case's
 * current status and assignment. Output is aggregate unless IDs are requested. */
export function auditCasebookHistory(bookValue, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const options = object(optionsValue, 'audit options');
  if (options.includeCaseIds !== undefined && typeof options.includeCaseIds !== 'boolean') {
    throw new TypeError('includeCaseIds must be a boolean');
  }
  const maximumFindings = boundedLimit(options.maximumFindings, 'maximumFindings', 1000, 10_000);
  const findings = [];
  const byCode = {};
  let totalFindings = 0;
  let checkedEvents = 0;
  const addFinding = (item, event, code) => {
    totalFindings++;
    byCode[code] = (byCode[code] ?? 0) + 1;
    if (findings.length < maximumFindings) {
      findings.push({
        ...(options.includeCaseIds ? { caseId: item.caseId } : {}),
        eventSequence: event?.sequence ?? null,
        code,
      });
    }
  };
  for (const item of book.cases) {
    const createdEvents = item.events.filter((event) => event.type === 'created');
    if (createdEvents.length !== 1) addFinding(item, createdEvents[0], 'created_event_count');
    if (item.events[0]?.type !== 'created') addFinding(item, item.events[0], 'created_event_not_first');
    if (item.events[0]?.to !== 'new') addFinding(item, item.events[0], 'created_status_invalid');
    let status = 'new';
    let assigneeId = null;
    let previousEventAt = null;
    for (const event of item.events) {
      checkedEvents++;
      const eventAt = Date.parse(event.at);
      if (previousEventAt !== null && eventAt < previousEventAt) addFinding(item, event, 'event_timestamp_regressed');
      previousEventAt = eventAt;
      if (event.type === 'status') {
        if (event.from !== status) addFinding(item, event, 'status_from_mismatch');
        if (!STATUSES.has(event.to) || !TRANSITIONS[event.from]?.has(event.to)) addFinding(item, event, 'invalid_status_transition');
        if (STATUSES.has(event.to)) status = event.to;
      } else if (event.type === 'assigned') {
        if (event.from !== assigneeId) addFinding(item, event, 'assignee_from_mismatch');
        assigneeId = event.to;
      } else if (event.type === 'note' && !event.note) {
        addFinding(item, event, 'note_text_missing');
      }
    }
    if (status !== item.status) addFinding(item, item.events.at(-1), 'current_status_mismatch');
    if (assigneeId !== item.assigneeId) addFinding(item, item.events.at(-1), 'current_assignee_mismatch');
  }
  return {
    format: 'attendance-casebook-history-audit',
    version: 1,
    casebookId: book.id,
    casebookRevision: book.revision,
    summary: {
      cases: book.cases.length,
      events: checkedEvents,
      findings: totalFindings,
      findingRowsReturned: findings.length,
      findingsTruncated: totalFindings > findings.length,
      valid: totalFindings === 0,
      byCode,
    },
    findings,
  };
}

/** Export the audit findings without embedding case details or event notes. */
export function casebookHistoryAuditToCsv(auditValue) {
  const audit = object(auditValue, 'casebook history audit');
  if (audit.format !== 'attendance-casebook-history-audit' || audit.version !== 1 || !Array.isArray(audit.findings)) {
    throw new TypeError('invalid casebook history audit');
  }
  const hasCaseIds = audit.findings.some((finding) => Object.hasOwn(finding, 'caseId'));
  const header = [...(hasCaseIds ? ['caseId'] : []), 'eventSequence', 'code'];
  return `${[header, ...audit.findings.map((finding) => [
    ...(hasCaseIds ? [finding.caseId] : []), finding.eventSequence, finding.code,
  ])].map((row) => row.map(historyCsvCell).join(',')).join('\r\n')}\r\n`;
}
