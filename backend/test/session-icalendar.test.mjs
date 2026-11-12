import test from 'node:test';
import assert from 'node:assert/strict';
import { sessionsToICalendar } from '../session-icalendar.mjs';

const sessions = [{ id: 'class 1', start: '2026-01-01T09:00:00+07:00',
  end: '2026-01-01T10:00:00+07:00', resources: [] }];
const options = { uidDomain: 'example.com', generatedAt: '2026-01-01T00:00:00Z' };

test('exports UTC times, stable IDs and escaped text', () => {
  const output = sessionsToICalendar(sessions, { ...options, title: 'Lớp, A;\nRoom\\1' });
  assert.match(output, /UID:class%201@example\.com\r\n/);
  assert.match(output, /DTSTART:20260101T020000Z\r\nDTEND:20260101T030000Z/);
  assert.ok(output.includes('SUMMARY:Lớp\\, A\\;\\nRoom\\\\1\r\n'));
  assert.ok(output.endsWith('END:VCALENDAR\r\n'));
});

test('folds long UTF-8 lines at 75 octets and can be unfolded', () => {
  const title = 'Điểm danh '.repeat(20);
  const output = sessionsToICalendar(sessions, { ...options, title });
  for (const line of output.split('\r\n')) assert.ok(Buffer.byteLength(line, 'utf8') <= 75);
  assert.ok(output.replace(/\r\n /g, '').includes(`SUMMARY:${title}`));
});

test('rejects invalid timestamps, domains and fractional session times', () => {
  assert.throws(() => sessionsToICalendar(sessions, { ...options, uidDomain: 'bad\nvalue' }), /uidDomain/);
  assert.throws(() => sessionsToICalendar(sessions, { ...options, generatedAt: '2026-02-30T00:00:00Z' }), /valid/);
  assert.throws(() => sessionsToICalendar([{ ...sessions[0], start: '2026-01-01T09:00:00.500+07:00' }], options), /precision/);
  assert.throws(() => sessionsToICalendar([sessions[0], sessions[0]], options), /duplicate/);
});
