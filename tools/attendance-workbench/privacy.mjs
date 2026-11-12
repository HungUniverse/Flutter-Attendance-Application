import { createHmac } from 'node:crypto';
import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { createBundle, parseBundle, putClass, serializeBundle } from './bundle.mjs';
import { parseArchive } from './archive.mjs';

const EMAIL_DOMAIN = 'example.invalid';
const REFERENCE_DATE = Date.UTC(2000, 0, 1);

function text(value, field, fallback, maximum = 40) {
  const result = value ?? fallback;
  if (typeof result !== 'string' || !result.trim() || result.trim().length > maximum) {
    throw new TypeError(`${field} must be a non-empty string of at most ${maximum} characters`);
  }
  return result.trim();
}

function normalizeOptions(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('anonymization options must be an object');
  const { secret } = value;
  if (typeof secret !== 'string' || Buffer.byteLength(secret, 'utf8') < 16 || Buffer.byteLength(secret, 'utf8') > 4096) {
    throw new TypeError('secret must contain between 16 and 4096 UTF-8 bytes');
  }
  if (value.keepSessionIds !== undefined && typeof value.keepSessionIds !== 'boolean') {
    throw new TypeError('keepSessionIds must be a boolean');
  }
  return {
    secret,
    keepSessionIds: value.keepSessionIds ?? false,
    studentPrefix: text(value.studentPrefix, 'studentPrefix', 'STUDENT'),
    sessionPrefix: text(value.sessionPrefix, 'sessionPrefix', 'SESSION'),
    classPrefix: text(value.classPrefix, 'classPrefix', 'CLASS'),
    archivePrefix: text(value.archivePrefix, 'archivePrefix', 'ARCHIVE'),
  };
}

function digest(secret, purpose, value) {
  return createHmac('sha256', secret).update(`${purpose}\0${value}`, 'utf8').digest('hex').toUpperCase();
}

function aliasFor(context, namespace, value, prefix) {
  const key = `${namespace}\0${value}`;
  if (context.aliases.has(key)) return context.aliases.get(key);
  const occupied = context.occupied.get(namespace) ?? new Map();
  const hash = digest(context.secret, namespace, value);
  for (let length = 12; length <= hash.length; length += 4) {
    const alias = `${prefix}-${hash.slice(0, length)}`;
    const previous = occupied.get(alias);
    if (previous === undefined || previous === value) {
      occupied.set(alias, value);
      context.occupied.set(namespace, occupied);
      context.aliases.set(key, alias);
      return alias;
    }
  }
  throw new Error(`unable to allocate a unique ${namespace} pseudonym`);
}

function makeContext(options) {
  return {
    ...options,
    aliases: new Map(),
    occupied: new Map(),
  };
}

function copySnapshot(snapshot) {
  return parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshot));
}

function anonymizeSnapshotWithContext(sourceValue, context) {
  const source = copySnapshot(sourceValue);
  const roster = source.roster.map((student) => {
    const id = aliasFor(context, 'student', student.id, context.studentPrefix);
    const identity = digest(context.secret, 'display-name', student.id).slice(0, 10);
    return { id, name: `Participant ${identity}`, email: `${id.toLowerCase()}@${EMAIL_DOMAIN}` };
  });
  const sessionIds = source.sessionIds.map((sessionId) => context.keepSessionIds
    ? sessionId
    : aliasFor(context, 'session', sessionId, context.sessionPrefix));
  const studentIds = new Map(source.roster.map((student, index) => [student.id, roster[index].id]));
  const sessionMap = new Map(source.sessionIds.map((sessionId, index) => [sessionId, sessionIds[index]]));
  const records = source.records.map((record) => ({
    studentId: studentIds.get(record.studentId),
    sessionId: sessionMap.get(record.sessionId),
    status: record.status,
  }));
  return createAttendanceSnapshot(roster, sessionIds, records);
}

/**
 * Replace roster identities with stable HMAC-SHA-256 pseudonyms. The secret is
 * never included in a returned document and no original-to-pseudonym map is
 * exposed. Attendance values and ordering are preserved.
 */
export function anonymizeSnapshot(snapshotValue, optionsValue) {
  const context = makeContext(normalizeOptions(optionsValue));
  return anonymizeSnapshotWithContext(snapshotValue, context);
}

/** Anonymize every class while reusing pseudonyms for the same person/session. */
export function anonymizeBundle(bundleValue, optionsValue) {
  const options = normalizeOptions(optionsValue);
  const bundle = parseBundle(typeof bundleValue === 'string' ? bundleValue : serializeBundle(bundleValue));
  const context = makeContext(options);
  let output = createBundle();
  for (let index = 0; index < bundle.classes.length; index++) {
    const entry = bundle.classes[index];
    const id = aliasFor(context, 'class', entry.id, options.classPrefix);
    const name = `Class ${digest(options.secret, 'class-name', entry.id).slice(0, 8)}`;
    output = putClass(output, id, name, anonymizeSnapshotWithContext(entry.snapshot, context));
  }
  return parseBundle(serializeBundle(output));
}

/**
 * Redact an archive's identity, notes, authors, revision labels and timestamps,
 * then pseudonymize each revision with one shared identity mapping.
 */
export function anonymizeArchive(archiveValue, optionsValue) {
  const options = normalizeOptions(optionsValue);
  const archive = parseArchive(archiveValue);
  const context = makeContext(options);
  const revisionIds = new Map(archive.revisions.map((revision, index) => [revision.id, `r${index + 1}`]));
  const revisions = archive.revisions.map((revision, index) => ({
    id: revisionIds.get(revision.id),
    parentId: revision.parentId === null ? null : revisionIds.get(revision.parentId),
    createdAt: new Date(REFERENCE_DATE + index * 60_000).toISOString(),
    author: 'Anonymous',
    message: `Revision ${index + 1}`,
    snapshot: anonymizeSnapshotWithContext(revision.snapshot, context),
  }));
  return parseArchive({
    schemaVersion: archive.schemaVersion,
    id: aliasFor(context, 'archive', archive.id, options.archivePrefix),
    title: 'Anonymized attendance history',
    headId: revisionIds.get(archive.headId),
    revisions,
  });
}

/** Return counts and a field checklist without values from the source data. */
export function anonymizationReport(sourceValue, anonymizedValue) {
  const source = copySnapshot(sourceValue);
  const anonymized = copySnapshot(anonymizedValue);
  const issues = [];
  if (source.roster.length !== anonymized.roster.length) issues.push('roster-size-changed');
  if (source.sessionIds.length !== anonymized.sessionIds.length) issues.push('session-count-changed');
  if (source.records.length !== anonymized.records.length) issues.push('record-count-changed');
  const roster = anonymized.roster.map((student) => student.id);
  if (new Set(roster).size !== roster.length) issues.push('duplicate-pseudonym');
  const sessions = anonymized.sessionIds;
  if (new Set(sessions).size !== sessions.length) issues.push('duplicate-session-pseudonym');
  const originalIds = new Set(source.roster.map((student) => student.id));
  if (source.roster.some((student, index) => anonymized.roster[index]?.id === student.id) ||
      anonymized.roster.some((student) => originalIds.has(student.id))) issues.push('original-student-id-retained');
  if (source.roster.some((student, index) => anonymized.roster[index]?.email === student.email)) issues.push('original-email-retained');
  if (source.roster.some((student, index) => anonymized.roster[index]?.name === student.name)) issues.push('original-name-retained');
  const sourceStudentIndex = new Map(source.roster.map((student, index) => [student.id, index]));
  const outputStudentIndex = new Map(anonymized.roster.map((student, index) => [student.id, index]));
  const sourceSessionIndex = new Map(source.sessionIds.map((sessionId, index) => [sessionId, index]));
  const outputSessionIndex = new Map(anonymized.sessionIds.map((sessionId, index) => [sessionId, index]));
  if (source.records.some((record, index) => {
    const counterpart = anonymized.records[index];
    return !counterpart || counterpart.status !== record.status ||
      outputStudentIndex.get(counterpart.studentId) !== sourceStudentIndex.get(record.studentId) ||
      outputSessionIndex.get(counterpart.sessionId) !== sourceSessionIndex.get(record.sessionId);
  })) issues.push('attendance-content-changed');
  const sessionsChanged = source.sessionIds.some((sessionId, index) => anonymized.sessionIds[index] !== sessionId);
  return {
    version: 1,
    algorithm: 'HMAC-SHA-256',
    valid: issues.length === 0,
    issues,
    source: { students: source.roster.length, sessions: source.sessionIds.length, records: source.records.length },
    output: { students: anonymized.roster.length, sessions: anonymized.sessionIds.length, records: anonymized.records.length },
    replacedFields: ['student IDs', 'names', 'emails', ...(sessionsChanged ? ['session IDs'] : []), 'attendance-linked references'],
    secretIncluded: false,
  };
}

