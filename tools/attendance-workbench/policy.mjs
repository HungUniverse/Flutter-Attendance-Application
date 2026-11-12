import { buildAttendanceReport } from '../../backend/attendance-report.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

/**
 * Evaluate a caller-defined minimum rate and maximum absence count. Missing
 * outcomes are bounded by treating all as present or all as absent. A result
 * is uncertain when its outcome depends on resolving those missing entries.
 */
export function evaluatePolicy(snapshot, policy) {
  const data = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshot));
  if (!policy || typeof policy !== 'object' || Array.isArray(policy)) throw new TypeError('policy must be an object');
  const { minimumRate, maximumAbsences } = policy;
  if (!Number.isFinite(minimumRate) || minimumRate < 0 || minimumRate > 1) {
    throw new RangeError('minimumRate must be between 0 and 1');
  }
  if (!Number.isSafeInteger(maximumAbsences) || maximumAbsences < 0) {
    throw new RangeError('maximumAbsences must be a non-negative safe integer');
  }
  return buildAttendanceReport(data.roster, data.sessionIds, data.records).map((report) => {
    const total = report.present + report.absent + report.missing;
    if (!total) return { student: report.student, status: 'undetermined', reasons: ['no_sessions'],
      present: 0, absent: 0, missing: 0, minimumRate: null, maximumRate: null };
    const lowestRate = report.present / total;
    const highestRate = (report.present + report.missing) / total;
    const reasons = [];
    if (highestRate < minimumRate) reasons.push('rate_below_minimum');
    if (report.absent > maximumAbsences) reasons.push('absences_above_maximum');
    let status = 'pass';
    if (reasons.length) status = 'fail';
    else if (lowestRate < minimumRate || report.absent + report.missing > maximumAbsences) {
      status = 'undetermined';
      reasons.push('missing_results');
    }
    return { student: report.student, status, reasons, present: report.present, absent: report.absent,
      missing: report.missing, minimumRate: lowestRate, maximumRate: highestRate };
  });
}
