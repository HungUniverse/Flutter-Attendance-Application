import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const FORMAT = 'attendance-snapshot-query';
const VERSION = 1;
const MAX_CELLS = 2_000_000;
const MAX_MATCHES = 250_000;
const MAX_PAGE_SIZE = 500;
const MAX_QUERY_NODES = 120;
const MAX_QUERY_DEPTH = 8;
const STATUSES = new Set(['present', 'absent', 'missing']);
const FIELDS = new Set(['studentId', 'studentName', 'studentEmail', 'sessionId', 'status']);
const TEXT_FIELDS = new Set(['studentId', 'studentName', 'studentEmail', 'sessionId']);
const OPERATORS = new Set(['eq', 'neq', 'in', 'notIn', 'contains', 'prefix', 'suffix', 'gt', 'gte', 'lt', 'lte', 'isMissing', 'isPresent']);
const COLUMNS = new Set(['studentId', 'studentName', 'studentEmail', 'sessionId', 'status']);

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function integer(value, field, minimum, maximum) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}

function text(value, field, maximum = 256) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > maximum) {
    throw new TypeError(`${field} must be non-empty text up to ${maximum} characters`);
  }
  return value.trim();
}

function ownKeysOnly(value, allowed, field) {
  const extra = Object.keys(value).filter((key) => !allowed.has(key));
  if (extra.length) throw new TypeError(`${field} contains unsupported field: ${extra[0]}`);
}

function normalizeValue(field, value, label) {
  if (field === 'status') {
    if (!STATUSES.has(value)) throw new TypeError(`${label} must be present, absent or missing`);
    return value;
  }
  return text(value, label, field === 'studentEmail' ? 320 : 256);
}

function normalizeQuery(queryValue) {
  const query = object(queryValue, 'query');
  ownKeysOnly(query, new Set(['where', 'columns', 'sort', 'page', 'pageSize', 'maxMatches', 'includeUnrecorded',
    'groupBy', 'minimumGroupSize', 'caseSensitive']), 'query');
  const columns = query.columns === undefined ? ['studentId', 'sessionId', 'status'] : query.columns;
  if (!Array.isArray(columns) || columns.length < 1 || columns.length > COLUMNS.size ||
      columns.some((column) => !COLUMNS.has(column)) || new Set(columns).size !== columns.length) {
    throw new TypeError('columns must contain 1 to 5 unique supported fields');
  }
  const sort = query.sort ?? [];
  if (!Array.isArray(sort) || sort.length > 3) throw new RangeError('sort must contain at most 3 fields');
  const normalizedSort = sort.map((item, index) => {
    object(item, `sort[${index}]`);
    ownKeysOnly(item, new Set(['field', 'direction']), `sort[${index}]`);
    if (!FIELDS.has(item.field)) throw new TypeError(`sort[${index}].field is unsupported`);
    const direction = item.direction ?? 'asc';
    if (!['asc', 'desc'].includes(direction)) throw new TypeError(`sort[${index}].direction must be asc or desc`);
    return { field: item.field, direction };
  });
  if (new Set(normalizedSort.map((item) => item.field)).size !== normalizedSort.length) throw new TypeError('sort fields must be unique');
  const groupBy = query.groupBy ?? [];
  if (!Array.isArray(groupBy) || groupBy.length > 3 || groupBy.some((field) => !FIELDS.has(field)) ||
      new Set(groupBy).size !== groupBy.length) throw new TypeError('groupBy must contain up to 3 unique supported fields');
  if (groupBy.length && query.page !== undefined && query.page !== 1) throw new TypeError('group summaries do not support page offsets');
  const includeUnrecorded = query.includeUnrecorded ?? true;
  const caseSensitive = query.caseSensitive ?? false;
  if (typeof includeUnrecorded !== 'boolean') throw new TypeError('includeUnrecorded must be a boolean');
  if (typeof caseSensitive !== 'boolean') throw new TypeError('caseSensitive must be a boolean');
  return {
    columns: [...columns], sort: normalizedSort,
    page: integer(query.page ?? 1, 'page', 1, 1_000_000),
    pageSize: integer(query.pageSize ?? 100, 'pageSize', 1, MAX_PAGE_SIZE),
    maxMatches: integer(query.maxMatches ?? MAX_MATCHES, 'maxMatches', 1, MAX_MATCHES),
    includeUnrecorded, caseSensitive, groupBy: [...groupBy],
    minimumGroupSize: integer(query.minimumGroupSize ?? 1, 'minimumGroupSize', 1, 100_000),
    where: query.where ?? null,
  };
}

function makePredicate(node, context, depth = 0) {
  if (depth > MAX_QUERY_DEPTH) throw new RangeError(`where nesting must not exceed ${MAX_QUERY_DEPTH}`);
  context.nodes++;
  if (context.nodes > MAX_QUERY_NODES) throw new RangeError(`where tree must not exceed ${MAX_QUERY_NODES} nodes`);
  object(node, 'where expression');
  if (Object.hasOwn(node, 'all') || Object.hasOwn(node, 'any')) {
    const key = Object.hasOwn(node, 'all') ? 'all' : 'any';
    ownKeysOnly(node, new Set([key]), 'where group');
    if (!Array.isArray(node[key]) || node[key].length < 1 || node[key].length > 50) {
      throw new RangeError(`${key} must contain 1 to 50 expressions`);
    }
    const children = node[key].map((child) => makePredicate(child, context, depth + 1));
    return key === 'all' ? (row) => children.every((predicate) => predicate(row)) :
      (row) => children.some((predicate) => predicate(row));
  }
  if (Object.hasOwn(node, 'not')) {
    ownKeysOnly(node, new Set(['not']), 'where group');
    const child = makePredicate(node.not, context, depth + 1);
    return (row) => !child(row);
  }
  ownKeysOnly(node, new Set(['field', 'op', 'value']), 'where predicate');
  const field = node.field;
  if (!FIELDS.has(field)) throw new TypeError(`unsupported query field: ${field}`);
  const op = node.op;
  if (!OPERATORS.has(op)) throw new TypeError(`unsupported query operator: ${op}`);
  if (op === 'isMissing' || op === 'isPresent') {
    if (Object.hasOwn(node, 'value')) throw new TypeError(`${op} does not accept a value`);
    return (row) => {
      const missing = field === 'status' ? row.status === 'missing' : row[field] === null;
      return op === 'isMissing' ? missing : !missing;
    };
  }
  if (!Object.hasOwn(node, 'value')) throw new TypeError(`${op} requires a value`);
  let expected;
  if (op === 'in' || op === 'notIn') {
    if (!Array.isArray(node.value) || node.value.length < 1 || node.value.length > 100) {
      throw new RangeError(`${op} value must contain 1 to 100 entries`);
    }
    expected = node.value.map((value, index) => normalizeValue(field, value, `where.value[${index}]`));
  } else {
    expected = normalizeValue(field, node.value, 'where.value');
  }
  if (!TEXT_FIELDS.has(field) && !['eq', 'neq', 'in', 'notIn'].includes(op)) {
    throw new TypeError(`${op} is only supported on text fields`);
  }
  if (TEXT_FIELDS.has(field) && ['contains', 'prefix', 'suffix'].includes(op) && expected.length > 120) {
    throw new RangeError('text matching values must not exceed 120 characters');
  }
  const normalize = (value) => context.caseSensitive ? value : value.toLocaleLowerCase('en-US');
  const equal = (left, right) => left !== null && right !== null && normalize(String(left)) === normalize(String(right));
  return (row) => {
    const actual = row[field];
    if (op === 'eq') return equal(actual, expected);
    if (op === 'neq') return actual !== null && !equal(actual, expected);
    if (op === 'in') return expected.some((value) => equal(actual, value));
    if (op === 'notIn') return actual !== null && !expected.some((value) => equal(actual, value));
    if (actual === null) return false;
    const left = normalize(actual);
    const right = normalize(expected);
    if (op === 'contains') return left.includes(right);
    if (op === 'prefix') return left.startsWith(right);
    if (op === 'suffix') return left.endsWith(right);
    const compared = left.localeCompare(right, 'en-US', { numeric: true, sensitivity: context.caseSensitive ? 'variant' : 'base' });
    if (op === 'gt') return compared > 0;
    if (op === 'gte') return compared >= 0;
    if (op === 'lt') return compared < 0;
    return compared <= 0;
  };
}

function compareValues(left, right, caseSensitive) {
  if (left === right) return 0;
  if (left === null) return -1;
  if (right === null) return 1;
  return String(left).localeCompare(String(right), 'en-US', {
    numeric: true, sensitivity: caseSensitive ? 'variant' : 'base',
  });
}

function rowComparator(sort, caseSensitive) {
  return (left, right) => {
    for (const item of sort) {
      const result = compareValues(left[item.field], right[item.field], caseSensitive);
      if (result) return item.direction === 'desc' ? -result : result;
    }
    return left.studentId.localeCompare(right.studentId, 'en-US', { numeric: true }) ||
      left.sessionId.localeCompare(right.sessionId, 'en-US', { numeric: true });
  };
}

function makeRows(snapshot) {
  const cells = snapshot.roster.length * snapshot.sessionIds.length;
  if (cells > MAX_CELLS) throw new RangeError(`snapshot has ${cells} cells; query limit is ${MAX_CELLS}`);
  const recordMap = new Map(snapshot.records.map((record) => [JSON.stringify([record.studentId, record.sessionId]), record.status]));
  const rows = [];
  for (const student of snapshot.roster) for (const sessionId of snapshot.sessionIds) {
    rows.push({ studentId: student.id, studentName: student.name, studentEmail: student.email,
      sessionId, status: recordMap.get(JSON.stringify([student.id, sessionId])) ?? 'missing' });
  }
  return rows;
}

function groupRows(rows, fields, minimumGroupSize) {
  const groups = new Map();
  for (const row of rows) {
    const key = JSON.stringify(fields.map((field) => row[field]));
    if (!groups.has(key)) groups.set(key, { dimensions: Object.fromEntries(fields.map((field) => [field, row[field]])),
      students: new Set(), sessions: new Set(), present: 0, absent: 0, missing: 0, cells: 0 });
    const group = groups.get(key);
    group.students.add(row.studentId);
    group.sessions.add(row.sessionId);
    group.cells++;
    if (row.status === 'present') group.present++;
    else if (row.status === 'absent') group.absent++;
    else group.missing++;
  }
  return [...groups.values()].map((group) => {
    const size = group.students.size;
    const suppressed = size < minimumGroupSize;
    const recorded = group.present + group.absent;
    return {
      ...group.dimensions,
      studentCount: suppressed ? null : size,
      sessionCount: suppressed ? null : group.sessions.size,
      cellCount: suppressed ? null : group.cells,
      present: suppressed ? null : group.present,
      absent: suppressed ? null : group.absent,
      missing: suppressed ? null : group.missing,
      attendanceRate: suppressed || recorded === 0 ? null : group.present / recorded,
      coverage: suppressed || group.cells === 0 ? null : recorded / group.cells,
      suppressed,
    };
  });
}

function selectColumns(row, columns) {
  return Object.fromEntries(columns.map((column) => [column, row[column]]));
}

/** Run a bounded, declarative query across a validated snapshot. No code is evaluated. */
export function queryAttendanceSnapshot(snapshotValue, queryValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const query = normalizeQuery(queryValue);
  const context = { nodes: 0, caseSensitive: query.caseSensitive };
  const predicate = query.where === null ? () => true : makePredicate(query.where, context);
  const allRows = makeRows(snapshot);
  const matched = allRows.filter((row) => (query.includeUnrecorded || row.status !== 'missing') && predicate(row));
  if (matched.length > query.maxMatches) throw new RangeError(`query matched ${matched.length} rows; maxMatches is ${query.maxMatches}`);
  matched.sort(rowComparator(query.sort, query.caseSensitive));
  const grouped = query.groupBy.length > 0;
  const records = grouped ? groupRows(matched, query.groupBy, query.minimumGroupSize) : null;
  const total = grouped ? records.length : matched.length;
  const start = (query.page - 1) * query.pageSize;
  const selected = grouped ? records : matched.slice(start, start + query.pageSize).map((row) => selectColumns(row, query.columns));
  const recorded = matched.filter((row) => row.status !== 'missing').length;
  const present = matched.filter((row) => row.status === 'present').length;
  const absent = matched.filter((row) => row.status === 'absent').length;
  return {
    format: FORMAT,
    version: VERSION,
    query: { columns: query.columns, sort: query.sort, where: query.where === null ? null : structuredClone(query.where), includeUnrecorded: query.includeUnrecorded,
      groupBy: query.groupBy, minimumGroupSize: query.minimumGroupSize, caseSensitive: query.caseSensitive },
    summary: { scannedCells: allRows.length, matchedRows: matched.length, recordedRows: recorded,
      present, absent, missing: matched.length - recorded, attendanceRate: recorded ? present / recorded : null,
      coverage: matched.length ? recorded / matched.length : null, groups: grouped ? records.length : null,
      page: grouped ? null : query.page, pageSize: grouped ? null : query.pageSize,
      totalPages: grouped ? null : Math.ceil(matched.length / query.pageSize), hasMore: grouped ? false : start + selected.length < matched.length },
    rows: grouped ? null : selected,
    groups: grouped ? selected : null,
    note: 'Query results are an in-memory view. Student names and emails appear only when requested as columns or group dimensions.',
  };
}

function comparableRows(snapshotValue, queryValue) {
  const query = normalizeQuery({ ...queryValue, page: 1, pageSize: MAX_PAGE_SIZE, groupBy: [] });
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const context = { nodes: 0, caseSensitive: query.caseSensitive };
  const predicate = query.where === null ? () => true : makePredicate(query.where, context);
  const rows = makeRows(snapshot).filter((row) => (query.includeUnrecorded || row.status !== 'missing') && predicate(row));
  if (rows.length > query.maxMatches) throw new RangeError(`query matched ${rows.length} rows; maxMatches is ${query.maxMatches}`);
  rows.sort(rowComparator(query.sort, query.caseSensitive));
  return rows;
}

/** Compare matching student/session cells between two snapshots without persisting either result. */
export function compareAttendanceQueryResults(beforeValue, afterValue, queryValue = {}) {
  const before = comparableRows(beforeValue, queryValue);
  const after = comparableRows(afterValue, queryValue);
  const key = (row) => JSON.stringify([row.studentId, row.sessionId]);
  const beforeMap = new Map(before.map((row) => [key(row), row]));
  const afterMap = new Map(after.map((row) => [key(row), row]));
  const added = [];
  const removed = [];
  const changed = [];
  for (const [identity, row] of afterMap) {
    if (!beforeMap.has(identity)) added.push({ before: null, after: row });
    else {
      const original = beforeMap.get(identity);
      const fields = ['studentId', 'studentName', 'studentEmail', 'sessionId', 'status'];
      const differences = fields.filter((field) => original[field] !== row[field]);
      if (differences.length) changed.push({ fields: differences, before: original, after: row });
    }
  }
  for (const [identity, row] of beforeMap) if (!afterMap.has(identity)) removed.push({ before: row, after: null });
  return { format: 'attendance-snapshot-query-diff', version: VERSION,
    columns: normalizeQuery(queryValue).columns,
    summary: { beforeMatched: before.length, afterMatched: after.length, added: added.length, removed: removed.length, changed: changed.length,
      unchanged: Math.max(0, Math.min(before.length, after.length) - changed.length - Math.min(added.length, removed.length)) },
    added, removed, changed };
}

function csvCell(value) {
  let cell = value === null || value === undefined ? '' : String(value);
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

function csv(headers, rows) {
  return [headers, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}

/** Export one query section; private columns are present only if requested in the query. */
export function attendanceQueryToCsv(resultValue, section = 'rows') {
  const result = object(resultValue, 'query result');
  if (result.format !== FORMAT || result.version !== VERSION) throw new TypeError('invalid attendance query result');
  if (section === 'rows') {
    if (!Array.isArray(result.rows)) throw new TypeError('row results are unavailable for grouped queries');
    return csv(result.query.columns, result.rows.map((row) => result.query.columns.map((column) => row[column])));
  }
  if (section === 'groups') {
    if (!Array.isArray(result.groups)) throw new TypeError('group results are unavailable for row queries');
    const headers = [...result.query.groupBy, 'studentCount', 'sessionCount', 'cellCount', 'present', 'absent', 'missing',
      'attendanceRate', 'coverage', 'suppressed'];
    return csv(headers, result.groups.map((row) => headers.map((header) => row[header])));
  }
  throw new TypeError('section must be rows or groups');
}

/** Export a query diff without exposing fields that are not requested by the caller. */
export function attendanceQueryDiffToCsv(diffValue, section = 'changed') {
  const diff = object(diffValue, 'query diff');
  if (diff.format !== 'attendance-snapshot-query-diff' || diff.version !== VERSION) throw new TypeError('invalid attendance query diff');
  if (!['added', 'removed', 'changed'].includes(section)) throw new TypeError('section must be added, removed or changed');
  if (section === 'changed') return csv(['fields', 'studentId', 'sessionId', 'beforeStatus', 'afterStatus'],
    diff.changed.map((item) => [item.fields.join('|'), item.before.studentId, item.before.sessionId, item.before.status, item.after.status]));
  const columns = Array.isArray(diff.columns) && diff.columns.every((column) => COLUMNS.has(column))
    ? diff.columns : ['studentId', 'sessionId', 'status'];
  return csv(columns, diff[section].map((item) => {
    const row = item[section === 'added' ? 'after' : 'before'];
    return columns.map((column) => row[column]);
  }));
}
