import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { normalizeEmail } from '../../backend/roster-reconciliation.mjs';

const DELIMITERS = [',', ';', '\t', '|'];
const MAX_CSV_BYTES = 20_000_000;
const MAX_CSV_ROWS = 500_000;
const MAX_CSV_COLUMNS = 256;
const REQUIRED_FIELDS = Object.freeze({
  roster: ['id', 'name', 'email'],
  attendance: ['studentId', 'sessionId', 'status'],
});

const HEADER_ALIASES = Object.freeze({
  roster: {
    id: ['id', 'studentid', 'studentnumber', 'studentno', 'studentcode', 'rollno', 'rollnumber', 'mssv', 'masinhvien', 'sinhvienid'],
    name: ['name', 'studentname', 'fullname', 'fullstudentname', 'hovaten', 'tensinhvien', 'hoten'],
    email: ['email', 'emailaddress', 'mail', 'studentemail', 'emailsinhvien', 'emailtruong', 'thuđiệntử', 'thudientu'],
  },
  attendance: {
    studentId: ['studentid', 'studentnumber', 'studentno', 'studentcode', 'rollno', 'mssv', 'masinhvien', 'id'],
    sessionId: ['sessionid', 'sessioncode', 'meetingid', 'meeting', 'lessonid', 'classsession', 'buoi', 'buoihoc', 'mahocphan'],
    status: ['status', 'attendance', 'attendancestatus', 'result', 'checkin', 'state', 'trangthai', 'diemdanh', 'ketqua'],
  },
});

const STATUS_ALIASES = Object.freeze({
  present: ['present', 'here', 'attended', 'attendance', 'checked in', 'checkin', 'true', '1', 'yes', 'y',
    'co mat', 'co', 'di hoc', 'da hoc', 'hien dien'],
  absent: ['absent', 'away', 'missed', 'not attended', 'false', '0', 'no', 'n',
    'vang', 'vang mat', 'nghi', 'nghi hoc', 'khong co mat'],
  missing: ['', 'missing', 'not recorded', 'unrecorded', 'pending', 'chua ghi', 'chua co', 'bo trong'],
});

function requiredText(value, field, maximum = 512) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${field} must be a non-empty string of at most ${maximum} characters`);
  }
  return value.trim();
}

function normalizeHeader(value) {
  return String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('vi').replace(/đ/g, 'd').replace(/[^a-z0-9]+/g, '');
}

function countDelimiters(line, delimiter) {
  let quoted = false;
  let count = 0;
  for (let index = 0; index < line.length; index++) {
    if (line[index] === '"') {
      if (quoted && line[index + 1] === '"') index++;
      else quoted = !quoted;
    } else if (!quoted && line[index] === delimiter) count++;
  }
  return count;
}

function detectDelimiter(source) {
  const first = source.split(/\r?\n/, 1)[0] ?? '';
  const ranked = DELIMITERS.map((delimiter, index) => ({ delimiter, index, count: countDelimiters(first, delimiter) }))
    .sort((left, right) => right.count - left.count || left.index - right.index);
  return ranked[0].count > 0 ? ranked[0].delimiter : ',';
}

/** Parse comma, semicolon, tab or pipe delimited text with quoted newlines. */
export function parseDelimitedCsv(text, options = {}) {
  if (typeof text !== 'string') throw new TypeError('CSV must be a string');
  if (text.length > MAX_CSV_BYTES) throw new RangeError(`CSV must not exceed ${MAX_CSV_BYTES} characters`);
  if (!options || typeof options !== 'object' || Array.isArray(options)) throw new TypeError('CSV options must be an object');
  const source = text.startsWith('\uFEFF') ? text.slice(1) : text;
  const delimiter = options.delimiter === undefined || options.delimiter === 'auto'
    ? detectDelimiter(source) : options.delimiter;
  if (typeof delimiter !== 'string' || !DELIMITERS.includes(delimiter)) {
    throw new TypeError('delimiter must be comma, semicolon, tab, pipe, or auto');
  }
  const rows = [];
  let fields = [];
  let field = '';
  let state = 'start';
  let line = 1;
  let rowLine = 1;
  let rowStarted = false;
  const finishField = () => { fields.push(field); field = ''; state = 'start'; };
  const finishRow = () => { finishField(); rows.push({ line: rowLine, fields }); fields = []; rowStarted = false; };

  for (let index = 0; index < source.length; index++) {
    const char = source[index];
    if (state === 'quoted') {
      if (char === '"') {
        if (source[index + 1] === '"') { field += '"'; index++; }
        else state = 'closed';
      } else if (char === '\r' || char === '\n') {
        if (char === '\r' && source[index + 1] === '\n') { field += '\r\n'; index++; }
        else field += char;
        line++;
      } else field += char;
      continue;
    }
    if (char === delimiter || char === '\r' || char === '\n') {
      rowStarted = true;
      if (char === delimiter) finishField();
      else {
        finishRow();
        if (char === '\r' && source[index + 1] === '\n') index++;
        line++;
        rowLine = line;
      }
      continue;
    }
    if (state === 'closed') throw new SyntaxError(`unexpected character after closing quote on line ${line}`);
    if (char === '"') {
      if (state !== 'start') throw new SyntaxError(`unexpected quote on line ${line}`);
      state = 'quoted';
      rowStarted = true;
      continue;
    }
    field += char;
    state = 'unquoted';
    rowStarted = true;
  }
  if (state === 'quoted') throw new SyntaxError(`unclosed quoted field starting on line ${rowLine}`);
  if (rowStarted) finishRow();
  if (rows.length > MAX_CSV_ROWS) throw new RangeError(`CSV must not exceed ${MAX_CSV_ROWS} rows`);
  if (rows.some((row) => row.fields.length > MAX_CSV_COLUMNS)) throw new RangeError(`CSV must not exceed ${MAX_CSV_COLUMNS} columns`);
  return { delimiter, rows };
}

function editDistance(left, right, maximum = 2) {
  if (Math.abs(left.length - right.length) > maximum) return maximum + 1;
  const previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let row = 1; row <= left.length; row++) {
    const current = [row];
    for (let column = 1; column <= right.length; column++) {
      current[column] = Math.min(
        current[column - 1] + 1,
        previous[column] + 1,
        previous[column - 1] + Number(left[row - 1] !== right[column - 1]),
      );
    }
    if (Math.min(...current) > maximum) return maximum + 1;
    previous.splice(0, previous.length, ...current);
  }
  return previous[right.length] > maximum ? maximum + 1 : previous[right.length];
}

function canonicalField(value, kind) {
  const allowed = REQUIRED_FIELDS[kind];
  if (!allowed) throw new TypeError('kind must be roster or attendance');
  if (typeof value !== 'string' || !allowed.includes(value)) throw new TypeError(`unknown ${kind} field: ${value}`);
  return value;
}

/** Suggest field-to-header mappings without reading or returning row values. */
export function suggestHeaderMapping(headersValue, kind) {
  if (!Array.isArray(headersValue) || headersValue.some((header) => typeof header !== 'string')) {
    throw new TypeError('headers must be an array of strings');
  }
  const fields = REQUIRED_FIELDS[kind];
  const aliases = HEADER_ALIASES[kind];
  if (!fields) throw new TypeError('kind must be roster or attendance');
  const normalized = headersValue.map(normalizeHeader);
  const suggestions = fields.map((field) => {
    const accepted = new Set([normalizeHeader(field), ...aliases[field].map(normalizeHeader)]);
    const exact = normalized.map((header, index) => accepted.has(header) ? index : -1).filter((index) => index >= 0);
    const approximate = exact.length ? [] : normalized.map((header, index) => {
      const distance = Math.min(...[...accepted].map((alias) => editDistance(header, alias)));
      return distance > 0 && distance <= 2 ? { index, distance } : null;
    }).filter(Boolean).sort((left, right) => left.distance - right.distance || left.index - right.index);
    const bestApproximate = approximate[0]?.distance;
    const candidates = exact.length ? exact : approximate.filter((item) => item.distance === bestApproximate).map((item) => item.index);
    return {
      field,
      status: candidates.length === 1 ? (exact.length ? 'matched' : 'suggested') : candidates.length > 1 ? 'ambiguous' : 'missing',
      header: candidates.length === 1 && exact.length ? headersValue[candidates[0]] : null,
      candidates: candidates.map((index) => headersValue[index]),
    };
  });
  const mapping = Object.fromEntries(suggestions.map((item) => [item.field, item.status === 'matched' ? item.header : null]));
  const used = Object.values(mapping).filter(Boolean);
  if (new Set(used).size !== used.length) {
    for (const item of suggestions) {
      if (item.header && used.filter((header) => header === item.header).length > 1) {
        item.status = 'ambiguous';
        item.candidates = [item.header];
        item.header = null;
        mapping[item.field] = null;
      }
    }
  }
  return { kind, headers: [...headersValue], ready: Object.values(mapping).every(Boolean), mapping, fields: suggestions };
}

function resolveMapping(headers, kind, supplied) {
  const suggestion = suggestHeaderMapping(headers, kind);
  if (supplied === undefined) return suggestion;
  if (!supplied || typeof supplied !== 'object' || Array.isArray(supplied)) throw new TypeError('mapping must be an object');
  const mapping = { ...suggestion.mapping };
  for (const [rawField, header] of Object.entries(supplied)) {
    const field = canonicalField(rawField, kind);
    if (typeof header !== 'string' || !headers.includes(header)) throw new TypeError(`mapping.${field} must name an existing CSV header`);
    mapping[field] = header;
  }
  const selected = Object.values(mapping).filter(Boolean);
  const duplicate = new Set(selected).size !== selected.length;
  const fields = suggestion.fields.map((entry) => ({
    ...entry,
    header: mapping[entry.field] ?? null,
    status: supplied[entry.field] ? 'manual' : entry.status,
  }));
  if (duplicate) {
    for (const entry of fields) {
      if (entry.header && selected.filter((header) => header === entry.header).length > 1) {
        entry.status = 'ambiguous';
        entry.header = null;
        mapping[entry.field] = null;
      }
    }
  }
  return { kind, headers: [...headers], ready: !duplicate && Object.values(mapping).every(Boolean), mapping, fields };
}

function parseForImport(text, kind, settings = {}) {
  const parsed = parseDelimitedCsv(text, { delimiter: settings.delimiter });
  if (!parsed.rows.length) throw new TypeError('CSV must have a header');
  const headers = parsed.rows[0].fields.map((value) => value.trim());
  if (headers.some((header) => !header)) throw new TypeError('CSV headers cannot be empty');
  if (headers.some((header) => header.length > 128)) throw new RangeError('CSV headers must not exceed 128 characters');
  if (new Set(headers).size !== headers.length) throw new TypeError('duplicate CSV header');
  return { ...parsed, headers, dataRows: parsed.rows.slice(1), suggestion: resolveMapping(headers, kind, settings.mapping) };
}

function duplicatePolicy(value, field) {
  const policy = value ?? 'reject';
  if (!['reject', 'first', 'last'].includes(policy)) throw new TypeError(`${field} must be reject, first or last`);
  return policy;
}

function isBlankRow(fields) {
  return fields.every((value) => !value.trim());
}

function makeMappingError(source, suggestion) {
  return suggestion.fields.filter((field) => !field.header).map((field) => ({
    source,
    line: 1,
    code: field.status === 'ambiguous' ? 'ambiguous_header' : 'missing_header',
    field: field.field,
    message: field.status === 'ambiguous'
      ? `More than one column could map to ${field.field}. Choose one explicitly.`
      : `No column could be mapped to ${field.field}.`,
    candidates: field.candidates,
  }));
}

function rowObject(row, headers, suggestion) {
  if (row.fields.length !== headers.length) return null;
  return Object.fromEntries(Object.entries(suggestion.mapping).map(([field, header]) =>
    [field, row.fields[headers.indexOf(header)]?.trim() ?? '']));
}

function normalizeRosterRows(parsed, options = {}) {
  const students = [];
  const errors = makeMappingError('roster', parsed.suggestion);
  const warnings = [];
  const byId = new Map();
  const byEmail = new Map();
  const policy = duplicatePolicy(options.duplicatePolicy, 'roster duplicatePolicy');
  let blankRows = 0;
  for (const row of parsed.dataRows) {
    if (isBlankRow(row.fields)) { blankRows++; continue; }
    const values = rowObject(row, parsed.headers, parsed.suggestion);
    if (!values) { errors.push({ source: 'roster', line: row.line, code: 'column_count', message: 'Column count does not match header.' }); continue; }
    let id;
    let name;
    let rawEmail;
    try {
      id = requiredText(values.id, 'student ID', 256);
      name = requiredText(values.name, 'student name', 256);
      rawEmail = requiredText(values.email, 'student email', 320);
    } catch {
      errors.push({ source: 'roster', line: row.line, code: 'missing_field', message: 'ID, name and email are required and must fit the field limits.' });
      continue;
    }
    let email;
    try { email = normalizeEmail(rawEmail); }
    catch { errors.push({ source: 'roster', line: row.line, code: 'invalid_email', message: 'Email format is invalid.' }); continue; }
    const idDuplicate = byId.get(id);
    const emailDuplicate = byEmail.get(email);
    if (idDuplicate || emailDuplicate) {
      const firstLine = Math.min(idDuplicate?.line ?? Infinity, emailDuplicate?.line ?? Infinity);
      if (policy === 'reject') {
        errors.push({ source: 'roster', line: row.line, code: idDuplicate ? 'duplicate_id' : 'duplicate_email', firstLine,
          message: 'Duplicate roster identity; no row was silently selected.' });
        continue;
      }
      if (policy === 'first') {
        warnings.push({ source: 'roster', line: row.line, code: 'duplicate_skipped', firstLine,
          message: 'Duplicate roster identity skipped by the explicit first-row policy.' });
        continue;
      }
      const duplicate = idDuplicate ?? emailDuplicate;
      if ((idDuplicate && emailDuplicate && idDuplicate !== emailDuplicate) ||
          (!idDuplicate && emailDuplicate) || (!emailDuplicate && idDuplicate)) {
        errors.push({ source: 'roster', line: row.line, code: 'duplicate_conflict', firstLine,
          message: 'Duplicate ID and email point to different rows; last-row replacement is ambiguous.' });
        continue;
      }
      students[duplicate.index] = { id, name, email };
      byId.set(id, { index: duplicate.index, line: row.line });
      byEmail.set(email, { index: duplicate.index, line: row.line });
      warnings.push({ source: 'roster', line: row.line, code: 'duplicate_replaced', firstLine,
        message: 'Earlier duplicate replaced by the explicit last-row policy.' });
      continue;
    }
    const entry = { id, name, email };
    byId.set(id, { index: students.length, line: row.line });
    byEmail.set(email, { index: students.length, line: row.line });
    students.push(entry);
  }
  if (blankRows) warnings.push({ source: 'roster', line: null, code: 'blank_rows', count: blankRows,
    message: `${blankRows} completely empty rows were ignored.` });
  return { students, errors, warnings, parsedRows: parsed.dataRows.length - blankRows, delimiter: parsed.delimiter,
    mapping: parsed.suggestion };
}

function normalizeStatus(value, aliases = STATUS_ALIASES) {
  const token = normalizeHeader(value);
  const matches = Object.entries(aliases).filter(([, values]) => values.some((item) => normalizeHeader(item) === token)).map(([status]) => status);
  if (matches.length > 1) return { status: null, code: 'ambiguous_status' };
  if (!matches.length) return { status: null, code: 'invalid_status' };
  return { status: matches[0], code: null };
}

function normalizeStatusAliases(value) {
  if (value === undefined) return STATUS_ALIASES;
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('statusAliases must be an object');
  const aliases = Object.fromEntries(Object.entries(STATUS_ALIASES).map(([key, values]) => [key, [...values]]));
  for (const [status, values] of Object.entries(value)) {
    if (!Object.hasOwn(aliases, status)) throw new TypeError(`unknown status alias group: ${status}`);
    if (!Array.isArray(values) || values.some((item) => typeof item !== 'string')) throw new TypeError(`statusAliases.${status} must be an array of strings`);
    aliases[status].push(...values);
  }
  return aliases;
}

function normalizeAttendanceRows(parsed, options = {}) {
  const records = [];
  const errors = makeMappingError('attendance', parsed.suggestion);
  const warnings = [];
  const byCell = new Map();
  const policy = duplicatePolicy(options.duplicatePolicy, 'attendance duplicatePolicy');
  const aliases = normalizeStatusAliases(options.statusAliases);
  let blankRows = 0;
  let unrecordedRows = 0;
  for (const row of parsed.dataRows) {
    if (isBlankRow(row.fields)) { blankRows++; continue; }
    const values = rowObject(row, parsed.headers, parsed.suggestion);
    if (!values) { errors.push({ source: 'attendance', line: row.line, code: 'column_count', message: 'Column count does not match header.' }); continue; }
    try {
      values.studentId = requiredText(values.studentId, 'student ID', 256);
      values.sessionId = requiredText(values.sessionId, 'session ID', 256);
    } catch { errors.push({ source: 'attendance', line: row.line, code: 'missing_id', message: 'Student and session IDs are required.' }); continue; }
    const status = normalizeStatus(values.status, aliases);
    if (status.code) {
      errors.push({ source: 'attendance', line: row.line, code: status.code, message: status.code === 'ambiguous_status'
        ? 'Status value matches more than one configured alias.' : 'Status value is not recognized.' });
      continue;
    }
    if (status.status === 'missing') { unrecordedRows++; continue; }
    const key = JSON.stringify([values.studentId, values.sessionId]);
    const duplicateIndex = byCell.get(key);
    if (duplicateIndex !== undefined) {
      if (policy === 'reject') {
        errors.push({ source: 'attendance', line: row.line, code: 'duplicate_cell', firstLine: records[duplicateIndex].line,
          message: 'More than one result exists for this student and session.' });
        continue;
      }
      if (policy === 'first') {
        warnings.push({ source: 'attendance', line: row.line, code: 'duplicate_skipped', firstLine: records[duplicateIndex].line,
          message: 'Duplicate result skipped by the explicit first-row policy.' });
        continue;
      }
      warnings.push({ source: 'attendance', line: row.line, code: 'duplicate_replaced', firstLine: records[duplicateIndex].line,
        message: 'Earlier result replaced by the explicit last-row policy.' });
      records[duplicateIndex] = { studentId: values.studentId, sessionId: values.sessionId, status: status.status, line: row.line };
      continue;
    }
    byCell.set(key, records.length);
    records.push({ studentId: values.studentId, sessionId: values.sessionId, status: status.status, line: row.line });
  }
  if (blankRows) warnings.push({ source: 'attendance', line: null, code: 'blank_rows', count: blankRows,
    message: `${blankRows} completely empty rows were ignored.` });
  if (unrecordedRows) warnings.push({ source: 'attendance', line: null, code: 'unrecorded_rows', count: unrecordedRows,
    message: `${unrecordedRows} explicit missing-result rows were omitted from the snapshot.` });
  return { records: records.map(({ line, ...record }) => record), recordLines: records.map((record) => record.line), errors, warnings,
    parsedRows: parsed.dataRows.length - blankRows, unrecordedRows, delimiter: parsed.delimiter, mapping: parsed.suggestion };
}

function normalizeSessions(value) {
  let sessions = value;
  if (typeof sessions === 'string') {
    try { sessions = JSON.parse(sessions); }
    catch { throw new TypeError('sessions must contain a JSON array'); }
  }
  if (!Array.isArray(sessions)) throw new TypeError('sessions must be an array');
  const result = sessions.map((session, index) => {
    if (typeof session !== 'string' || !session.trim()) throw new TypeError(`invalid session ID at index ${index}`);
    return session.trim();
  });
  if (new Set(result).size !== result.length) throw new TypeError('session IDs must be unique');
  return result;
}

/** Preview non-standard roster and attendance CSVs using explicit or suggested mappings. */
export function previewMappedImport(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) throw new TypeError('input must be an object');
  if (typeof input.rosterCsv !== 'string' || typeof input.attendanceCsv !== 'string') {
    throw new TypeError('rosterCsv and attendanceCsv must be strings');
  }
  const sessionIds = normalizeSessions(input.sessions);
  const rosterOptions = input.rosterOptions === undefined ? {} : input.rosterOptions;
  const attendanceOptions = input.attendanceOptions === undefined ? {} : input.attendanceOptions;
  if (!rosterOptions || typeof rosterOptions !== 'object' || Array.isArray(rosterOptions)) throw new TypeError('rosterOptions must be an object');
  if (!attendanceOptions || typeof attendanceOptions !== 'object' || Array.isArray(attendanceOptions)) throw new TypeError('attendanceOptions must be an object');
  const rosterParsed = parseForImport(input.rosterCsv, 'roster', rosterOptions);
  const attendanceParsed = parseForImport(input.attendanceCsv, 'attendance', attendanceOptions);
  const roster = normalizeRosterRows(rosterParsed, rosterOptions);
  const attendance = normalizeAttendanceRows(attendanceParsed, attendanceOptions);
  const errors = [...roster.errors, ...attendance.errors];
  const warnings = [...roster.warnings, ...attendance.warnings];
  const studentIds = new Set(roster.students.map((student) => student.id));
  const knownSessions = new Set(sessionIds);
  for (let index = 0; index < attendance.records.length; index++) {
    const record = attendance.records[index];
    if (!studentIds.has(record.studentId)) errors.push({ source: 'attendance', line: attendance.recordLines[index],
      code: 'unknown_student', message: 'Attendance row references a student missing from the roster.' });
    if (!knownSessions.has(record.sessionId)) errors.push({ source: 'attendance', line: attendance.recordLines[index],
      code: 'unknown_session', message: 'Attendance row references a session missing from the schedule.' });
  }
  const expected = roster.students.length * sessionIds.length;
  const records = attendance.records.filter((record) => studentIds.has(record.studentId) && knownSessions.has(record.sessionId));
  const missing = Math.max(0, expected - records.length);
  if (missing && !errors.length) warnings.push({ source: 'summary', line: null, code: 'incomplete_coverage', count: missing,
    message: `${missing} student-session cells have no recorded result.` });
  let snapshot = null;
  if (!errors.length) snapshot = createAttendanceSnapshot(roster.students, sessionIds, records);
  return {
    version: 1,
    ready: snapshot !== null,
    delimiters: { roster: roster.delimiter, attendance: attendance.delimiter },
    mappings: { roster: roster.mapping, attendance: attendance.mapping },
    summary: {
      roster: { parsed: roster.parsedRows, accepted: roster.students.length, rejected: roster.parsedRows - roster.students.length },
      sessions: sessionIds.length,
      attendance: { parsed: attendance.parsedRows, accepted: records.length, rejected: attendance.parsedRows - records.length,
        explicitMissing: attendance.unrecordedRows },
      expected,
      recorded: records.length,
      missing,
      coverage: expected ? records.length / expected : null,
    },
    errors,
    warnings,
    snapshot,
  };
}

/** Export mapping and row issues without copying source-cell values. */
export function mappedImportIssuesToCsv(preview) {
  if (!preview || preview.version !== 1 || !Array.isArray(preview.errors) || !Array.isArray(preview.warnings)) {
    throw new TypeError('invalid mapped import preview');
  }
  const quote = (value) => {
    let text = String(value ?? '');
    if (/^[\t\r\n ]*[=+\-@]/.test(text)) text = `'${text}`;
    return `"${text.replaceAll('"', '""')}"`;
  };
  const rows = [
    ['severity', 'source', 'line', 'code', 'field', 'message'],
    ...preview.errors.map((issue) => ['error', issue.source, issue.line, issue.code, issue.field, issue.message]),
    ...preview.warnings.map((issue) => ['warning', issue.source, issue.line, issue.code, issue.field, issue.message]),
  ];
  return `${rows.map((row) => row.map(quote).join(',')).join('\r\n')}\r\n`;
}

