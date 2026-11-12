import { parseCasebook } from './casebook.mjs';
import { allocateReviewCasesConstrained } from './review-allocator.mjs';

const FORMAT = 'attendance-review-board';
const VERSION = 1;
const MAX_REVIEWERS = 1_000;
const MAX_CASES = 50_000;
const DEFAULT_WEIGHTS = Object.freeze({ urgent: 8, high: 4, review: 1, normal: 1 });
const TERMINAL = new Set(['resolved', 'dismissed']);

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 160) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function integer(value, field, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < 0 || value > maximum) throw new RangeError(`${field} must be a non-negative integer up to ${maximum}`);
  return value;
}

function normalizeReviewers(value) {
  if (!Array.isArray(value) || value.length > MAX_REVIEWERS) throw new RangeError(`reviewers must contain at most ${MAX_REVIEWERS} entries`);
  const ids = new Set();
  return value.map((entry, index) => {
    object(entry, `reviewers[${index}]`);
    const id = text(entry.id, `reviewers[${index}].id`, 120);
    if (ids.has(id)) throw new TypeError(`duplicate reviewer ID: ${id}`);
    ids.add(id);
    if (entry.active !== undefined && typeof entry.active !== 'boolean') throw new TypeError(`reviewers[${index}].active must be a boolean`);
    return { id, name: text(entry.name, `reviewers[${index}].name`, 160), active: entry.active !== false,
      capacityCases: integer(entry.capacityCases, `reviewers[${index}].capacityCases`, MAX_CASES),
      capacityPoints: integer(entry.capacityPoints, `reviewers[${index}].capacityPoints`, 10_000_000),
      skills: entry.skills, conflictStudentIds: entry.conflictStudentIds, blockedCaseIds: entry.blockedCaseIds };
  });
}

function normalizeOptions(value) {
  const options = object(value, 'review board options');
  const includeStudentIds = options.includeStudentIds ?? false;
  const includeReviewerNames = options.includeReviewerNames ?? false;
  if (typeof includeStudentIds !== 'boolean' || typeof includeReviewerNames !== 'boolean') throw new TypeError('review board detail options must be booleans');
  const maximumWorkloadRatio = options.maximumWorkloadRatio ?? 1;
  const cohortBalanceWeight = options.cohortBalanceWeight ?? 0.25;
  const repeatStudentWeight = options.repeatStudentWeight ?? 0.5;
  const priorityWeights = { ...DEFAULT_WEIGHTS, ...(options.priorityWeights ?? {}) };
  for (const [priority, weight] of Object.entries(priorityWeights)) {
    text(priority, 'priority weight name', 40);
    integer(weight, `priorityWeights.${priority}`, 100);
    if (weight === 0) throw new RangeError(`priorityWeights.${priority} must be at least 1`);
  }
  return { includeStudentIds, includeReviewerNames, maximumWorkloadRatio, cohortBalanceWeight, repeatStudentWeight, priorityWeights };
}

function safeCell(value) {
  let source = value === undefined || value === null ? '' : String(value);
  if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
  return `"${source.replaceAll('"', '""')}"`;
}

function csv(headers, rows) {
  return [headers, ...rows].map((row) => row.map(safeCell).join(',')).join('\r\n') + '\r\n';
}

/** Reconcile existing casebook load with a proposed queue and allocate only new work. */
export function planReviewBoard(bookValue, planValue, reviewerValues, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const plan = object(planValue, 'review plan');
  const reviewers = normalizeReviewers(reviewerValues);
  const options = normalizeOptions(optionsValue);
  if (plan.version !== 1 || !Array.isArray(plan.cases) || plan.cases.length > MAX_CASES) throw new TypeError('invalid or oversized review plan');
  const weights = { ...options.priorityWeights };
  const existingIds = new Set(book.cases.map((item) => item.caseId));
  const knownReviewers = new Map(reviewers.map((item) => [item.id, item]));
  const current = new Map(reviewers.map((item) => [item.id, { cases: 0, points: 0, stale: 0 }]));
  const currentOpen = book.cases.filter((item) => !TERMINAL.has(item.status));
  const orphanedAssignments = currentOpen.filter((item) => item.assigneeId && !knownReviewers.has(item.assigneeId));
  const unassignedCurrent = currentOpen.filter((item) => !item.assigneeId);
  for (const item of currentOpen) {
    const load = current.get(item.assigneeId);
    if (!load) continue;
    load.cases += 1;
    load.points += weights[item.priority] ?? weights.review;
    if (item.stale) load.stale += 1;
  }
  const incoming = plan.cases;
  const alreadyTracked = incoming.filter((item) => existingIds.has(item.caseId));
  const newCases = incoming.filter((item) => !existingIds.has(item.caseId));
  const allocationReviewers = reviewers.map((item) => {
    const load = current.get(item.id);
    const overCapacity = load.cases > item.capacityCases || load.points > item.capacityPoints;
    return { ...item,
      active: item.active && !overCapacity,
      currentLoadPoints: overCapacity ? item.capacityPoints : load.points,
      maxCases: overCapacity ? 0 : item.capacityCases - load.cases };
  });
  const allocationOptions = { maximumWorkloadRatio: options.maximumWorkloadRatio,
    cohortBalanceWeight: options.cohortBalanceWeight, repeatStudentWeight: options.repeatStudentWeight,
    priorityWeights: options.priorityWeights, includeReviewerNames: options.includeReviewerNames };
  const allocation = allocateReviewCasesConstrained({ cases: newCases }, allocationReviewers, allocationOptions);
  const assignedByReviewer = new Map(reviewers.map((item) => [item.id, { cases: 0, points: 0 }]));
  for (const item of allocation.assigned) {
    const load = assignedByReviewer.get(item.reviewerId);
    load.cases += 1;
    load.points += item.workloadWeight;
  }
  const reviewerRows = reviewers.map((profile) => {
    const currentLoad = current.get(profile.id);
    const proposed = assignedByReviewer.get(profile.id);
    const finalCases = currentLoad.cases + proposed.cases;
    const finalPoints = currentLoad.points + proposed.points;
    const caseUtilization = profile.capacityCases ? finalCases / profile.capacityCases : (finalCases ? null : 0);
    const pointUtilization = profile.capacityPoints ? finalPoints / profile.capacityPoints : (finalPoints ? null : 0);
    const utilization = caseUtilization === null || pointUtilization === null ? null : Math.max(caseUtilization, pointUtilization);
    return { id: profile.id, ...(options.includeReviewerNames ? { name: profile.name } : {}), active: profile.active,
      capacityCases: profile.capacityCases, currentCases: currentLoad.cases, proposedCases: proposed.cases, finalCases,
      capacityPoints: profile.capacityPoints, currentPoints: currentLoad.points, proposedPoints: proposed.points, finalPoints,
      utilization, utilizationPercent: utilization === null ? null : Math.round(utilization * 10_000) / 100,
      overCapacity: finalCases > profile.capacityCases || finalPoints > profile.capacityPoints,
      currentlyOverCapacity: currentLoad.cases > profile.capacityCases || currentLoad.points > profile.capacityPoints,
      staleCurrentCases: currentLoad.stale };
  });
  const assignments = allocation.assigned.map((item) => ({ caseId: item.caseId,
    ...(options.includeStudentIds ? { studentId: item.studentId } : {}), reviewerId: item.reviewerId,
    ...(options.includeReviewerNames ? { reviewerName: item.reviewerName } : {}), priority: item.priority,
    workloadWeight: item.workloadWeight, reviewerLoadAfter: item.reviewerLoadAfter,
    capacityPoints: item.capacityPoints, utilizationAfter: item.utilizationAfter }));
  const unassigned = allocation.unassigned.map((item) => ({ caseId: item.caseId,
    ...(options.includeStudentIds ? { studentId: item.studentId } : {}), priority: item.priority,
    workloadWeight: item.workloadWeight, reason: item.reason }));
  return { format: FORMAT, version: VERSION, casebookId: book.id, casebookRevision: book.revision,
    settings: { maximumWorkloadRatio: options.maximumWorkloadRatio, priorityWeights: options.priorityWeights,
      includeStudentIds: options.includeStudentIds, includeReviewerNames: options.includeReviewerNames },
    summary: { currentOpenCases: currentOpen.length, currentUnassignedCases: unassignedCurrent.length,
      orphanedAssignments: orphanedAssignments.length, incomingCases: incoming.length, alreadyTrackedCases: alreadyTracked.length,
      newCases: newCases.length, proposedAssignments: assignments.length, proposedUnassigned: unassigned.length,
      currentOverCapacityReviewers: reviewerRows.filter((item) => item.currentlyOverCapacity).length,
      projectedOverCapacityReviewers: reviewerRows.filter((item) => item.overCapacity).length,
      activeReviewers: reviewers.filter((item) => item.active).length },
    reviewers: reviewerRows, assignments, unassigned,
    note: 'New assignments are local suggestions. Existing casebook assignments and the review plan remain unchanged.' };
}

/** Export board sections with spreadsheet-safe cells. */
export function reviewBoardToCsv(boardValue, section = 'reviewers') {
  const board = object(boardValue, 'review board');
  if (board.format !== FORMAT || board.version !== VERSION || !board.summary || !Array.isArray(board.reviewers)) throw new TypeError('invalid review board');
  if (section === 'summary') return csv(Object.keys(board.summary), [Object.values(board.summary)]);
  if (section === 'reviewers') return csv(['reviewerId', 'reviewerName', 'active', 'capacityCases', 'currentCases', 'proposedCases',
    'finalCases', 'capacityPoints', 'currentPoints', 'proposedPoints', 'finalPoints', 'utilizationPercent',
    'overCapacity', 'currentlyOverCapacity', 'staleCurrentCases'], board.reviewers.map((item) => [item.id, item.name, item.active,
    item.capacityCases, item.currentCases, item.proposedCases, item.finalCases, item.capacityPoints,
    item.currentPoints, item.proposedPoints, item.finalPoints, item.utilizationPercent,
    item.overCapacity, item.currentlyOverCapacity, item.staleCurrentCases]));
  if (section === 'assignments') return csv(['caseId', 'studentId', 'reviewerId', 'reviewerName', 'priority', 'workloadWeight',
    'reviewerLoadAfter', 'capacityPoints', 'utilizationAfter'], board.assignments.map((item) => [item.caseId,
    item.studentId, item.reviewerId, item.reviewerName, item.priority, item.workloadWeight,
    item.reviewerLoadAfter, item.capacityPoints, item.utilizationAfter]));
  if (section === 'unassigned') return csv(['caseId', 'studentId', 'priority', 'workloadWeight', 'reason'], board.unassigned.map((item) => [
    item.caseId, item.studentId, item.priority, item.workloadWeight, item.reason]));
  throw new TypeError('section must be summary, reviewers, assignments or unassigned');
}
