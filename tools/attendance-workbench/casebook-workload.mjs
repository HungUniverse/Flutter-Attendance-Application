import { parseCasebook } from './casebook.mjs';

const FORMAT = 'attendance-review-workload';
const VERSION = 1;
const TERMINAL = new Set(['resolved', 'dismissed']);
const DEFAULT_WEIGHTS = Object.freeze({ urgent: 3, high: 2, review: 1 });
const MAX_REVIEWERS = 1_000;
const MAX_CASES = 50_000;

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

function fraction(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 100) throw new RangeError(`${field} must be a percentage from 0 to 100`);
  return value;
}

function normalizeOptions(value) {
  const options = object(value, 'workload options');
  const priorityWeights = { ...DEFAULT_WEIGHTS, ...(options.priorityWeights ?? {}) };
  for (const [priority, weight] of Object.entries(priorityWeights)) {
    text(priority, 'priority weight name', 40);
    integer(weight, `priorityWeights.${priority}`, 100);
    if (weight === 0) throw new RangeError(`priorityWeights.${priority} must be at least 1`);
  }
  const includeCaseRows = options.includeCaseRows ?? false;
  const includeReviewerNames = options.includeReviewerNames ?? false;
  const includeStudentDetails = options.includeStudentDetails ?? false;
  for (const [name, value] of Object.entries({ includeCaseRows, includeReviewerNames, includeStudentDetails })) {
    if (typeof value !== 'boolean') throw new TypeError(`${name} must be a boolean`);
  }
  const maximumCaseRows = integer(options.maximumCaseRows ?? 1_000, 'maximumCaseRows', MAX_CASES);
  const utilizationWarningPercent = fraction(options.utilizationWarningPercent ?? 85, 'utilizationWarningPercent');
  return { priorityWeights, includeCaseRows, includeReviewerNames, includeStudentDetails, maximumCaseRows, utilizationWarningPercent };
}

function normalizeReviewers(value) {
  if (!Array.isArray(value) || value.length > MAX_REVIEWERS) throw new RangeError(`reviewers must contain at most ${MAX_REVIEWERS} entries`);
  const seen = new Set();
  return value.map((entry, index) => {
    object(entry, `reviewers[${index}]`);
    const id = text(entry.id, `reviewers[${index}].id`, 120);
    if (seen.has(id)) throw new TypeError(`duplicate reviewer ID: ${id}`);
    seen.add(id);
    if (entry.active !== undefined && typeof entry.active !== 'boolean') throw new TypeError(`reviewers[${index}].active must be a boolean`);
    return { id, name: text(entry.name, `reviewers[${index}].name`, 160), active: entry.active !== false,
      capacityCases: integer(entry.capacityCases, `reviewers[${index}].capacityCases`, MAX_CASES),
      capacityPoints: integer(entry.capacityPoints, `reviewers[${index}].capacityPoints`, 10_000_000) };
  });
}

function standardDeviation(values) {
  if (!values.length) return null;
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  return Math.sqrt(values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / values.length);
}

function safeCsvCell(value) {
  let source = value === undefined || value === null ? '' : String(value);
  if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
  return `"${source.replaceAll('"', '""')}"`;
}

function csv(headers, rows) {
  return [headers, ...rows].map((row) => row.map(safeCsvCell).join(',')).join('\r\n') + '\r\n';
}

/** Compare current non-terminal case assignments with an explicit reviewer capacity roster. */
export function reportCasebookWorkload(bookValue, reviewerValues, optionsValue = {}) {
  const book = parseCasebook(bookValue);
  const reviewers = normalizeReviewers(reviewerValues);
  const options = normalizeOptions(optionsValue);
  if (options.includeCaseRows && book.cases.length > options.maximumCaseRows) {
    throw new RangeError(`case rows exceed maximumCaseRows (${options.maximumCaseRows})`);
  }
  if (book.cases.length > MAX_CASES) throw new RangeError(`casebook exceeds ${MAX_CASES} cases`);
  const reviewerById = new Map(reviewers.map((reviewer) => [reviewer.id, {
    ...reviewer, openCases: 0, workloadPoints: 0, staleCases: 0, priorityCounts: { urgent: 0, high: 0, review: 0 },
  }]));
  const priorityCounts = new Map();
  const statusCounts = new Map();
  const unassigned = [];
  const orphaned = [];
  const inactiveAssigned = [];
  const caseRows = [];
  let terminalCases = 0;
  let staleOpenCases = 0;
  for (const item of book.cases) {
    const terminal = TERMINAL.has(item.status);
    if (terminal) terminalCases += 1;
    else if (item.stale) staleOpenCases += 1;
    const priorityWeight = options.priorityWeights[item.priority] ?? options.priorityWeights.review;
    const reviewer = item.assigneeId ? reviewerById.get(item.assigneeId) : null;
    if (!terminal) {
      priorityCounts.set(item.priority, (priorityCounts.get(item.priority) ?? 0) + 1);
      statusCounts.set(item.status, (statusCounts.get(item.status) ?? 0) + 1);
      if (!item.assigneeId) unassigned.push(item);
      else if (!reviewer) orphaned.push(item);
      else {
        reviewer.openCases += 1;
        reviewer.workloadPoints += priorityWeight;
        reviewer.priorityCounts[item.priority] = (reviewer.priorityCounts[item.priority] ?? 0) + 1;
        if (item.stale) reviewer.staleCases += 1;
        if (!reviewer.active) inactiveAssigned.push(item);
      }
    }
    if (options.includeCaseRows) {
      caseRows.push({ caseId: item.caseId,
        ...(options.includeStudentDetails ? { studentId: item.studentId, studentName: item.studentName } : {}),
        status: item.status, priority: item.priority, assigneeId: item.assigneeId, stale: item.stale,
        workloadPoints: terminal ? 0 : priorityWeight, terminal });
    }
  }
  const reviewerRows = reviewers.map((reviewer) => {
    const item = reviewerById.get(reviewer.id);
    const caseUtilization = reviewer.capacityCases ? item.openCases / reviewer.capacityCases : (item.openCases ? null : 0);
    const pointUtilization = reviewer.capacityPoints ? item.workloadPoints / reviewer.capacityPoints : (item.workloadPoints ? null : 0);
    const utilization = caseUtilization === null || pointUtilization === null ? null : Math.max(caseUtilization, pointUtilization);
    return { id: item.id, ...(options.includeReviewerNames ? { name: item.name } : {}), active: item.active,
      capacityCases: item.capacityCases, openCases: item.openCases, remainingCaseSlots: Math.max(0, item.capacityCases - item.openCases),
      capacityPoints: item.capacityPoints, workloadPoints: item.workloadPoints,
      remainingPoints: Math.max(0, item.capacityPoints - item.workloadPoints), caseUtilization, pointUtilization,
      utilization, utilizationPercent: utilization === null ? null : Math.round(utilization * 10_000) / 100,
      atWarningThreshold: utilization !== null && utilization * 100 >= options.utilizationWarningPercent,
      overCapacity: item.openCases > item.capacityCases || item.workloadPoints > item.capacityPoints,
      staleCases: item.staleCases, priorityCounts: item.priorityCounts };
  }).sort((left, right) => (right.utilization ?? -1) - (left.utilization ?? -1) || left.id.localeCompare(right.id));
  const utilizations = reviewerRows.filter((item) => item.active && item.utilization !== null).map((item) => item.utilization);
  const overCapacityReviewers = reviewerRows.filter((item) => item.overCapacity).length;
  const activeAtWarning = reviewerRows.filter((item) => item.active && item.atWarningThreshold).length;
  const summary = { totalCases: book.cases.length, openCases: book.cases.length - terminalCases, terminalCases,
    assignedOpenCases: reviewerRows.reduce((sum, item) => sum + item.openCases, 0),
    unassignedOpenCases: unassigned.length, orphanedAssignments: orphaned.length,
    inactiveAssignedCases: inactiveAssigned.length, staleOpenCases, reviewers: reviewers.length,
    activeReviewers: reviewers.filter((item) => item.active).length, reviewersOverCapacity: overCapacityReviewers,
    activeReviewersAtWarningThreshold: activeAtWarning, meanActiveUtilization: utilizations.length
      ? utilizations.reduce((sum, value) => sum + value, 0) / utilizations.length : null,
    activeUtilizationStandardDeviation: standardDeviation(utilizations) };
  const countRows = (map) => [...map].sort(([left], [right]) => left.localeCompare(right)).map(([key, total]) => ({ key, total }));
  return { format: FORMAT, version: VERSION, casebookId: book.id, casebookRevision: book.revision,
    settings: { priorityWeights: options.priorityWeights, utilizationWarningPercent: options.utilizationWarningPercent,
      includeCaseRows: options.includeCaseRows, includeReviewerNames: options.includeReviewerNames,
      includeStudentDetails: options.includeStudentDetails },
    summary, reviewers: reviewerRows, byPriority: countRows(priorityCounts), byStatus: countRows(statusCounts),
    unassignedCaseCount: unassigned.length, orphanedCaseCount: orphaned.length,
    inactiveAssignedCaseCount: inactiveAssigned.length,
    ...(options.includeCaseRows ? { cases: caseRows } : {}),
    note: 'Read-only workload comparison. It does not reassign cases or update reviewer records.',
  };
}

/** Export workload summary rows without including student details by default. */
export function casebookWorkloadToCsv(reportValue, section = 'reviewers') {
  const report = object(reportValue, 'workload report');
  if (report.format !== FORMAT || report.version !== VERSION || !report.summary || !Array.isArray(report.reviewers)) {
    throw new TypeError('invalid casebook workload report');
  }
  if (section === 'summary') return csv(Object.keys(report.summary), [Object.values(report.summary)]);
  if (section === 'reviewers') return csv(['reviewerId', 'reviewerName', 'active', 'capacityCases', 'openCases',
    'remainingCaseSlots', 'capacityPoints', 'workloadPoints', 'remainingPoints', 'caseUtilization', 'pointUtilization',
    'utilizationPercent', 'atWarningThreshold', 'overCapacity', 'staleCases', 'priorityCounts'], report.reviewers.map((item) => [
    item.id, item.name, item.active, item.capacityCases, item.openCases, item.remainingCaseSlots, item.capacityPoints,
    item.workloadPoints, item.remainingPoints, item.caseUtilization, item.pointUtilization, item.utilizationPercent,
    item.atWarningThreshold, item.overCapacity, item.staleCases, JSON.stringify(item.priorityCounts)]));
  if (section === 'priorities' || section === 'statuses') {
    const rows = section === 'priorities' ? report.byPriority : report.byStatus;
    return csv(['key', 'total'], rows.map((item) => [item.key, item.total]));
  }
  if (section === 'cases') {
    if (!Array.isArray(report.cases)) throw new TypeError('case rows were not enabled in this workload report');
    return csv(['caseId', 'studentId', 'studentName', 'status', 'priority', 'assigneeId', 'stale', 'workloadPoints', 'terminal'],
      report.cases.map((item) => [item.caseId, item.studentId, item.studentName, item.status, item.priority,
        item.assigneeId, item.stale, item.workloadPoints, item.terminal]));
  }
  throw new TypeError('section must be summary, reviewers, priorities, statuses or cases');
}
