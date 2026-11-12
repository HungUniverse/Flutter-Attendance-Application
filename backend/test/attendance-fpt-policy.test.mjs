import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateFptAttendancePolicy,
  fptPolicyReportToCsv,
} from '../attendance-fpt-policy.mjs';

const roster = [
  { id: 'SE001', name: 'Nguyen Van A', email: 'a@fpt.edu.vn' },
  { id: 'SE002', name: '=Tran Thi B', email: 'b@fpt.edu.vn' },
  { id: 'SE003', name: 'Le Van C', email: 'c@fpt.edu.vn' },
];
const sessions = ['s1', 's2', 's3', 's4', 's5', 's6'];

test('evaluates FPT 15% warning and >20% debarred rules across 20 planned sessions', () => {
  const records = [
    // SE001: 1 absence / 20 = 5% (eligible)
    { studentId: 'SE001', sessionId: 's1', status: 'absent' },
    { studentId: 'SE001', sessionId: 's2', status: 'present' },
    // SE002: 3 absences / 20 = 15% (warning)
    { studentId: 'SE002', sessionId: 's1', status: 'absent' },
    { studentId: 'SE002', sessionId: 's2', status: 'absent' },
    { studentId: 'SE002', sessionId: 's3', status: 'absent' },
    // SE003: 5 absences / 20 = 25% (debarred)
    { studentId: 'SE003', sessionId: 's1', status: 'absent' },
    { studentId: 'SE003', sessionId: 's2', status: 'absent' },
    { studentId: 'SE003', sessionId: 's3', status: 'absent' },
    { studentId: 'SE003', sessionId: 's4', status: 'absent' },
    { studentId: 'SE003', sessionId: 's5', status: 'absent' },
  ];

  const result = evaluateFptAttendancePolicy(roster, sessions, records, {
    totalPlannedSessions: 20,
  });

  assert.equal(result.policy.maxAllowedAbsences, 4);
  assert.deepEqual(result.summary, {
    totalStudents: 3,
    completedSessions: 6,
    totalPlannedSessions: 20,
    maxAllowedAbsences: 4,
    eligible: 1,
    warning: 1,
    debarred: 1,
  });

  assert.equal(result.students[0].status, 'eligible');
  assert.equal(result.students[0].remainingAbsences, 3);
  assert.equal(result.students[0].canStillPass, true);

  assert.equal(result.students[1].status, 'warning');
  assert.equal(result.students[1].remainingAbsences, 1);
  assert.equal(result.students[1].canStillPass, true);

  assert.equal(result.students[2].status, 'debarred');
  assert.equal(result.students[2].remainingAbsences, 0);
  assert.equal(result.students[2].canStillPass, false);
});

test('validates options and exports spreadsheet-safe CSV', () => {
  assert.throws(
    () => evaluateFptAttendancePolicy(roster, sessions, [], { totalPlannedSessions: 3 }),
    RangeError,
  );
  assert.throws(
    () => evaluateFptAttendancePolicy(roster, sessions, [], { warningRatio: 0.25, maxAbsenceRatio: 0.2 }),
    RangeError,
  );

  const evaluation = evaluateFptAttendancePolicy(roster, sessions, [], {
    totalPlannedSessions: 20,
  });
  evaluation.students.push({
    ...evaluation.students[0],
    student: { id: 'SE004', name: '\tTabbed Name', email: 'd@fpt.edu.vn' },
  });
  const csv = fptPolicyReportToCsv(evaluation);
  assert.match(csv, /"SE002","'=Tran Thi B","b@fpt\.edu\.vn"/);
  assert.match(csv, /"SE004","'\tTabbed Name","d@fpt\.edu\.vn"/);
  assert.throws(() => fptPolicyReportToCsv(null), TypeError);
});
