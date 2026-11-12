import { test } from "node:test";
import assert from "node:assert/strict";
import { AdminError } from "../src/admin/model.js";
import {
  RISK_SAFE,
  RISK_WARNING,
  RISK_CRITICAL,
  classifyAbsenceRisk,
  evaluateStudentCourseAttendance,
  buildCourseAttendanceAnalytics,
  exportClassAttendanceCsv,
} from "../src/admin/analytics.js";

const sampleCourse = () => ({
  id: "remote-c1",
  data: {
    id: "FA26_PRM393_SE1917",
    courseCode: "PRM393",
    classCode: "SE1917",
    students: [
      {
        rollNumber: "SE001",
        memberCode: "M001",
        fullName: "Nguyễn Văn An",
        email: "an@fpt.edu.vn",
      },
      {
        rollNumber: "SE002",
        memberCode: "M002",
        fullName: "=Trần Thị Bình",
        email: "binh@fpt.edu.vn",
      },
      {
        rollNumber: "SE003",
        memberCode: "M003",
        fullName: "Lê Văn Cường",
        email: "cuong@fpt.edu.vn",
      },
    ],
  },
  meetings: Array.from({ length: 20 }, (_, i) => {
    const num = i + 1;
    const isClosed = num <= 6;
    const records = {};
    if (isClosed) {
      // SE001: 1 absence out of 20 (5% -> safe)
      records.SE001 = { status: num === 2 ? "A" : "P" };
      // SE002: 3 absences out of 20 (15% -> warning), with 2 consecutive at m5, m6
      records.se002 = { status: [2, 5, 6].includes(num) ? "A" : "P" };
      // SE003: 5 absences out of 20 (25% -> critical), with 4 consecutive at m3..m6
      records.SE003 = { status: [1, 3, 4, 5, 6].includes(num) ? "A" : "P" };
    }
    return {
      id: `m${num}`,
      number: num,
      startAt: `2026-09-${String(num).padStart(2, "0")}T07:30:00.000`,
      state: isClosed ? "closed" : "upcoming",
      records,
    };
  }),
});

test("classifyAbsenceRisk enforces FPT 15% warning and >20% critical boundaries", () => {
  assert.equal(classifyAbsenceRisk(0), RISK_SAFE);
  assert.equal(classifyAbsenceRisk(0.1499), RISK_SAFE);
  assert.equal(classifyAbsenceRisk(0.15), RISK_WARNING);
  assert.equal(classifyAbsenceRisk(0.2), RISK_WARNING);
  assert.equal(classifyAbsenceRisk(0.2001), RISK_CRITICAL);
  assert.throws(
    () => classifyAbsenceRisk(0.1, { warningThreshold: 0.3, criticalThreshold: 0.2 }),
    AdminError,
  );
});

test("evaluateStudentCourseAttendance calculates streaks, allowance, and case-insensitive lookup", () => {
  const course = sampleCourse();

  const s1 = evaluateStudentCourseAttendance(course, "se001");
  assert.equal(s1.presentCount, 5);
  assert.equal(s1.absentCount, 1);
  assert.equal(s1.unmarkedCount, 14);
  assert.equal(s1.absenceRate, 0.05);
  assert.equal(s1.maxAllowedAbsences, 4);
  assert.equal(s1.remainingAbsenceAllowance, 3);
  assert.equal(s1.currentAbsenceStreak, 0);
  assert.equal(s1.maxAbsenceStreak, 1);
  assert.equal(s1.riskLevel, RISK_SAFE);
  assert.equal(s1.exceededLimit, false);

  const s2 = evaluateStudentCourseAttendance(course, "SE002");
  assert.equal(s2.absentCount, 3);
  assert.equal(s2.absenceRate, 0.15);
  assert.equal(s2.remainingAbsenceAllowance, 1);
  assert.equal(s2.currentAbsenceStreak, 2);
  assert.equal(s2.maxAbsenceStreak, 2);
  assert.equal(s2.riskLevel, RISK_WARNING);

  const s3 = evaluateStudentCourseAttendance(course, "SE003");
  assert.equal(s3.absentCount, 5);
  assert.equal(s3.absenceRate, 0.25);
  assert.equal(s3.remainingAbsenceAllowance, 0);
  assert.equal(s3.currentAbsenceStreak, 4);
  assert.equal(s3.maxAbsenceStreak, 4);
  assert.equal(s3.riskLevel, RISK_CRITICAL);
  assert.equal(s3.exceededLimit, true);

  assert.throws(
    () => evaluateStudentCourseAttendance(course, "SE999"),
    AdminError,
  );
});

test("buildCourseAttendanceAnalytics and exportClassAttendanceCsv summarize and escape formula cells", () => {
  const course = sampleCourse();
  const summary = buildCourseAttendanceAnalytics(course);
  assert.equal(summary.totalStudents, 3);
  assert.equal(summary.totalMeetings, 20);
  assert.equal(summary.closedMeetings, 6);
  assert.equal(summary.safeCount, 1);
  assert.equal(summary.warningCount, 1);
  assert.equal(summary.criticalCount, 1);

  const csv = exportClassAttendanceCsv(course);
  const lines = csv.split("\r\n");
  assert.equal(lines.length, 4);
  assert.match(lines[0], /"course_code","class_code","roll_number"/);
  assert.match(lines[2], /"'=Trần Thị Bình"/);
  assert.match(lines[3], /"critical","0"/);
});
