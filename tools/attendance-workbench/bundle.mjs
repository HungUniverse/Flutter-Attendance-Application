import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { attendanceQualityReport } from '../../backend/attendance-quality-report.mjs';

const format = 'attendance-workbench-bundle';

function text(value, name) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${name} must be a non-empty string`);
  return value.trim();
}

function copySnapshot(value) {
  return parseAttendanceSnapshot(serializeAttendanceSnapshot(value));
}

/** A bundle is a portable JSON document. No filesystem access occurs here. */
export function createBundle() {
  return { format, version: 1, classes: [] };
}

/** Validate every class and snapshot before returning an independent copy. */
export function parseBundle(source) {
  if (typeof source !== 'string') throw new TypeError('bundle must be JSON text');
  const data = JSON.parse(source);
  if (!data || typeof data !== 'object' || data.format !== format || data.version !== 1 ||
      !Array.isArray(data.classes)) throw new TypeError('invalid or unsupported bundle');
  const ids = new Set();
  const classes = data.classes.map((entry) => {
    if (!entry || typeof entry !== 'object') throw new TypeError('invalid class');
    const id = text(entry.id, 'class ID');
    const name = text(entry.name, 'class name');
    if (ids.has(id)) throw new TypeError(`duplicate class ID: ${id}`);
    ids.add(id);
    return { id, name, snapshot: copySnapshot(entry.snapshot) };
  });
  return { format, version: 1, classes };
}

export function serializeBundle(bundle) {
  return JSON.stringify(parseBundle(JSON.stringify(bundle)), null, 2);
}

/** Add a class, or replace its name and snapshot when the ID already exists. */
export function putClass(bundle, id, name, snapshot) {
  const result = parseBundle(serializeBundle(bundle));
  const classId = text(id, 'class ID');
  const entry = { id: classId, name: text(name, 'class name'), snapshot: copySnapshot(snapshot) };
  const index = result.classes.findIndex((item) => item.id === classId);
  if (index < 0) result.classes.push(entry);
  else result.classes[index] = entry;
  return result;
}

export function removeClass(bundle, id) {
  const result = parseBundle(serializeBundle(bundle));
  const classId = text(id, 'class ID');
  const index = result.classes.findIndex((item) => item.id === classId);
  if (index < 0) throw new TypeError(`unknown class ID: ${classId}`);
  result.classes.splice(index, 1);
  return result;
}

export function summarizeBundle(bundle) {
  const result = parseBundle(serializeBundle(bundle));
  return result.classes.map(({ id, name, snapshot }) => {
    const report = attendanceQualityReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
    return { id, name, students: snapshot.roster.length, sessions: snapshot.sessionIds.length,
      expected: report.expected, recorded: report.recorded, missing: report.missing, coverage: report.coverage };
  });
}

/** Return a validated copy of one class snapshot. */
export function getClassSnapshot(bundle, id) {
  const classId = text(id, 'class ID');
  const result = parseBundle(serializeBundle(bundle));
  const entry = result.classes.find((item) => item.id === classId);
  if (!entry) throw new TypeError(`unknown class ID: ${classId}`);
  return entry.snapshot;
}

/**
 * Aggregate attendance by student ID across classes. Every class remains
 * visible in the result, and differing names or emails are reported as
 * identity variants so callers can investigate rather than silently merging.
 */
export function summarizeStudentsAcrossClasses(bundle) {
  const result = parseBundle(serializeBundle(bundle));
  const students = new Map();
  for (const entry of result.classes) {
    const report = attendanceQualityReport(entry.snapshot.roster, entry.snapshot.sessionIds, entry.snapshot.records);
    for (const item of report.students) {
      let total = students.get(item.student.id);
      if (!total) {
        total = { studentId: item.student.id, identities: [], classes: [], present: 0, absent: 0, missing: 0 };
        students.set(item.student.id, total);
      }
      if (!total.identities.some((identity) => identity.name === item.student.name && identity.email === item.student.email)) {
        total.identities.push({ name: item.student.name, email: item.student.email });
      }
      const missing = item.missingSessionIds.length;
      total.classes.push({ classId: entry.id, className: entry.name, present: item.present, absent: item.absent, missing });
      total.present += item.present;
      total.absent += item.absent;
      total.missing += missing;
    }
  }
  return [...students.values()].map((student) => ({
    ...student,
    identityConflict: student.identities.length > 1,
    attendanceRate: student.present + student.absent ? student.present / (student.present + student.absent) : null,
  }));
}
