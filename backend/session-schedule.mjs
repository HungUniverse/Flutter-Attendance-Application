// Offline scheduling helpers. Times are ISO 8601 instants with an explicit offset.
// Intervals are half-open, so a session may start when another one ends.

function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new TypeError(`${field} must be a non-empty string`);
  }
  return value.trim();
}

function instant(value, field) {
  if (typeof value !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    throw new TypeError(`${field} must be an ISO timestamp with an offset`);
  }
  const result = Date.parse(value);
  if (!Number.isFinite(result)) throw new TypeError(`${field} is not a valid timestamp`);
  // Date.parse accepts some out-of-range calendar days. Validate the original
  // local calendar components independently of its offset.
  const [year, month, day] = value.slice(0, 10).split('-').map(Number);
  const calendar = new Date(0);
  calendar.setUTCFullYear(year, month - 1, day);
  if (calendar.getUTCFullYear() !== year || calendar.getUTCMonth() !== month - 1 ||
      calendar.getUTCDate() !== day) {
    throw new TypeError(`${field} is not a valid timestamp`);
  }
  return result;
}

function interval(start, end) {
  const startMs = instant(start, 'start');
  const endMs = instant(end, 'end');
  if (startMs >= endMs) throw new RangeError('start must be before end');
  return { startMs, endMs };
}

/** Validate and copy sessions. Resource IDs identify rooms, teachers, or groups. */
export function normalizeSchedule(sessions) {
  if (!Array.isArray(sessions)) throw new TypeError('sessions must be an array');
  const ids = new Set();
  return sessions.map((session) => {
    if (!session || typeof session !== 'object') throw new TypeError('invalid session');
    const id = requiredText(session.id, 'id');
    if (ids.has(id)) throw new TypeError(`duplicate session ID: ${id}`);
    ids.add(id);
    const { startMs, endMs } = interval(session.start, session.end);
    if (!Array.isArray(session.resources)) throw new TypeError('resources must be an array');
    const resources = session.resources.map((resource) => requiredText(resource, 'resource'));
    if (new Set(resources).size !== resources.length) throw new TypeError(`duplicate resource in ${id}`);
    return { id, start: new Date(startMs).toISOString(), end: new Date(endMs).toISOString(), resources };
  });
}

/** Find overlapping session pairs with at least one shared resource. */
export function findScheduleConflicts(sessions) {
  const sorted = normalizeSchedule(sessions).sort((a, b) =>
    a.start.localeCompare(b.start) || a.id.localeCompare(b.id));
  const conflicts = [];
  for (let index = 0; index < sorted.length; index++) {
    const first = sorted[index];
    const firstResources = new Set(first.resources);
    for (let next = index + 1; next < sorted.length && sorted[next].start < first.end; next++) {
      const second = sorted[next];
      const resources = second.resources.filter((resource) => firstResources.has(resource)).sort();
      if (resources.length) {
        conflicts.push({
          firstId: first.id,
          secondId: second.id,
          start: second.start,
          end: first.end < second.end ? first.end : second.end,
          resources,
        });
      }
    }
  }
  return conflicts;
}

/** Return available intervals for a resource within a requested window. */
export function findAvailability(sessions, resource, start, end) {
  const target = requiredText(resource, 'resource');
  const window = interval(start, end);
  const busy = normalizeSchedule(sessions)
    .filter((session) => session.resources.includes(target))
    .map((session) => ({ start: Date.parse(session.start), end: Date.parse(session.end) }))
    .filter((item) => item.end > window.startMs && item.start < window.endMs)
    .sort((a, b) => a.start - b.start || a.end - b.end);
  const available = [];
  let cursor = window.startMs;
  for (const item of busy) {
    if (item.start > cursor) {
      available.push({ start: new Date(cursor).toISOString(), end: new Date(item.start).toISOString() });
    }
    cursor = Math.max(cursor, item.end);
    if (cursor >= window.endMs) break;
  }
  if (cursor < window.endMs) {
    available.push({ start: new Date(cursor).toISOString(), end: new Date(window.endMs).toISOString() });
  }
  return available;
}
