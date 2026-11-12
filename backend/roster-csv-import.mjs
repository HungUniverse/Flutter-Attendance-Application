import { parseCsv } from './attendance-csv-import.mjs';
import { normalizeEmail } from './roster-reconciliation.mjs';

/**
 * Parse a roster CSV with id, name and email headers. Returns valid rows and
 * row errors without persisting either. Duplicate checks apply to accepted rows,
 * and emails are compared case-insensitively after normalization.
 */
export function importRosterCsv(text) {
  const rows = parseCsv(text);
  if (!rows.length) throw new TypeError('CSV must have a header');
  const header = rows[0].fields.map((field) => field.trim());
  if (new Set(header).size !== header.length) throw new TypeError('duplicate CSV header');
  const indexes = ['id', 'name', 'email'].map((field) => header.indexOf(field));
  if (indexes.some((index) => index < 0)) throw new TypeError('CSV requires id, name and email headers');
  const students = [];
  const errors = [];
  const ids = new Map();
  const emails = new Map();
  for (const row of rows.slice(1)) {
    if (row.fields.length !== header.length) {
      errors.push({ line: row.line, code: 'column_count' });
      continue;
    }
    const [id, name, rawEmail] = indexes.map((index) => row.fields[index].trim());
    if (!id || !name) {
      errors.push({ line: row.line, code: 'missing_field' });
      continue;
    }
    let email;
    try {
      email = normalizeEmail(rawEmail);
    } catch (error) {
      if (!(error instanceof TypeError)) throw error;
      errors.push({ line: row.line, code: 'invalid_email' });
      continue;
    }
    if (ids.has(id)) {
      errors.push({ line: row.line, code: 'duplicate_id', firstLine: ids.get(id) });
      continue;
    }
    if (emails.has(email)) {
      errors.push({ line: row.line, code: 'duplicate_email', firstLine: emails.get(email) });
      continue;
    }
    ids.set(id, row.line);
    emails.set(email, row.line);
    students.push({ id, name, email });
  }
  return { students, errors };
}
