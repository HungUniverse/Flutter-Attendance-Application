import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { buildCloseoutPackage, closeoutComparisonToCsv, closeoutInspectionToCsv, compareCloseoutPackages,
  inspectCloseoutPackage, parseCloseoutPackage, readCloseoutFile, serializeCloseoutPackage } from './closeout-pack.mjs';

function snapshot() {
  return createAttendanceSnapshot([
    { id: 'A', name: 'An Example', email: 'an@example.test' },
    { id: 'B', name: 'Binh Example', email: 'binh@example.test' },
  ], ['S1', 'S2', 'S3'], [
    { studentId: 'A', sessionId: 'S1', status: 'present' },
    { studentId: 'A', sessionId: 'S2', status: 'absent' },
    { studentId: 'B', sessionId: 'S1', status: 'present' },
    { studentId: 'B', sessionId: 'S2', status: 'present' },
  ]);
}

function refreshManifest(pack) {
  pack.manifest.files = pack.files.filter((file) => file.name !== 'manifest.json').map(({ name, mimeType, bytes, sha256 }) =>
    ({ name, mimeType, bytes, sha256 }));
  const manifestFile = pack.files.find((file) => file.name === 'manifest.json');
  manifestFile.content = `${JSON.stringify(pack.manifest, null, 2)}\n`;
  manifestFile.bytes = Buffer.byteLength(manifestFile.content, 'utf8');
  manifestFile.sha256 = createHash('sha256').update(manifestFile.content, 'utf8').digest('hex');
  return pack;
}

test('creates a deterministic default closeout package with checksummed report files', () => {
  const options = { reportOptions: { title: 'Course closeout', generatedAt: '2026-11-01T00:00:00Z' } };
  const first = buildCloseoutPackage(snapshot(), options);
  const again = buildCloseoutPackage(snapshot(), options);
  assert.deepEqual(first, again);
  assert.equal(first.format, 'attendance-closeout-package');
  assert.equal(first.manifest.containsFullSnapshot, false);
  assert.deepEqual(first.files.map((file) => file.name), [
    'attendance-report.html', 'report.json', 'summary.csv', 'students.csv', 'sessions.csv', 'manifest.json',
  ]);
  assert.ok(first.files.every((file) => file.sha256.length === 64 && file.bytes > 0));
  assert.match(readCloseoutFile(first, 'attendance-report.html'), /Course closeout/);
  assert.doesNotMatch(JSON.stringify(first), /attendance-snapshot\.json/);
  assert.deepEqual(parseCloseoutPackage(serializeCloseoutPackage(first)), first);
});

test('adds optional matrix, audit, policy and full snapshot files with matching manifest entries', () => {
  const pack = buildCloseoutPackage(snapshot(), {
    includeSnapshot: true,
    reportOptions: { includeMatrix: true, includeAudit: true, policy: { minimumRate: 0.75, maximumAbsences: 1 },
      generatedAt: '2026-11-01T00:00:00Z' },
  });
  const names = pack.files.map((file) => file.name);
  assert.ok(names.includes('attendance-matrix.csv'));
  assert.ok(names.includes('data-quality.csv'));
  assert.ok(names.includes('policy-review.csv'));
  assert.ok(names.includes('attendance-snapshot.json'));
  assert.equal(pack.manifest.containsFullSnapshot, true);
  assert.equal(pack.manifest.files.length, pack.files.length - 1);
  assert.match(readCloseoutFile(pack, 'attendance-snapshot.json'), /attendance-snapshot/);
  assert.throws(() => readCloseoutFile(pack, 'missing.json'), /unknown package file/);
});

test('marks identity fields when a minimized report package omits names and IDs', () => {
  const pack = buildCloseoutPackage(snapshot(), {
    reportOptions: { includeStudentNames: false, includeStudentIds: false, includeSessionIds: false,
      includeAudit: true, generatedAt: '2026-11-01T00:00:00Z' },
  });
  assert.equal(pack.manifest.containsStudentNames, false);
  assert.equal(pack.manifest.containsStudentIds, false);
  const data = pack.files.filter((file) => file.name !== 'manifest.json').map((file) => file.content).join('\n');
  assert.doesNotMatch(data, /An Example|Binh Example|an@example\.test|S1/);
});

test('detects changed contents, changed hashes, invalid paths and malformed package JSON', () => {
  const pack = buildCloseoutPackage(snapshot(), { reportOptions: { generatedAt: '2026-11-01T00:00:00Z' } });
  const changed = structuredClone(pack);
  changed.files[0].content += 'tampered';
  changed.files[0].bytes += Buffer.byteLength('tampered', 'utf8');
  assert.throws(() => parseCloseoutPackage(changed), /checksum mismatch/);
  const badManifest = structuredClone(pack);
  badManifest.manifest.files[0].sha256 = '0'.repeat(64);
  assert.throws(() => parseCloseoutPackage(badManifest), /manifest file checksums/);
  const badPath = structuredClone(pack);
  badPath.files[0].name = '../report.html';
  assert.throws(() => parseCloseoutPackage(badPath), /file name/);
  assert.throws(() => parseCloseoutPackage('{'), /valid JSON/);
});

test('validates package options and enforces generated package bounds', () => {
  assert.throws(() => buildCloseoutPackage(snapshot(), null), /closeout options/);
  assert.throws(() => buildCloseoutPackage(snapshot(), { includeSnapshot: 'yes' }), /includeSnapshot/);
  assert.throws(() => buildCloseoutPackage(snapshot(), { reportOptions: null }), /reportOptions/);
  assert.throws(() => readCloseoutFile({}, ''), /package/);
});

test('inspects verified privacy flags and file metadata without returning contents', () => {
  const pack = buildCloseoutPackage(snapshot(), { reportOptions: { title: '=Course closeout', generatedAt: '2026-11-01T00:00:00Z' } });
  const inspected = inspectCloseoutPackage(pack);
  assert.equal(inspected.integrity, 'valid');
  assert.equal(inspected.title, '=Course closeout');
  assert.equal(inspected.privacy.containsStudentNames, true);
  assert.equal(inspected.fileCount, pack.files.length);
  assert.equal(inspected.totalBytes, pack.files.reduce((sum, file) => sum + file.bytes, 0));
  assert.equal(Object.hasOwn(inspected.files[0], 'content'), false);
  assert.match(closeoutInspectionToCsv(inspected), /"name","mimeType","bytes","sha256"/);
  assert.doesNotMatch(closeoutInspectionToCsv(inspected), /=Course closeout/);
  assert.throws(() => inspectCloseoutPackage({ ...pack, files: pack.files.map((file, index) => index ? file : { ...file, content: 'changed' }) }), /incorrect byte count|checksum mismatch/);
  assert.throws(() => closeoutInspectionToCsv({ format: 'invalid', files: [] }), /invalid/);
});

test('compares only verified file metadata and reports package privacy and dimension changes', () => {
  const before = buildCloseoutPackage(snapshot(), { reportOptions: { title: 'Before', generatedAt: '2026-11-01T00:00:00Z' } });
  const after = buildCloseoutPackage(snapshot(), { includeSnapshot: true, reportOptions: {
    title: 'After', generatedAt: '2026-11-02T00:00:00Z', includeStudentNames: false, includeStudentIds: false,
  } });
  const comparison = compareCloseoutPackages(before, after);
  assert.equal(comparison.format, 'attendance-closeout-comparison');
  assert.equal(comparison.summary.added, 1);
  assert.equal(comparison.files.find((file) => file.name === 'attendance-snapshot.json').status, 'added');
  assert.ok(comparison.summary.changed > 0);
  assert.ok(comparison.summary.unchanged > 0);
  assert.equal(comparison.before.containsFullSnapshot, false);
  assert.equal(comparison.after.containsFullSnapshot, true);
  assert.equal(comparison.privacy.after.containsStudentNames, false);
  assert.deepEqual(comparison.dimensionDelta, { students: 0, sessions: 0, expected: 0, recorded: 0, missing: 0 });
  assert.equal(Object.hasOwn(comparison.files[0], 'content'), false);
  assert.match(closeoutComparisonToCsv(comparison), /"name","status","beforeBytes"/);
  assert.throws(() => compareCloseoutPackages(before, { ...after, manifest: { ...after.manifest, version: 2 } }), /invalid closeout package manifest/);
  assert.throws(() => closeoutComparisonToCsv({ format: 'invalid', files: [] }), /invalid/);
  const withoutSnapshot = buildCloseoutPackage(snapshot(), { reportOptions: { title: 'After',
    generatedAt: '2026-11-02T00:00:00Z', includeStudentNames: false, includeStudentIds: false } });
  const removed = compareCloseoutPackages(after, withoutSnapshot);
  assert.equal(removed.summary.removed, 1);
  assert.equal(removed.files.find((file) => file.name === 'attendance-snapshot.json').status, 'removed');
});

test('compares identical packages as unchanged and reports row count deltas for different dimensions', () => {
  const source = snapshot();
  const identical = buildCloseoutPackage(source, { reportOptions: { generatedAt: '2026-11-01T00:00:00Z' } });
  const same = compareCloseoutPackages(identical, serializeCloseoutPackage(identical));
  assert.equal(same.summary.changed, 0);
  assert.equal(same.summary.added, 0);
  assert.equal(same.summary.removed, 0);
  assert.equal(same.summary.unchanged, identical.files.length);
  const expanded = createAttendanceSnapshot([...source.roster,
    { id: 'C', name: 'Chi Example', email: 'chi@example.test' }], [...source.sessionIds, 'S4'], source.records);
  const changed = buildCloseoutPackage(expanded, { reportOptions: { generatedAt: '2026-11-01T00:00:00Z' } });
  const diff = compareCloseoutPackages(identical, changed);
  assert.equal(diff.dimensionDelta.students, 1);
  assert.equal(diff.dimensionDelta.sessions, 1);
  assert.equal(diff.dimensionDelta.expected, 6);
});

test('validates manifest arithmetic and report metadata after checksum verification', () => {
  const pack = buildCloseoutPackage(snapshot(), { reportOptions: { generatedAt: '2026-11-01T00:00:00Z' } });
  const inconsistent = structuredClone(pack);
  inconsistent.manifest.dimensions.students++;
  const manifestFile = inconsistent.files.find((file) => file.name === 'manifest.json');
  manifestFile.content = `${JSON.stringify(inconsistent.manifest, null, 2)}\n`;
  manifestFile.bytes = Buffer.byteLength(manifestFile.content, 'utf8');
  manifestFile.sha256 = createHash('sha256').update(manifestFile.content, 'utf8').digest('hex');
  assert.throws(() => parseCloseoutPackage(inconsistent), /dimensions are inconsistent/);

  const mismatchedReport = structuredClone(pack);
  mismatchedReport.manifest.containsFullSnapshot = true;
  const changedManifestFile = mismatchedReport.files.find((file) => file.name === 'manifest.json');
  changedManifestFile.content = `${JSON.stringify(mismatchedReport.manifest, null, 2)}\n`;
  changedManifestFile.bytes = Buffer.byteLength(changedManifestFile.content, 'utf8');
  changedManifestFile.sha256 = createHash('sha256').update(changedManifestFile.content, 'utf8').digest('hex');
  assert.throws(() => parseCloseoutPackage(mismatchedReport), /snapshot file does not match/);
});

test('rejects a report whose metadata was changed along with internally consistent file hashes', () => {
  const pack = buildCloseoutPackage(snapshot(), { reportOptions: { generatedAt: '2026-11-01T00:00:00Z' } });
  const tampered = structuredClone(pack);
  const reportFile = tampered.files.find((file) => file.name === 'report.json');
  const report = JSON.parse(reportFile.content);
  report.title = 'Edited after package creation';
  reportFile.content = `${JSON.stringify(report, null, 2)}\n`;
  reportFile.bytes = Buffer.byteLength(reportFile.content, 'utf8');
  reportFile.sha256 = createHash('sha256').update(reportFile.content, 'utf8').digest('hex');
  refreshManifest(tampered);
  assert.throws(() => parseCloseoutPackage(tampered), /report.json metadata does not match/);
});

test('rejects identity flags that disagree with the embedded report filters', () => {
  const pack = buildCloseoutPackage(snapshot(), { reportOptions: {
    generatedAt: '2026-11-01T00:00:00Z', includeStudentNames: false,
  } });
  const tampered = structuredClone(pack);
  tampered.manifest.containsStudentNames = true;
  refreshManifest(tampered);
  assert.throws(() => parseCloseoutPackage(tampered), /identity settings do not match/);
});
