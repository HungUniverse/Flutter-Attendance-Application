import { parseCasebook } from './casebook.mjs';

const FORMAT = 'attendance-review-activity';
const VERSION = 1;
const MAX_EVENTS = 1_000_000;
const MAX_EVENT_ROWS = 20_000;
const EVENT_TYPES = ['created', 'status', 'assigned', 'note', 'refreshed', 'stale'];
const TERMINAL = new Set(['resolved', 'dismissed']);

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function date(value, field) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw new TypeError(`${field} must be a valid timestamp`);
  return new Date(value).toISOString();
}

function integer(value, field, maximum) {
  if (!Number.isSafeInteger(value) || value < 1 || value > maximum) throw new RangeError(`${field} must be an integer from 1 to ${maximum}`);
  return value;
}

function normalizeOptions(value, book) {
  const options = object(value, 'activity options');
  const from = date(options.from ?? book.createdAt, 'from');
  const to = date(options.to ?? book.updatedAt, 'to');
  if (Date.parse(from) > Date.parse(to)) throw new RangeError('from must not be after to');
  const includeActorBreakdown = options.includeActorBreakdown ?? false;
  const includeEventRows = options.includeEventRows ?? false;
  if (typeof includeActorBreakdown !== 'boolean' || typeof includeEventRows !== 'boolean') throw new TypeError('activity opt-in options must be booleans');
  const maximumEventRows = integer(options.maximumEventRows ?? 2_000, 'maximumEventRows', MAX_EVENT_ROWS);
  const eventCount = book.cases.reduce((sum, item) => sum + item.events.length, 0);
  if (eventCount > MAX_EVENTS) throw new RangeError(`casebook exceeds ${MAX_EVENTS} events`);
  if (includeEventRows && eventCount > maximumEventRows) throw new RangeError(`event rows exceed maximumEventRows (${maximumEventRows})`);
  return { from, to, includeActorBreakdown, includeEventRows, maximumEventRows };
}

function dayKey(value) {
  return value.slice(0, 10);
}

function quantile(sortedValues, fraction) {
  if (!sortedValues.length) return null;
  const index = Math.min(sortedValues.length - 1, Math.ceil(sortedValues.length * fraction) - 1);
  return sortedValues[index];
}

function durationSummary(values) {
  const sorted = values.map((value) => Math.round(value * 100) / 100).sort((left, right) => left - right);
  return { count: sorted.length,
    meanHours: sorted.length ? Math.round(sorted.reduce((sum, value) => sum + value, 0) / sorted.length * 100) / 100 : null,
    medianHours: sorted.length ? (sorted.length % 2 ? sorted[Math.floor(sorted.length / 2)]
      : Math.round((sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2 * 100) / 100) : null,
    p90Hours: quantile(sorted, 0.9) };
}

/** Summarize review events and resolution cycles from an append-only casebook. */
export function reportCasebookActivity(bookValue, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const options = normalizeOptions(optionsValue, book);
  const fromMs = Date.parse(options.from);
  const toMs = Date.parse(options.to);
  const byType = Object.fromEntries(EVENT_TYPES.map((type) => [type, 0]));
  const byDay = new Map();
  const transitions = new Map();
  const actorCounts = new Map();
  const resolutions = [];
  const eventRows = [];
  const resolvedCaseIds = new Set();
  const dismissedCaseIds = new Set();
  let totalEvents = 0;
  let reopenEvents = 0;
  let openedCases = 0;
  let resolvedCases = 0;
  let dismissedCases = 0;
  for (const item of book.cases) {
    let status = null;
    let openStartedAt = null;
    let previousEventMs = null;
    for (const event of item.events) {
      const eventMs = Date.parse(event.at);
      if (previousEventMs !== null && eventMs < previousEventMs) throw new RangeError(`case ${item.caseId} events are not chronological`);
      previousEventMs = eventMs;
      if (event.type === 'created') {
        status = event.to;
        openStartedAt = TERMINAL.has(status) ? null : eventMs;
      } else if (event.type === 'status') {
        if (TERMINAL.has(event.to)) {
          const closedAt = eventMs;
          if (openStartedAt !== null && eventMs >= fromMs && eventMs <= toMs) resolutions.push({ priority: item.priority, resolution: event.to,
            hours: (closedAt - openStartedAt) / 3_600_000 });
          if (eventMs >= fromMs && eventMs <= toMs) {
            if (event.to === 'resolved') resolvedCaseIds.add(item.caseId);
            else dismissedCaseIds.add(item.caseId);
          }
          openStartedAt = null;
        } else if (TERMINAL.has(status) && !TERMINAL.has(event.to)) {
          openStartedAt = eventMs;
        }
        status = event.to;
        if (event.to === 'reopened' && eventMs >= fromMs && eventMs <= toMs) reopenEvents += 1;
      }
      if (event.type === 'created' && eventMs >= fromMs && eventMs <= toMs) openedCases += 1;
      if (eventMs < fromMs || eventMs > toMs) continue;
      totalEvents += 1;
      byType[event.type] += 1;
      const day = dayKey(event.at);
      if (!byDay.has(day)) byDay.set(day, { date: day, total: 0, ...Object.fromEntries(EVENT_TYPES.map((type) => [type, 0])) });
      const daily = byDay.get(day);
      daily.total += 1;
      daily[event.type] += 1;
      if (event.type === 'status') {
        const key = `${event.from ?? 'unknown'}->${event.to ?? 'unknown'}`;
        transitions.set(key, (transitions.get(key) ?? 0) + 1);
      }
      if (options.includeActorBreakdown && event.actor) actorCounts.set(event.actor, (actorCounts.get(event.actor) ?? 0) + 1);
      if (options.includeEventRows) eventRows.push({ caseId: item.caseId, sequence: event.sequence, type: event.type,
        at: event.at, ...(options.includeActorBreakdown ? { actor: event.actor } : {}), from: event.from, to: event.to });
    }
  }
  const resolvedDurations = resolutions.filter((item) => item.resolution === 'resolved').map((item) => item.hours);
  const dismissedDurations = resolutions.filter((item) => item.resolution === 'dismissed').map((item) => item.hours);
  return { format: FORMAT, version: VERSION, casebookId: book.id, casebookRevision: book.revision,
    window: { from: options.from, to: options.to },
    settings: { includeActorBreakdown: options.includeActorBreakdown, includeEventRows: options.includeEventRows },
    summary: { totalEvents, openedCases, resolvedCases: resolvedCaseIds.size, dismissedCases: dismissedCaseIds.size, reopenedCases: reopenEvents,
      byType, resolvedDuration: durationSummary(resolvedDurations), dismissedDuration: durationSummary(dismissedDurations) },
    byDay: [...byDay.values()].sort((left, right) => left.date.localeCompare(right.date)),
    transitions: [...transitions].sort(([left], [right]) => left.localeCompare(right)).map(([transition, total]) => ({ transition, total })),
    actors: options.includeActorBreakdown ? [...actorCounts].sort(([left], [right]) => left.localeCompare(right)).map(([actor, total]) => ({ actor, total })) : [],
    ...(options.includeEventRows ? { events: eventRows.sort((left, right) => left.at.localeCompare(right.at) || left.caseId.localeCompare(right.caseId) || left.sequence - right.sequence) } : {}),
    note: 'Aggregate review history only. Note contents and student identities are never included.',
  };
}

/** Export an activity section with spreadsheet formula protection. */
export function casebookActivityToCsv(reportValue, section = 'summary') {
  const report = object(reportValue, 'activity report');
  if (report.format !== FORMAT || report.version !== VERSION || !report.summary || !report.window) throw new TypeError('invalid casebook activity report');
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (section === 'summary') return csv(['casebookId', 'casebookRevision', 'from', 'to', 'totalEvents', 'openedCases',
    'resolvedCases', 'dismissedCases', 'reopenedCases', 'meanResolutionHours', 'medianResolutionHours', 'p90ResolutionHours'],
  [[report.casebookId, report.casebookRevision, report.window.from, report.window.to, report.summary.totalEvents,
    report.summary.openedCases, report.summary.resolvedCases, report.summary.dismissedCases, report.summary.reopenedCases,
    report.summary.resolvedDuration.meanHours, report.summary.resolvedDuration.medianHours, report.summary.resolvedDuration.p90Hours]]);
  if (section === 'daily') return csv(['date', 'total', ...EVENT_TYPES], report.byDay.map((item) => [item.date, item.total, ...EVENT_TYPES.map((type) => item[type])]));
  if (section === 'transitions') return csv(['transition', 'total'], report.transitions.map((item) => [item.transition, item.total]));
  if (section === 'actors') return csv(['actor', 'total'], report.actors.map((item) => [item.actor, item.total]));
  if (section === 'events') {
    if (!Array.isArray(report.events)) throw new TypeError('event rows were not enabled in this activity report');
    return csv(['caseId', 'sequence', 'type', 'at', 'actor', 'from', 'to'], report.events.map((item) => [item.caseId,
      item.sequence, item.type, item.at, item.actor, item.from, item.to]));
  }
  throw new TypeError('section must be summary, daily, transitions, actors or events');
}
