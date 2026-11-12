import { findScheduleConflicts, normalizeSchedule } from '../../backend/session-schedule.mjs';

const FORMAT = 'attendance-schedule-insights';
const VERSION = 1;
const DAY_MINUTES = 24 * 60;
const MAX_WINDOW_DAYS = 366;

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 160) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function integer(value, field, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  return value;
}

function instant(value, field) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) || !Number.isFinite(Date.parse(value))) {
    throw new TypeError(`${field} must be an ISO timestamp with an explicit offset`);
  }
  return Date.parse(value);
}

function minuteOfDay(value, field) {
  if (typeof value !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) throw new TypeError(`${field} must use HH:mm in UTC`);
  const [hour, minute] = value.split(':').map(Number);
  return hour * 60 + minute;
}

function normalizeSessions(values) {
  if (!Array.isArray(values) || values.length > 100_000) throw new RangeError('schedule must be an array with at most 100000 sessions');
  const normalized = normalizeSchedule(values);
  const originalById = new Map(values.map((session) => [session.id, session]));
  return normalized.map((session) => {
    const original = originalById.get(session.id);
    const optionalIds = {};
    for (const field of ['roomId', 'groupId', 'instructorId']) {
      optionalIds[field] = original[field] === undefined || original[field] === null || original[field] === '' ? null : text(original[field], `${session.id}.${field}`);
    }
    const attendees = original.attendees === undefined ? null : integer(original.attendees, `${session.id}.attendees`, 0, 1_000_000);
    const title = original.title === undefined ? session.id : text(original.title, `${session.id}.title`, 300);
    return { ...session, ...optionalIds, attendees, title, startMs: Date.parse(session.start), endMs: Date.parse(session.end),
      durationMinutes: (Date.parse(session.end) - Date.parse(session.start)) / 60_000 };
  });
}

function normalizeCatalog(value) {
  if (value === undefined) return new Map();
  if (!Array.isArray(value) || value.length > 10_000) throw new RangeError('resourceCatalog must be an array with at most 10000 entries');
  const entries = new Map();
  for (let index = 0; index < value.length; index++) {
    const entry = object(value[index], `resourceCatalog[${index}]`);
    const id = text(entry.id, `resourceCatalog[${index}].id`);
    if (entries.has(id)) throw new TypeError(`duplicate resource catalog ID: ${id}`);
    const kind = text(entry.kind ?? 'unclassified', `resourceCatalog[${index}].kind`, 80);
    const capacity = entry.capacity === undefined || entry.capacity === null ? null : integer(entry.capacity, `${id}.capacity`, 0, 1_000_000);
    entries.set(id, { id, kind, capacity, label: text(entry.label ?? id, `${id}.label`, 160) });
  }
  return entries;
}

function normalizeAvailability(value, resourceIds) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 20_000) throw new RangeError('availability must be an array with at most 20000 recurring windows');
  return value.map((entry, index) => {
    object(entry, `availability[${index}]`);
    const resourceId = text(entry.resourceId, `availability[${index}].resourceId`);
    if (!resourceIds.has(resourceId)) throw new TypeError(`availability refers to a resource not used in the schedule: ${resourceId}`);
    if (!Array.isArray(entry.weekdays) || !entry.weekdays.length) throw new TypeError(`availability[${index}].weekdays must be a non-empty array`);
    const weekdays = entry.weekdays.map((day) => integer(day, `availability[${index}].weekday`, 0, 6));
    if (new Set(weekdays).size !== weekdays.length) throw new TypeError(`availability[${index}].weekdays must be unique`);
    const startMinute = minuteOfDay(entry.start, `availability[${index}].start`);
    const endMinute = minuteOfDay(entry.end, `availability[${index}].end`);
    if (startMinute >= endMinute) throw new RangeError(`availability[${index}] must end later on the same UTC day`);
    return { resourceId, weekdays, startMinute, endMinute };
  });
}

function normalizeOptions(value, sessions) {
  const options = object(value, 'schedule insights options');
  const bounds = options.window === undefined ? null : object(options.window, 'window');
  const window = bounds ? { start: instant(bounds.start, 'window.start'), end: instant(bounds.end, 'window.end') } : null;
  if (window && window.start >= window.end) throw new RangeError('window.start must be before window.end');
  const resourceCatalog = normalizeCatalog(options.resourceCatalog);
  const resourceIds = new Set(sessions.flatMap((session) => session.resources));
  for (const session of sessions) for (const id of [session.roomId, session.groupId, session.instructorId]) if (id) resourceIds.add(id);
  const availability = normalizeAvailability(options.availability, resourceIds);
  const minimumBufferMinutes = integer(options.minimumBufferMinutes ?? 0, 'minimumBufferMinutes', 0, 1440);
  const maximumDailySessions = options.maximumDailySessions === undefined ? null : integer(options.maximumDailySessions, 'maximumDailySessions', 1, 1000);
  const maximumDailyMinutes = options.maximumDailyMinutes === undefined ? null : integer(options.maximumDailyMinutes, 'maximumDailyMinutes', 1, 1440);
  return { window, resourceCatalog, availability, minimumBufferMinutes, maximumDailySessions, maximumDailyMinutes,
    includeTimeline: options.includeTimeline !== false, maximumTimelineRows: integer(options.maximumTimelineRows ?? 10_000, 'maximumTimelineRows', 1, 100_000) };
}

function dayKey(milliseconds) {
  return new Date(milliseconds).toISOString().slice(0, 10);
}

function dayOfWeek(key) {
  return new Date(`${key}T00:00:00.000Z`).getUTCDay();
}

function mergeIntervals(intervals) {
  const sorted = intervals.map(([start, end]) => [start, end]).sort((left, right) => left[0] - right[0] || left[1] - right[1]);
  const merged = [];
  for (const interval of sorted) {
    const last = merged.at(-1);
    if (!last || interval[0] > last[1]) merged.push(interval);
    else last[1] = Math.max(last[1], interval[1]);
  }
  return merged;
}

function sumMinutes(intervals) {
  return intervals.reduce((sum, [start, end]) => sum + (end - start) / 60_000, 0);
}

function resourceIntervals(resourceId, sessions) {
  return sessions.filter((session) => session.resources.includes(resourceId) ||
    session.roomId === resourceId || session.groupId === resourceId || session.instructorId === resourceId)
    .map((session) => [session.startMs, session.endMs]);
}

function availabilityMinutes(resourceId, availability, start, end) {
  if (!availability.length) return null;
  const applicable = availability.filter((window) => window.resourceId === resourceId);
  if (!applicable.length) return null;
  const startDay = Date.parse(`${dayKey(start)}T00:00:00.000Z`);
  const endDay = Date.parse(`${dayKey(Math.max(start, end - 1))}T00:00:00.000Z`);
  const intervals = [];
  for (let day = startDay; day <= endDay; day += 86_400_000) {
    const weekday = new Date(day).getUTCDay();
    for (const window of applicable) if (window.weekdays.includes(weekday)) {
      const open = day + window.startMinute * 60_000;
      const close = day + window.endMinute * 60_000;
      intervals.push([Math.max(open, start), Math.min(close, end)]);
    }
  }
  return sumMinutes(mergeIntervals(intervals.filter(([open, close]) => open < close)));
}

function intersectionMinutes(interval, windows) {
  return mergeIntervals(windows.flatMap((window) => {
    const start = Math.max(interval[0], window[0]);
    const end = Math.min(interval[1], window[1]);
    return start < end ? [[start, end]] : [];
  })).reduce((sum, [start, end]) => sum + (end - start) / 60_000, 0);
}

function gapsForResource(resourceId, sessions, bufferMinutes, warnings) {
  const assigned = sessions.filter((session) => session.resources.includes(resourceId) ||
    session.roomId === resourceId || session.groupId === resourceId || session.instructorId === resourceId)
    .sort((left, right) => left.startMs - right.startMs || left.id.localeCompare(right.id));
  const gaps = [];
  for (let index = 1; index < assigned.length; index++) {
    const previous = assigned[index - 1];
    const next = assigned[index];
    const gapMinutes = (next.startMs - previous.endMs) / 60_000;
    if (gapMinutes < 0) continue;
    gaps.push(gapMinutes);
    if (gapMinutes < bufferMinutes) warnings.push({ code: 'short_resource_turnaround', severity: 'warning', resourceId,
      firstSessionId: previous.id, secondSessionId: next.id, gapMinutes, requiredBufferMinutes: bufferMinutes });
  }
  return gaps;
}

function intervalOutsideAvailability(interval, windows, start, end) {
  if (!windows.length) return 0;
  const clipped = [Math.max(interval[0], start), Math.min(interval[1], end)];
  if (clipped[0] >= clipped[1]) return 0;
  const total = (clipped[1] - clipped[0]) / 60_000;
  return Math.max(0, total - intersectionMinutes(clipped, windows));
}

function computeOutsideAvailability(resourceId, sessions, availability, start, end) {
  const windows = [];
  const startDay = Date.parse(`${dayKey(start)}T00:00:00.000Z`);
  const endDay = Date.parse(`${dayKey(Math.max(start, end - 1))}T00:00:00.000Z`);
  for (let day = startDay; day <= endDay; day += 86_400_000) {
    const weekday = new Date(day).getUTCDay();
    for (const item of availability) if (item.resourceId === resourceId && item.weekdays.includes(weekday)) {
      windows.push([Math.max(day + item.startMinute * 60_000, start), Math.min(day + item.endMinute * 60_000, end)]);
    }
  }
  return sessions.reduce((sum, session) => sum + intervalOutsideAvailability([session.startMs, session.endMs], windows, start, end), 0);
}

function addWarning(warnings, code, fields = {}) {
  warnings.push({ code, severity: 'warning', ...fields });
}

/** Analyze utilization, resource turnarounds, day loads and schedule conflicts. */
export function analyzeScheduleInsights(scheduleValue, optionsValue = {}) {
  const sessions = normalizeSessions(scheduleValue);
  const options = normalizeOptions(optionsValue, sessions);
  let start = options.window?.start ?? (sessions.length ? Math.min(...sessions.map((session) => session.startMs)) : 0);
  let end = options.window?.end ?? (sessions.length ? Math.max(...sessions.map((session) => session.endMs)) : 0);
  if (start === end && !options.window) end = start + 1;
  const dayCount = end > start ? Math.floor((Date.parse(`${dayKey(Math.max(start, end - 1))}T00:00:00.000Z`) - Date.parse(`${dayKey(start)}T00:00:00.000Z`)) / 86_400_000) + 1 : 0;
  if (dayCount > MAX_WINDOW_DAYS) throw new RangeError(`analysis window must not exceed ${MAX_WINDOW_DAYS} days`);
  const scoped = sessions.filter((session) => session.endMs > start && session.startMs < end);
  const warnings = [];
  const conflicts = findScheduleConflicts(scoped.map((session) => ({ ...session, resources: [...new Set([
    ...session.resources, session.roomId, session.groupId, session.instructorId,
  ].filter(Boolean))] })));
  for (const conflict of conflicts) addWarning(warnings, 'shared_resource_overlap', { ...conflict, severity: 'error' });

  const days = new Map();
  for (const session of scoped) {
    const date = dayKey(session.startMs);
    if (!days.has(date)) days.set(date, []);
    days.get(date).push(session);
    if (session.endMs > end || session.startMs < start) addWarning(warnings, 'session_crosses_analysis_window', { sessionId: session.id });
  }
  const dailyRows = [...days.entries()].sort(([left], [right]) => left.localeCompare(right)).map(([date, items]) => {
    const totalMinutes = items.reduce((sum, item) => sum + item.durationMinutes, 0);
    if (options.maximumDailySessions !== null && items.length > options.maximumDailySessions) {
      addWarning(warnings, 'daily_session_limit_exceeded', { date, actual: items.length, maximum: options.maximumDailySessions });
    }
    if (options.maximumDailyMinutes !== null && totalMinutes > options.maximumDailyMinutes) {
      addWarning(warnings, 'daily_minutes_limit_exceeded', { date, actual: totalMinutes, maximum: options.maximumDailyMinutes });
    }
    return { date, weekday: dayOfWeek(date), sessions: items.length, totalMinutes,
      earliestStart: items.reduce((min, item) => Math.min(min, item.startMs), Infinity),
      latestEnd: items.reduce((max, item) => Math.max(max, item.endMs), -Infinity) };
  }).map((day) => ({ ...day, earliestStart: new Date(day.earliestStart).toISOString(), latestEnd: new Date(day.latestEnd).toISOString() }));

  const resourceIds = new Set(scoped.flatMap((session) => [
    ...session.resources,
    ...(session.roomId ? [session.roomId] : []),
    ...(session.groupId ? [session.groupId] : []),
    ...(session.instructorId ? [session.instructorId] : []),
  ]));
  for (const item of options.availability) resourceIds.add(item.resourceId);
  const resources = [...resourceIds].sort().map((id) => {
    const catalog = options.resourceCatalog.get(id) ?? { id, label: id, kind: 'unclassified', capacity: null };
    const assigned = scoped.filter((session) => session.resources.includes(id) || session.roomId === id || session.groupId === id || session.instructorId === id);
    const intervals = resourceIntervals(id, scoped);
    const unionMinutes = sumMinutes(mergeIntervals(intervals));
    const assignedMinutes = assigned.reduce((sum, session) => sum + session.durationMinutes, 0);
    const availableMinutes = availabilityMinutes(id, options.availability, start, end);
    const gaps = gapsForResource(id, scoped, options.minimumBufferMinutes, warnings);
    const outsideMinutes = computeOutsideAvailability(id, assigned, options.availability, start, end);
    return {
      id,
      label: catalog.label,
      kind: catalog.kind,
      capacity: catalog.capacity,
      sessions: assigned.length,
      assignedMinutes,
      unionOccupiedMinutes: unionMinutes,
      overlapMinutes: Math.max(0, assignedMinutes - unionMinutes),
      availableMinutes,
      utilization: availableMinutes ? unionMinutes / availableMinutes : null,
      outsideAvailabilityMinutes: availableMinutes === null ? null : outsideMinutes,
      turnaround: { gapCount: gaps.length, minimumGapMinutes: gaps.length ? Math.min(...gaps) : null,
        averageGapMinutes: gaps.length ? gaps.reduce((sum, gap) => sum + gap, 0) / gaps.length : null },
    };
  });

  for (const session of scoped) {
    if (session.attendees === null) continue;
    if (!session.roomId) addWarning(warnings, 'session_attendee_count_without_room', { sessionId: session.id, attendees: session.attendees });
    const room = session.roomId ? options.resourceCatalog.get(session.roomId) : null;
    if (room?.capacity !== null && room?.capacity !== undefined && session.attendees > room.capacity) {
      addWarning(warnings, 'room_capacity_exceeded', { sessionId: session.id, roomId: session.roomId,
        attendees: session.attendees, capacity: room.capacity, excess: session.attendees - room.capacity });
    }
  }

  const weekdays = Array.from({ length: 7 }, (_, weekday) => ({ weekday,
    sessions: scoped.filter((session) => new Date(session.startMs).getUTCDay() === weekday).length,
    minutes: scoped.filter((session) => new Date(session.startMs).getUTCDay() === weekday)
      .reduce((sum, session) => sum + session.durationMinutes, 0),
  }));
  const hours = Array.from({ length: 24 }, (_, hour) => ({ hour,
    sessionsStarting: scoped.filter((session) => new Date(session.startMs).getUTCHours() === hour).length,
  }));
  const totalMinutes = scoped.reduce((sum, session) => sum + session.durationMinutes, 0);
  const timeline = options.includeTimeline ? scoped.slice().sort((left, right) => left.startMs - right.startMs || left.id.localeCompare(right.id))
    .slice(0, options.maximumTimelineRows).map((session) => ({ id: session.id, title: session.title,
      start: session.start, end: session.end, durationMinutes: session.durationMinutes,
      roomId: session.roomId, groupId: session.groupId, instructorId: session.instructorId, resources: [...session.resources],
      attendees: session.attendees })) : null;
  return {
    format: FORMAT,
    version: VERSION,
    window: { start: new Date(start).toISOString(), end: new Date(end).toISOString(), days: dayCount },
    settings: { minimumBufferMinutes: options.minimumBufferMinutes, maximumDailySessions: options.maximumDailySessions,
      maximumDailyMinutes: options.maximumDailyMinutes, includeTimeline: options.includeTimeline,
      maximumTimelineRows: options.maximumTimelineRows },
    summary: { sessions: scoped.length, daysUsed: dailyRows.length, resources: resources.length, totalMinutes,
      totalHours: totalMinutes / 60, conflicts: conflicts.length, warnings: warnings.length,
      scheduledAttendees: scoped.reduce((sum, session) => sum + (session.attendees ?? 0), 0),
      sessionsWithAttendanceCount: scoped.filter((session) => session.attendees !== null).length,
      timelineTruncated: options.includeTimeline ? Math.max(0, scoped.length - options.maximumTimelineRows) : null },
    resources,
    daily: dailyRows,
    weekdays,
    hours,
    conflicts,
    warnings,
    timeline,
    note: 'Utilization and workload summaries describe the supplied schedule only; they do not reserve resources or publish calendar events.',
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

/** Export one schedule analysis section with spreadsheet-safe cells. */
export function scheduleInsightsToCsv(reportValue, section = 'resources') {
  const report = object(reportValue, 'schedule insights report');
  if (report.format !== FORMAT || report.version !== VERSION) throw new TypeError('invalid schedule insights report');
  if (section === 'resources') return csv(['resourceId', 'label', 'kind', 'capacity', 'sessions', 'assignedMinutes',
    'unionOccupiedMinutes', 'overlapMinutes', 'availableMinutes', 'utilization', 'outsideAvailabilityMinutes',
    'gapCount', 'minimumGapMinutes', 'averageGapMinutes'], report.resources.map((item) => [
    item.id, item.label, item.kind, item.capacity, item.sessions, item.assignedMinutes, item.unionOccupiedMinutes,
    item.overlapMinutes, item.availableMinutes, item.utilization, item.outsideAvailabilityMinutes,
    item.turnaround.gapCount, item.turnaround.minimumGapMinutes, item.turnaround.averageGapMinutes,
  ]));
  if (section === 'daily') return csv(['date', 'weekday', 'sessions', 'totalMinutes', 'earliestStart', 'latestEnd'],
    report.daily.map((item) => [item.date, item.weekday, item.sessions, item.totalMinutes, item.earliestStart, item.latestEnd]));
  if (section === 'conflicts') return csv(['firstId', 'secondId', 'start', 'end', 'resources'],
    report.conflicts.map((item) => [item.firstId, item.secondId, item.start, item.end, item.resources.join('|')]));
  if (section === 'warnings') return csv(['code', 'severity', 'sessionId', 'resourceId', 'date', 'actual', 'maximum', 'gapMinutes', 'message'],
    report.warnings.map((item) => [item.code, item.severity, item.sessionId, item.resourceId, item.date,
      item.actual, item.maximum, item.gapMinutes, item.message]));
  if (section === 'timeline') {
    if (!Array.isArray(report.timeline)) throw new TypeError('timeline was not included in this report');
    return csv(['sessionId', 'title', 'start', 'end', 'durationMinutes', 'roomId', 'groupId', 'instructorId', 'attendees', 'resources'],
      report.timeline.map((item) => [item.id, item.title, item.start, item.end, item.durationMinutes,
        item.roomId, item.groupId, item.instructorId, item.attendees, item.resources.join('|')]));
  }
  if (section === 'weekdays') return csv(['weekday', 'sessions', 'minutes'], report.weekdays.map((item) => [item.weekday, item.sessions, item.minutes]));
  if (section === 'hours') return csv(['hourUtc', 'sessionsStarting'], report.hours.map((item) => [item.hour, item.sessionsStarting]));
  throw new TypeError('section must be resources, daily, conflicts, warnings, timeline, weekdays or hours');
}
