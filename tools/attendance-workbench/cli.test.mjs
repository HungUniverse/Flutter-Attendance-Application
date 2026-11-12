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

test('builds review worklists, case histories, reports and checksummed closeout packages', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'attendance-workbench-closeout-'));
  try {
    const run = (...args) => execFileSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    const source = join(dir, 'snapshot.json');
    const reviewOptions = join(dir, 'review-options.json');
    const plan = join(dir, 'review-plan.json');
    const reviewers = join(dir, 'reviewers.json');
    const casebook = join(dir, 'casebook.json');
    const casebookOptions = join(dir, 'casebook-options.json');
    const update = join(dir, 'update.json');
    const reportOptions = join(dir, 'report-options.json');
    const closeoutOptions = join(dir, 'closeout-options.json');
    const historyOptions = join(dir, 'history-options.json');
    const minimizedCloseoutOptions = join(dir, 'minimized-closeout-options.json');
    await writeFile(source, run('demo-generate'));
    await writeFile(reviewOptions, JSON.stringify({ targetRate: 0.8, futureSessions: 2, absenceStreak: 2 }));
    await writeFile(plan, run('review-plan', source, reviewOptions));
    const review = JSON.parse(await readFile(plan, 'utf8'));
    assert.ok(review.summary.total > 0);
    assert.match(run('review-plan-csv', source, reviewOptions), /"caseId","priority"/);
    await writeFile(reviewers, JSON.stringify([{ id: 'team-a', name: 'Team A', capacity: 1 }]));
    const allocation = JSON.parse(run('review-allocate', plan, reviewers));
    assert.equal(allocation.summary.assigned, 1);
    assert.ok(allocation.summary.unassigned >= 0);

    await writeFile(casebookOptions, JSON.stringify({ createdAt: '2026-11-01T00:00:00Z', actor: 'Initial reviewer' }));
    await writeFile(casebook, run('casebook-new', plan, casebookOptions));
    const initial = JSON.parse(await readFile(casebook, 'utf8'));
    const firstCase = initial.cases[0];
    assert.equal(JSON.parse(run('casebook-summary', casebook)).summary.total, review.summary.total);
    await writeFile(update, JSON.stringify({ expectedRevision: 1, actor: 'Reviewer', at: '2026-11-10T10:00:00Z',
      action: { status: 'in_review', assigneeId: 'team-a', note: 'Verify source records.' } }));
    const changed = JSON.parse(run('casebook-update', casebook, firstCase.caseId, update));
    assert.equal(changed.cases[0].status, 'in_review');
    assert.equal(changed.cases[0].assigneeId, 'team-a');
    await writeFile(casebook, JSON.stringify(changed));
    assert.equal(JSON.parse(run('casebook-reconcile', casebook, plan)).revision, 3);
    assert.doesNotMatch(run('casebook-csv', casebook), /Verify source records/);
    assert.match(run('casebook-csv', casebook, '--include-notes'), /Verify source records/);
    const history = JSON.parse(run('casebook-events', casebook));
    assert.ok(history.summary.totalMatches > 0);
    assert.equal(history.summary.truncated, false);
    await writeFile(historyOptions, JSON.stringify({ types: ['note'], includeNotes: true,
      includeStudentDetails: true, limit: 1 }));
    const privateHistory = JSON.parse(run('casebook-events', casebook, historyOptions));
    assert.ok(privateHistory.summary.totalMatches > 0);
    assert.ok(privateHistory.events[0].studentId);
    assert.ok(privateHistory.events[0].note);
    assert.match(run('casebook-events-csv', casebook), /"caseId","sequence","type"/);
    const historyAudit = JSON.parse(run('casebook-history-audit', casebook));
    assert.deepEqual(historyAudit.findings, []);
    assert.match(run('casebook-history-audit-csv', casebook), /"eventSequence","code"/);

    await writeFile(reportOptions, JSON.stringify({ title: 'Term report', generatedAt: '2026-11-10T10:00:00Z',
      includeMatrix: true, includeAudit: true, policy: { minimumRate: 0.75, maximumAbsences: 2 }, maxStudentRows: 30 }));
    const report = JSON.parse(run('report-studio', source, reportOptions));
    assert.equal(report.title, 'Term report');
    assert.ok(report.matrix);
    assert.ok(report.audit);
    assert.match(run('report-html-studio', source, reportOptions), /Term report/);
    assert.match(run('report-csv-studio', source, 'students', reportOptions), /"studentId","studentName"/);

    await writeFile(closeoutOptions, JSON.stringify({ includeSnapshot: true, reportOptions: JSON.parse(await readFile(reportOptions, 'utf8')) }));
    const packageValue = JSON.parse(run('closeout-pack', source, closeoutOptions));
    assert.equal(packageValue.format, 'attendance-closeout-package');
    assert.equal(packageValue.manifest.containsFullSnapshot, true);
    assert.ok(packageValue.files.some((file) => file.name === 'attendance-matrix.csv'));
    assert.ok(packageValue.files.some((file) => file.name === 'manifest.json'));
    const packFile = join(dir, 'closeout.json');
    const minimizedPackFile = join(dir, 'minimized-closeout.json');
    await writeFile(packFile, run('closeout-pack', source, closeoutOptions));
    await writeFile(minimizedCloseoutOptions, JSON.stringify({ reportOptions: {
      generatedAt: '2026-11-11T00:00:00Z', includeStudentNames: false, includeStudentIds: false,
    } }));
    await writeFile(minimizedPackFile, run('closeout-pack', source, minimizedCloseoutOptions));
    const inspection = JSON.parse(run('closeout-inspect', minimizedPackFile));
    assert.equal(inspection.integrity, 'valid');
    assert.equal(inspection.privacy.containsStudentNames, false);
    assert.match(run('closeout-inspect-csv', minimizedPackFile), /"name","mimeType","bytes","sha256"/);
    assert.match(run('closeout-extract', minimizedPackFile, 'report.json'), /"title"/);
    assert.throws(() => run('closeout-extract', minimizedPackFile, '../snapshot.json'), /unknown package file/);
    const closeoutDiff = JSON.parse(run('closeout-compare', minimizedPackFile, packFile));
    assert.ok(closeoutDiff.summary.changed > 0);
    assert.ok(closeoutDiff.summary.added > 0);
    assert.match(run('closeout-compare-csv', minimizedPackFile, packFile), /"status"/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('compares policy candidates and missing-data assumptions through opt-in offline commands', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'attendance-workbench-policy-lab-'));
  try {
    const run = (...args) => execFileSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    const source = join(dir, 'snapshot.json');
    const gridOptions = join(dir, 'grid.json');
    const policies = join(dir, 'policies.json');
    await writeFile(source, run('demo-generate'));
    const generated = JSON.parse(await readFile(source, 'utf8'));
    await writeFile(gridOptions, JSON.stringify({ minimumRates: [0.65, 0.8], maximumAbsences: [1, 3] }));
    const grid = JSON.parse(run('policy-grid', gridOptions));
    assert.equal(grid.length, 4);
    await writeFile(policies, JSON.stringify({ policies: grid.slice(0, 2), minimumCohortSize: 5,
      missingModes: ['bounded', 'assume-present'], cohorts: [{ id: 'demo-groups', label: 'Demo groups',
        studentIds: generated.roster.slice(0, 2).map((student) => student.id) }] }));
    const lab = JSON.parse(run('policy-lab', source, policies));
    assert.equal(lab.format, 'attendance-policy-lab');
    assert.equal(lab.scenarios.length, 4);
    assert.equal(lab.scenarios.every((scenario) => !Object.hasOwn(scenario, 'students')), true);
    assert.match(run('policy-lab-csv', source, policies, 'summary'), /"scenarioId","policyId"/);
    assert.match(run('policy-lab-csv', source, policies, 'cohorts'), /"cohortLabel"/);
    assert.match(run('policy-lab-csv', source, policies, 'comparisons'), /"changed","pass_to_pass"/);
    assert.throws(() => run('policy-lab-csv', source, policies, 'students'), /student rows were not enabled/);
    await writeFile(policies, JSON.stringify({ policies: grid.slice(0, 1), missingModes: ['bounded'], includeStudentRows: true }));
    assert.match(run('policy-lab-csv', source, policies, 'students'), /"scenarioId","studentId"/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
