import { buildAttendanceReport } from './attendance-report.mjs';

/**
 * Build contiguous runs for each student in the supplied session order.
 * A missing result forms its own run and breaks a present or absent streak.
 */
export function attendanceRuns(roster, sessionIds, records) {
  return buildAttendanceReport(roster, sessionIds, records).map((report) => {
    const runs = [];
    for (const session of report.sessions) {
      let run = runs.at(-1);
      if (!run || run.status !== session.status) {
        run = { status: session.status, sessionIds: [] };
        runs.push(run);
      }
      run.sessionIds.push(session.sessionId);
    }
    return { student: report.student, runs };
  });
}

/** Return the longest runs, preserving all ties in chronological order. */
export function longestAttendanceRuns(roster, sessionIds, records, status) {
  if (!['present', 'absent', 'missing'].includes(status)) {
    throw new TypeError('status must be present, absent, or missing');
  }
  return attendanceRuns(roster, sessionIds, records).map(({ student, runs }) => {
    const matching = runs.filter((run) => run.status === status);
    const length = matching.reduce((max, run) => Math.max(max, run.sessionIds.length), 0);
    return {
      student,
      length,
      runs: matching.filter((run) => run.sessionIds.length === length),
    };
  });
}

/** Find students with at least the requested number of consecutive absences. */
export function findConsecutiveAbsences(roster, sessionIds, records, minimum) {
  if (!Number.isSafeInteger(minimum) || minimum < 1) {
    throw new RangeError('minimum must be a positive safe integer');
  }
  return attendanceRuns(roster, sessionIds, records).flatMap(({ student, runs }) =>
    runs.filter((run) => run.status === 'absent' && run.sessionIds.length >= minimum)
      .map((run) => ({ student, sessionIds: run.sessionIds })));
}
