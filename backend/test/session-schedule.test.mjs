import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeSchedule, findScheduleConflicts, findAvailability } from '../session-schedule.mjs';

const session = (id, start, end, resources = ['room']) => ({ id, start, end, resources });
const time = (hour) => `2026-01-01T${String(hour).padStart(2, '0')}:00:00Z`;

test('normalizes offsets and checks dates, IDs, and resources', () => {
  const input = [session(' a ', '2026-01-01T08:00+07:00', '2026-01-01T09:00+07:00', [' room '])];
  assert.deepEqual(normalizeSchedule(input), [session('a', time(1).replace('Z', '.000Z'), time(2).replace('Z', '.000Z'))]);
  assert.equal(input[0].id, ' a ');
  assert.throws(() => normalizeSchedule([session('a', '2026-02-30T08:00Z', time(9))]), /valid timestamp/);
  assert.throws(() => normalizeSchedule([session('a', time(8), time(9)), session(' a ', time(9), time(10))]), /duplicate session/);
  assert.throws(() => normalizeSchedule([session('a', time(8), time(9), ['room', ' room '])]), /duplicate resource/);
  assert.throws(() => normalizeSchedule([session('a', time(8), time(8))]), RangeError);
  assert.throws(() => normalizeSchedule([session('a', '2026-01-01T08:00', time(9))]), /offset/);
});

test('finds only overlapping sessions sharing a resource', () => {
  const conflicts = findScheduleConflicts([
    session('a', time(8), time(10), ['room', 'teacher']),
    session('b', time(9), time(11), ['teacher', 'room']),
    session('c', time(10), time(11), ['room']),
    session('d', time(9), time(10), ['other']),
  ]);
  assert.deepEqual(conflicts.map(({ firstId, secondId, resources }) => [firstId, secondId, resources]), [
    ['a', 'b', ['room', 'teacher']], ['b', 'c', ['room']],
  ]);
  assert.equal(conflicts[0].start, '2026-01-01T09:00:00.000Z');
  assert.equal(conflicts[0].end, '2026-01-01T10:00:00.000Z');
});

test('availability merges overlapping and adjacent busy periods and clips to window', () => {
  const busy = [session('a', time(7), time(9)), session('b', time(8), time(10)),
    session('c', time(10), time(11)), session('d', time(12), time(14))];
  assert.deepEqual(findAvailability(busy, 'room', time(8), time(13)), [
    { start: '2026-01-01T11:00:00.000Z', end: '2026-01-01T12:00:00.000Z' },
  ]);
  assert.deepEqual(findAvailability(busy, 'other', time(8), time(9)), [
    { start: '2026-01-01T08:00:00.000Z', end: '2026-01-01T09:00:00.000Z' },
  ]);
});
