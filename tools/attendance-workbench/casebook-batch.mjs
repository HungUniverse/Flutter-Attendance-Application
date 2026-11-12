import { parseCasebook, updateCasebook } from './casebook.mjs';

const MAX_BATCH_OPERATIONS = 2_000;

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function text(value, field, maximum = 160) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  return value.trim();
}

function normalizeBatch(value) {
  const batch = object(value, 'casebook batch');
  if (!Number.isSafeInteger(batch.expectedBookRevision) || batch.expectedBookRevision < 1) {
    throw new RangeError('expectedBookRevision must be a positive integer');
  }
  if (!Array.isArray(batch.operations) || batch.operations.length < 1 || batch.operations.length > MAX_BATCH_OPERATIONS) {
    throw new RangeError(`operations must contain 1 to ${MAX_BATCH_OPERATIONS} entries`);
  }
  const seen = new Set();
  const operations = batch.operations.map((entry, index) => {
    object(entry, `operations[${index}]`);
    const caseId = text(entry.caseId, `operations[${index}].caseId`, 160);
    if (seen.has(caseId)) throw new TypeError(`case ${caseId} occurs more than once in this batch`);
    seen.add(caseId);
    if (!Number.isSafeInteger(entry.expectedRevision) || entry.expectedRevision < 1) {
      throw new RangeError(`operations[${index}].expectedRevision must be a positive integer`);
    }
    const action = object(entry.action, `operations[${index}].action`);
    return { caseId, expectedRevision: entry.expectedRevision, action };
  });
  return { expectedBookRevision: batch.expectedBookRevision, operations,
    actor: batch.actor === undefined ? undefined : text(batch.actor, 'actor', 80),
    at: batch.at === undefined ? undefined : text(batch.at, 'at', 64) };
}

/** Apply distinct, revision-checked case updates as one all-or-none operation. */
export function applyCasebookBatch(bookValue, batchValue) {
  let book = parseCasebook(bookValue);
  const batch = normalizeBatch(batchValue);
  if (book.revision !== batch.expectedBookRevision) {
    throw new Error(`stale casebook revision: expected ${batch.expectedBookRevision}, actual ${book.revision}`);
  }
  const cases = new Map(book.cases.map((item) => [item.caseId, item]));
  for (const operation of batch.operations) {
    const item = cases.get(operation.caseId);
    if (!item) throw new TypeError(`unknown case ID: ${operation.caseId}`);
    if (item.revision !== operation.expectedRevision) {
      throw new Error(`stale case revision for ${operation.caseId}: expected ${operation.expectedRevision}, actual ${item.revision}`);
    }
  }
  for (const operation of batch.operations) {
    book = updateCasebook(book, operation.caseId, operation.action, {
      expectedRevision: operation.expectedRevision,
      actor: batch.actor,
      at: batch.at,
    });
  }
  return book;
}
