import { createHash } from 'node:crypto';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { buildReportStudio, renderReportStudioHtml, reportStudioToCsv } from './report-studio.mjs';

const FORMAT = 'attendance-closeout-package';
const VERSION = 1;
const MAX_PACKAGE_BYTES = 100_000_000;

function hash(content) {
  return createHash('sha256').update(content, 'utf8').digest('hex');
}

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function normalizedFiles(value) {
  if (!Array.isArray(value) || value.length < 2 || value.length > 16) throw new RangeError('package files must contain between 2 and 16 entries');
  const names = new Set();
  const files = value.map((file, index) => {
    object(file, `files[${index}]`);
    if (typeof file.name !== 'string' || !/^[a-z0-9][a-z0-9._-]{0,100}$/i.test(file.name)) throw new TypeError(`invalid file name at index ${index}`);
    if (names.has(file.name)) throw new TypeError(`duplicate package file: ${file.name}`);
    names.add(file.name);
    if (typeof file.mimeType !== 'string' || !file.mimeType.trim()) throw new TypeError(`invalid MIME type at index ${index}`);
    if (typeof file.content !== 'string') throw new TypeError(`file content at index ${index} must be a string`);
    const bytes = Buffer.byteLength(file.content, 'utf8');
    if (file.bytes !== undefined && file.bytes !== bytes) throw new TypeError(`incorrect byte count for ${file.name}`);
    const sha256 = hash(file.content);
    if (file.sha256 !== undefined && file.sha256 !== sha256) throw new TypeError(`checksum mismatch for ${file.name}`);
    return { name: file.name, mimeType: file.mimeType.trim(), bytes, sha256, content: file.content };
  });
  const totalBytes = files.reduce((sum, file) => sum + file.bytes, 0);
  if (totalBytes > MAX_PACKAGE_BYTES) throw new RangeError(`closeout package must not exceed ${MAX_PACKAGE_BYTES} bytes`);
  return files;
}

function validatePackage(value) {
  object(value, 'closeout package');
  if (value.format !== FORMAT || value.version !== VERSION) throw new TypeError('unsupported closeout package format or version');
  const files = normalizedFiles(value.files);
  object(value.manifest, 'manifest');
  if (value.manifest.format !== FORMAT || value.manifest.version !== VERSION || !Array.isArray(value.manifest.files)) {
    throw new TypeError('invalid closeout package manifest');
  }
  if (typeof value.manifest.title !== 'string' || !value.manifest.title.trim() || value.manifest.title.length > 160 ||
      typeof value.manifest.generatedAt !== 'string' || !Number.isFinite(Date.parse(value.manifest.generatedAt))) {
    throw new TypeError('manifest title or generatedAt is invalid');
  }
  if (typeof value.manifest.containsFullSnapshot !== 'boolean' || typeof value.manifest.containsStudentNames !== 'boolean' ||
      typeof value.manifest.containsStudentIds !== 'boolean' || typeof value.manifest.containsSessionIds !== 'boolean') {
    throw new TypeError('manifest privacy flags must be boolean values');
  }
  object(value.manifest.dimensions, 'manifest dimensions');
  for (const field of ['students', 'sessions', 'expected', 'recorded', 'missing']) {
    if (!Number.isSafeInteger(value.manifest.dimensions[field]) || value.manifest.dimensions[field] < 0) {
      throw new TypeError(`manifest dimensions.${field} must be a non-negative safe integer`);
    }
  }
  const { students, sessions, expected, recorded, missing } = value.manifest.dimensions;
  if (!Number.isSafeInteger(students * sessions) || expected !== students * sessions || recorded + missing !== expected) {
    throw new TypeError('manifest attendance dimensions are inconsistent');
  }
  const actual = files.filter((file) => file.name !== 'manifest.json').map(({ name, mimeType, bytes, sha256 }) => ({ name, mimeType, bytes, sha256 }));
  if (JSON.stringify(actual) !== JSON.stringify(value.manifest.files)) throw new TypeError('manifest file checksums do not match package contents');
  const manifestFile = files.find((file) => file.name === 'manifest.json');
  if (!manifestFile || JSON.stringify(JSON.parse(manifestFile.content)) !== JSON.stringify(value.manifest)) {
    throw new TypeError('manifest.json does not match the package manifest');
  }
  const reportFile = files.find((file) => file.name === 'report.json');
  if (!reportFile) throw new TypeError('closeout package is missing report.json');
  let report;
  try { report = JSON.parse(reportFile.content); }
  catch { throw new TypeError('report.json must contain valid JSON'); }
  if (report.version !== 1 || !report.summary || !report.filters || report.title !== value.manifest.title ||
      report.generatedAt !== value.manifest.generatedAt) {
    throw new TypeError('report.json metadata does not match the package manifest');
  }
  const reportDimensions = { students: report.summary.students, sessions: report.summary.sessions,
    expected: report.summary.expected, recorded: report.summary.recorded, missing: report.summary.missing };
  if (JSON.stringify(reportDimensions) !== JSON.stringify(value.manifest.dimensions)) {
    throw new TypeError('report.json dimensions do not match the package manifest');
  }
  if (report.filters.includeStudentNames !== value.manifest.containsStudentNames ||
      report.filters.includeStudentIds !== value.manifest.containsStudentIds ||
      report.filters.includeSessionIds !== value.manifest.containsSessionIds) {
    throw new TypeError('report identity settings do not match the package manifest');
  }
  const snapshotFile = files.find((file) => file.name === 'attendance-snapshot.json');
  if (Boolean(snapshotFile) !== value.manifest.containsFullSnapshot) {
    throw new TypeError('snapshot file does not match the manifest privacy flag');
  }
  if (snapshotFile) parseAttendanceSnapshot(snapshotFile.content);
  return { format: FORMAT, version: VERSION, manifest: structuredClone(value.manifest), files };
}

/** Assemble a portable local closeout package entirely in memory. */
export function buildCloseoutPackage(snapshotValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  object(optionsValue, 'closeout options');
  const includeSnapshot = optionsValue.includeSnapshot === undefined ? false : optionsValue.includeSnapshot;
  if (typeof includeSnapshot !== 'boolean') throw new TypeError('includeSnapshot must be a boolean');
  const reportOptions = optionsValue.reportOptions === undefined ? {} : optionsValue.reportOptions;
  object(reportOptions, 'reportOptions');
  const report = buildReportStudio(snapshot, reportOptions);
  const contents = [
    { name: 'attendance-report.html', mimeType: 'text/html; charset=utf-8', content: renderReportStudioHtml(report) },
    { name: 'report.json', mimeType: 'application/json; charset=utf-8', content: `${JSON.stringify(report, null, 2)}\n` },
    { name: 'summary.csv', mimeType: 'text/csv; charset=utf-8', content: reportStudioToCsv(report, 'summary') },
    { name: 'students.csv', mimeType: 'text/csv; charset=utf-8', content: reportStudioToCsv(report, 'students') },
    { name: 'sessions.csv', mimeType: 'text/csv; charset=utf-8', content: reportStudioToCsv(report, 'sessions') },
  ];
  if (report.matrix) contents.push({ name: 'attendance-matrix.csv', mimeType: 'text/csv; charset=utf-8', content: reportStudioToCsv(report, 'matrix') });
  if (report.audit) contents.push({ name: 'data-quality.csv', mimeType: 'text/csv; charset=utf-8', content: reportStudioToCsv(report, 'audit') });
  if (report.policy) contents.push({ name: 'policy-review.csv', mimeType: 'text/csv; charset=utf-8', content: reportStudioToCsv(report, 'policy') });
  if (includeSnapshot) contents.push({ name: 'attendance-snapshot.json', mimeType: 'application/json; charset=utf-8',
    content: `${serializeAttendanceSnapshot(snapshot)}\n` });
  const files = contents.map((file) => ({ ...file, bytes: Buffer.byteLength(file.content, 'utf8'), sha256: hash(file.content) }));
  const manifest = {
    format: FORMAT,
    version: VERSION,
    generatedAt: report.generatedAt,
    title: report.title,
    dimensions: { students: report.summary.students, sessions: report.summary.sessions,
      expected: report.summary.expected, recorded: report.summary.recorded, missing: report.summary.missing },
    containsFullSnapshot: includeSnapshot,
    containsStudentNames: report.filters.includeStudentNames,
    containsStudentIds: report.filters.includeStudentIds,
    containsSessionIds: report.filters.includeSessionIds,
    files: files.map(({ name, mimeType, bytes, sha256 }) => ({ name, mimeType, bytes, sha256 })),
  };
  files.push({ name: 'manifest.json', mimeType: 'application/json; charset=utf-8',
    content: `${JSON.stringify(manifest, null, 2)}\n`, bytes: Buffer.byteLength(`${JSON.stringify(manifest, null, 2)}\n`, 'utf8') });
  files.at(-1).sha256 = hash(files.at(-1).content);
  return validatePackage({ format: FORMAT, version: VERSION, manifest, files });
}

/** Parse a serialized closeout package and verify every file against the manifest. */
export function parseCloseoutPackage(value) {
  let parsed = value;
  if (typeof value === 'string') {
    try { parsed = JSON.parse(value); }
    catch { throw new TypeError('closeout package must contain valid JSON'); }
  }
  return validatePackage(parsed);
}

/** Serialize a package as JSON for callers to save or extract locally. */
export function serializeCloseoutPackage(value) {
  return `${JSON.stringify(parseCloseoutPackage(value), null, 2)}\n`;
}

/** Verify file hashes and return the content for a named package file. */
export function readCloseoutFile(value, nameValue) {
  const packageValue = parseCloseoutPackage(value);
  if (typeof nameValue !== 'string' || !nameValue.trim()) throw new TypeError('file name must be non-empty');
  const file = packageValue.files.find((item) => item.name === nameValue.trim());
  if (!file) throw new TypeError(`unknown package file: ${nameValue}`);
  return file.content;
}

/** Inspect integrity, privacy flags and file metadata without returning any
 * report contents. parseCloseoutPackage verifies every SHA-256 digest first. */
export function inspectCloseoutPackage(value) {
  const packageValue = parseCloseoutPackage(value);
  const { manifest } = packageValue;
  const files = packageValue.files.map(({ name, mimeType, bytes, sha256 }) => ({ name, mimeType, bytes, sha256 }));
  return {
    format: 'attendance-closeout-inspection',
    version: 1,
    integrity: 'valid',
    title: manifest.title,
    generatedAt: manifest.generatedAt,
    privacy: {
      containsFullSnapshot: manifest.containsFullSnapshot,
      containsStudentNames: manifest.containsStudentNames,
      containsStudentIds: manifest.containsStudentIds,
      containsSessionIds: manifest.containsSessionIds,
    },
    dimensions: structuredClone(manifest.dimensions),
    fileCount: files.length,
    totalBytes: files.reduce((sum, file) => sum + file.bytes, 0),
    files,
  };
}

/** Compare two verified packages by manifest metadata and file hashes. This
 * reports change categories only; it never includes file payloads. */
export function compareCloseoutPackages(beforeValue, afterValue) {
  const before = parseCloseoutPackage(beforeValue);
  const after = parseCloseoutPackage(afterValue);
  const beforeFiles = new Map(before.files.map((file) => [file.name, file]));
  const afterFiles = new Map(after.files.map((file) => [file.name, file]));
  const fileChanges = [];
  for (const name of [...new Set([...beforeFiles.keys(), ...afterFiles.keys()])].sort()) {
    const left = beforeFiles.get(name);
    const right = afterFiles.get(name);
    let status;
    if (!left) status = 'added';
    else if (!right) status = 'removed';
    else if (left.sha256 !== right.sha256 || left.mimeType !== right.mimeType || left.bytes !== right.bytes) status = 'changed';
    else status = 'unchanged';
    fileChanges.push({ name, status, beforeBytes: left?.bytes ?? null, afterBytes: right?.bytes ?? null,
      beforeSha256: left?.sha256 ?? null, afterSha256: right?.sha256 ?? null });
  }
  const dimensionDelta = Object.fromEntries(['students', 'sessions', 'expected', 'recorded', 'missing'].map((key) => [
    key, after.manifest.dimensions[key] - before.manifest.dimensions[key],
  ]));
  return {
    format: 'attendance-closeout-comparison',
    version: 1,
    before: { title: before.manifest.title, generatedAt: before.manifest.generatedAt,
      containsFullSnapshot: before.manifest.containsFullSnapshot },
    after: { title: after.manifest.title, generatedAt: after.manifest.generatedAt,
      containsFullSnapshot: after.manifest.containsFullSnapshot },
    privacy: {
      before: { containsStudentNames: before.manifest.containsStudentNames, containsStudentIds: before.manifest.containsStudentIds,
        containsSessionIds: before.manifest.containsSessionIds },
      after: { containsStudentNames: after.manifest.containsStudentNames, containsStudentIds: after.manifest.containsStudentIds,
        containsSessionIds: after.manifest.containsSessionIds },
    },
    dimensionDelta,
    summary: {
      files: fileChanges.length,
      added: fileChanges.filter((file) => file.status === 'added').length,
      removed: fileChanges.filter((file) => file.status === 'removed').length,
      changed: fileChanges.filter((file) => file.status === 'changed').length,
      unchanged: fileChanges.filter((file) => file.status === 'unchanged').length,
    },
    files: fileChanges,
  };
}

function metadataCsvCell(value) {
  let cell = String(value ?? '');
  if (/^[\t\r\n ]*[=+\-@]/.test(cell)) cell = `'${cell}`;
  return `"${cell.replaceAll('"', '""')}"`;
}

/** Spreadsheet-safe package file inventory without package payloads. */
export function closeoutInspectionToCsv(value) {
  const inspection = object(value, 'closeout inspection');
  if (inspection.format !== 'attendance-closeout-inspection' || inspection.version !== 1 || !Array.isArray(inspection.files)) {
    throw new TypeError('invalid closeout inspection');
  }
  const rows = [['name', 'mimeType', 'bytes', 'sha256'], ...inspection.files.map((file) => [file.name, file.mimeType, file.bytes, file.sha256])];
  return `${rows.map((row) => row.map(metadataCsvCell).join(',')).join('\r\n')}\r\n`;
}

/** Spreadsheet-safe change inventory for two verified closeout packages. */
export function closeoutComparisonToCsv(value) {
  const comparison = object(value, 'closeout comparison');
  if (comparison.format !== 'attendance-closeout-comparison' || comparison.version !== 1 || !Array.isArray(comparison.files)) {
    throw new TypeError('invalid closeout comparison');
  }
  const headers = ['name', 'status', 'beforeBytes', 'afterBytes', 'beforeSha256', 'afterSha256'];
  const rows = comparison.files.map((file) => headers.map((key) => file[key]));
  return `${[headers, ...rows].map((row) => row.map(metadataCsvCell).join(',')).join('\r\n')}\r\n`;
}
