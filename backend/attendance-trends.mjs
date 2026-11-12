import { buildAttendanceReport } from './attendance-report.mjs';

/**
 * Calculate full rolling windows in caller-supplied chronological order.
 * The rate excludes missing records and is null if no results were recorded.
 * A window is omitted until the specified number of sessions is available.
 */
export function rollingAttendance(roster, sessionIds, records, windowSize) {
  if (!Number.isSafeInteger(windowSize) || windowSize < 1) {
    throw new RangeError('windowSize must be a positive safe integer');
  }
  return buildAttendanceReport(roster, sessionIds, records).map((report) => {
    const windows = [];
    let present = 0;
    let absent = 0;
    for (let index = 0; index < report.sessions.length; index++) {
      const current = report.sessions[index];
      if (current.status === 'present') present++;
      if (current.status === 'absent') absent++;
      if (index >= windowSize) {
        const previous = report.sessions[index - windowSize];
        if (previous.status === 'present') present--;
        if (previous.status === 'absent') absent--;
      }
      if (index + 1 >= windowSize) {
        const recorded = present + absent;
        windows.push({
          startSessionId: report.sessions[index + 1 - windowSize].sessionId,
          endSessionId: current.sessionId,
          present,
          absent,
          missing: windowSize - recorded,
          attendanceRate: recorded ? present / recorded : null,
        });
      }
    }
    return { student: report.student, windows };
  });
}

/**
 * Compare two disjoint inclusive ranges identified by session IDs. Null rates
 * remain incomparable, so change is null whenever either range lacks records.
 */
export function compareAttendancePeriods(roster, sessionIds, records, first, second) {
  const reports = buildAttendanceReport(roster, sessionIds, records);
  const normalizedIds = sessionIds.map((id) => id.trim());
  function bounds(period) {
    if (!period || typeof period !== 'object' || typeof period.start !== 'string' ||
        typeof period.end !== 'string') throw new TypeError('period requires start and end IDs');
    const start = normalizedIds.indexOf(period.start.trim());
    const end = normalizedIds.indexOf(period.end.trim());
    if (start < 0 || end < start) throw new RangeError('period must be an ordered range of sessions');
    return { start, end };
  }
  const before = bounds(first);
  const after = bounds(second);
  if (before.end >= after.start) throw new RangeError('periods must be disjoint and chronological');
  function summarize(sessions, range) {
    const subset = sessions.slice(range.start, range.end + 1);
    const present = subset.filter((session) => session.status === 'present').length;
    const absent = subset.filter((session) => session.status === 'absent').length;
    return { present, absent, missing: subset.length - present - absent,
      attendanceRate: present + absent ? present / (present + absent) : null };
  }
  return reports.map((report) => {
    const firstSummary = summarize(report.sessions, before);
    const secondSummary = summarize(report.sessions, after);
    const change = firstSummary.attendanceRate === null || secondSummary.attendanceRate === null
      ? null : secondSummary.attendanceRate - firstSummary.attendanceRate;
    return { student: report.student, first: firstSummary, second: secondSummary, change };
  });
}
