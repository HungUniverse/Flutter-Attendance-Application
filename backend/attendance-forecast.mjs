import { buildAttendanceReport } from './attendance-report.mjs';

function count(value, name) {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new RangeError(`${name} must be a non-negative safe integer`);
  }
  return value;
}

function threshold(value) {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new RangeError('target must be between 0 and 1');
  }
  return value;
}

/**
 * Project a final attendance rate after all remaining sessions are recorded.
 * Missing historical records must be resolved by the caller before using counts.
 * With no sessions in the final total, rates and the required count are null.
 */
export function forecastAttendance(present, absent, remaining, target) {
  count(present, 'present');
  count(absent, 'absent');
  count(remaining, 'remaining');
  threshold(target);
  const recorded = present + absent;
  const total = recorded + remaining;
  if (!Number.isSafeInteger(recorded) || !Number.isSafeInteger(total)) {
    throw new RangeError('total sessions exceed the safe integer range');
  }
  if (total === 0) {
    return { recorded, remaining, total, currentRate: null, minimumFinalRate: null,
      maximumFinalRate: null, requiredPresent: null, allowedAbsences: null, achievable: false };
  }

  // Search by the same division used to report rates, avoiding rounding errors
  // caused by applying Math.ceil to a floating-point product.
  let low = 0;
  let high = remaining;
  const achievable = (present + remaining) / total >= target;
  if (achievable) {
    while (low < high) {
      const middle = low + Math.floor((high - low) / 2);
      if ((present + middle) / total >= target) high = middle;
      else low = middle + 1;
    }
  }
  const requiredPresent = achievable ? low : null;
  return {
    recorded,
    remaining,
    total,
    currentRate: recorded ? present / recorded : null,
    minimumFinalRate: present / total,
    maximumFinalRate: (present + remaining) / total,
    requiredPresent,
    allowedAbsences: achievable ? remaining - requiredPresent : null,
    achievable,
  };
}

/**
 * Forecast every student in a roster using an explicit list of completed sessions.
 * Students with missing historical results are reported separately with no forecast.
 */
export function forecastRoster(roster, completedSessionIds, records, remaining, target) {
  count(remaining, 'remaining');
  threshold(target);
  return buildAttendanceReport(roster, completedSessionIds, records).map((report) => ({
    student: report.student,
    present: report.present,
    absent: report.absent,
    missingSessionIds: report.sessions
      .filter((session) => session.status === 'missing')
      .map((session) => session.sessionId),
    forecast: report.missing ? null : forecastAttendance(report.present, report.absent, remaining, target),
  }));
}

/** Compare several possible attendance counts for the same fixed remaining schedule. */
export function compareAttendanceScenarios(present, absent, remaining, scenarios) {
  count(present, 'present');
  count(absent, 'absent');
  count(remaining, 'remaining');
  if (!Number.isSafeInteger(present + absent + remaining)) {
    throw new RangeError('total sessions exceed the safe integer range');
  }
  if (!Array.isArray(scenarios)) throw new TypeError('scenarios must be an array');
  const total = present + absent + remaining;
  return scenarios.map((attended) => {
    count(attended, 'scenario attendance');
    if (attended > remaining) throw new RangeError('scenario attendance exceeds remaining sessions');
    return {
      attended,
      missed: remaining - attended,
      finalPresent: present + attended,
      finalAbsent: absent + remaining - attended,
      finalRate: total ? (present + attended) / total : null,
    };
  });
}
