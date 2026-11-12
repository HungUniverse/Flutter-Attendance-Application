import { parseCasebook } from './casebook.mjs';

const FORMAT = 'attendance-review-service-level';
const VERSION = 1;
const MAX_CASE_ROWS = 20_000;
const DEFAULT_RULES = Object.freeze({
  urgent: Object.freeze({ responseHours: 4, resolutionHours: 24 }),
  high: Object.freeze({ responseHours: 12, resolutionHours: 72 }),
  review: Object.freeze({ responseHours: 24, resolutionHours: 120 }),
});
const TERMINAL = new Set(['resolved', 'dismissed']);

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function date(value, field) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw new TypeError(`${field} must be a valid timestamp`);
  return new Date(value).toISOString();
}

function hours(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 24 * 3650) throw new RangeError(`${field} must be from 0 to 87600 hours`);
  return value;
}

function normalizeOptions(value, book) {
  const options = object(value, 'service-level options');
  const from = date(options.from ?? book.createdAt, 'from');
  const to = date(options.to ?? book.updatedAt, 'to');
  const asOf = date(options.asOf ?? to, 'asOf');
  if (Date.parse(from) > Date.parse(to)) throw new RangeError('from must not be after to');
  if (Date.parse(to) > Date.parse(asOf)) throw new RangeError('to must not be after asOf');
  const rules = Object.fromEntries(Object.entries(DEFAULT_RULES).map(([priority, defaults]) => {
    const override = options.rules?.[priority] ?? {};
    object(override, `rules.${priority}`);
    return [priority, { responseHours: hours(override.responseHours ?? defaults.responseHours, `rules.${priority}.responseHours`),
      resolutionHours: hours(override.resolutionHours ?? defaults.resolutionHours, `rules.${priority}.resolutionHours`) }];
  }));
  const pauseStatuses = options.pauseStatuses ?? ['data_needed'];
  if (!Array.isArray(pauseStatuses) || pauseStatuses.length > 10 || pauseStatuses.some((status) => typeof status !== 'string' || !status.trim())) {
    throw new TypeError('pauseStatuses must be an array of non-empty status names');
  }
  if (new Set(pauseStatuses).size !== pauseStatuses.length) throw new TypeError('pauseStatuses must not contain duplicates');
  if (pauseStatuses.some((status) => !['new', 'in_review', 'data_needed', 'resolved', 'dismissed', 'reopened'].includes(status))) {
    throw new TypeError('pauseStatuses contains an unsupported case status');
  }
  const includeCaseRows = options.includeCaseRows ?? false;
  if (typeof includeCaseRows !== 'boolean') throw new TypeError('includeCaseRows must be a boolean');
  const maximumCaseRows = options.maximumCaseRows ?? 2_000;
  if (!Number.isSafeInteger(maximumCaseRows) || maximumCaseRows < 1 || maximumCaseRows > MAX_CASE_ROWS) throw new RangeError(`maximumCaseRows must be from 1 to ${MAX_CASE_ROWS}`);
  return { from, to, asOf, rules, pauseStatuses, includeCaseRows, maximumCaseRows };
}

function elapsedActiveHours(events, startMs, endMs, pauseStatuses) {
  let status = null;
  let previousMs = null;
  let elapsedMs = 0;
  for (const event of events) {
    const eventMs = Date.parse(event.at);
    if (previousMs !== null) {
      const left = Math.max(previousMs, startMs);
      const right = Math.min(eventMs, endMs);
      if (right > left && status !== null && !pauseStatuses.includes(status) && !TERMINAL.has(status)) elapsedMs += right - left;
    }
    if (event.type === 'created' || event.type === 'status') status = event.to;
    previousMs = eventMs;
  }
  if (previousMs !== null) {
    const left = Math.max(previousMs, startMs);
    if (endMs > left && status !== null && !pauseStatuses.includes(status) && !TERMINAL.has(status)) elapsedMs += endMs - left;
  }
  return Math.round(elapsedMs / 3_600_000 * 100) / 100;
}

function responseEvent(event) {
  if (event.type === 'assigned') return event.to !== null;
  return event.type === 'status' && ['in_review', 'data_needed', 'resolved', 'dismissed', 'reopened'].includes(event.to);
}

function makeCaseResult(item, options) {
  let previous = null;
  for (const event of item.events) {
    const eventMs = Date.parse(event.at);
    if (previous !== null && eventMs < previous) throw new RangeError(`case ${item.caseId} events are not chronological`);
    previous = eventMs;
  }
  const asOfMs = Date.parse(options.asOf);
  const events = item.events.filter((event) => Date.parse(event.at) <= asOfMs);
  const created = events.find((event) => event.type === 'created');
  if (!created) throw new RangeError(`case ${item.caseId} was created after asOf`);
  const createdMs = Date.parse(created.at);
  const threshold = options.rules[item.priority];
  const response = events.find((event) => event.sequence > created.sequence && responseEvent(event));
  const responseAtMs = response ? Date.parse(response.at) : asOfMs;
  const responseHours = elapsedActiveHours(events, createdMs, responseAtMs, options.pauseStatuses);
  const responseState = response
    ? (responseHours <= threshold.responseHours ? 'met' : 'missed')
    : (responseHours > threshold.responseHours ? 'breached_open' : 'pending');
  const cycles = [];
  let cycleStart = createdMs;
  let currentStatus = created.to;
  for (const event of events.slice(1)) {
    if (event.type !== 'status') continue;
    const eventMs = Date.parse(event.at);
    if (TERMINAL.has(event.to)) {
      const elapsedHours = elapsedActiveHours(events, cycleStart, eventMs, options.pauseStatuses);
      cycles.push({ outcome: event.to, hours: elapsedHours,
        state: elapsedHours <= threshold.resolutionHours ? 'met' : 'missed', at: event.at });
      cycleStart = null;
    } else if (TERMINAL.has(currentStatus) && !TERMINAL.has(event.to)) {
      cycleStart = eventMs;
    }
    currentStatus = event.to;
  }
  const openResolutionHours = cycleStart === null ? null : elapsedActiveHours(events, cycleStart, Date.parse(options.asOf), options.pauseStatuses);
  const resolutionState = cycleStart === null ? 'closed'
    : (openResolutionHours > threshold.resolutionHours ? 'breached_open' : 'pending');
  return { caseId: item.caseId, priority: item.priority, status: item.status, stale: item.stale,
    createdAt: created.at, lastEventAt: events.at(-1).at,
    responseHours, responseAt: response?.at ?? null, responseState,
    resolutionHours: openResolutionHours, resolutionState,
    resolutionCycles: cycles, resolvedCycles: cycles.filter((cycle) => cycle.outcome === 'resolved').length,
    dismissedCycles: cycles.filter((cycle) => cycle.outcome === 'dismissed').length,
    missedResolutionCycles: cycles.filter((cycle) => cycle.state === 'missed').length,
  };
}

function blankCounts(key) {
  return { key, cases: 0, responsesMet: 0, responsesMissed: 0, responsesBreachedOpen: 0, responsesPending: 0,
    resolutionCycles: 0, resolutionMet: 0, resolutionMissed: 0, resolutionsPending: 0, resolutionsBreachedOpen: 0 };
}

function addResult(counts, item) {
  counts.cases += 1;
  counts[`responses${item.responseState === 'met' ? 'Met' : item.responseState === 'missed' ? 'Missed'
    : item.responseState === 'breached_open' ? 'BreachedOpen' : 'Pending'}`] += 1;
  counts.resolutionCycles += item.resolutionCycles.length;
  counts.resolutionMet += item.resolutionCycles.filter((cycle) => cycle.state === 'met').length;
  counts.resolutionMissed += item.resolutionCycles.filter((cycle) => cycle.state === 'missed').length;
  if (item.resolutionState === 'pending') counts.resolutionsPending += 1;
  if (item.resolutionState === 'breached_open') counts.resolutionsBreachedOpen += 1;
}

/** Evaluate response and resolution service levels from casebook event history. */
export function evaluateCasebookServiceLevels(bookValue, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const options = normalizeOptions(optionsValue, book);
  const fromMs = Date.parse(options.from);
  const toMs = Date.parse(options.to);
  const asOfMs = Date.parse(options.asOf);
  const selected = book.cases.filter((item) => {
    const created = item.events.find((event) => event.type === 'created');
    const createdMs = Date.parse(created.at);
    return createdMs >= fromMs && createdMs <= toMs;
  });
  if (options.includeCaseRows && selected.length > options.maximumCaseRows) throw new RangeError(`case rows exceed maximumCaseRows (${options.maximumCaseRows})`);
  const results = selected.map((item) => makeCaseResult(item, options));
  const byPriority = new Map();
  const totals = blankCounts('all');
  for (const result of results) {
    if (!byPriority.has(result.priority)) byPriority.set(result.priority, blankCounts(result.priority));
    addResult(byPriority.get(result.priority), result);
    addResult(totals, result);
  }
  const rates = (counts) => ({ responseMetRate: counts.responsesMet + counts.responsesMissed
    ? counts.responsesMet / (counts.responsesMet + counts.responsesMissed) : null,
  resolutionMetRate: counts.resolutionCycles ? counts.resolutionMet / counts.resolutionCycles : null });
  const priorityRows = [...byPriority.values()].sort((left, right) => left.key.localeCompare(right.key))
    .map((item) => ({ ...item, ...rates(item) }));
  return { format: FORMAT, version: VERSION, casebookId: book.id, casebookRevision: book.revision,
    window: { from: options.from, to: options.to, asOf: options.asOf },
    settings: { rules: options.rules, pauseStatuses: options.pauseStatuses, includeCaseRows: options.includeCaseRows },
    summary: { ...totals, ...rates(totals) }, byPriority: priorityRows,
    ...(options.includeCaseRows ? { cases: results } : {}),
    note: 'A local historical review report. It does not contact reviewers or alter case status.',
  };
}

/** Export aggregate or explicitly enabled per-case service-level rows. */
export function casebookServiceLevelsToCsv(reportValue, section = 'summary') {
  const report = object(reportValue, 'service-level report');
  if (report.format !== FORMAT || report.version !== VERSION || !report.summary || !Array.isArray(report.byPriority)) {
    throw new TypeError('invalid service-level report');
  }
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (section === 'summary') return csv(Object.keys(report.summary), [Object.values(report.summary)]);
  if (section === 'priority') return csv(Object.keys(report.byPriority[0] ?? blankCounts('')).concat(['responseMetRate', 'resolutionMetRate']),
    report.byPriority.map((item) => Object.values(item)));
  if (section === 'cases') {
    if (!Array.isArray(report.cases)) throw new TypeError('case rows were not enabled in this service-level report');
    return csv(['caseId', 'priority', 'status', 'stale', 'createdAt', 'lastEventAt', 'responseHours', 'responseAt',
      'responseState', 'resolutionHours', 'resolutionState', 'resolvedCycles', 'dismissedCycles', 'missedResolutionCycles'],
    report.cases.map((item) => [item.caseId, item.priority, item.status, item.stale, item.createdAt, item.lastEventAt,
      item.responseHours, item.responseAt, item.responseState, item.resolutionHours, item.resolutionState,
      item.resolvedCycles, item.dismissedCycles, item.missedResolutionCycles]));
  }
  throw new TypeError('section must be summary, priority or cases');
}
