import test from 'node:test';
import assert from 'node:assert/strict';
import { generateRecurringSessions } from '../session-recurrence.mjs';
import { findScheduleConflicts } from '../session-schedule.mjs';

const options = {
  startDate: '2026-01-01', endDate: '2026-01-15', startTime: '09:30',
  durationMinutes: 90, weekdays: [1, 4], resources: ['room'], idPrefix: 'class',
  exceptions: ['2026-01-08'],
};

test('generates stable UTC sessions in date order and skips exceptions', () => {
  const sessions = generateRecurringSessions(options);
  assert.deepEqual(sessions.map((session) => session.id), [
    'class-2026-01-01', 'class-2026-01-05', 'class-2026-01-12', 'class-2026-01-15',
  ]);
  assert.equal(sessions[0].start, '2026-01-01T09:30:00.000Z');
  assert.equal(sessions[0].end, '2026-01-01T11:00:00.000Z');
  assert.deepEqual(findScheduleConflicts(sessions), []);
  assert.deepEqual(generateRecurringSessions(options), sessions);
});

test('allows a session to end on the next date', () => {
  const [session] = generateRecurringSessions({ ...options, endDate: '2026-01-01',
    startTime: '23:30', durationMinutes: 60 });
  assert.equal(session.end, '2026-01-02T00:30:00.000Z');
});

test('validates the date range, time, weekdays and exceptions', () => {
  assert.throws(() => generateRecurringSessions({ ...options, startDate: '2026-02-30' }), /valid date/);
  assert.throws(() => generateRecurringSessions({ ...options, endDate: '2025-12-31' }), RangeError);
  assert.throws(() => generateRecurringSessions({ ...options, endDate: '2040-01-01' }), RangeError);
  assert.throws(() => generateRecurringSessions({ ...options, startTime: '24:00' }), /startTime/);
  assert.throws(() => generateRecurringSessions({ ...options, weekdays: [1, 1] }), /weekdays/);
  assert.throws(() => generateRecurringSessions({ ...options, exceptions: ['2026-01-08', '2026-01-08'] }), /duplicate/);
  assert.throws(() => generateRecurringSessions({ ...options, durationMinutes: 0 }), RangeError);
});

test('validates resources even if no dates match', () => {
  assert.throws(() => generateRecurringSessions({ ...options, startDate: '2026-01-01',
    endDate: '2026-01-01', weekdays: [1], resources: null }), /resources/);
});
