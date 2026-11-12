import { normalizeSchedule } from './session-schedule.mjs';

const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_DAYS = 3660;

function parseDate(value, name) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new TypeError(`${name} must be a YYYY-MM-DD date`);
  }
  const timestamp = Date.parse(`${value}T00:00:00.000Z`);
  if (!Number.isFinite(timestamp) || new Date(timestamp).toISOString().slice(0, 10) !== value) {
    throw new TypeError(`${name} must be a valid date`);
  }
  return timestamp;
}

function parseTime(value) {
  if (typeof value !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) {
    throw new TypeError('startTime must be HH:MM in UTC');
  }
  const [hours, minutes] = value.split(':').map(Number);
  return (hours * 60 + minutes) * 60 * 1000;
}

/**
 * Generate sessions on selected UTC weekdays within an inclusive date range.
 * Exceptions suppress occurrences without extending the end date. IDs combine
 * the caller's prefix with the UTC date so reruns use stable identifiers.
 */
export function generateRecurringSessions(options) {
  if (!options || typeof options !== 'object') throw new TypeError('options must be an object');
  const { startDate, endDate, startTime, durationMinutes, weekdays, resources, idPrefix } = options;
  const first = parseDate(startDate, 'startDate');
  const last = parseDate(endDate, 'endDate');
  if (last < first || (last - first) / DAY_MS >= MAX_DAYS) {
    throw new RangeError('date range must be ordered and shorter than 3660 days');
  }
  const time = parseTime(startTime);
  if (!Number.isInteger(durationMinutes) || durationMinutes < 1 || durationMinutes > 1440) {
    throw new RangeError('durationMinutes must be between 1 and 1440');
  }
  if (!Array.isArray(weekdays) || !weekdays.length ||
      weekdays.some((day) => !Number.isInteger(day) || day < 0 || day > 6) ||
      new Set(weekdays).size !== weekdays.length) {
    throw new TypeError('weekdays must contain distinct values from 0 to 6');
  }
  if (typeof idPrefix !== 'string' || !idPrefix.trim()) throw new TypeError('idPrefix is required');
  const exceptions = options.exceptions ?? [];
  if (!Array.isArray(exceptions)) throw new TypeError('exceptions must be an array');
  const excluded = new Set(exceptions.map((date) => parseDate(date, 'exception')));
  if (excluded.size !== exceptions.length) throw new TypeError('duplicate exception');
  const selectedDays = new Set(weekdays);
  const sessions = [];
  for (let date = first; date <= last; date += DAY_MS) {
    if (!selectedDays.has(new Date(date).getUTCDay()) || excluded.has(date)) continue;
    const start = date + time;
    const end = start + durationMinutes * 60 * 1000;
    sessions.push({
      id: `${idPrefix.trim()}-${new Date(date).toISOString().slice(0, 10)}`,
      start: new Date(start).toISOString(),
      end: new Date(end).toISOString(),
      resources,
    });
  }
  // Validate resources even if the range has no occurrences.
  normalizeSchedule([{ id: 'validation', start: '2000-01-01T00:00:00Z',
    end: '2000-01-01T00:01:00Z', resources }]);
  return normalizeSchedule(sessions);
}
