// Offline roster comparison. This module performs no file or network access and
// is deliberately not imported by the application server.

function text(value, field) {
  if (typeof value !== 'string' || !value.trim()) {
    throw new TypeError(`${field} must be a non-empty string`);
  }
  return value.trim();
}

/** Normalize an email for matching. This does not prove that it exists. */
export function normalizeEmail(value) {
  const email = text(value, 'email').toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new TypeError('invalid email');
  return email;
}

/** Create validated copies of roster entries, rejecting duplicate identifiers. */
export function normalizeRoster(roster) {
  if (!Array.isArray(roster)) throw new TypeError('roster must be an array');
  const ids = new Set();
  const emails = new Set();
  return roster.map((student) => {
    if (!student || typeof student !== 'object') throw new TypeError('student must be an object');
    const id = text(student.id, 'id');
    const name = text(student.name, 'name');
    const email = normalizeEmail(student.email);
    if (ids.has(id)) throw new TypeError(`duplicate student id: ${id}`);
    if (emails.has(email)) throw new TypeError(`duplicate email: ${email}`);
    ids.add(id);
    emails.add(email);
    return { id, name, email };
  });
}

/** Compare snapshots by stable student ID; never modify the supplied entries. */
export function compareRosters(previous, current) {
  const before = normalizeRoster(previous);
  const after = normalizeRoster(current);
  const oldById = new Map(before.map((student) => [student.id, student]));
  const newById = new Map(after.map((student) => [student.id, student]));
  const added = after.filter((student) => !oldById.has(student.id));
  const removed = before.filter((student) => !newById.has(student.id));
  const changed = [];
  for (const student of after) {
    const old = oldById.get(student.id);
    if (!old) continue;
    const fields = ['name', 'email'].filter((field) => old[field] !== student[field]);
    if (fields.length) changed.push({ id: student.id, fields, before: old, after: student });
  }
  return { added, removed, changed };
}

/** Find identifiers shared by two independently validated class rosters. */
export function findSharedStudents(first, second) {
  const firstRoster = normalizeRoster(first);
  const secondById = new Map(normalizeRoster(second).map((student) => [student.id, student]));
  return firstRoster.filter((student) => secondById.has(student.id)).map((student) => ({
    id: student.id, first: student, second: secondById.get(student.id),
  }));
}

/** Match input emails to the roster, preserving input order and reporting misses. */
export function matchEmails(roster, emails) {
  const lookup = new Map(normalizeRoster(roster).map((student) => [student.email, student]));
  if (!Array.isArray(emails)) throw new TypeError('emails must be an array');
  return emails.map((raw) => {
    const email = normalizeEmail(raw);
    return { email, student: lookup.get(email) ?? null };
  });
}

/** Return roster entries whose name, ID, or email includes a case-insensitive query. */
export function searchRoster(roster, query) {
  const needle = text(query, 'query').toLocaleLowerCase();
  return normalizeRoster(roster).filter((student) =>
    [student.id, student.name, student.email].some((value) => value.toLocaleLowerCase().includes(needle)));
}

/** Split a roster into ordered, non-empty chunks of at most the requested size. */
export function chunkRoster(roster, size) {
  if (!Number.isInteger(size) || size < 1) throw new RangeError('size must be a positive integer');
  const students = normalizeRoster(roster);
  const chunks = [];
  for (let index = 0; index < students.length; index += size) chunks.push(students.slice(index, index + size));
  return chunks;
}
