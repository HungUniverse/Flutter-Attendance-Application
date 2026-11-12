// Offline CSV import for the attendance record shape used by the analytics module.
// No file access is performed here. Callers decide whether to persist valid rows.

/**
 * Parse CSV text into rows with the physical line on which each row starts.
 * Quoted fields can contain commas, line breaks and escaped double quotes.
 * Invalid quoting is rejected because subsequent row boundaries are ambiguous.
 */
export function parseCsv(text) {
  if (typeof text !== 'string') throw new TypeError('CSV must be a string');
  const source = text.startsWith('\uFEFF') ? text.slice(1) : text;
  const rows = [];
  let fields = [];
  let field = '';
  let state = 'start';
  let line = 1;
  let rowLine = 1;
  let rowStarted = false;

  function finishField() {
    fields.push(field);
    field = '';
    state = 'start';
  }

  function finishRow() {
    finishField();
    rows.push({ line: rowLine, fields });
    fields = [];
    rowStarted = false;
  }

  for (let index = 0; index < source.length; index++) {
    const char = source[index];
    if (state === 'quoted') {
      if (char === '"') {
        if (source[index + 1] === '"') {
          field += '"';
          index++;
        } else {
          state = 'closed';
        }
      } else if (char === '\r' || char === '\n') {
        if (char === '\r' && source[index + 1] === '\n') {
          field += '\r\n';
          index++;
        } else {
          field += char;
        }
        line++;
      } else {
        field += char;
      }
      continue;
    }

    if (char === ',' || char === '\r' || char === '\n') {
      rowStarted = true;
      if (char === ',') {
        finishField();
      } else {
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
  return rows;
}

/**
 * Validate a CSV with studentId, sessionId and status columns in any order.
 * Returns all valid rows and row-level errors, without changing any stored data.
 * The caller must explicitly decide whether partial imports are acceptable.
 */
export function importAttendanceCsv(text) {
  const rows = parseCsv(text);
  if (!rows.length) throw new TypeError('CSV must have a header');
  const header = rows[0].fields.map((value) => value.trim());
  const required = ['studentId', 'sessionId', 'status'];
  if (new Set(header).size !== header.length) throw new TypeError('duplicate CSV header');
  const indexes = required.map((name) => header.indexOf(name));
  if (indexes.some((index) => index < 0)) throw new TypeError('CSV requires studentId, sessionId and status headers');

  const records = [];
  const errors = [];
  const seen = new Map();
  for (const row of rows.slice(1)) {
    if (row.fields.length !== header.length) {
      errors.push({ line: row.line, code: 'column_count', message: 'Column count does not match header' });
      continue;
    }
    const [studentId, sessionId, status] = indexes.map((index) => row.fields[index].trim());
    if (!studentId || !sessionId) {
      errors.push({ line: row.line, code: 'missing_id', message: 'Student and session IDs are required' });
      continue;
    }
    if (status !== 'present' && status !== 'absent') {
      errors.push({ line: row.line, code: 'invalid_status', message: 'Status must be present or absent' });
      continue;
    }
    const key = JSON.stringify([studentId, sessionId]);
    if (seen.has(key)) {
      errors.push({ line: row.line, code: 'duplicate', message: `Duplicate of line ${seen.get(key)}` });
      continue;
    }
    seen.set(key, row.line);
    records.push({ studentId, sessionId, status });
  }
  return { records, errors };
}
