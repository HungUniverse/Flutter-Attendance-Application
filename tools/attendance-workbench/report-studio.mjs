import { buildAttendanceReport } from '../../backend/attendance-report.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot, createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { auditAttendanceSnapshot } from './audit.mjs';
import { evaluatePolicy } from './policy.mjs';

const SORTS = new Set(['name', 'rateAscending', 'rateDescending', 'absentDescending', 'missingDescending']);
const STATUSES = Object.freeze({ present: 'Present', absent: 'Absent', missing: 'Not recorded' });
const AUDIT_MESSAGES = Object.freeze({
  empty_roster: 'The selected roster is empty.',
  empty_schedule: 'The selected period has no sessions.',
  no_recorded_results: 'No attendance results have been recorded.',
  incomplete_coverage: 'Some attendance cells are not recorded.',
  duplicate_name: 'Roster entries share a normalized display name.',
  student_missing_results: 'A student has one or more unrecorded outcomes.',
  low_student_rate: 'A recorded attendance rate is below the configured threshold.',
  absence_streak: 'A student has a consecutive absence run.',
  session_unrecorded: 'A session has no recorded outcomes.',
  low_session_rate: 'A session rate is below the configured threshold.',
});

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function bool(value, field, fallback) {
  if (value === undefined) return fallback;
  if (typeof value !== 'boolean') throw new TypeError(`${field} must be a boolean`);
  return value;
}

function integer(value, field, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}

function fraction(value, field) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
    throw new RangeError(`${field} must be null or a number from 0 to 1`);
  }
  return value;
}

function text(value, field, fallback, maximum = 160) {
  const result = value ?? fallback;
  if (typeof result !== 'string' || !result.trim() || result.trim().length > maximum) {
    throw new TypeError(`${field} must be a non-empty string of at most ${maximum} characters`);
  }
  return result.trim();
}

function searchText(value) {
  if (value === undefined) return '';
  if (typeof value !== 'string' || value.trim().length > 160) throw new TypeError('search must be a string of at most 160 characters');
  return value.trim();
}

function normalizeIds(value, available, field) {
  if (value === undefined) return [...available];
  if (!Array.isArray(value)) throw new TypeError(`${field} must be an array`);
  const known = new Set(available);
  const ids = value.map((id) => {
    if (typeof id !== 'string' || !id.trim()) throw new TypeError(`${field} entries must be non-empty strings`);
    const normalized = id.trim();
    if (!known.has(normalized)) throw new TypeError(`unknown ${field} entry: ${normalized}`);
    return normalized;
  });
  if (new Set(ids).size !== ids.length) throw new TypeError(`${field} must not contain duplicates`);
  return ids;
}

function normalizeOptions(value = {}) {
  object(value, 'report options');
  const sortBy = value.sortBy ?? 'name';
  if (!SORTS.has(sortBy)) throw new TypeError(`sortBy must be one of: ${[...SORTS].join(', ')}`);
  const minimumRate = fraction(value.minimumRate, 'minimumRate');
  const maximumRate = fraction(value.maximumRate, 'maximumRate');
  if (minimumRate !== null && maximumRate !== null && minimumRate > maximumRate) {
    throw new RangeError('minimumRate must not exceed maximumRate');
  }
  const generatedAt = value.generatedAt ?? new Date().toISOString();
  if (typeof generatedAt !== 'string' || !Number.isFinite(Date.parse(generatedAt))) throw new TypeError('generatedAt must be a valid timestamp');
  if (value.auditOptions !== undefined) object(value.auditOptions, 'auditOptions');
  if (value.policy !== undefined) object(value.policy, 'policy');
  return {
    title: text(value.title, 'title', 'Attendance period report'),
    generatedAt: new Date(generatedAt).toISOString(),
    studentIds: value.studentIds,
    sessionIds: value.sessionIds,
    search: searchText(value.search),
    minimumRate,
    maximumRate,
    minimumRecorded: integer(value.minimumRecorded ?? 0, 'minimumRecorded', 0, 500),
    sortBy,
    maxStudentRows: integer(value.maxStudentRows ?? 500, 'maxStudentRows', 1, 10_000),
    maxFindings: integer(value.maxFindings ?? 500, 'maxFindings', 1, 10_000),
    includeStudentNames: bool(value.includeStudentNames, 'includeStudentNames', true),
    includeStudentIds: bool(value.includeStudentIds, 'includeStudentIds', true),
    includeSessionIds: bool(value.includeSessionIds, 'includeSessionIds', true),
    includeMatrix: bool(value.includeMatrix, 'includeMatrix', false),
    includeAudit: bool(value.includeAudit, 'includeAudit', false),
    policy: value.policy,
    auditOptions: value.auditOptions ?? {},
    maxMatrixCells: integer(value.maxMatrixCells ?? 20_000, 'maxMatrixCells', 1, 250_000),
  };
}

function compareName(left, right) {
  return left.student.name.localeCompare(right.student.name, 'vi') || left.student.id.localeCompare(right.student.id);
}

function sortStudents(rows, sortBy) {
  const byName = compareName;
  const byRate = (left, right) => (left.attendanceRate ?? -1) - (right.attendanceRate ?? -1) || byName(left, right);
  const comparators = {
    name: byName,
    rateAscending: byRate,
    rateDescending: (left, right) => byRate(right, left),
    absentDescending: (left, right) => right.absent - left.absent || byRate(left, right),
    missingDescending: (left, right) => right.missing - left.missing || byRate(left, right),
  };
  return [...rows].sort(comparators[sortBy]);
}

function safeIdentity(student, options) {
  return {
    studentId: options.includeStudentIds ? student.id : null,
    studentName: options.includeStudentNames ? student.name : null,
  };
}

function auditView(audit, options, maxFindings) {
  const findings = audit.issues.slice(0, maxFindings).map((item) => ({
    severity: item.severity,
    code: item.code,
    subject: options.includeStudentIds ? (item.studentId ?? item.sessionId ?? item.subject) : null,
    message: AUDIT_MESSAGES[item.code] ?? 'Review this data-quality finding.',
    suggestion: item.suggestion,
    count: item.missing ?? item.length ?? null,
    attendanceRate: item.attendanceRate ?? null,
  }));
  return {
    summary: audit.summary,
    findings,
    totalFindings: audit.issues.length,
    truncated: audit.issues.length > findings.length,
  };
}

function csvCell(value) {
  let cell = String(value ?? '');
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

function rowsToCsv(header, rows) {
  return `${[header, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n')}\r\n`;
}

/** Build a filterable, privacy-configurable report from a validated snapshot. */
export function buildReportStudio(snapshotValue, optionsValue = {}) {
  const source = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = normalizeOptions(optionsValue);
  const studentIds = normalizeIds(options.studentIds, source.roster.map((student) => student.id), 'studentIds');
  const sessionIds = normalizeIds(options.sessionIds, source.sessionIds, 'sessionIds');
  const studentSet = new Set(studentIds);
  const sessionSet = new Set(sessionIds);
  const roster = source.roster.filter((student) => studentSet.has(student.id));
  const records = source.records.filter((record) => studentSet.has(record.studentId) && sessionSet.has(record.sessionId));
  const scoped = createAttendanceSnapshot(roster, sessionIds, records);
  const fullReport = buildAttendanceReport(scoped.roster, scoped.sessionIds, scoped.records);
  const needle = options.search.normalize('NFKC').toLocaleLowerCase('vi');
  const filtered = fullReport.filter((student) => {
    const recorded = student.present + student.absent;
    if (recorded < options.minimumRecorded) return false;
    if (options.minimumRate !== null && (student.attendanceRate === null || student.attendanceRate < options.minimumRate)) return false;
    if (options.maximumRate !== null && student.attendanceRate !== null && student.attendanceRate > options.maximumRate) return false;
    if (needle && ![student.student.id, student.student.name].some((value) => value.normalize('NFKC').toLocaleLowerCase('vi').includes(needle))) return false;
    return true;
  });
  const sorted = sortStudents(filtered, options.sortBy);
  const studentRows = sorted.slice(0, options.maxStudentRows);
  const summary = {
    students: filtered.length,
    studentRows: studentRows.length,
    studentsTruncated: filtered.length - studentRows.length,
    sessions: sessionIds.length,
    expected: filtered.length * sessionIds.length,
    recorded: filtered.reduce((sum, student) => sum + student.present + student.absent, 0),
    present: filtered.reduce((sum, student) => sum + student.present, 0),
    absent: filtered.reduce((sum, student) => sum + student.absent, 0),
    missing: filtered.reduce((sum, student) => sum + student.missing, 0),
  };
  summary.coverage = summary.expected ? summary.recorded / summary.expected : null;
  summary.attendanceRate = summary.recorded ? summary.present / summary.recorded : null;
  const selectedSet = new Set(filtered.map((student) => student.student.id));
  const selectedRecords = records.filter((record) => selectedSet.has(record.studentId));
  const allSelectedRoster = roster.filter((student) => selectedSet.has(student.id));
  const fullScoped = createAttendanceSnapshot(allSelectedRoster, sessionIds, selectedRecords);
  const sessionRows = buildAttendanceReport(allSelectedRoster, sessionIds, selectedRecords);
  const sessions = sessionIds.map((sessionId, index) => {
    const rows = sessionRows.flatMap((student) => student.sessions[index] ? [student.sessions[index]] : []);
    const present = rows.filter((row) => row.status === 'present').length;
    const absent = rows.filter((row) => row.status === 'absent').length;
    const missing = rows.length - present - absent;
    return { sessionId: options.includeSessionIds ? sessionId : null, present, absent, missing,
      attendanceRate: present + absent ? present / (present + absent) : null };
  });
  const studentOutput = studentRows.map((student) => ({
    ...safeIdentity(student.student, options),
    present: student.present,
    absent: student.absent,
    missing: student.missing,
    recorded: student.present + student.absent,
    attendanceRate: student.attendanceRate,
    missingSessionIds: options.includeSessionIds ? student.sessions.filter((item) => item.status === 'missing').map((item) => item.sessionId) : [],
  }));
  let matrix = null;
  if (options.includeMatrix) {
    const matrixCells = studentRows.length * sessionIds.length;
    if (matrixCells > options.maxMatrixCells) throw new RangeError(`attendance matrix would contain ${matrixCells} cells; maximum is ${options.maxMatrixCells}`);
    matrix = studentRows.map((student) => ({
      ...safeIdentity(student.student, options),
      cells: student.sessions.map((item) => ({ sessionId: options.includeSessionIds ? item.sessionId : null, status: item.status })),
    }));
  }
  let policy = null;
  if (options.policy !== undefined) {
    policy = evaluatePolicy(fullScoped, options.policy).filter((item) => selectedSet.has(item.student.id)).slice(0, options.maxStudentRows)
      .map((item) => ({ ...safeIdentity(item.student, options), status: item.status, reasons: item.reasons,
        present: item.present, absent: item.absent, missing: item.missing, minimumRate: item.minimumRate, maximumRate: item.maximumRate }));
  }
  let audit = null;
  if (options.includeAudit) audit = auditView(auditAttendanceSnapshot(fullScoped, options.auditOptions), options, options.maxFindings);
  return {
    version: 1,
    title: options.title,
    generatedAt: options.generatedAt,
    filters: {
      search: options.search,
      minimumRate: options.minimumRate,
      maximumRate: options.maximumRate,
      minimumRecorded: options.minimumRecorded,
      sortBy: options.sortBy,
      selectedStudents: roster.length,
      selectedSessions: sessionIds.length,
      includeStudentNames: options.includeStudentNames,
      includeStudentIds: options.includeStudentIds,
      includeSessionIds: options.includeSessionIds,
    },
    summary,
    students: studentOutput,
    sessions,
    matrix,
    policy,
    audit,
    notice: 'Attendance rates use recorded results. Missing outcomes remain separate and do not count as absences.',
  };
}

function escapeHtml(value) {
  return String(value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}

function percent(value) {
  return value === null || value === undefined ? '—' : `${(value * 100).toFixed(1)}%`;
}

function table(headers, rows, emptyMessage) {
  const header = headers.map((item) => `<th scope="col">${escapeHtml(item)}</th>`).join('');
  const body = rows.length ? rows.map((row) => `<tr>${row.map((cell) => `<td>${escapeHtml(cell)}</td>`).join('')}</tr>`).join('')
    : `<tr><td colspan="${headers.length}">${escapeHtml(emptyMessage)}</td></tr>`;
  return `<div class="table-wrap"><table><thead><tr>${header}</tr></thead><tbody>${body}</tbody></table></div>`;
}

/** Render a self-contained, printable HTML report with no script or network resources. */
export function renderReportStudioHtml(reportValue) {
  object(reportValue, 'report');
  if (reportValue.version !== 1 || !reportValue.summary || !Array.isArray(reportValue.students) || !Array.isArray(reportValue.sessions)) {
    throw new TypeError('invalid report studio document');
  }
  const report = reportValue;
  const studentTable = table(['Student', 'Present', 'Absent', 'Missing', 'Rate'], report.students.map((item) => [
    [item.studentName, item.studentId].filter(Boolean).join(' · ') || 'Student', item.present, item.absent, item.missing, percent(item.attendanceRate),
  ]), 'No students match the selected filters.');
  const sessionTable = table(['Session', 'Present', 'Absent', 'Missing', 'Rate'], report.sessions.map((item) => [
    item.sessionId ?? 'Session', item.present, item.absent, item.missing, percent(item.attendanceRate),
  ]), 'No sessions in this report.');
  const policyTable = report.policy ? table(['Student', 'Status', 'Reasons', 'Present / absent / missing'], report.policy.map((item) => [
    [item.studentName, item.studentId].filter(Boolean).join(' · ') || 'Student', item.status,
    item.reasons.join('; '), `${item.present} / ${item.absent} / ${item.missing}`,
  ]), 'No policy rows.') : '';
  const auditTable = report.audit ? table(['Severity', 'Finding', 'Subject', 'Details'], report.audit.findings.map((item) => [
    item.severity, item.message, item.subject ?? 'Details hidden', item.suggestion,
  ]), 'No audit findings.') : '';
  const matrixRows = report.matrix ? table(['Student', ...report.matrix[0]?.cells.map((cell, index) => cell.sessionId ?? `Session ${index + 1}`) ?? []],
    report.matrix.map((item) => [[item.studentName, item.studentId].filter(Boolean).join(' · ') || 'Student',
      ...item.cells.map((cell) => STATUSES[cell.status])]), 'No matrix rows.') : '';
  const summary = report.summary;
  const title = escapeHtml(report.title);
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title><style>
:root{font-family:system-ui,sans-serif;color:#16252c;background:#f3f6f4;color-scheme:light}body{max-width:1180px;margin:0 auto;padding:2rem 1rem;line-height:1.5}h1,h2{line-height:1.2}header{border-bottom:2px solid #2d7658;padding-bottom:1rem;margin-bottom:1.4rem}.meta,.note{color:#586a70;font-size:.9rem}.metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:.65rem;margin:1rem 0 2rem}.metric{background:#fff;border:1px solid #d5e0dc;border-radius:.55rem;padding:1rem}.metric strong{display:block;font-size:1.45rem}.section{margin:2rem 0}.table-wrap{overflow:auto;background:#fff;border:1px solid #d5e0dc;border-radius:.55rem}table{width:100%;border-collapse:collapse;text-align:left}th,td{padding:.6rem .7rem;border-bottom:1px solid #e5ece9;vertical-align:top}th{background:#e8f1ed}td{overflow-wrap:anywhere}tr:last-child td{border-bottom:0}.rate{font-variant-numeric:tabular-nums}@media print{body{max-width:none;padding:0;background:#fff}.table-wrap{overflow:visible;border-color:#aaa}.section{break-inside:avoid}h2{break-after:avoid}}
</style></head><body><main>
<header><h1>${title}</h1><p class="meta">Generated ${escapeHtml(report.generatedAt)} · ${summary.students} matching students · ${summary.sessions} sessions</p><p class="note">${escapeHtml(report.notice)}</p></header>
<div class="metrics"><div class="metric"><strong>${summary.present}</strong>Present results</div><div class="metric"><strong>${summary.absent}</strong>Absent results</div><div class="metric"><strong>${summary.missing}</strong>Missing results</div><div class="metric"><strong>${percent(summary.coverage)}</strong>Coverage</div><div class="metric"><strong>${percent(summary.attendanceRate)}</strong>Recorded attendance</div></div>
<section class="section"><h2>Student summary</h2>${studentTable}${summary.studentsTruncated ? `<p class="note">${summary.studentsTruncated} more matching students were omitted by the row limit.</p>` : ''}</section>
<section class="section"><h2>Session summary</h2>${sessionTable}</section>
${policyTable ? `<section class="section"><h2>Policy review</h2>${policyTable}</section>` : ''}
${auditTable ? `<section class="section"><h2>Data quality findings</h2>${auditTable}${report.audit.truncated ? `<p class="note">Showing ${report.audit.findings.length} of ${report.audit.totalFindings} findings.</p>` : ''}</section>` : ''}
${matrixRows ? `<section class="section"><h2>Attendance matrix</h2>${matrixRows}</section>` : ''}
</main></body></html>\n`;
}

/** Export one report section as formula-safe CSV. */
export function reportStudioToCsv(reportValue, sectionValue) {
  object(reportValue, 'report');
  if (reportValue.version !== 1) throw new TypeError('invalid report studio document');
  const section = sectionValue;
  if (section === 'students') return rowsToCsv(['studentId', 'studentName', 'present', 'absent', 'missing', 'recorded', 'attendanceRate', 'missingSessions'],
    reportValue.students.map((item) => [item.studentId, item.studentName, item.present, item.absent, item.missing,
      item.recorded, percent(item.attendanceRate), item.missingSessionIds.join(';')]));
  if (section === 'sessions') return rowsToCsv(['sessionId', 'present', 'absent', 'missing', 'attendanceRate'],
    reportValue.sessions.map((item) => [item.sessionId, item.present, item.absent, item.missing, percent(item.attendanceRate)]));
  if (section === 'matrix') {
    if (!Array.isArray(reportValue.matrix)) throw new TypeError('matrix section was not included in this report');
    const headers = ['studentId', 'studentName', ...((reportValue.matrix[0]?.cells ?? []).map((cell, index) => cell.sessionId ?? `session${index + 1}`))];
    return rowsToCsv(headers, reportValue.matrix.map((item) => [item.studentId, item.studentName, ...item.cells.map((cell) => STATUSES[cell.status])]));
  }
  if (section === 'audit') {
    if (!reportValue.audit) throw new TypeError('audit section was not included in this report');
    return rowsToCsv(['severity', 'code', 'subject', 'message', 'suggestion'], reportValue.audit.findings.map((item) =>
      [item.severity, item.code, item.subject, item.message, item.suggestion]));
  }
  if (section === 'policy') {
    if (!Array.isArray(reportValue.policy)) throw new TypeError('policy section was not included in this report');
    return rowsToCsv(['studentId', 'studentName', 'status', 'reasons', 'present', 'absent', 'missing', 'minimumRate', 'maximumRate'],
      reportValue.policy.map((item) => [item.studentId, item.studentName, item.status, item.reasons.join(';'), item.present,
        item.absent, item.missing, percent(item.minimumRate), percent(item.maximumRate)]));
  }
  if (section === 'summary') {
    return rowsToCsv(['metric', 'value'], Object.entries(reportValue.summary).map(([key, value]) => [key, value]));
  }
  throw new TypeError('section must be summary, students, sessions, matrix, audit or policy');
}
