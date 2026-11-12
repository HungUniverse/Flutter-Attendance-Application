import { applyAttendanceBatch } from '../../backend/attendance-batch.mjs';
import { attendanceQualityReport } from '../../backend/attendance-quality-report.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { evaluatePolicy } from './policy.mjs';

const schemaVersion = 1;
const statuses = new Set(['present', 'absent', 'missing']);

function text(value, name, maximum = 240) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${name} must be a non-empty string of at most ${maximum} characters`);
  }
  return value.trim();
}

function normalizePolicy(value) {
  if (value === null || value === undefined) return null;
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('policy must be an object or null');
  const policy = { minimumRate: value.minimumRate, maximumAbsences: value.maximumAbsences };
  if (!Number.isFinite(policy.minimumRate) || policy.minimumRate < 0 || policy.minimumRate > 1) {
    throw new RangeError('minimumRate must be between 0 and 1');
  }
  if (!Number.isSafeInteger(policy.maximumAbsences) || policy.maximumAbsences < 0) {
    throw new RangeError('maximumAbsences must be a non-negative safe integer');
  }
  return policy;
}

function snapshotCopy(value) {
  return parseAttendanceSnapshot(serializeAttendanceSnapshot(value));
}

function recordStatus(snapshot, studentId, sessionId) {
  return snapshot.records.find((record) => record.studentId === studentId && record.sessionId === sessionId)?.status ?? null;
}

function changeKey(change) {
  return JSON.stringify([change.studentId, change.sessionId]);
}

function toBatchChanges(changes) {
  return changes.map((change) => ({ ...change, status: change.status === 'missing' ? null : change.status }));
}

/** Create a self-contained scenario whose baseline is never changed in place. */
export function createScenario(snapshot, options = {}) {
  if (!options || typeof options !== 'object' || Array.isArray(options)) throw new TypeError('options must be an object');
  const baseline = snapshotCopy(snapshot);
  const policy = normalizePolicy(options.policy ?? null);
  if (policy) evaluatePolicy(baseline, policy);
  return {
    schemaVersion,
    title: text(options.title ?? 'Kịch bản điểm danh', 'title', 120),
    description: typeof options.description === 'string' ? options.description.trim().slice(0, 2000) : '',
    policy,
    baseline,
    changes: [],
  };
}

/** Parse and fully validate a persisted scenario without mutating its input. */
export function parseScenario(value) {
  let source = value;
  if (typeof source === 'string') {
    try { source = JSON.parse(source); }
    catch { throw new TypeError('scenario must contain valid JSON'); }
  }
  if (!source || typeof source !== 'object' || Array.isArray(source)) throw new TypeError('scenario must be an object');
  if (source.schemaVersion !== schemaVersion) throw new TypeError(`unsupported scenario version: ${source.schemaVersion}`);
  const baseline = snapshotCopy(source.baseline);
  const policy = normalizePolicy(source.policy ?? null);
  if (policy) evaluatePolicy(baseline, policy);
  if (!Array.isArray(source.changes)) throw new TypeError('changes must be an array');
  const changes = source.changes.map((change, index) => {
    if (!change || typeof change !== 'object' || Array.isArray(change)) throw new TypeError(`invalid change at index ${index}`);
    const studentId = text(change.studentId, `studentId at index ${index}`);
    const sessionId = text(change.sessionId, `sessionId at index ${index}`);
    if (!statuses.has(change.status)) throw new TypeError(`invalid status at index ${index}`);
    const expected = recordStatus(baseline, studentId, sessionId);
    if (expected === change.status) throw new TypeError(`change at index ${index} does not change the baseline`);
    if (change.expected !== expected) throw new TypeError(`change at index ${index} does not match the baseline`);
    return { studentId, sessionId, expected, status: change.status };
  });
  if (new Set(changes.map(changeKey)).size !== changes.length) throw new TypeError('scenario contains duplicate attendance cells');
  // Reuse the batch validator to catch references to unknown students or sessions.
  const applied = applyAttendanceBatch(baseline, toBatchChanges(changes));
  if (applied.conflicts.length) throw new TypeError('scenario changes conflict with their baseline');
  return {
    schemaVersion,
    title: text(source.title, 'title', 120),
    description: typeof source.description === 'string' ? source.description.trim().slice(0, 2000) : '',
    policy,
    baseline,
    changes,
  };
}

/** Add or replace a proposed cell value; selecting its baseline value clears it. */
export function setScenarioChange(scenarioValue, studentIdValue, sessionIdValue, statusValue) {
  const scenario = parseScenario(scenarioValue);
  const studentId = text(studentIdValue, 'studentId');
  const sessionId = text(sessionIdValue, 'sessionId');
  if (!statuses.has(statusValue)) throw new TypeError('status must be present, absent, or missing');
  const expected = recordStatus(scenario.baseline, studentId, sessionId);
  const changes = scenario.changes.filter((change) => change.studentId !== studentId || change.sessionId !== sessionId);
  if (statusValue !== (expected ?? 'missing')) changes.push({ studentId, sessionId, expected, status: statusValue });
  return parseScenario({ ...scenario, changes });
}

/** Remove one proposed cell value and leave every other proposal untouched. */
export function removeScenarioChange(scenarioValue, studentIdValue, sessionIdValue) {
  const scenario = parseScenario(scenarioValue);
  const studentId = text(studentIdValue, 'studentId');
  const sessionId = text(sessionIdValue, 'sessionId');
  return parseScenario({ ...scenario, changes: scenario.changes.filter((change) =>
    change.studentId !== studentId || change.sessionId !== sessionId) });
}

function totals(quality) {
  const present = quality.students.reduce((sum, student) => sum + student.present, 0);
  const absent = quality.students.reduce((sum, student) => sum + student.absent, 0);
  const recorded = present + absent;
  return {
    students: quality.students.length,
    sessions: quality.sessions.length,
    present,
    absent,
    missing: quality.missing,
    expected: quality.expected,
    recorded: quality.recorded,
    coverage: quality.coverage,
    attendanceRate: recorded ? present / recorded : null,
  };
}

function policyByStudent(snapshot, policy) {
  if (!policy) return new Map();
  return new Map(evaluatePolicy(snapshot, policy).map((item) => [item.student.id, item]));
}

/**
 * Evaluate proposed corrections against an immutable baseline. Supplying a
 * second snapshot checks whether the source data changed since the scenario was made.
 */
export function evaluateScenario(scenarioValue, currentSnapshot) {
  const scenario = parseScenario(scenarioValue);
  const beforeSnapshot = currentSnapshot === undefined ? scenario.baseline : snapshotCopy(currentSnapshot);
  const currentValues = new Map(beforeSnapshot.records.map((record) => [
    JSON.stringify([record.studentId, record.sessionId]), record.status,
  ]));
  const studentIds = new Set(beforeSnapshot.roster.map((student) => student.id));
  const sessionIds = new Set(beforeSnapshot.sessionIds);
  const unavailable = scenario.changes.flatMap((change, index) => {
    const reason = !studentIds.has(change.studentId) ? 'student_removed'
      : !sessionIds.has(change.sessionId) ? 'session_removed' : null;
    return reason ? [{ index, studentId: change.studentId, sessionId: change.sessionId,
      expected: change.expected, actual: null, proposed: change.status, reason }] : [];
  });
  if (unavailable.length) {
    return {
      ok: false,
      scenario: { title: scenario.title, description: scenario.description },
      conflicts: unavailable,
      changes: scenario.changes.map((change) => ({ ...change,
        actual: currentValues.get(changeKey(change)) ?? null,
      })),
    };
  }
  const result = applyAttendanceBatch(beforeSnapshot, toBatchChanges(scenario.changes));
  if (result.conflicts.length) {
    return {
      ok: false,
      scenario: { title: scenario.title, description: scenario.description },
      conflicts: result.conflicts.map((conflict) => ({ ...conflict,
        proposed: scenario.changes[conflict.index]?.status ?? null,
      })),
      changes: scenario.changes.map((change) => ({ ...change,
        actual: currentValues.get(changeKey(change)) ?? null,
      })),
    };
  }

  const beforeQuality = attendanceQualityReport(beforeSnapshot.roster, beforeSnapshot.sessionIds, beforeSnapshot.records);
  const afterQuality = attendanceQualityReport(result.snapshot.roster, result.snapshot.sessionIds, result.snapshot.records);
  const beforeTotals = totals(beforeQuality);
  const afterTotals = totals(afterQuality);
  const beforePolicy = policyByStudent(beforeSnapshot, scenario.policy);
  const afterPolicy = policyByStudent(result.snapshot, scenario.policy);
  const studentMap = new Map(beforeSnapshot.roster.map((student) => [student.id, student]));
  const sessionSet = new Set(beforeSnapshot.sessionIds);
  const beforeByStudent = new Map(beforeQuality.students.map((student) => [student.student.id, student]));
  const afterByStudent = new Map(afterQuality.students.map((student) => [student.student.id, student]));
  const impactByStudent = new Map();
  for (const change of scenario.changes) {
    const student = studentMap.get(change.studentId);
    const before = beforeByStudent.get(change.studentId);
    const after = afterByStudent.get(change.studentId);
    const oldPolicy = beforePolicy.get(change.studentId);
    const newPolicy = afterPolicy.get(change.studentId);
    impactByStudent.set(change.studentId, {
      student,
      presentBefore: before.present,
      presentAfter: after.present,
      absentBefore: before.absent,
      absentAfter: after.absent,
      missingBefore: before.missingSessionIds.length,
      missingAfter: after.missingSessionIds.length,
      rateBefore: before.present + before.absent ? before.present / (before.present + before.absent) : null,
      rateAfter: after.present + after.absent ? after.present / (after.present + after.absent) : null,
      policyBefore: oldPolicy?.status ?? null,
      policyAfter: newPolicy?.status ?? null,
    });
  }
  const details = scenario.changes.map((change) => ({
    ...change,
    student: studentMap.get(change.studentId),
    sessionExists: sessionSet.has(change.sessionId),
    actual: currentValues.get(changeKey(change)) ?? null,
  }));
  const students = [...impactByStudent.values()].map((item) => ({
    ...item,
    rateDelta: item.rateBefore === null || item.rateAfter === null ? null : item.rateAfter - item.rateBefore,
    newlyPassing: item.policyBefore !== 'pass' && item.policyAfter === 'pass',
    newlyFailing: item.policyBefore === 'pass' && item.policyAfter === 'fail',
  }));
  const policyChanges = students.filter((item) => item.policyBefore !== item.policyAfter);
  return {
    ok: true,
    scenario: { title: scenario.title, description: scenario.description, policy: scenario.policy },
    snapshot: result.snapshot,
    changes: details,
    students,
    before: beforeTotals,
    after: afterTotals,
    delta: {
      present: afterTotals.present - beforeTotals.present,
      absent: afterTotals.absent - beforeTotals.absent,
      missing: afterTotals.missing - beforeTotals.missing,
      recorded: afterTotals.recorded - beforeTotals.recorded,
      coverage: beforeTotals.coverage === null || afterTotals.coverage === null ? null : afterTotals.coverage - beforeTotals.coverage,
      attendanceRate: beforeTotals.attendanceRate === null || afterTotals.attendanceRate === null
        ? null : afterTotals.attendanceRate - beforeTotals.attendanceRate,
      affectedStudents: students.length,
      newlyPassing: students.filter((item) => item.newlyPassing).length,
      newlyFailing: students.filter((item) => item.newlyFailing).length,
      policyChanged: policyChanges.length,
    },
  };
}

/** Render an evaluated scenario as an escaped, spreadsheet-friendly CSV. */
export function scenarioToCsv(evaluationValue) {
  if (!evaluationValue || evaluationValue.ok !== true || !Array.isArray(evaluationValue.changes)) {
    throw new TypeError('a successful scenario evaluation is required');
  }
  const quote = (value) => {
    let textValue = String(value ?? '');
    if (/^[\t\r\n ]*[=+\-@]/.test(textValue)) textValue = `'${textValue}`;
    return `"${textValue.replaceAll('"', '""')}"`;
  };
  const header = ['studentId', 'studentName', 'sessionId', 'expected', 'proposed', 'rateBefore', 'rateAfter', 'policyBefore', 'policyAfter'];
  const rows = evaluationValue.changes.map((change) => {
    const impact = evaluationValue.students.find((student) => student.student.id === change.studentId);
    return [change.studentId, change.student?.name ?? '', change.sessionId, change.expected ?? 'missing', change.status,
      impact?.rateBefore ?? '', impact?.rateAfter ?? '', impact?.policyBefore ?? '', impact?.policyAfter ?? ''];
  });
  return [header, ...rows].map((row) => row.map(quote).join(',')).join('\r\n') + '\r\n';
}

/** Serialize a normalized scenario for explicit download or CLI output. */
export function serializeScenario(value) {
  return `${JSON.stringify(parseScenario(value), null, 2)}\n`;
}
