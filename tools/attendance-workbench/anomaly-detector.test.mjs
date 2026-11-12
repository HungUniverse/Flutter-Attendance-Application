import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { anomaliesToCsv, detectAttendanceAnomalies } from './anomaly-detector.mjs';
import { runCommand } from './cli.mjs';

function buildTestSnapshot() {
  const roster = [
    { id: 'SE101', name: 'Nguyen Van A', email: 'a@fpt.edu.vn' },
    { id: 'SE102', name: 'Tran Thi B', email: 'b@fpt.edu.vn' },
    { id: 'SE103', name: 'Le Van C', email: 'c@fpt.edu.vn' },
  ];
  const sessionIds = ['S1', 'S2', 'S3', 'S4'];
  const records = [
    // S1: 3/3 present (100%)
    { studentId: 'SE101', sessionId: 'S1', status: 'present' },
    { studentId: 'SE102', sessionId: 'S1', status: 'present' },
    { studentId: 'SE103', sessionId: 'S1', status: 'present' },
    // S2: SE101 present, SE102 absent, SE103 present (66.7%)
    { studentId: 'SE101', sessionId: 'S2', status: 'present' },
    { studentId: 'SE102', sessionId: 'S2', status: 'absent' },
    { studentId: 'SE103', sessionId: 'S2', status: 'present' },
    // S3: 0/3 present (0%) -> sudden drop + uniform absent
    { studentId: 'SE101', sessionId: 'S3', status: 'absent' },
    { studentId: 'SE102', sessionId: 'S3', status: 'present' },
    { studentId: 'SE103', sessionId: 'S3', status: 'absent' },
    // S4: 0/3 present (0%) -> uniform absent
    { studentId: 'SE101', sessionId: 'S4', status: 'absent' },
    { studentId: 'SE102', sessionId: 'S4', status: 'absent' },
    { studentId: 'SE103', sessionId: 'S4', status: 'absent' },
  ];
  return createAttendanceSnapshot(roster, sessionIds, records);
}

test('detectAttendanceAnomalies identifies uniform absent, sudden drop, drop-off, and alternation', () => {
  const snapshot = buildTestSnapshot();
  const report = detectAttendanceAnomalies(snapshot, {
    sessionDropThreshold: 0.3,
    studentDropoffThreshold: 0.5,
    alternationLength: 4,
  });

  assert.equal(report.version, 1);
  const codes = report.anomalies.map((item) => `${item.code}:${item.subject}`);
  assert.ok(codes.includes('session_uniform_absent:S4'));
  assert.ok(codes.includes('session_sudden_drop:S3'));
  assert.ok(codes.includes('late_semester_dropoff:SE101'));
  assert.ok(codes.includes('late_semester_dropoff:SE103'));
  assert.ok(codes.includes('status_alternation:SE102'));
  assert.equal(report.summary.total, report.anomalies.length);
});

test('anomaliesToCsv formats formula-safe CSV output and validates input', () => {
  const snapshot = buildTestSnapshot();
  const report = detectAttendanceAnomalies(snapshot);
  const csv = anomaliesToCsv(report);
  assert.match(csv, /^"severity","code","subject","description"\r\n/);
  assert.match(csv, /"high","session_uniform_absent","S4"/);

  assert.throws(() => anomaliesToCsv(null), /invalid anomaly report/);
  assert.throws(() => detectAttendanceAnomalies(snapshot, { sessionDropThreshold: 1.5 }), /sessionDropThreshold must be between 0 and 1/);
  assert.throws(() => detectAttendanceAnomalies(snapshot, { alternationLength: 2 }), /alternationLength must be an integer of at least 3/);
});

test('CLI anomaly-scan and anomaly-scan-csv commands execute cleanly', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'workbench-anomaly-'));
  try {
    const snapPath = join(dir, 'snapshot.json');
    await writeFile(snapPath, serializeAttendanceSnapshot(buildTestSnapshot()), 'utf8');
    const jsonOutput = JSON.parse(await runCommand(['anomaly-scan', snapPath]));
    assert.equal(jsonOutput.version, 1);
    assert.ok(jsonOutput.anomalies.length >= 4);

    const csvOutput = await runCommand(['anomaly-scan-csv', snapPath]);
    assert.match(csvOutput, /"session_uniform_absent"/);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
