import { normalizeSchedule } from './session-schedule.mjs';

function escapeText(value) {
  return value.replaceAll('\\', '\\\\').replace(/\r\n|\r|\n/g, '\\n')
    .replaceAll(';', '\\;').replaceAll(',', '\\,');
}

function foldLine(line) {
  const segments = [];
  let current = '';
  let bytes = 0;
  for (const character of line) {
    const size = Buffer.byteLength(character, 'utf8');
    if (bytes + size > 75) {
      segments.push(current);
      current = ' ';
      bytes = 1;
    }
    current += character;
    bytes += size;
  }
  segments.push(current);
  return segments.join('\r\n');
}

function formatInstant(value, field) {
  // UTC timestamps with second precision avoid changing a session's duration.
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.000Z$/.test(value)) {
    throw new TypeError(`${field} must have second precision`);
  }
  return value.replace(/[-:]/g, '').replace('.000', '');
}

/**
 * Export normalized sessions as a calendar string. Each session uses its ID
 * plus the caller-supplied domain as a stable UID. generatedAt is caller-owned
 * so repeated exports can be reproducible. No filesystem access is performed.
 */
export function sessionsToICalendar(sessions, { uidDomain, generatedAt, title = 'Class session' } = {}) {
  if (typeof uidDomain !== 'string' || !/^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(uidDomain)) {
    throw new TypeError('uidDomain must be a hostname');
  }
  if (typeof title !== 'string' || !title.trim()) throw new TypeError('title is required');
  if (typeof generatedAt !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(generatedAt)) {
    throw new TypeError('generatedAt must be a UTC timestamp with seconds');
  }
  const timestamp = new Date(generatedAt);
  if (!Number.isFinite(timestamp.getTime()) || timestamp.toISOString() !== generatedAt.replace('Z', '.000Z')) {
    throw new TypeError('generatedAt must be a valid timestamp');
  }
  const lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Attendance Utilities//Session Calendar//EN',
    'CALSCALE:GREGORIAN'];
  for (const session of normalizeSchedule(sessions)) {
    lines.push('BEGIN:VEVENT', `UID:${encodeURIComponent(session.id)}@${uidDomain}`,
      `DTSTAMP:${formatInstant(timestamp.toISOString(), 'generatedAt')}`,
      `DTSTART:${formatInstant(session.start, 'start')}`,
      `DTEND:${formatInstant(session.end, 'end')}`,
      `SUMMARY:${escapeText(title)}`, 'END:VEVENT');
  }
  lines.push('END:VCALENDAR');
  return `${lines.map(foldLine).join('\r\n')}\r\n`;
}
