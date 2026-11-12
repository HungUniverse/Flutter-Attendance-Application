import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { buildAttendanceReport } from '../../backend/attendance-report.mjs';

const DEFAULTS = Object.freeze({
  targetRate: 0.75,
  futureSessions: 4,
  minimumObserved: 3,
  lowRate: 0.6,
  criticalRate: 0.35,
  maximumMissing: 2,
  absenceStreak: 3,
  recentWindow: 3,
  declineBy: 0.25,
  maximumCases: 10_000,
});

const PRIORITY = Object.freeze({ urgent: 0, high: 1, review: 2 });
const NEXT_STEP = Object.freeze({
  missing_results: 'Verify the missing attendance records before reviewing the rate.',
  low_rate: 'Review the recorded sessions and the applicable attendance rule.',
  absence_streak: 'Confirm the consecutive absences and check whether context is available.',
  recent_decline: 'Compare the recent window with earlier sessions before deciding on follow-up.',
  target_unreachable: 'Check the remaining-session count and explain the calculation to the reviewer.',
});

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function integer(value, field, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}

function fraction(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1) {
    throw new RangeError(`${field} must be a number from 0 to 1`);
  }
  return value;
}

function optionsFrom(value = {}) {
  object(value, 'options');
  const targetRate = fraction(value.targetRate ?? DEFAULTS.targetRate, 'targetRate');
  const lowRate = fraction(value.lowRate ?? DEFAULTS.lowRate, 'lowRate');
  const criticalRate = fraction(value.criticalRate ?? DEFAULTS.criticalRate, 'criticalRate');
  const declineBy = fraction(value.declineBy ?? DEFAULTS.declineBy, 'declineBy');
  if (criticalRate > lowRate) throw new RangeError('criticalRate must not exceed lowRate');
  return {
    targetRate,
    futureSessions: integer(value.futureSessions ?? DEFAULTS.futureSessions, 'futureSessions', 0, 500),
    minimumObserved: integer(value.minimumObserved ?? DEFAULTS.minimumObserved, 'minimumObserved', 1, 500),
    lowRate,
    criticalRate,
    maximumMissing: integer(value.maximumMissing ?? DEFAULTS.maximumMissing, 'maximumMissing', 0, 500),
    absenceStreak: integer(value.absenceStreak ?? DEFAULTS.absenceStreak, 'absenceStreak', 2, 500),
    recentWindow: integer(value.recentWindow ?? DEFAULTS.recentWindow, 'recentWindow', 1, 500),
    declineBy,
    maximumCases: integer(value.maximumCases ?? DEFAULTS.maximumCases, 'maximumCases', 1, 50_000),
  };
}

function stableId(text) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < text.length; index++) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36).toUpperCase().padStart(7, '0');
}

function rateOf(statuses) {
  const recorded = statuses.filter((status) => status !== 'missing');
  if (!recorded.length) return null;
  return recorded.filter((status) => status === 'present').length / recorded.length;
}

function absenceRuns(statuses) {
  const runs = [];
  let run = [];
  for (let index = 0; index < statuses.length; index++) {
    if (statuses[index] === 'absent') run.push(index);
    else {
      if (run.length) runs.push(run);
      run = [];
    }
  }
  if (run.length) runs.push(run);
  return runs;
}

function recentComparison(statuses, windowSize) {
  const recent = statuses.slice(-windowSize);
  const earlier = statuses.slice(Math.max(0, statuses.length - windowSize * 2), Math.max(0, statuses.length - windowSize));
  const earlierRate = rateOf(earlier);
  const recentRate = rateOf(recent);
  return {
    earlierRate,
    recentRate,
    decline: earlierRate === null || recentRate === null ? null : earlierRate - recentRate,
  };
}

function targetProjection(present, absent, targetRate, futureSessions) {
  const recorded = present + absent;
  const requiredPresent = Math.max(0, Math.ceil(targetRate * (recorded + futureSessions) - present - Number.EPSILON));
  return {
    recorded,
    requiredPresent,
    remainingSessions: futureSessions,
    reachable: requiredPresent <= futureSessions,
    projectedRateIfAllAttend: recorded + futureSessions ? (present + futureSessions) / (recorded + futureSessions) : null,
  };
}

function classifyPriority(signals) {
  if ((signals.absenceStreak?.length ?? 0) >= 2 && signals.criticalRate) return 'urgent';
  if (signals.targetUnreachable && signals.absenceStreak) return 'urgent';
  if (signals.absenceStreak || signals.lowRate || signals.targetUnreachable) return 'high';
  return 'review';
}

function csvCell(value) {
  let cell = String(value ?? '');
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

/**
 * Build an explainable human-review queue from attendance facts. The output is
 * advisory: it never changes a snapshot, contacts a student or decides a case.
 */
export function buildReviewPlan(snapshotValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = optionsFrom(optionsValue);
  const reports = buildAttendanceReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
  const cases = [];
  for (const student of reports) {
    const statusBySession = student.sessions.map((item) => item.status);
    const runs = absenceRuns(statusBySession).sort((left, right) => right.length - left.length);
    const longestRun = runs[0] ?? [];
    const comparison = recentComparison(statusBySession, options.recentWindow);
    const projection = targetProjection(student.present, student.absent, options.targetRate, options.futureSessions);
    const signals = {
      missingResults: student.missing > options.maximumMissing ? student.missing : 0,
      lowRate: student.present + student.absent >= options.minimumObserved && student.attendanceRate !== null &&
        student.attendanceRate < options.lowRate,
      criticalRate: student.present + student.absent >= options.minimumObserved && student.attendanceRate !== null &&
        student.attendanceRate <= options.criticalRate,
      absenceStreak: longestRun.length >= options.absenceStreak ? longestRun.map((index) => snapshot.sessionIds[index]) : null,
      recentDecline: comparison.decline !== null && comparison.decline >= options.declineBy,
      targetUnreachable: student.present + student.absent >= options.minimumObserved &&
        !projection.reachable,
    };
    const reasons = [];
    if (signals.missingResults) reasons.push({ code: 'missing_results', count: signals.missingResults, sessionIds: student.sessions
      .filter((item) => item.status === 'missing').map((item) => item.sessionId) });
    if (signals.lowRate) reasons.push({ code: 'low_rate', value: student.attendanceRate, threshold: options.lowRate });
    if (signals.absenceStreak) reasons.push({ code: 'absence_streak', count: signals.absenceStreak.length,
      sessionIds: signals.absenceStreak });
    if (signals.recentDecline) reasons.push({ code: 'recent_decline', value: comparison.decline,
      earlierRate: comparison.earlierRate, recentRate: comparison.recentRate });
    if (signals.targetUnreachable) reasons.push({ code: 'target_unreachable', requiredPresent: projection.requiredPresent,
      remainingSessions: options.futureSessions, projectedRateIfAllAttend: projection.projectedRateIfAllAttend });
    if (!reasons.length) continue;
    const priority = classifyPriority(signals);
    const identity = `${student.student.id}\0${reasons.map((reason) => reason.code).sort().join(',')}`;
    cases.push({
      caseId: `review-${stableId(identity)}`,
      studentId: student.student.id,
      studentName: student.student.name,
      priority,
      status: 'needs_review',
      present: student.present,
      absent: student.absent,
      missing: student.missing,
      recorded: student.present + student.absent,
      attendanceRate: student.attendanceRate,
      reasons,
      recent: comparison,
      target: { rate: options.targetRate, ...projection },
      suggestedSteps: [...new Set(reasons.map((reason) => NEXT_STEP[reason.code]))],
      humanReviewRequired: true,
    });
  }
  cases.sort((left, right) => PRIORITY[left.priority] - PRIORITY[right.priority] ||
    (left.attendanceRate ?? -1) - (right.attendanceRate ?? -1) || right.missing - left.missing ||
    left.studentId.localeCompare(right.studentId));
  if (cases.length > options.maximumCases) throw new RangeError(`review plan exceeds ${options.maximumCases} cases`);
  const snapshotFingerprint = stableId(JSON.stringify(snapshot));
  return {
    version: 1,
    snapshotFingerprint,
    generatedFor: { students: snapshot.roster.length, sessions: snapshot.sessionIds.length,
      records: snapshot.records.length },
    options,
    summary: {
      total: cases.length,
      urgent: cases.filter((item) => item.priority === 'urgent').length,
      high: cases.filter((item) => item.priority === 'high').length,
      review: cases.filter((item) => item.priority === 'review').length,
      byReason: Object.fromEntries([...new Set(cases.flatMap((item) => item.reasons.map((reason) => reason.code)))].sort().map((code) =>
        [code, cases.filter((item) => item.reasons.some((reason) => reason.code === code)).length])),
    },
    notice: 'Advisory review queue only. Confirm source records and apply institutional policy before taking action.',
    cases,
  };
}

/** Assign cases by priority while respecting each reviewer's declared capacity. */
export function allocateReviewCases(planValue, reviewersValue) {
  const plan = planValue;
  if (!plan || plan.version !== 1 || !Array.isArray(plan.cases)) throw new TypeError('invalid review plan');
  if (!Array.isArray(reviewersValue)) throw new TypeError('reviewers must be an array');
  const ids = new Set();
  const reviewers = reviewersValue.map((reviewer, index) => {
    object(reviewer, `reviewers[${index}]`);
    const id = typeof reviewer.id === 'string' && reviewer.id.trim() ? reviewer.id.trim() : null;
    const name = typeof reviewer.name === 'string' && reviewer.name.trim() ? reviewer.name.trim() : null;
    if (!id || !name) throw new TypeError(`reviewers[${index}] requires an ID and name`);
    if (ids.has(id)) throw new TypeError(`duplicate reviewer ID: ${id}`);
    ids.add(id);
    return { id, name, capacity: integer(reviewer.capacity, `reviewers[${index}].capacity`, 0, 50_000), assigned: [] };
  });
  const assigned = [];
  const unassigned = [];
  const orderedCases = [...plan.cases].sort((left, right) => PRIORITY[left.priority] - PRIORITY[right.priority] ||
    left.caseId.localeCompare(right.caseId));
  for (const item of orderedCases) {
    const candidates = reviewers.filter((reviewer) => reviewer.assigned.length < reviewer.capacity)
      .sort((left, right) => left.assigned.length - right.assigned.length || left.id.localeCompare(right.id));
    if (!candidates.length) { unassigned.push(item.caseId); continue; }
    const reviewer = candidates[0];
    reviewer.assigned.push(item.caseId);
    assigned.push({ caseId: item.caseId, reviewerId: reviewer.id, reviewerName: reviewer.name, priority: item.priority });
  }
  return {
    version: 1,
    assigned,
    unassigned,
    reviewers: reviewers.map(({ id, name, capacity, assigned: caseIds }) => ({ id, name, capacity, assigned: caseIds.length, caseIds })),
    summary: { cases: plan.cases.length, assigned: assigned.length, unassigned: unassigned.length,
      reviewers: reviewers.length, capacity: reviewers.reduce((sum, reviewer) => sum + reviewer.capacity, 0) },
  };
}

/** Export the review worklist in a spreadsheet-safe, value-limited format. */
export function reviewPlanToCsv(plan) {
  if (!plan || plan.version !== 1 || !Array.isArray(plan.cases)) throw new TypeError('invalid review plan');
  const header = ['caseId', 'priority', 'status', 'studentId', 'studentName', 'attendanceRate', 'present', 'absent', 'missing',
    'reasonCodes', 'suggestedSteps', 'humanReviewRequired'];
  const rows = plan.cases.map((item) => [item.caseId, item.priority, item.status, item.studentId, item.studentName,
    item.attendanceRate === null ? '' : `${(item.attendanceRate * 100).toFixed(1)}%`, item.present, item.absent, item.missing,
    item.reasons.map((reason) => reason.code).join(';'), item.suggestedSteps.join(';'), item.humanReviewRequired]);
  return `${[header, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n')}\r\n`;
}
