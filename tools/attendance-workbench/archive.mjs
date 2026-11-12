import { compareAttendanceSnapshots } from '../../backend/attendance-snapshot-diff.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const schemaVersion = 1;
const maximumRevisions = 5_000;

function requiredText(value, field, maximum = 500) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${field} must be a non-empty string of at most ${maximum} characters`);
  }
  return value.trim();
}

function optionalText(value, field, maximum = 160) {
  if (value === undefined || value === null || value === '') return '';
  if (typeof value !== 'string' || value.trim().length > maximum) throw new TypeError(`${field} must be a string of at most ${maximum} characters`);
  return value.trim();
}

function timestamp(value, field) {
  const source = value ?? new Date().toISOString();
  if (typeof source !== 'string' || !Number.isFinite(Date.parse(source))) throw new TypeError(`${field} must be a valid timestamp`);
  return new Date(source).toISOString();
}

function snapshotCopy(value) {
  return parseAttendanceSnapshot(serializeAttendanceSnapshot(value));
}

function normalizeRevision(value, index) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`revisions[${index}] must be an object`);
  const parentId = value.parentId === null ? null : requiredText(value.parentId, `revisions[${index}].parentId`, 120);
  return {
    id: requiredText(value.id, `revisions[${index}].id`, 120),
    parentId,
    createdAt: timestamp(value.createdAt, `revisions[${index}].createdAt`),
    author: optionalText(value.author, `revisions[${index}].author`),
    message: requiredText(value.message, `revisions[${index}].message`),
    snapshot: snapshotCopy(value.snapshot),
  };
}

function archiveShape(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('archive must be an object');
  if (value.schemaVersion !== schemaVersion) throw new TypeError(`unsupported archive version: ${value.schemaVersion}`);
  if (!Array.isArray(value.revisions) || value.revisions.length === 0 || value.revisions.length > maximumRevisions) {
    throw new RangeError(`archive revisions must contain between 1 and ${maximumRevisions} entries`);
  }
  const revisions = value.revisions.map(normalizeRevision);
  const byId = new Map();
  for (const revision of revisions) {
    if (byId.has(revision.id)) throw new TypeError(`duplicate revision ID: ${revision.id}`);
    byId.set(revision.id, revision);
  }
  const roots = revisions.filter((revision) => revision.parentId === null);
  if (roots.length !== 1) throw new TypeError('archive must contain exactly one root revision');
  for (const revision of revisions) {
    if (revision.parentId !== null && !byId.has(revision.parentId)) throw new TypeError(`unknown parent revision: ${revision.parentId}`);
  }
  const visited = new Set();
  for (const revision of revisions) {
    let cursor = revision;
    const path = new Set();
    while (cursor) {
      if (path.has(cursor.id)) throw new TypeError('archive revision graph contains a cycle');
      path.add(cursor.id);
      cursor = cursor.parentId === null ? null : byId.get(cursor.parentId);
    }
    for (const id of path) visited.add(id);
  }
  if (visited.size !== revisions.length) throw new TypeError('archive contains a disconnected revision');
  const headId = requiredText(value.headId, 'headId', 120);
  if (!byId.has(headId)) throw new TypeError(`unknown archive head: ${headId}`);
  return {
    schemaVersion,
    id: requiredText(value.id, 'archive ID', 120),
    title: requiredText(value.title, 'archive title', 160),
    headId,
    revisions,
  };
}

/** Parse and validate an immutable revision graph. */
export function parseArchive(value) {
  if (typeof value === 'string') {
    try { value = JSON.parse(value); }
    catch { throw new TypeError('archive must contain valid JSON'); }
  }
  return archiveShape(value);
}

/** Start an archive with one root revision. */
export function createArchive(snapshot, options = {}) {
  if (!options || typeof options !== 'object' || Array.isArray(options)) throw new TypeError('options must be an object');
  const id = requiredText(options.id ?? 'attendance-archive', 'archive ID', 120);
  const revision = {
    id: 'r1', parentId: null, createdAt: timestamp(options.createdAt, 'createdAt'),
    author: optionalText(options.author, 'author'),
    message: requiredText(options.message ?? 'Initial snapshot', 'message'),
    snapshot: snapshotCopy(snapshot),
  };
  return archiveShape({ schemaVersion, id, title: requiredText(options.title ?? 'Attendance history', 'title', 160),
    headId: revision.id, revisions: [revision] });
}

function allocateRevisionId(revisions) {
  const used = new Set(revisions.map((revision) => revision.id));
  for (let index = 1; index <= maximumRevisions; index++) if (!used.has(`r${index}`)) return `r${index}`;
  throw new RangeError('no revision ID is available');
}

/** Append a new revision, optionally branching from an earlier revision. */
export function appendArchiveRevision(archiveValue, snapshot, options = {}) {
  const archive = parseArchive(archiveValue);
  if (!options || typeof options !== 'object' || Array.isArray(options)) throw new TypeError('options must be an object');
  if (archive.revisions.length >= maximumRevisions) throw new RangeError('archive revision limit reached');
  if (options.expectedHeadId !== undefined && options.expectedHeadId !== archive.headId) {
    throw new Error(`archive head changed: expected ${options.expectedHeadId}, actual ${archive.headId}`);
  }
  const parentId = options.parentId === undefined ? archive.headId : requiredText(options.parentId, 'parentId', 120);
  if (!archive.revisions.some((revision) => revision.id === parentId)) throw new TypeError(`unknown parent revision: ${parentId}`);
  const revision = {
    id: options.id === undefined ? allocateRevisionId(archive.revisions) : requiredText(options.id, 'revision ID', 120),
    parentId,
    createdAt: timestamp(options.createdAt, 'createdAt'),
    author: optionalText(options.author, 'author'),
    message: requiredText(options.message, 'message'),
    snapshot: snapshotCopy(snapshot),
  };
  if (archive.revisions.some((item) => item.id === revision.id)) throw new TypeError(`duplicate revision ID: ${revision.id}`);
  return archiveShape({ ...archive, headId: revision.id, revisions: [...archive.revisions, revision] });
}

/** Restore an older revision by appending it as a new child of the current head. */
export function restoreArchiveRevision(archiveValue, revisionId, options = {}) {
  const archive = parseArchive(archiveValue);
  const target = archive.revisions.find((revision) => revision.id === requiredText(revisionId, 'revision ID', 120));
  if (!target) throw new TypeError(`unknown revision ID: ${revisionId}`);
  return appendArchiveRevision(archive, target.snapshot, {
    ...options,
    message: options.message ?? `Restore ${target.id}`,
  });
}

/** Return an independent snapshot copy from one revision. */
export function getArchiveSnapshot(archiveValue, revisionId) {
  const archive = parseArchive(archiveValue);
  const revision = archive.revisions.find((item) => item.id === requiredText(revisionId, 'revision ID', 120));
  if (!revision) throw new TypeError(`unknown revision ID: ${revisionId}`);
  return snapshotCopy(revision.snapshot);
}

function changeCounts(previous, current) {
  const diff = compareAttendanceSnapshots(previous, current);
  return {
    studentsAdded: diff.roster.added.length,
    studentsRemoved: diff.roster.removed.length,
    studentsChanged: diff.roster.changed.length,
    sessionsAdded: diff.sessions.added.length,
    sessionsRemoved: diff.sessions.removed.length,
    sessionsReordered: diff.sessions.reordered,
    recordsAdded: diff.attendance.added.length,
    recordsRemoved: diff.attendance.removed.length,
    recordsChanged: diff.attendance.changed.length,
  };
}

/** List revisions with parentage, current-head state, and change counts. */
export function listArchiveRevisions(archiveValue) {
  const archive = parseArchive(archiveValue);
  const byId = new Map(archive.revisions.map((revision) => [revision.id, revision]));
  return archive.revisions.map((revision, index) => {
    const snapshot = revision.snapshot;
    const parent = revision.parentId ? byId.get(revision.parentId) : null;
    return {
      id: revision.id,
      parentId: revision.parentId,
      createdAt: revision.createdAt,
      author: revision.author,
      message: revision.message,
      isHead: revision.id === archive.headId,
      branch: archive.revisions.some((item) => item.parentId === revision.id),
      sequence: index + 1,
      students: snapshot.roster.length,
      sessions: snapshot.sessionIds.length,
      records: snapshot.records.length,
      changes: parent ? changeCounts(parent.snapshot, snapshot) : null,
    };
  });
}

/** Compare any two revisions in the archive using semantic snapshot differences. */
export function compareArchiveRevisions(archiveValue, beforeId, afterId) {
  const archive = parseArchive(archiveValue);
  const before = archive.revisions.find((revision) => revision.id === requiredText(beforeId, 'before revision ID', 120));
  const after = archive.revisions.find((revision) => revision.id === requiredText(afterId, 'after revision ID', 120));
  if (!before || !after) throw new TypeError('both archive revisions must exist');
  return {
    before: { id: before.id, message: before.message },
    after: { id: after.id, message: after.message },
    changes: compareAttendanceSnapshots(before.snapshot, after.snapshot),
  };
}

/** Serialize a normalized revision archive for explicit file output. */
export function serializeArchive(value) {
  return `${JSON.stringify(parseArchive(value), null, 2)}\n`;
}

/** Export a compact spreadsheet-safe revision index, without attendance details. */
export function archiveToCsv(value) {
  const rows = listArchiveRevisions(value);
  const quote = (input) => {
    let cell = String(input ?? '');
    if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
    return `"${cell.replaceAll('"', '""')}"`;
  };
  const header = ['revisionId', 'parentId', 'createdAt', 'author', 'message', 'isHead', 'students', 'sessions', 'records',
    'studentsAdded', 'studentsRemoved', 'studentsChanged', 'sessionsAdded', 'sessionsRemoved', 'sessionsReordered',
    'recordsAdded', 'recordsRemoved', 'recordsChanged'];
  const data = rows.map((revision) => [revision.id, revision.parentId, revision.createdAt, revision.author, revision.message,
    revision.isHead, revision.students, revision.sessions, revision.records,
    revision.changes?.studentsAdded ?? '', revision.changes?.studentsRemoved ?? '', revision.changes?.studentsChanged ?? '',
    revision.changes?.sessionsAdded ?? '', revision.changes?.sessionsRemoved ?? '', revision.changes?.sessionsReordered ?? '',
    revision.changes?.recordsAdded ?? '', revision.changes?.recordsRemoved ?? '', revision.changes?.recordsChanged ?? '']);
  return [header, ...data].map((row) => row.map(quote).join(',')).join('\r\n') + '\r\n';
}
