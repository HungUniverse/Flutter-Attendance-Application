import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-snapshot-migration';
const VERSION = 1;
const POLICIES = new Set(['strict', 'prefer-present', 'prefer-absent']);
const MAX_MAPPINGS = 100_000;

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 256) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function stableId(value) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36).toUpperCase().padStart(7, '0');
}

function normalizeMappings(value, sourceIds, field) {
  if (value === undefined) return new Map();
  if (!Array.isArray(value) || value.length > MAX_MAPPINGS) throw new RangeError(`${field} must contain at most ${MAX_MAPPINGS} entries`);
  const result = new Map();
  for (const [index, item] of value.entries()) {
    object(item, `${field}[${index}]`);
    const from = text(item.from, `${field}[${index}].from`);
    const to = text(item.to, `${field}[${index}].to`);
    if (!sourceIds.has(from)) throw new TypeError(`${field}[${index}] refers to unknown source ID ${from}`);
    if (result.has(from)) throw new TypeError(`${field} contains duplicate source mapping ${from}`);
    result.set(from, to);
  }
  return result;
}

function normalizeTargetRoster(value) {
  if (value === undefined) return null;
  if (!Array.isArray(value) || value.length > 100_000) throw new RangeError('targetRoster must be an array with at most 100000 students');
  return value.map((student, index) => {
    object(student, `targetRoster[${index}]`);
    return { id: text(student.id, `targetRoster[${index}].id`),
      name: text(student.name, `targetRoster[${index}].name`, 256),
      email: text(student.email, `targetRoster[${index}].email`, 320) };
  });
}

function normalizeTargetSessions(value) {
  if (value === undefined) return null;
  if (!Array.isArray(value) || value.length > 10_000) throw new RangeError('targetSessionIds must be an array with at most 10000 sessions');
  const result = value.map((session, index) => text(session, `targetSessionIds[${index}]`));
  if (new Set(result).size !== result.length) throw new TypeError('targetSessionIds contains duplicate sessions');
  return result;
}

function cellKey(studentId, sessionId) {
  return JSON.stringify([studentId, sessionId]);
}

function normalizedName(value) {
  return String(value ?? '').normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('vi');
}

function normalizedEmail(value) {
  return String(value ?? '').normalize('NFKC').trim().toLocaleLowerCase('en-US');
}

function csv(headers, rows) {
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  return [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
}

/** Preview one snapshot's roster/session re-keying, removals and record collisions. */
export function planSnapshotMigration(snapshotValue, optionsValue = {}) {
  const source = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = object(optionsValue, 'migration options');
  const studentMap = normalizeMappings(options.studentMappings, new Set(source.roster.map((student) => student.id)), 'studentMappings');
  const sessionMap = normalizeMappings(options.sessionMappings, new Set(source.sessionIds), 'sessionMappings');
  const explicitRoster = normalizeTargetRoster(options.targetRoster);
  const explicitSessions = normalizeTargetSessions(options.targetSessionIds);
  const dropUnmappedStudents = options.dropUnmappedStudents ?? false;
  const dropUnmappedSessions = options.dropUnmappedSessions ?? false;
  const includeSnapshot = options.includeSnapshot ?? false;
  const recordConflictPolicy = options.recordConflictPolicy ?? 'strict';
  if (typeof dropUnmappedStudents !== 'boolean' || typeof dropUnmappedSessions !== 'boolean' || typeof includeSnapshot !== 'boolean') {
    throw new TypeError('drop flags and includeSnapshot must be booleans');
  }
  if (!POLICIES.has(recordConflictPolicy)) throw new TypeError('recordConflictPolicy must be strict, prefer-present or prefer-absent');
  const issues = [];
  const blocking = (code, message, fields = {}) => issues.push({ code, blocking: true, message, ...fields });
  const warnings = [];
  const warning = (code, message, fields = {}) => warnings.push({ code, blocking: false, message, ...fields });

  const mappedStudents = source.roster.map((student) => ({ ...student, targetId: studentMap.get(student.id) ?? student.id }));
  const mappedSessions = source.sessionIds.map((sessionId) => sessionMap.get(sessionId) ?? sessionId);
  let targetRoster = explicitRoster;
  if (targetRoster === null) {
    const rosterById = new Map();
    for (const student of mappedStudents) {
      if (!rosterById.has(student.targetId)) rosterById.set(student.targetId, { id: student.targetId, name: student.name, email: student.email });
      else {
        const existing = rosterById.get(student.targetId);
        if (normalizedName(existing.name) !== normalizedName(student.name) || normalizedEmail(existing.email) !== normalizedEmail(student.email)) {
          blocking('merged_identity_conflict', `Multiple source students mapped to ${student.targetId} have different identity fields.`,
            { targetStudentId: student.targetId, sourceStudentIds: mappedStudents.filter((item) => item.targetId === student.targetId).map((item) => item.id) });
        }
      }
    }
    targetRoster = [...rosterById.values()];
  }
  let targetSessionIds = explicitSessions;
  if (targetSessionIds === null) targetSessionIds = [...new Set(mappedSessions)];
  const validatedTarget = createAttendanceSnapshot(targetRoster, targetSessionIds, []);
  targetRoster = validatedTarget.roster;
  targetSessionIds = validatedTarget.sessionIds;
  const targetRosterIds = new Set(targetRoster.map((student) => student.id));
  const targetSessionSet = new Set(targetSessionIds);
  const sourceStudentIds = new Set(source.roster.map((student) => student.id));
  const sourceSessionIds = new Set(source.sessionIds);
  for (const [from, to] of studentMap) if (!sourceStudentIds.has(from) || !targetRosterIds.has(to)) {
    blocking('student_mapping_target_missing', `Student mapping ${from} → ${to} does not point to a target roster entry.`, { from, to });
  }
  for (const [from, to] of sessionMap) if (!sourceSessionIds.has(from) || !targetSessionSet.has(to)) {
    blocking('session_mapping_target_missing', `Session mapping ${from} → ${to} does not point to a target session.`, { from, to });
  }
  const droppedStudents = mappedStudents.filter((student) => !targetRosterIds.has(student.targetId));
  const droppedSessions = source.sessionIds.filter((sessionId) => !targetSessionSet.has(sessionMap.get(sessionId) ?? sessionId));
  if (droppedStudents.length && !dropUnmappedStudents) blocking('students_removed_without_opt_in', 'Target roster removes source students; set dropUnmappedStudents to true to accept.',
    { studentIds: droppedStudents.map((student) => student.id) });
  else if (droppedStudents.length) warning('students_dropped', 'Source students outside the target roster will be omitted.',
    { studentIds: droppedStudents.map((student) => student.id) });
  if (droppedSessions.length && !dropUnmappedSessions) blocking('sessions_removed_without_opt_in', 'Target sessions remove source sessions; set dropUnmappedSessions to true to accept.',
    { sessionIds: droppedSessions });
  else if (droppedSessions.length) warning('sessions_dropped', 'Source sessions outside the target list will be omitted.', { sessionIds: droppedSessions });

  if (explicitRoster) {
    const mappedByTarget = new Map();
    for (const student of mappedStudents) {
      if (!mappedByTarget.has(student.targetId)) mappedByTarget.set(student.targetId, []);
      mappedByTarget.get(student.targetId).push(student);
    }
    for (const target of targetRoster) {
      const candidates = mappedByTarget.get(target.id) ?? [];
      const mismatch = candidates.filter((student) => normalizedName(student.name) !== normalizedName(target.name) ||
        normalizedEmail(student.email) !== normalizedEmail(target.email));
      if (mismatch.length) warning('target_identity_authority', `Target roster identity fields replace differing source values for ${target.id}.`,
        { targetStudentId: target.id, sourceStudentIds: mismatch.map((student) => student.id) });
    }
  }

  const buckets = new Map();
  let omittedRecords = 0;
  for (const record of source.records) {
    const studentId = studentMap.get(record.studentId) ?? record.studentId;
    const sessionId = sessionMap.get(record.sessionId) ?? record.sessionId;
    if (!targetRosterIds.has(studentId) || !targetSessionSet.has(sessionId)) { omittedRecords++; continue; }
    const key = cellKey(studentId, sessionId);
    if (!buckets.has(key)) buckets.set(key, { studentId, sessionId, candidates: [] });
    buckets.get(key).candidates.push({ sourceStudentId: record.studentId, sourceSessionId: record.sessionId, status: record.status });
  }
  const conflicts = [];
  const selectedRecords = [];
  let agreeingDuplicates = 0;
  const resolutions = options.conflictResolutions ?? [];
  if (!Array.isArray(resolutions) || resolutions.length > 1_000_000) throw new RangeError('conflictResolutions must be an array with at most 1000000 entries');
  const resolutionMap = new Map();
  for (const [index, item] of resolutions.entries()) {
    object(item, `conflictResolutions[${index}]`);
    const conflictId = text(item.conflictId, `conflictResolutions[${index}].conflictId`, 120);
    if (!['present', 'absent'].includes(item.status)) throw new TypeError(`conflictResolutions[${index}].status must be present or absent`);
    if (resolutionMap.has(conflictId)) throw new TypeError(`duplicate conflict resolution: ${conflictId}`);
    resolutionMap.set(conflictId, item.status);
  }
  for (const bucket of buckets.values()) {
    const statuses = [...new Set(bucket.candidates.map((candidate) => candidate.status))].sort();
    if (statuses.length === 1) {
      selectedRecords.push({ studentId: bucket.studentId, sessionId: bucket.sessionId, status: statuses[0] });
      agreeingDuplicates += bucket.candidates.length - 1;
      continue;
    }
    const conflictId = `migration-${stableId(cellKey(bucket.studentId, bucket.sessionId))}`;
    const policyStatus = recordConflictPolicy === 'prefer-present' ? 'present' : recordConflictPolicy === 'prefer-absent' ? 'absent' : null;
    const selectedStatus = resolutionMap.get(conflictId) ?? policyStatus;
    const conflict = { conflictId, studentId: bucket.studentId, sessionId: bucket.sessionId,
      candidates: bucket.candidates, candidateStatuses: statuses, status: selectedStatus ? 'resolved' : 'unresolved', selectedStatus };
    conflicts.push(conflict);
    if (selectedStatus) selectedRecords.push({ studentId: bucket.studentId, sessionId: bucket.sessionId, status: selectedStatus });
  }
  const knownConflicts = new Set(conflicts.map((item) => item.conflictId));
  for (const conflictId of resolutionMap.keys()) if (!knownConflicts.has(conflictId)) {
    blocking('stale_conflict_resolution', `Conflict resolution ${conflictId} no longer matches a migration conflict.`, { conflictId });
  }
  for (const conflict of conflicts) if (conflict.status === 'unresolved') {
    blocking('record_conflict_unresolved', `Attendance values conflict at ${conflict.studentId}/${conflict.sessionId}.`,
      { conflictId: conflict.conflictId, studentId: conflict.studentId, sessionId: conflict.sessionId });
  }
  if (omittedRecords > 0 && (dropUnmappedStudents || dropUnmappedSessions)) warning('records_omitted', 'Records outside the target dimensions will be omitted.', { count: omittedRecords });
  const ready = !issues.some((issue) => issue.blocking);
  const result = { format: FORMAT, version: VERSION,
    settings: { dropUnmappedStudents, dropUnmappedSessions, recordConflictPolicy, includeSnapshot },
    source: { students: source.roster.length, sessions: source.sessionIds.length, records: source.records.length },
    target: { students: targetRoster.length, sessions: targetSessionIds.length, records: selectedRecords.length,
      studentIds: targetRoster.map((student) => student.id), sessionIds: [...targetSessionIds] },
    summary: { ready, studentMappings: studentMap.size, sessionMappings: sessionMap.size,
      studentsAdded: [...targetRosterIds].filter((id) => !mappedStudents.some((student) => student.targetId === id)).length,
      studentsRemoved: droppedStudents.length, sessionsAdded: targetSessionIds.filter((id) => !mappedSessions.includes(id)).length,
      sessionsRemoved: droppedSessions.length, selectedRecords: selectedRecords.length, omittedRecords,
      agreeingDuplicates, conflicts: conflicts.length, unresolvedConflicts: conflicts.filter((item) => item.status === 'unresolved').length,
      blockers: issues.length },
    issues, warnings, conflicts,
    identityMappings: mappedStudents.map((student) => ({ from: student.id, to: student.targetId })),
    sessionMappings: source.sessionIds.map((id, index) => ({ from: id, to: mappedSessions[index] })),
    note: 'This migration plan is an in-memory preview. It never edits the source snapshot or writes the target snapshot.' };
  if (ready && includeSnapshot) result.snapshot = createAttendanceSnapshot(targetRoster, targetSessionIds, selectedRecords);
  return result;
}

/** Export blockers, decisions or the re-keyed attendance preview. */
export function snapshotMigrationToCsv(planValue, section = 'issues') {
  const plan = object(planValue, 'snapshot migration plan');
  if (plan.format !== FORMAT || plan.version !== VERSION || !plan.summary) throw new TypeError('invalid snapshot migration plan');
  if (section === 'issues') return csv(['code', 'blocking', 'message', 'studentId', 'sessionId', 'conflictId'],
    plan.issues.map((item) => [item.code, item.blocking, item.message, item.studentId, item.sessionId, item.conflictId]));
  if (section === 'conflicts') return csv(['conflictId', 'studentId', 'sessionId', 'status', 'selectedStatus', 'candidates'],
    plan.conflicts.map((item) => [item.conflictId, item.studentId, item.sessionId, item.status, item.selectedStatus,
      item.candidates.map((candidate) => `${candidate.sourceStudentId}/${candidate.sourceSessionId}:${candidate.status}`).join('|')]));
  if (section === 'records') {
    if (!plan.snapshot) throw new TypeError('target snapshot was not included');
    return csv(['studentId', 'sessionId', 'status'], plan.snapshot.records.map((record) => [record.studentId, record.sessionId, record.status]));
  }
  throw new TypeError('section must be issues, conflicts or records');
}
