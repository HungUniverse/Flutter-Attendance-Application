import { buildAttendanceReport } from './attendance-report.mjs';

/** Summarize each session across a roster, including unrecorded results. */
export function buildSessionMatrix(roster, sessionIds, records) {
  const reports = buildAttendanceReport(roster, sessionIds, records);
  // buildAttendanceReport validates and normalizes the session IDs even for an empty roster.
  return sessionIds.map((id, index) => {
    let present = 0;
    let absent = 0;
    const entries = reports.map((report) => {
      const status = report.sessions[index].status;
      if (status === 'present') present++;
      else if (status === 'absent') absent++;
      return {
        student: report.student,
        status,
      };
    });
    const recorded = present + absent;
    return {
      sessionId: id.trim(),
      present,
      absent,
      missing: entries.length - recorded,
      attendanceRate: recorded ? present / recorded : null,
      entries,
    };
  });
}

/** List missing student/session pairs in session order, then roster order. */
export function findMissingAttendance(roster, sessionIds, records) {
  return buildSessionMatrix(roster, sessionIds, records).flatMap((session) =>
    session.entries.filter((entry) => entry.status === 'missing').map((entry) => ({
      sessionId: session.sessionId,
      student: entry.student,
    })));
}
