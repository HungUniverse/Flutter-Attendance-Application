import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-snapshot-contract';
const REPORT_FORMAT = 'attendance-snapshot-contract-report';
const VERSION = 1;
const CHECK_TYPES = new Set(['min_students', 'max_students', 'min_sessions', 'max_sessions', 'min_records', 'max_records',
  'minimum_coverage', 'maximum_missing', 'maximum_missing_per_student', 'require_student', 'require_session',
  'exact_session_order', 'cell_status', 'maximum_absence_rate', 'no_placeholder_identity']);
const SEVERITIES = new Set(['error', 'warning']);
const PLACEHOLDERS = new Set(['unknown', 'test', 'demo', 'placeholder', 'n/a', 'na', 'none', 'null', '-']);

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 256) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function integer(value, field, minimum, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  return value;
}

function fraction(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) throw new RangeError(`${field} must be a fraction from 0 to 1`);
  return value;
}

function normalizeCheck(check, index) {
  object(check, `checks[${index}]`);
  const type = text(check.type, `checks[${index}].type`, 48);
  if (!CHECK_TYPES.has(type)) throw new TypeError(`checks[${index}].type is unsupported`);
  const id = text(check.id ?? `${type}-${index + 1}`, `checks[${index}].id`, 80);
  const severity = check.severity ?? 'error';
  if (!SEVERITIES.has(severity)) throw new TypeError(`checks[${index}].severity must be error or warning`);
  const result = { id, type, severity, label: text(check.label ?? id, `checks[${index}].label`, 160) };
  if (['min_students', 'max_students'].includes(type)) result.value = integer(check.value, `checks[${index}].value`, 0, 100_000);
  else if (['min_sessions', 'max_sessions'].includes(type)) result.value = integer(check.value, `checks[${index}].value`, 0, 10_000);
  else if (['min_records', 'max_records', 'maximum_missing'].includes(type)) result.value = integer(check.value, `checks[${index}].value`, 0, 10_000_000);
  else if (type === 'minimum_coverage') result.value = fraction(check.value, `checks[${index}].value`);
  else if (type === 'maximum_missing_per_student') result.value = integer(check.value, `checks[${index}].value`, 0, 10_000);
  else if (type === 'maximum_absence_rate') result.value = fraction(check.value, `checks[${index}].value`);
  else if (type === 'require_student') result.studentId = text(check.studentId, `checks[${index}].studentId`);
  else if (type === 'require_session') result.sessionId = text(check.sessionId, `checks[${index}].sessionId`);
  else if (type === 'exact_session_order') {
    if (!Array.isArray(check.sessionIds) || check.sessionIds.length > 10_000) throw new RangeError(`checks[${index}].sessionIds must be an array`);
    result.sessionIds = check.sessionIds.map((id, itemIndex) => text(id, `checks[${index}].sessionIds[${itemIndex}]`));
    if (new Set(result.sessionIds).size !== result.sessionIds.length) throw new TypeError(`checks[${index}].sessionIds contains duplicates`);
  } else if (type === 'cell_status') {
    result.studentId = text(check.studentId, `checks[${index}].studentId`);
    result.sessionId = text(check.sessionId, `checks[${index}].sessionId`);
    if (!['present', 'absent', 'missing'].includes(check.status)) throw new TypeError(`checks[${index}].status is unsupported`);
    result.status = check.status;
  } else if (type === 'no_placeholder_identity') {
    result.checkNames = check.checkNames ?? true;
    result.checkEmails = check.checkEmails ?? true;
    if (typeof result.checkNames !== 'boolean' || typeof result.checkEmails !== 'boolean' || (!result.checkNames && !result.checkEmails)) {
      throw new TypeError(`checks[${index}] must check names, emails or both`);
    }
  }
  return result;
}

function normalizeContract(value) {
  object(value, 'snapshot contract');
  if (value.format !== FORMAT || value.version !== VERSION) throw new TypeError('unsupported snapshot contract format or version');
  if (!Array.isArray(value.checks) || value.checks.length < 1 || value.checks.length > 500) throw new RangeError('contract must contain 1 to 500 checks');
  const checks = value.checks.map(normalizeCheck);
  if (new Set(checks.map((check) => check.id)).size !== checks.length) throw new TypeError('contract check IDs must be unique');
  return { format: FORMAT, version: VERSION, id: text(value.id, 'contract ID', 120),
    title: text(value.title, 'contract title', 200), revision: integer(value.revision, 'contract revision', 1),
    checks, note: optionalNote(value.note) };
}

function optionalNote(value) {
  if (value === undefined || value === null || value === '') return null;
  return text(value, 'contract note', 1_000);
}

function snapshotFingerprint(snapshot) {
  let hash = 0x811c9dc5;
  const value = serializeAttendanceSnapshot(snapshot);
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return `snapshot-${(hash >>> 0).toString(36).toUpperCase().padStart(7, '0')}`;
}

function evaluateCheck(check, snapshot, recordMap, recordsPerStudent) {
  const students = snapshot.roster.length;
  const sessions = snapshot.sessionIds.length;
  const expectedCells = students * sessions;
  const missing = expectedCells - snapshot.records.length;
  const coverage = expectedCells ? snapshot.records.length / expectedCells : null;
  let actual;
  let passed;
  let details = null;
  if (check.type === 'min_students') { actual = students; passed = actual >= check.value; }
  else if (check.type === 'max_students') { actual = students; passed = actual <= check.value; }
  else if (check.type === 'min_sessions') { actual = sessions; passed = actual >= check.value; }
  else if (check.type === 'max_sessions') { actual = sessions; passed = actual <= check.value; }
  else if (check.type === 'min_records') { actual = snapshot.records.length; passed = actual >= check.value; }
  else if (check.type === 'max_records') { actual = snapshot.records.length; passed = actual <= check.value; }
  else if (check.type === 'minimum_coverage') { actual = coverage; passed = actual !== null && actual >= check.value; }
  else if (check.type === 'maximum_missing') { actual = missing; passed = actual <= check.value; }
  else if (check.type === 'maximum_missing_per_student') {
    const counts = snapshot.roster.map((student) => sessions - (recordsPerStudent.get(student.id) ?? []).length);
    actual = counts.length ? Math.max(...counts) : 0;
    passed = actual <= check.value;
  } else if (check.type === 'require_student') { actual = snapshot.roster.some((student) => student.id === check.studentId); passed = actual; }
  else if (check.type === 'require_session') { actual = snapshot.sessionIds.includes(check.sessionId); passed = actual; }
  else if (check.type === 'exact_session_order') {
    actual = snapshot.sessionIds;
    passed = JSON.stringify(actual) === JSON.stringify(check.sessionIds);
  } else if (check.type === 'cell_status') {
    const exists = snapshot.roster.some((student) => student.id === check.studentId) && snapshot.sessionIds.includes(check.sessionId);
    actual = exists ? recordMap.get(JSON.stringify([check.studentId, check.sessionId])) ?? 'missing' : 'unknown_target';
    passed = exists && actual === check.status;
  } else if (check.type === 'maximum_absence_rate') {
    const rates = snapshot.roster.map((student) => {
      const recorded = recordsPerStudent.get(student.id) ?? [];
      return recorded.length ? recorded.filter((record) => record.status === 'absent').length / recorded.length : null;
    }).filter((rate) => rate !== null);
    actual = rates.length ? Math.max(...rates) : null;
    passed = actual !== null && actual <= check.value;
  } else {
    const findings = [];
    for (const student of snapshot.roster) {
      const identityValues = [];
      if (check.checkNames) identityValues.push(['name', student.name]);
      if (check.checkEmails) identityValues.push(['email', student.email]);
      for (const [field, value] of identityValues) {
        const normalized = String(value ?? '').trim().toLocaleLowerCase('en-US');
        const emailLocalPart = field === 'email' ? normalized.split('@')[0] : null;
        if (!normalized || PLACEHOLDERS.has(normalized) || (emailLocalPart !== null && PLACEHOLDERS.has(emailLocalPart))) {
          findings.push({ studentId: student.id, field });
        }
      }
    }
    actual = findings.length;
    passed = actual === 0;
    details = findings;
  }
  return { checkId: check.id, type: check.type, label: check.label, severity: check.severity,
    expected: check.value ?? (check.type === 'cell_status' ? check.status : check.type === 'exact_session_order' ? check.sessionIds : null),
    actual, passed, message: passed ? 'Contract check passed.' : `${check.label} did not match the snapshot.`,
    details: check.type === 'no_placeholder_identity' && !passed ? details : null };
}

/** Normalize a reusable, declarative snapshot acceptance contract. */
export function createSnapshotContract(value) {
  return normalizeContract(value);
}

/** Parse serialized contract JSON. */
export function parseSnapshotContract(value) {
  if (typeof value === 'string') {
    try { value = JSON.parse(value); }
    catch { throw new TypeError('snapshot contract must contain valid JSON'); }
  }
  return normalizeContract(value);
}

/** Validate a snapshot against every declared acceptance check. */
export function validateSnapshotContract(snapshotValue, contractValue) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const contract = parseSnapshotContract(contractValue);
  const recordMap = new Map(snapshot.records.map((record) => [JSON.stringify([record.studentId, record.sessionId]), record.status]));
  const recordsPerStudent = new Map(snapshot.roster.map((student) => [student.id, []]));
  for (const record of snapshot.records) recordsPerStudent.get(record.studentId).push(record);
  const results = contract.checks.map((check) => evaluateCheck(check, snapshot, recordMap, recordsPerStudent));
  const failed = results.filter((result) => !result.passed);
  const errors = failed.filter((result) => result.severity === 'error').length;
  const warnings = failed.filter((result) => result.severity === 'warning').length;
  return { format: REPORT_FORMAT, version: VERSION, contractId: contract.id, contractRevision: contract.revision,
    snapshotFingerprint: snapshotFingerprint(snapshot), accepted: errors === 0,
    summary: { checks: results.length, passed: results.length - failed.length, failed: failed.length, errors, warnings,
      students: snapshot.roster.length, sessions: snapshot.sessionIds.length, records: snapshot.records.length,
      expectedCells: snapshot.roster.length * snapshot.sessionIds.length },
    results,
    note: 'Acceptance results follow only the caller-authored contract. They are not a substitute for institutional policy review.' };
}

/** Serialize a validated contract. */
export function serializeSnapshotContract(contractValue) {
  return `${JSON.stringify(parseSnapshotContract(contractValue), null, 2)}\n`;
}

/** Export check results or a compact run summary. */
export function snapshotContractToCsv(reportValue, section = 'checks') {
  const report = object(reportValue, 'snapshot contract report');
  if (report.format !== REPORT_FORMAT || report.version !== VERSION || !Array.isArray(report.results)) throw new TypeError('invalid snapshot contract report');
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (section === 'checks') return csv(['checkId', 'type', 'label', 'severity', 'expected', 'actual', 'passed', 'message'],
    report.results.map((result) => [result.checkId, result.type, result.label, result.severity,
      JSON.stringify(result.expected), JSON.stringify(result.actual), result.passed, result.message]));
  if (section === 'summary') return csv(['contractId', 'contractRevision', 'snapshotFingerprint', 'accepted',
    'checks', 'passed', 'failed', 'errors', 'warnings'], [[report.contractId, report.contractRevision,
    report.snapshotFingerprint, report.accepted, report.summary.checks, report.summary.passed,
    report.summary.failed, report.summary.errors, report.summary.warnings]]);
  throw new TypeError('section must be checks or summary');
}
