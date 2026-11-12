import { parseCasebook } from './casebook.mjs';

const FORMAT = 'attendance-review-sla-report';
const VERSION = 1;
const DEFAULT_RULES = Object.freeze({
  urgent: Object.freeze({ warnAfterHours: 4, breachAfterHours: 8 }),
  high: Object.freeze({ warnAfterHours: 24, breachAfterHours: 48 }),
  review: Object.freeze({ warnAfterHours: 48, breachAfterHours: 96 }),
});
const TERMINAL = new Set(['resolved', 'dismissed']);

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 160) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  }
  return value.trim();
}

function date(value, field) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw new TypeError(`${field} must be a valid timestamp`);
  return new Date(value).toISOString();
}

function number(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 24 * 3650) {
    throw new RangeError(`${field} must be a number from 0 to 87600`);
  }
  return value;
}

function normalizeOptions(value) {
  const options = object(value, 'SLA options');
  const asOf = date(options.asOf ?? new Date().toISOString(), 'asOf');
  const rules = Object.fromEntries(Object.entries(DEFAULT_RULES).map(([priority, defaults]) => {
    const override = options.rules?.[priority] ?? {};
    object(override, `rules.${priority}`);
    const warnAfterHours = number(override.warnAfterHours ?? defaults.warnAfterHours, `rules.${priority}.warnAfterHours`);
    const breachAfterHours = number(override.breachAfterHours ?? defaults.breachAfterHours, `rules.${priority}.breachAfterHours`);
    if (warnAfterHours > breachAfterHours) throw new RangeError(`rules.${priority}.warnAfterHours cannot exceed breachAfterHours`);
    return [priority, { warnAfterHours, breachAfterHours }];
  }));
  const pauseStatuses = options.pauseStatuses ?? ['data_needed'];
  if (!Array.isArray(pauseStatuses) || pauseStatuses.length > 10 || pauseStatuses.some((item) => typeof item !== 'string' || !item.trim())) {
    throw new TypeError('pauseStatuses must be an array of non-empty status names');
  }
  if (new Set(pauseStatuses).size !== pauseStatuses.length) throw new TypeError('pauseStatuses must not contain duplicates');
  const invalidStatuses = pauseStatuses.filter((status) => !['new', 'in_review', 'data_needed', 'resolved', 'dismissed', 'reopened'].includes(status));
  if (invalidStatuses.length) throw new TypeError(`unsupported pause status: ${invalidStatuses[0]}`);
  const includeStudentDetails = options.includeStudentDetails ?? false;
  if (typeof includeStudentDetails !== 'boolean') throw new TypeError('includeStudentDetails must be a boolean');
  return { asOf, rules, pauseStatuses: [...pauseStatuses], includeStudentDetails };
}

function activeMilliseconds(item, asOf, pauseStatuses) {
  const cutoff = Date.parse(asOf);
  let status = null;
  let active = 0;
  let paused = 0;
  for (let index = 0; index < item.events.length; index += 1) {
    const event = item.events[index];
    const starts = Date.parse(event.at);
    if (starts > cutoff) throw new RangeError(`case ${item.caseId} has an event after asOf`);
    if (event.type === 'created' || event.type === 'status') status = event.to;
    const next = item.events[index + 1];
    const ends = next ? Date.parse(next.at) : cutoff;
    if (ends < starts) throw new RangeError(`case ${item.caseId} events are not chronological`);
    const duration = ends - starts;
    if (pauseStatuses.includes(status)) paused += duration;
    else if (status !== null && !TERMINAL.has(status)) active += duration;
  }
  return { active, paused };
}

function hours(value) {
  return Math.round(value / 3_600_000 * 100) / 100;
}

function classify(item, activeHours, options) {
  if (TERMINAL.has(item.status)) return 'closed';
  if (options.pauseStatuses.includes(item.status)) return 'paused';
  const threshold = options.rules[item.priority];
  if (activeHours >= threshold.breachAfterHours) return 'breached';
  if (activeHours >= threshold.warnAfterHours) return 'due_soon';
  return 'on_track';
}

function addCount(map, key, field) {
  const current = map.get(key) ?? { key, total: 0, on_track: 0, due_soon: 0, breached: 0, paused: 0, closed: 0 };
  current.total += 1;
  current[field] += 1;
  map.set(key, current);
}

function sortedCounts(map) {
  return [...map.values()].sort((left, right) => left.key.localeCompare(right.key));
}

/** Report review-case aging without changing the append-only casebook. */
export function reportCasebookSla(bookValue, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const options = normalizeOptions(optionsValue);
  const cases = book.cases.map((item) => {
    const duration = activeMilliseconds(item, options.asOf, options.pauseStatuses);
    const activeHours = hours(duration.active);
    const pausedHours = hours(duration.paused);
    const state = classify(item, activeHours, options);
    const thresholds = options.rules[item.priority];
    return {
      caseId: item.caseId,
      ...(options.includeStudentDetails ? { studentId: item.studentId, studentName: item.studentName } : {}),
      priority: item.priority,
      status: item.status,
      assigneeId: item.assigneeId,
      stale: item.stale,
      activeHours,
      pausedHours,
      warnAfterHours: thresholds.warnAfterHours,
      breachAfterHours: thresholds.breachAfterHours,
      hoursUntilWarning: Math.max(0, Math.round((thresholds.warnAfterHours - activeHours) * 100) / 100),
      hoursUntilBreach: Math.max(0, Math.round((thresholds.breachAfterHours - activeHours) * 100) / 100),
      state,
      lastEventAt: item.events.at(-1)?.at ?? null,
    };
  }).sort((left, right) => {
    const severity = { breached: 0, due_soon: 1, on_track: 2, paused: 3, closed: 4 };
    return severity[left.state] - severity[right.state] || right.activeHours - left.activeHours || left.caseId.localeCompare(right.caseId);
  });
  const byState = Object.fromEntries(['on_track', 'due_soon', 'breached', 'paused', 'closed'].map((state) => [
    state, cases.filter((item) => item.state === state).length,
  ]));
  const priorityCounts = new Map();
  const assigneeCounts = new Map();
  for (const item of cases) {
    addCount(priorityCounts, item.priority, item.state);
    addCount(assigneeCounts, item.assigneeId ?? 'unassigned', item.state);
  }
  return {
    format: FORMAT,
    version: VERSION,
    casebookId: book.id,
    casebookRevision: book.revision,
    asOf: options.asOf,
    settings: { rules: options.rules, pauseStatuses: options.pauseStatuses, includeStudentDetails: options.includeStudentDetails },
    summary: { total: cases.length, ...byState, stale: cases.filter((item) => item.stale).length,
      assigned: cases.filter((item) => item.assigneeId !== null).length,
      activeHours: hours(cases.reduce((sum, item) => sum + item.activeHours * 3_600_000, 0)),
      pausedHours: hours(cases.reduce((sum, item) => sum + item.pausedHours * 3_600_000, 0)) },
    byPriority: sortedCounts(priorityCounts),
    byAssignee: sortedCounts(assigneeCounts),
    cases,
    note: 'A local elapsed-time report only. It does not notify assignees or update case status.',
  };
}

/** Export a bounded report section with spreadsheet-formula protection. */
export function casebookSlaToCsv(reportValue, section = 'cases') {
  const report = object(reportValue, 'SLA report');
  if (report.format !== FORMAT || report.version !== VERSION || !Array.isArray(report.cases) || !report.summary) {
    throw new TypeError('invalid casebook SLA report');
  }
  const cell = (value) => {
    let source = value === null || value === undefined ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (section === 'cases') return csv(['caseId', 'studentId', 'studentName', 'priority', 'status', 'assigneeId', 'stale',
    'activeHours', 'pausedHours', 'warnAfterHours', 'breachAfterHours', 'hoursUntilWarning', 'hoursUntilBreach', 'state', 'lastEventAt'],
  report.cases.map((item) => [item.caseId, item.studentId, item.studentName, item.priority, item.status, item.assigneeId,
    item.stale, item.activeHours, item.pausedHours, item.warnAfterHours, item.breachAfterHours,
    item.hoursUntilWarning, item.hoursUntilBreach, item.state, item.lastEventAt]));
  if (section === 'priority') return csv(['priority', 'total', 'on_track', 'due_soon', 'breached', 'paused', 'closed'],
    report.byPriority.map((item) => [item.key, item.total, item.on_track, item.due_soon, item.breached, item.paused, item.closed]));
  if (section === 'assignee') return csv(['assigneeId', 'total', 'on_track', 'due_soon', 'breached', 'paused', 'closed'],
    report.byAssignee.map((item) => [item.key, item.total, item.on_track, item.due_soon, item.breached, item.paused, item.closed]));
  if (section === 'summary') return csv(['asOf', 'casebookId', 'casebookRevision', ...Object.keys(report.summary)],
    [[report.asOf, report.casebookId, report.casebookRevision, ...Object.values(report.summary)]]);
  throw new TypeError('section must be cases, priority, assignee or summary');
}
