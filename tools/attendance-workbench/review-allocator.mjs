const FORMAT = 'attendance-review-allocation';
const VERSION = 1;
const MAX_CASES = 50_000;
const MAX_REVIEWERS = 1_000;
const PRIORITY_WEIGHT_DEFAULTS = Object.freeze({ urgent: 8, high: 4, review: 1, normal: 1 });

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 160) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function integer(value, field, minimum, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  return value;
}

function fraction(value, field, maximum = 1) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > maximum) throw new RangeError(`${field} must be from 0 to ${maximum}`);
  return value;
}

function uniqueTextList(value, field, maximum = 100) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > maximum) throw new RangeError(`${field} must contain at most ${maximum} values`);
  const values = value.map((item, index) => text(item, `${field}[${index}]`, 100));
  if (new Set(values).size !== values.length) throw new TypeError(`${field} contains duplicate values`);
  return values.sort((left, right) => left.localeCompare(right));
}

function normalizeCases(value) {
  const cases = Array.isArray(value) ? value : value?.cases;
  if (!Array.isArray(cases) || cases.length > MAX_CASES) throw new RangeError(`review cases must be an array with at most ${MAX_CASES} entries`);
  const ids = new Set();
  return cases.map((entry, index) => {
    object(entry, `cases[${index}]`);
    const caseId = text(entry.caseId, `cases[${index}].caseId`, 120);
    if (ids.has(caseId)) throw new TypeError(`duplicate review case ID: ${caseId}`);
    ids.add(caseId);
    const priority = text(entry.priority ?? 'normal', `cases[${index}].priority`, 40).toLowerCase();
    return { caseId, studentId: text(entry.studentId, `cases[${index}].studentId`, 256), priority,
      workloadWeight: entry.workloadWeight === undefined ? null : integer(entry.workloadWeight, `cases[${index}].workloadWeight`, 1, 100),
      requiredSkills: uniqueTextList(entry.requiredSkills, `cases[${index}].requiredSkills`, 30),
      preferredReviewerIds: uniqueTextList(entry.preferredReviewerIds, `cases[${index}].preferredReviewerIds`, MAX_REVIEWERS),
      blockedReviewerIds: uniqueTextList(entry.blockedReviewerIds, `cases[${index}].blockedReviewerIds`, MAX_REVIEWERS),
      cohortId: entry.cohortId === undefined || entry.cohortId === null ? null : text(entry.cohortId, `cases[${index}].cohortId`, 80) };
  });
}

function normalizeReviewers(value) {
  if (!Array.isArray(value) || value.length > MAX_REVIEWERS) throw new RangeError(`reviewers must be an array with at most ${MAX_REVIEWERS} entries`);
  const ids = new Set();
  return value.map((entry, index) => {
    object(entry, `reviewers[${index}]`);
    const id = text(entry.id, `reviewers[${index}].id`, 120);
    if (ids.has(id)) throw new TypeError(`duplicate reviewer ID: ${id}`);
    ids.add(id);
    const currentLoad = integer(entry.currentLoadPoints ?? 0, `reviewers[${index}].currentLoadPoints`, 0, 10_000_000);
    const capacity = integer(entry.capacityPoints, `reviewers[${index}].capacityPoints`, 0, 10_000_000);
    const maxCases = integer(entry.maxCases ?? MAX_CASES, `reviewers[${index}].maxCases`, 0, MAX_CASES);
    if (currentLoad > capacity) throw new RangeError(`reviewers[${index}] currentLoadPoints exceeds capacityPoints`);
    if (entry.active !== undefined && typeof entry.active !== 'boolean') throw new TypeError(`reviewers[${index}].active must be a boolean`);
    return { id, name: text(entry.name, `reviewers[${index}].name`, 160), skills: new Set(uniqueTextList(entry.skills, `reviewers[${index}].skills`, 100)),
      capacity, currentLoad, maxCases, active: entry.active !== false,
      conflicts: new Set(uniqueTextList(entry.conflictStudentIds, `reviewers[${index}].conflictStudentIds`, MAX_CASES)),
      blockedCases: new Set(uniqueTextList(entry.blockedCaseIds, `reviewers[${index}].blockedCaseIds`, MAX_CASES)),
      assigned: [], load: currentLoad, cohortLoad: new Map(), studentLoad: new Map() };
  });
}

function normalizeOptions(value) {
  const options = object(value, 'review allocation options');
  const priorityWeights = { ...PRIORITY_WEIGHT_DEFAULTS, ...(options.priorityWeights ?? {}) };
  for (const [priority, weight] of Object.entries(priorityWeights)) {
    text(priority, 'priority weight name', 40);
    integer(weight, `priorityWeights.${priority}`, 1, 100);
  }
  const maximumWorkloadRatio = fraction(options.maximumWorkloadRatio ?? 1, 'maximumWorkloadRatio', 2);
  const cohortBalanceWeight = fraction(options.cohortBalanceWeight ?? 0.25, 'cohortBalanceWeight', 10);
  const repeatStudentWeight = fraction(options.repeatStudentWeight ?? 0.5, 'repeatStudentWeight', 10);
  const includeReviewerNames = options.includeReviewerNames ?? false;
  if (typeof includeReviewerNames !== 'boolean') throw new TypeError('includeReviewerNames must be a boolean');
  return { priorityWeights, maximumWorkloadRatio, cohortBalanceWeight, repeatStudentWeight, includeReviewerNames };
}

function priorityWeight(item, options) {
  return item.workloadWeight ?? options.priorityWeights[item.priority] ?? options.priorityWeights.normal;
}

function eligibleReviewer(item, reviewer) {
  return reviewer.active && !reviewer.conflicts.has(item.studentId) && !reviewer.blockedCases.has(item.caseId) &&
    !item.blockedReviewerIds.includes(reviewer.id) &&
    item.requiredSkills.every((skill) => reviewer.skills.has(skill));
}

function eligibleReason(item, reviewers) {
  const active = reviewers.filter((reviewer) => reviewer.active);
  if (!active.length) return 'no_active_reviewers';
  const notBlocked = active.filter((reviewer) => !reviewer.conflicts.has(item.studentId) && !reviewer.blockedCases.has(item.caseId) &&
    !item.blockedReviewerIds.includes(reviewer.id));
  if (!notBlocked.length) return 'all_reviewers_conflicted_or_blocked';
  const skilled = notBlocked.filter((reviewer) => item.requiredSkills.every((skill) => reviewer.skills.has(skill)));
  if (!skilled.length) return 'required_skills_unavailable';
  const hasCaseSlots = skilled.some((reviewer) => reviewer.assigned.length < reviewer.maxCases);
  if (!hasCaseSlots) return 'reviewer_case_limits_reached';
  return 'capacity_exhausted';
}

function scoreReviewer(item, reviewer, weight, options) {
  const projectedLoad = reviewer.load + weight;
  const utilization = reviewer.capacity > 0 ? projectedLoad / reviewer.capacity : Number.POSITIVE_INFINITY;
  const cohortAssignments = item.cohortId ? reviewer.cohortLoad.get(item.cohortId) ?? 0 : 0;
  const studentAssignments = reviewer.studentLoad.get(item.studentId) ?? 0;
  const preference = item.preferredReviewerIds.includes(reviewer.id) ? -0.1 : 0;
  return utilization + cohortAssignments * options.cohortBalanceWeight + studentAssignments * options.repeatStudentWeight + preference;
}

function standardDeviation(values) {
  if (!values.length) return null;
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  return Math.sqrt(values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / values.length);
}

/** Assign a bounded review plan using skill, conflict, case and weighted-capacity rules. */
export function allocateReviewCasesConstrained(planValue, reviewerValues, optionsValue = {}) {
  const cases = normalizeCases(planValue);
  const reviewers = normalizeReviewers(reviewerValues);
  const options = normalizeOptions(optionsValue);
  if (cases.length * Math.max(1, reviewers.length) > 2_000_000) throw new RangeError('case/reviewer eligibility matrix exceeds 2000000 pairs');
  const eligibility = new Map(cases.map((item) => [item.caseId, reviewers.filter((reviewer) => eligibleReviewer(item, reviewer))]));
  const ordered = [...cases].sort((left, right) => priorityWeight(right, options) - priorityWeight(left, options) ||
    eligibility.get(left.caseId).length - eligibility.get(right.caseId).length || left.caseId.localeCompare(right.caseId));
  const assigned = [];
  const unassigned = [];
  for (const item of ordered) {
    const weight = priorityWeight(item, options);
    const candidates = eligibility.get(item.caseId).filter((reviewer) => reviewer.assigned.length < reviewer.maxCases &&
      reviewer.load + weight <= reviewer.capacity && (reviewer.capacity === 0 ? weight === 0 :
        (reviewer.load + weight) / reviewer.capacity <= options.maximumWorkloadRatio));
    candidates.sort((left, right) => scoreReviewer(item, left, weight, options) - scoreReviewer(item, right, weight, options) || left.id.localeCompare(right.id));
    const reviewer = candidates[0];
    if (!reviewer) {
      unassigned.push({ caseId: item.caseId, studentId: item.studentId, priority: item.priority, workloadWeight: weight,
        reason: eligibleReason(item, reviewers) });
      continue;
    }
    reviewer.assigned.push(item);
    reviewer.load += weight;
    if (item.cohortId) reviewer.cohortLoad.set(item.cohortId, (reviewer.cohortLoad.get(item.cohortId) ?? 0) + 1);
    reviewer.studentLoad.set(item.studentId, (reviewer.studentLoad.get(item.studentId) ?? 0) + 1);
    assigned.push({ caseId: item.caseId, studentId: item.studentId, reviewerId: reviewer.id,
      ...(options.includeReviewerNames ? { reviewerName: reviewer.name } : {}), priority: item.priority,
      workloadWeight: weight, cohortId: item.cohortId, reviewerLoadAfter: reviewer.load,
      capacityPoints: reviewer.capacity, utilizationAfter: reviewer.capacity ? reviewer.load / reviewer.capacity : null,
      reason: 'eligible_reviewer_with_lowest_projected_load' });
  }
  const loads = reviewers.map((reviewer) => reviewer.capacity ? reviewer.load / reviewer.capacity : null).filter((value) => value !== null);
  const meanUtilization = loads.length ? loads.reduce((sum, value) => sum + value, 0) / loads.length : null;
  const reviewerSummaries = reviewers.map((reviewer) => ({ id: reviewer.id,
    ...(options.includeReviewerNames ? { name: reviewer.name } : {}), active: reviewer.active,
    capacityPoints: reviewer.capacity, priorLoadPoints: reviewer.currentLoad, finalLoadPoints: reviewer.load,
    newLoadPoints: reviewer.load - reviewer.currentLoad, utilization: reviewer.capacity ? reviewer.load / reviewer.capacity : null,
    caseCount: reviewer.assigned.length, maxCases: reviewer.maxCases,
    cohorts: Object.fromEntries([...reviewer.cohortLoad].sort(([left], [right]) => left.localeCompare(right))) }));
  return { format: FORMAT, version: VERSION,
    settings: { maximumWorkloadRatio: options.maximumWorkloadRatio, cohortBalanceWeight: options.cohortBalanceWeight,
      repeatStudentWeight: options.repeatStudentWeight, includeReviewerNames: options.includeReviewerNames,
      priorityWeights: options.priorityWeights },
    summary: { cases: cases.length, assigned: assigned.length, unassigned: unassigned.length, reviewers: reviewers.length,
      activeReviewers: reviewers.filter((reviewer) => reviewer.active).length,
      totalCapacityPoints: reviewers.reduce((sum, reviewer) => sum + reviewer.capacity, 0),
      priorLoadPoints: reviewers.reduce((sum, reviewer) => sum + reviewer.currentLoad, 0),
      assignedLoadPoints: assigned.reduce((sum, item) => sum + item.workloadWeight, 0),
      meanUtilization, utilizationStandardDeviation: standardDeviation(loads),
      capacityCoverage: cases.length ? assigned.length / cases.length : null },
    assigned, unassigned, reviewers: reviewerSummaries,
    note: 'Assignments are a local planning suggestion. They do not contact reviewers or create tasks in another system.' };
}

/** Export assignment rows or per-reviewer load summaries. */
export function reviewAllocationToCsv(allocationValue, section = 'assignments') {
  const allocation = object(allocationValue, 'review allocation');
  if (allocation.format !== FORMAT || allocation.version !== VERSION || !allocation.summary) throw new TypeError('invalid review allocation');
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const csv = (headers, rows) => [headers, ...rows].map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
  if (section === 'assignments') return csv(['caseId', 'studentId', 'reviewerId', 'reviewerName', 'priority', 'workloadWeight',
    'cohortId', 'reviewerLoadAfter', 'capacityPoints', 'utilizationAfter', 'reason'], allocation.assigned.map((item) => [
    item.caseId, item.studentId, item.reviewerId, item.reviewerName, item.priority, item.workloadWeight,
    item.cohortId, item.reviewerLoadAfter, item.capacityPoints, item.utilizationAfter, item.reason]));
  if (section === 'reviewers') return csv(['reviewerId', 'reviewerName', 'active', 'capacityPoints', 'priorLoadPoints',
    'finalLoadPoints', 'newLoadPoints', 'utilization', 'caseCount', 'maxCases', 'cohorts'], allocation.reviewers.map((item) => [
    item.id, item.name, item.active, item.capacityPoints, item.priorLoadPoints, item.finalLoadPoints,
    item.newLoadPoints, item.utilization, item.caseCount, item.maxCases, JSON.stringify(item.cohorts)]));
  if (section === 'unassigned') return csv(['caseId', 'studentId', 'priority', 'workloadWeight', 'reason'], allocation.unassigned.map((item) => [
    item.caseId, item.studentId, item.priority, item.workloadWeight, item.reason]));
  throw new TypeError('section must be assignments, reviewers or unassigned');
}
