import { createHash } from 'node:crypto';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { parseSnapshotContract, validateSnapshotContract } from './snapshot-contract.mjs';

const PLAN_FORMAT = 'attendance-snapshot-release-plan';
const RECEIPT_FORMAT = 'attendance-snapshot-release-receipt';
const VERSION = 1;

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 256) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function timestamp(value, field) {
  const source = value ?? new Date().toISOString();
  if (typeof source !== 'string' || !Number.isFinite(Date.parse(source))) throw new TypeError(`${field} must be a valid timestamp`);
  return new Date(source).toISOString();
}

function stable(value) {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}

function digest(value) {
  return createHash('sha256').update(stable(value), 'utf8').digest('hex');
}

function uniqueIds(value, field) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 500) throw new RangeError(`${field} must be an array with at most 500 IDs`);
  const result = value.map((item, index) => text(item, `${field}[${index}]`, 80));
  if (new Set(result).size !== result.length) throw new TypeError(`${field} must not contain duplicate IDs`);
  return result.sort((left, right) => left.localeCompare(right));
}

/** Prepare a compact approval plan from a snapshot and caller-defined contract. */
export function planSnapshotRelease(snapshotValue, contractValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const contract = parseSnapshotContract(contractValue);
  const options = object(optionsValue, 'release plan options');
  const report = validateSnapshotContract(snapshot, contract);
  const createdAt = timestamp(options.createdAt, 'createdAt');
  const requestedBy = options.requestedBy === undefined ? null : text(options.requestedBy, 'requestedBy', 120);
  const failedChecks = report.results.filter((item) => !item.passed);
  const warningCheckIds = failedChecks.filter((item) => item.severity === 'warning').map((item) => item.checkId).sort();
  const errorCheckIds = failedChecks.filter((item) => item.severity === 'error').map((item) => item.checkId).sort();
  const contractFingerprint = digest(contract);
  const planCore = { format: PLAN_FORMAT, version: VERSION, contractId: contract.id,
    contractRevision: contract.revision, contractFingerprint, snapshotFingerprint: report.snapshotFingerprint,
    createdAt, requestedBy, status: report.accepted ? 'needs_approval' : 'blocked',
    summary: report.summary, warningCheckIds, errorCheckIds };
  return { ...planCore, planId: `release-${digest(planCore).slice(0, 24)}`,
    note: 'The plan is local. It does not modify the snapshot or publish data.' };
}

function normalizePlan(value) {
  const plan = object(value, 'release plan');
  if (plan.format !== PLAN_FORMAT || plan.version !== VERSION || !['needs_approval', 'blocked', 'rejected'].includes(plan.status)) {
    throw new TypeError('invalid snapshot release plan');
  }
  if (!Array.isArray(plan.warningCheckIds) || !Array.isArray(plan.errorCheckIds) || !plan.summary) throw new TypeError('release plan is missing checks or summary');
  return plan;
}

/** Approve or reject a plan; approval requires explicit acknowledgement of warnings. */
export function decideSnapshotRelease(planValue, approvalValue) {
  const plan = normalizePlan(planValue);
  const approval = object(approvalValue, 'release approval');
  if (plan.status !== 'needs_approval') throw new TypeError('only an accepted plan can be decided');
  const decision = approval.decision ?? 'approve';
  if (!['approve', 'reject'].includes(decision)) throw new TypeError('decision must be approve or reject');
  const actor = text(approval.actor, 'actor', 120);
  const reason = text(approval.reason, 'reason', 1_000);
  const at = timestamp(approval.at, 'at');
  const acknowledgedWarnings = uniqueIds(approval.acknowledgedWarnings, 'acknowledgedWarnings');
  const requiredWarnings = [...plan.warningCheckIds].sort();
  for (const id of acknowledgedWarnings) if (!requiredWarnings.includes(id)) throw new TypeError(`unknown warning acknowledgement: ${id}`);
  if (decision === 'approve') {
    const missing = requiredWarnings.filter((id) => !acknowledgedWarnings.includes(id));
    if (missing.length) throw new TypeError(`warning checks require acknowledgement: ${missing.join(', ')}`);
  }
  const updatedPlan = { ...plan, status: decision === 'approve' ? 'approved' : 'rejected',
    decision: { decision, actor, reason, at, acknowledgedWarnings } };
  if (decision === 'reject') return updatedPlan;
  const { note, ...planFields } = updatedPlan;
  const receiptCore = { format: RECEIPT_FORMAT, version: VERSION, plan: planFields,
    releasedSnapshotFingerprint: plan.snapshotFingerprint,
    releasedContractFingerprint: plan.contractFingerprint };
  return { ...receiptCore, receiptDigest: digest(receiptCore),
    note: 'The digest detects accidental receipt edits; it is not a digital signature.' };
}

/** Recheck a receipt against the supplied snapshot and contract. */
export function verifySnapshotReleaseReceipt(receiptValue, snapshotValue, contractValue) {
  let receipt = receiptValue;
  if (typeof receipt === 'string') {
    try { receipt = JSON.parse(receipt); }
    catch { throw new TypeError('release receipt must contain valid JSON'); }
  }
  object(receipt, 'release receipt');
  if (receipt.format !== RECEIPT_FORMAT || receipt.version !== VERSION || !receipt.plan || !receipt.receiptDigest) {
    throw new TypeError('invalid snapshot release receipt');
  }
  const { receiptDigest, note, ...receiptCore } = receipt;
  const digestMatches = digest(receiptCore) === receiptDigest;
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const contract = parseSnapshotContract(contractValue);
  const report = validateSnapshotContract(snapshot, contract);
  const snapshotMatches = report.snapshotFingerprint === receipt.releasedSnapshotFingerprint;
  const contractMatches = digest(contract) === receipt.releasedContractFingerprint && contract.id === receipt.plan.contractId &&
    contract.revision === receipt.plan.contractRevision;
  const contractAccepts = report.accepted;
  return { format: 'attendance-snapshot-release-verification', version: VERSION,
    valid: digestMatches && snapshotMatches && contractMatches && contractAccepts,
    checks: { digestMatches, snapshotMatches, contractMatches, contractAccepts },
    receiptDigest, releasedSnapshotFingerprint: receipt.releasedSnapshotFingerprint,
    contractId: contract.id, contractRevision: contract.revision };
}

/** Export compact approval evidence without snapshot records or identity fields. */
export function snapshotReleaseToCsv(value) {
  const receipt = object(value, 'release receipt');
  if (receipt.format !== RECEIPT_FORMAT || receipt.version !== VERSION || !receipt.plan || !receipt.receiptDigest) {
    throw new TypeError('invalid snapshot release receipt');
  }
  const plan = receipt.plan;
  const row = [plan.planId, plan.status, plan.contractId, plan.contractRevision, plan.contractFingerprint,
    plan.snapshotFingerprint, plan.createdAt, plan.requestedBy, plan.summary.students, plan.summary.sessions,
    plan.summary.records, plan.warningCheckIds.join(';'), plan.decision?.actor, plan.decision?.reason,
    plan.decision?.at, plan.decision?.acknowledgedWarnings.join(';'), receipt.receiptDigest];
  const cell = (input) => {
    let source = input === undefined || input === null ? '' : String(input);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  return [['planId', 'status', 'contractId', 'contractRevision', 'contractFingerprint', 'snapshotFingerprint',
    'createdAt', 'requestedBy', 'students', 'sessions', 'records', 'warningChecks', 'approver', 'reason',
    'approvedAt', 'acknowledgedWarnings', 'receiptDigest'], row].map((items) => items.map(cell).join(',')).join('\r\n') + '\r\n';
}

function readApprovedReceipt(value, field) {
  let receipt = value;
  if (typeof receipt === 'string') {
    try { receipt = JSON.parse(receipt); }
    catch { throw new TypeError(`${field} must contain valid JSON`); }
  }
  object(receipt, field);
  if (receipt.format !== RECEIPT_FORMAT || receipt.version !== VERSION || !receipt.plan ||
      receipt.plan.status !== 'approved' || !receipt.receiptDigest) throw new TypeError(`${field} is not an approved snapshot release receipt`);
  const { receiptDigest, note, ...core } = receipt;
  if (digest(core) !== receiptDigest) throw new TypeError(`${field} digest does not match its contents`);
  return receipt;
}

/** Compare two integrity-checked release receipts without reading snapshot data. */
export function compareSnapshotReleaseReceipts(beforeValue, afterValue) {
  const before = readApprovedReceipt(beforeValue, 'previous receipt');
  const after = readApprovedReceipt(afterValue, 'current receipt');
  const oldPlan = before.plan;
  const newPlan = after.plan;
  const snapshotChanged = before.releasedSnapshotFingerprint !== after.releasedSnapshotFingerprint;
  const contractChanged = before.releasedContractFingerprint !== after.releasedContractFingerprint ||
    oldPlan.contractId !== newPlan.contractId || oldPlan.contractRevision !== newPlan.contractRevision;
  const approvalChanged = oldPlan.decision.actor !== newPlan.decision.actor || oldPlan.decision.reason !== newPlan.decision.reason;
  const warningsChanged = JSON.stringify(oldPlan.warningCheckIds) !== JSON.stringify(newPlan.warningCheckIds) ||
    JSON.stringify(oldPlan.decision.acknowledgedWarnings) !== JSON.stringify(newPlan.decision.acknowledgedWarnings);
  const outcome = snapshotChanged ? 'snapshot_changed' : contractChanged ? 'contract_changed'
    : approvalChanged ? 'approval_changed' : warningsChanged ? 'warning_acknowledgements_changed' : 'unchanged';
  const delta = (key) => newPlan.summary[key] - oldPlan.summary[key];
  return { format: 'attendance-snapshot-release-diff', version: VERSION,
    previous: { planId: oldPlan.planId, approvedAt: oldPlan.decision.at, actor: oldPlan.decision.actor,
      snapshotFingerprint: before.releasedSnapshotFingerprint, contractId: oldPlan.contractId, contractRevision: oldPlan.contractRevision },
    current: { planId: newPlan.planId, approvedAt: newPlan.decision.at, actor: newPlan.decision.actor,
      snapshotFingerprint: after.releasedSnapshotFingerprint, contractId: newPlan.contractId, contractRevision: newPlan.contractRevision },
    summary: { outcome, snapshotChanged, contractChanged, approvalChanged, warningsChanged,
      studentsDelta: delta('students'), sessionsDelta: delta('sessions'), recordsDelta: delta('records'),
      passedChecksDelta: delta('passed'), failedChecksDelta: delta('failed') },
    note: 'Receipt comparison uses compact approval evidence only; it does not verify or expose snapshot records.' };
}

/** Export release-receipt differences as a compact CSV. */
export function snapshotReleaseDiffToCsv(diffValue) {
  const diff = object(diffValue, 'snapshot release diff');
  if (diff.format !== 'attendance-snapshot-release-diff' || diff.version !== VERSION || !diff.summary) {
    throw new TypeError('invalid snapshot release diff');
  }
  const cell = (value) => {
    let source = value === undefined || value === null ? '' : String(value);
    if (/^[\t\r\n ]*[=+\-@]/.test(source)) source = `'${source}`;
    return `"${source.replaceAll('"', '""')}"`;
  };
  const rows = [['previousPlanId', 'previousApprovedAt', 'previousActor', 'previousSnapshotFingerprint', 'previousContractId', 'previousContractRevision',
    'currentPlanId', 'currentApprovedAt', 'currentActor', 'currentSnapshotFingerprint', 'currentContractId', 'currentContractRevision',
    ...Object.keys(diff.summary)], [diff.previous.planId, diff.previous.approvedAt, diff.previous.actor, diff.previous.snapshotFingerprint,
    diff.previous.contractId, diff.previous.contractRevision, diff.current.planId, diff.current.approvedAt, diff.current.actor,
    diff.current.snapshotFingerprint, diff.current.contractId, diff.current.contractRevision, ...Object.values(diff.summary)]];
  return rows.map((row) => row.map(cell).join(',')).join('\r\n') + '\r\n';
}
