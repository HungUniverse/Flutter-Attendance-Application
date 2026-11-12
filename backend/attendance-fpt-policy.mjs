import { buildAttendanceReport } from './attendance-report.mjs';

function validateRatio(value, name) {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new RangeError(`${name} must be a number between 0 and 1`);
  }
  return value;
}

/**
 * Evaluate a roster against FPT University attendance eligibility rules.
 * By default, a student is debarred from the final exam when absences strictly
 * exceed 20% of total planned sessions, and enters the warning band at >=15%.
 */
export function evaluateFptAttendancePolicy(roster, sessionIds, records, options = {}) {
  if (!options || typeof options !== 'object' || Array.isArray(options)) {
    throw new TypeError('options must be an object');
  }
  const reports = buildAttendanceReport(roster, sessionIds, records);
  const completedSessions = sessionIds.length;
  const totalPlannedSessions = options.totalPlannedSessions ?? completedSessions;
  if (!Number.isSafeInteger(totalPlannedSessions) || totalPlannedSessions < completedSessions) {
    throw new RangeError('totalPlannedSessions must be an integer greater than or equal to completed sessions');
  }
  const warningRatio = validateRatio(options.warningRatio ?? 0.15, 'warningRatio');
  const maxAbsenceRatio = validateRatio(options.maxAbsenceRatio ?? 0.2, 'maxAbsenceRatio');
  if (warningRatio > maxAbsenceRatio) {
    throw new RangeError('warningRatio cannot exceed maxAbsenceRatio');
  }

  const maxAllowedAbsences = Math.floor(totalPlannedSessions * maxAbsenceRatio);
  let eligible = 0;
  let warning = 0;
  let debarred = 0;
  const students = reports.map((report) => {
    const { present, absent, missing } = report;
    const absenceRatio = totalPlannedSessions > 0 ? absent / totalPlannedSessions : 0;
    const pessimisticAbsenceRatio =
      totalPlannedSessions > 0 ? (absent + missing) / totalPlannedSessions : 0;
    const remainingAbsences = Math.max(0, maxAllowedAbsences - absent);
    const canStillPass = absent <= maxAllowedAbsences;
    let status = 'eligible';
    if (totalPlannedSessions > 0 && absenceRatio > maxAbsenceRatio) {
      status = 'debarred';
      debarred++;
    } else if (totalPlannedSessions > 0 && absenceRatio >= warningRatio) {
      status = 'warning';
      warning++;
    } else {
      eligible++;
    }
    return {
      student: report.student,
      present,
      absent,
      missing,
      completedSessions,
      totalPlannedSessions,
      maxAllowedAbsences,
      remainingAbsences,
      absenceRatio,
      pessimisticAbsenceRatio,
      canStillPass,
      status,
    };
  });

  const summary = {
    totalStudents: students.length,
    completedSessions,
    totalPlannedSessions,
    maxAllowedAbsences,
    eligible,
    warning,
    debarred,
  };

  return {
    policy: { warningRatio, maxAbsenceRatio, totalPlannedSessions, maxAllowedAbsences },
    summary,
    students,
  };
}

function escapeCsv(value) {
  const text = String(value ?? '');
  const safe = /^(?:[\t\r]|[\t\r\n ]*[=+\-@])/.test(text) ? `'${text}` : text;
  return `"${safe.replaceAll('"', '""')}"`;
}

/** Export FPT policy evaluation as spreadsheet-safe RFC 4180 CSV. */
export function fptPolicyReportToCsv(evaluation) {
  if (!evaluation || typeof evaluation !== 'object' || !Array.isArray(evaluation.students)) {
    throw new TypeError('invalid FPT policy evaluation');
  }
  const header = [
    'studentId',
    'name',
    'email',
    'present',
    'absent',
    'missing',
    'totalPlannedSessions',
    'maxAllowedAbsences',
    'remainingAbsences',
    'absenceRatio',
    'status',
  ];
  const rows = evaluation.students.map((item) => [
    item.student.id,
    item.student.name,
    item.student.email,
    item.present,
    item.absent,
    item.missing,
    item.totalPlannedSessions,
    item.maxAllowedAbsences,
    item.remainingAbsences,
    item.absenceRatio.toFixed(4),
    item.status,
  ]);
  return [header, ...rows].map((row) => row.map(escapeCsv).join(',')).join('\r\n');
}
