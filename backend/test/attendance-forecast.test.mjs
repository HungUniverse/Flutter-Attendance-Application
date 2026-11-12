import test from 'node:test';
import assert from 'node:assert/strict';
import { forecastAttendance, forecastRoster, compareAttendanceScenarios } from '../attendance-forecast.mjs';

test('finds the minimum future attendance and allowed absences', () => {
  assert.deepEqual(forecastAttendance(6, 2, 4, 0.75), {
    recorded: 8, remaining: 4, total: 12, currentRate: 0.75,
    minimumFinalRate: 0.5, maximumFinalRate: 10 / 12,
    requiredPresent: 3, allowedAbsences: 1, achievable: true,
  });
  assert.equal(forecastAttendance(6, 2, 4, 1).achievable, false);
  assert.equal(forecastAttendance(6, 2, 4, 1).requiredPresent, null);
  assert.equal(forecastAttendance(0, 2, 1, 0).requiredPresent, 0);
});

test('handles no recorded or remaining sessions explicitly', () => {
  assert.deepEqual(forecastAttendance(0, 0, 0, 0), {
    recorded: 0, remaining: 0, total: 0, currentRate: null,
    minimumFinalRate: null, maximumFinalRate: null, requiredPresent: null,
    allowedAbsences: null, achievable: false,
  });
  assert.equal(forecastAttendance(0, 0, 4, 0.5).requiredPresent, 2);
  assert.equal(forecastAttendance(3, 1, 0, 0.75).allowedAbsences, 0);
});

test('threshold search matches exhaustive results across small schedules', () => {
  for (let present = 0; present <= 5; present++) {
    for (let absent = 0; absent <= 5; absent++) {
      for (let remaining = 0; remaining <= 5; remaining++) {
        if (present + absent + remaining === 0) continue;
        for (const target of [0, 0.1, 0.3, 0.5, 0.75, 0.8, 1]) {
          const possibilities = Array.from({ length: remaining + 1 }, (_, i) => i);
          const expected = possibilities.find((i) =>
            (present + i) / (present + absent + remaining) >= target);
          assert.equal(forecastAttendance(present, absent, remaining, target).requiredPresent, expected ?? null);
        }
      }
    }
  }
});

test('does not forecast students with missing completed-session records', () => {
  const roster = [
    { id: 'A', name: 'An', email: 'a@example.com' },
    { id: 'B', name: 'Binh', email: 'b@example.com' },
  ];
  const result = forecastRoster(roster, ['1', '2'], [
    { studentId: 'A', sessionId: '1', status: 'present' },
    { studentId: 'A', sessionId: '2', status: 'absent' },
    { studentId: 'B', sessionId: '1', status: 'present' },
  ], 2, 0.75);
  assert.equal(result[0].forecast.requiredPresent, 2);
  assert.deepEqual(result[1].missingSessionIds, ['2']);
  assert.equal(result[1].forecast, null);
  assert.throws(() => forecastRoster(roster, ['1'], [], -1, 0.5), RangeError);
});

test('compares scenarios and validates inputs', () => {
  assert.deepEqual(compareAttendanceScenarios(2, 1, 2, [0, 2]).map((x) => x.finalRate), [0.4, 0.8]);
  assert.equal(compareAttendanceScenarios(0, 0, 0, [0])[0].finalRate, null);
  assert.throws(() => compareAttendanceScenarios(1, 0, 1, [2]), RangeError);
  assert.throws(() => forecastAttendance(1.5, 0, 1, 0.5), RangeError);
  assert.throws(() => forecastAttendance(1, 0, 1, NaN), RangeError);
  assert.throws(() => forecastAttendance(Number.MAX_SAFE_INTEGER, 1, 0, 0.5), RangeError);
});
