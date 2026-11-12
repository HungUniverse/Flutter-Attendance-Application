import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const cli = fileURLToPath(new URL('./cli.mjs', import.meta.url));

test('runs the full offline import, reporting, update and export workflow', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'attendance-workbench-'));
  try {
    const roster = join(dir, 'roster.csv');
    const sessions = join(dir, 'sessions.json');
    const attendance = join(dir, 'attendance.csv');
    const initial = join(dir, 'initial.json');
    const updated = join(dir, 'updated.json');
    const changes = join(dir, 'changes.json');
    await writeFile(roster, 'id,name,email\nA,An,a@example.com\nB,Binh,b@example.com\n');
    await writeFile(sessions, '["1","2"]');
    await writeFile(attendance, 'studentId,sessionId,status\nA,1,present\nB,1,absent\n');
    const run = (...args) => execFileSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    const importPreview = JSON.parse(run('preview-import', roster, sessions, attendance));
    assert.equal(importPreview.ready, true);
    assert.equal(importPreview.summary.missing, 2);
    await writeFile(initial, run('init', roster, sessions, attendance));
    const report = JSON.parse(run('report', initial));
    assert.equal(report.missing, 2);
    assert.equal(report.coverage, 0.5);
    assert.match(run('report-html', initial, 'Class report'), /<title>Class report<\/title>/);
    assert.equal(JSON.parse(run('rolling', initial, '1'))[0].windows.length, 2);
    assert.equal(JSON.parse(run('absence-runs', initial, '1'))[0].student.id, 'B');
    assert.equal(JSON.parse(run('forecast', initial, '2', '0.75'))[0].forecast, null);
    const policy = join(dir, 'policy.json');
    await writeFile(policy, '{"minimumRate":0.75,"maximumAbsences":1}');
    assert.equal(JSON.parse(run('policy', initial, policy))[0].status, 'undetermined');
    await writeFile(changes, JSON.stringify([
      { studentId: 'A', sessionId: '2', expected: null, status: 'present' },
    ]));
    await writeFile(updated, run('apply', initial, changes));
    assert.equal(JSON.parse(run('report', updated)).missing, 1);
    const revisedSessions = join(dir, 'revised-sessions.json');
    await writeFile(revisedSessions, '["1"]');
    const blocked = spawnSync(process.execPath, [cli, 'set-sessions', updated, revisedSessions], { encoding: 'utf8' });
    assert.equal(blocked.status, 1);
    assert.match(blocked.stderr, /drop-records/);
    assert.equal(JSON.parse(run('set-sessions', updated, revisedSessions, '--drop-records')).records.length, 2);
    assert.equal(JSON.parse(run('compare', initial, updated)).attendance.added.length, 1);
    assert.match(run('export-csv', updated), /"A","2","present"/);
    const emptyBundle = join(dir, 'empty-bundle.json');
    const classBundle = join(dir, 'class-bundle.json');
    await writeFile(emptyBundle, run('bundle-new'));
    await writeFile(classBundle, run('bundle-put', emptyBundle, 'course', 'Course', updated));
    assert.equal(JSON.parse(run('bundle-report', classBundle))[0].missing, 1);
    assert.equal(JSON.parse(run('bundle-students', classBundle)).length, 2);
    assert.equal(JSON.parse(run('bundle-extract', classBundle, 'course')).records.length, 3);
    assert.equal(JSON.parse(run('bundle-remove', classBundle, 'course')).classes.length, 0);
    const failed = spawnSync(process.execPath, [cli, 'apply', updated, changes], { encoding: 'utf8' });
    assert.equal(failed.status, 1);
    assert.match(failed.stderr, /conflicting changes/);
    assert.equal(JSON.parse(await readFile(updated, 'utf8')).records.length, 3);
    const scheduleOptions = join(dir, 'schedule-options.json');
    const schedule = join(dir, 'schedule.json');
    await writeFile(scheduleOptions, JSON.stringify({ startDate: '2026-01-01', endDate: '2026-01-15',
      startTime: '09:00', durationMinutes: 60, weekdays: [4], resources: ['room'], idPrefix: 'class' }));
    await writeFile(schedule, run('schedule-generate', scheduleOptions));
    assert.equal(JSON.parse(await readFile(schedule, 'utf8')).length, 3);
    assert.deepEqual(JSON.parse(run('schedule-conflicts', schedule)), []);
    assert.match(run('schedule-calendar', schedule, 'example.com', '2026-01-01T00:00:00Z'), /BEGIN:VEVENT/);
    const planOptions = join(dir, 'plan-options.json');
    await writeFile(planOptions, JSON.stringify({
      tasks: [{ id: 'lecture-a', groupId: 'g1', instructorId: 't1', durationMinutes: 60 }],
      slots: [{ id: 'slot-a', start: '2026-01-05T09:00:00Z', end: '2026-01-05T10:00:00Z', roomId: 'r1' }],
    }));
    assert.equal(JSON.parse(run('schedule-plan', planOptions)).complete, true);
    const archivePath = join(dir, 'archive.json');
    const archiveUpdated = join(dir, 'archive-updated.json');
    await writeFile(archivePath, run('archive-new', initial, 'Course history'));
    await writeFile(archiveUpdated, run('archive-add', archivePath, updated, 'Record review', 'Teacher'));
    assert.equal(JSON.parse(run('archive-list', archiveUpdated)).length, 2);
    assert.equal(JSON.parse(run('archive-compare', archiveUpdated, 'r1', 'r2')).changes.attendance.added.length, 1);
    assert.equal(JSON.parse(run('archive-restore', archiveUpdated, 'r1', 'Restore previous')).revisions.length, 3);
    assert.match(run('archive-csv', archiveUpdated), /"revisionId"/);
    const auditReport = JSON.parse(run('audit', initial));
    assert.equal(auditReport.version, 1);
    assert.ok(auditReport.summary.total > 0);
    assert.match(run('audit-csv', initial), /"severity","code","subject"/);
    const auditOptions = join(dir, 'audit-options.json');
    await writeFile(auditOptions, '{"minimumAttendanceRate":0.5,"minimumRecordedSessions":1}');
    assert.equal(JSON.parse(run('audit', initial, auditOptions)).options.minimumAttendanceRate, 0.5);
    const scenarioPath = join(dir, 'scenario.json');
    const scenarioChanged = join(dir, 'scenario-changed.json');
    await writeFile(scenarioPath, run('scenario-new', initial, 'Correction review', policy));
    await writeFile(scenarioChanged, run('scenario-set', scenarioPath, 'A', '2', 'present'));
    const scenarioResult = JSON.parse(run('scenario-evaluate', scenarioChanged));
    assert.equal(scenarioResult.ok, true);
    assert.equal(scenarioResult.delta.present, 1);
    assert.match(run('scenario-csv', scenarioChanged), /"A","An","2","missing","present"/);
    const scenarioConflict = JSON.parse(run('scenario-evaluate', scenarioChanged, updated));
    assert.equal(scenarioConflict.ok, false);
    assert.equal(scenarioConflict.conflicts.length, 1);
    assert.equal(JSON.parse(run('scenario-remove', scenarioChanged, 'A', '2')).changes.length, 0);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('returns errors without emitting a partial snapshot', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'attendance-workbench-'));
  try {
    const roster = join(dir, 'roster.csv');
    const sessions = join(dir, 'sessions.json');
    const attendance = join(dir, 'attendance.csv');
    await writeFile(roster, 'id,name,email\nA,An,invalid\n');
    await writeFile(sessions, '[]');
    await writeFile(attendance, 'studentId,sessionId,status\n');
    const result = spawnSync(process.execPath, [cli, 'init', roster, sessions, attendance], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /invalid_email/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('generates repeatable synthetic snapshots, profile docs and compact manifests', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'attendance-workbench-demo-'));
  try {
    const options = join(dir, 'options.json');
    const data = join(dir, 'synthetic.json');
    await writeFile(options, JSON.stringify({ students: 15, sessions: 8, seed: 'cli-fixture', missingRate: 0.15,
      missingPattern: 'recent', groupCount: 3 }));
    const run = (...args) => execFileSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    await writeFile(data, run('demo-generate', options));
    const snapshot = JSON.parse(await readFile(data, 'utf8'));
    const again = JSON.parse(run('demo-generate', options));
    assert.deepEqual(snapshot, again);
    assert.equal(snapshot.roster.length, 15);
    assert.equal(snapshot.sessionIds.length, 8);
    const manifest = JSON.parse(run('demo-manifest', options));
    assert.equal(manifest.synthetic, true);
    assert.equal(manifest.dimensions.students, 15);
    assert.equal(manifest.dimensions.missing, 30);
    assert.equal(JSON.parse(run('demo-profiles')).length, 8);
    assert.equal(JSON.parse(run('demo-summary', data)).coverage, 0.75);
    assert.equal(JSON.parse(run('report', data)).missing, 30);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('anonymizes snapshots, class bundles and revision archives from explicit local options', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'attendance-workbench-privacy-'));
  try {
    const run = (...args) => execFileSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    const source = join(dir, 'source.json');
    const options = join(dir, 'privacy-options.json');
    const anonymized = join(dir, 'anonymized.json');
    await writeFile(source, run('demo-generate',));
    await writeFile(options, JSON.stringify({ secret: 'temporary-local-test-secret-key' }));
    await writeFile(anonymized, run('anonymize-snapshot', source, options));
    const sourceJson = JSON.parse(await readFile(source, 'utf8'));
    const outputJson = JSON.parse(await readFile(anonymized, 'utf8'));
    assert.equal(outputJson.roster.length, sourceJson.roster.length);
    assert.equal(outputJson.records.length, sourceJson.records.length);
    assert.equal(JSON.parse(run('anonymize-report', source, options)).valid, true);
    assert.doesNotMatch(JSON.stringify(outputJson), /DEMO-|student-1@example\.invalid/);

    const empty = join(dir, 'empty-bundle.json');
    const bundle = join(dir, 'private-bundle.json');
    const anonymizedBundle = join(dir, 'anonymized-bundle.json');
    await writeFile(empty, run('bundle-new'));
    await writeFile(bundle, run('bundle-put', empty, 'private-course', 'Internal Class Name', source));
    await writeFile(anonymizedBundle, run('anonymize-bundle', bundle, options));
    assert.doesNotMatch(await readFile(anonymizedBundle, 'utf8'), /private-course|Internal Class Name|DEMO-/);

    const archive = join(dir, 'private-archive.json');
    const anonymizedArchive = join(dir, 'anonymized-archive.json');
    await writeFile(archive, run('archive-new', source, 'Internal attendance record'));
    await writeFile(anonymizedArchive, run('anonymize-archive', archive, options));
    const scrubbedArchive = JSON.parse(await readFile(anonymizedArchive, 'utf8'));
    assert.equal(scrubbedArchive.revisions[0].message, 'Revision 1');
    assert.doesNotMatch(await readFile(anonymizedArchive, 'utf8'), /Internal attendance record|DEMO-/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('maps localized CSV headers and previews explicit status and duplicate policies', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'attendance-workbench-map-'));
  try {
    const roster = join(dir, 'students.csv');
    const attendance = join(dir, 'marks.csv');
    const sessions = join(dir, 'sessions.json');
    const options = join(dir, 'mapping.json');
    const run = (...args) => execFileSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    await writeFile(roster, 'MSSV;Họ và tên;Email sinh viên\nA001;Nguyễn An;an@example.test\n');
    await writeFile(attendance, 'Mã sinh viên|Buổi học|Trạng thái\nA001|D1|Có mặt\nA001|D2|chưa ghi\n');
    await writeFile(sessions, '["D1","D2"]');
    const suggested = JSON.parse(run('map-suggest', roster, 'roster'));
    assert.equal(suggested.ready, true);
    const preview = JSON.parse(run('map-preview', roster, attendance, sessions));
    assert.equal(preview.ready, true);
    assert.equal(preview.summary.attendance.explicitMissing, 1);
    assert.equal(preview.snapshot.records.length, 1);
    await writeFile(attendance, 'Student ID|Session ID|Status\nA001|D1|P\nA001|D1|A\n');
    await writeFile(options, JSON.stringify({ attendanceOptions: {
      mapping: { studentId: 'Student ID', sessionId: 'Session ID', status: 'Status' },
      statusAliases: { present: ['P'], absent: ['A'] }, duplicatePolicy: 'last',
    } }));
    const resolved = JSON.parse(run('map-preview', roster, attendance, sessions, options));
    assert.equal(resolved.ready, true);
    assert.equal(resolved.snapshot.records[0].status, 'absent');
    assert.match(run('map-issues-csv', roster, attendance, sessions, options), /duplicate_replaced/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
