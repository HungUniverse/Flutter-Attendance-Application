import { AdminError } from "./model.js";

export const RISK_SAFE = "safe";
export const RISK_WARNING = "warning";
export const RISK_CRITICAL = "critical";

function normalizeRoll(value) {
  return String(value ?? "").trim().toUpperCase();
}

function recordForStudent(records, rollNumber) {
  if (!records || typeof records !== "object") return undefined;
  const target = normalizeRoll(rollNumber);
  if (Object.hasOwn(records, target)) return records[target];
  for (const [key, value] of Object.entries(records)) {
    if (normalizeRoll(key) === target) return value;
  }
  return undefined;
}

export function classifyAbsenceRisk(
  absenceRate,
  { warningThreshold = 0.15, criticalThreshold = 0.2 } = {},
) {
  if (
    !Number.isFinite(warningThreshold) ||
    !Number.isFinite(criticalThreshold) ||
    warningThreshold < 0 ||
    criticalThreshold < warningThreshold ||
    criticalThreshold > 1
  ) {
    throw new AdminError("Ngưỡng cảnh báo vắng học không hợp lệ.");
  }
  if (!Number.isFinite(absenceRate) || absenceRate < 0) return RISK_SAFE;
  if (absenceRate > criticalThreshold) return RISK_CRITICAL;
  if (absenceRate >= warningThreshold) return RISK_WARNING;
  return RISK_SAFE;
}

function sortCourseMeetings(meetings) {
  return [...(meetings || [])].sort(
    (a, b) =>
      String(a.startAt || "").localeCompare(String(b.startAt || "")) ||
      (Number(a.number) || 0) - (Number(b.number) || 0),
  );
}

function evaluateStudentWithMeetings(
  student,
  meetings,
  completedMeetings,
  options = {},
) {
  const targetRoll = normalizeRoll(student.rollNumber);
  const totalScheduled = meetings.length;
  let presentCount = 0;
  let absentCount = 0;
  let unmarkedCount = 0;
  let currentAbsenceStreak = 0;
  let maxAbsenceStreak = 0;
  let runningStreak = 0;

  for (const meeting of meetings) {
    if (meeting.state === "upcoming") {
      unmarkedCount++;
      continue;
    }
    const status = recordForStudent(meeting.records, targetRoll)?.status;
    if (status === "P") {
      presentCount++;
      runningStreak = 0;
    } else if (status === "A") {
      absentCount++;
      runningStreak++;
      if (runningStreak > maxAbsenceStreak) maxAbsenceStreak = runningStreak;
    } else {
      unmarkedCount++;
      runningStreak = 0;
    }
  }
  currentAbsenceStreak = runningStreak;

  const absenceRate = totalScheduled > 0 ? absentCount / totalScheduled : 0;
  const recordedCount = presentCount + absentCount;
  const attendanceRate = recordedCount > 0 ? presentCount / recordedCount : null;
  const criticalThreshold = options.criticalThreshold ?? 0.2;
  const maxAllowedAbsences = Math.floor(totalScheduled * criticalThreshold);
  const remainingAbsenceAllowance = Math.max(
    0,
    maxAllowedAbsences - absentCount,
  );
  const riskLevel = classifyAbsenceRisk(absenceRate, options);

  return {
    rollNumber: targetRoll,
    fullName: String(student.fullName ?? "").trim(),
    email: String(student.email ?? "").trim().toLowerCase(),
    memberCode: String(student.memberCode ?? "").trim(),
    totalScheduled,
    completedMeetings,
    presentCount,
    absentCount,
    unmarkedCount,
    absenceRate,
    attendanceRate,
    maxAllowedAbsences,
    remainingAbsenceAllowance,
    currentAbsenceStreak,
    maxAbsenceStreak,
    riskLevel,
    exceededLimit: absenceRate > criticalThreshold,
  };
}

export function evaluateStudentCourseAttendance(
  course,
  rollNumber,
  options = {},
) {
  if (!course || !course.data || !Array.isArray(course.data.students)) {
    throw new AdminError("Dữ liệu lớp học không hợp lệ.");
  }
  const targetRoll = normalizeRoll(rollNumber);
  const student = course.data.students.find(
    (item) => normalizeRoll(item.rollNumber) === targetRoll,
  );
  if (!student) {
    throw new AdminError(`Sinh viên ${targetRoll} không thuộc lớp học.`);
  }
  const meetings = sortCourseMeetings(course.meetings);
  let completedMeetings = 0;
  for (const meeting of meetings) {
    if (meeting.state === "closed") completedMeetings++;
  }
  return evaluateStudentWithMeetings(
    student,
    meetings,
    completedMeetings,
    options,
  );
}

export function buildCourseAttendanceAnalytics(course, options = {}) {
  if (!course || !course.data || !Array.isArray(course.data.students)) {
    throw new AdminError("Dữ liệu lớp học không hợp lệ.");
  }
  const meetings = sortCourseMeetings(course.meetings);
  let closedMeetings = 0;
  for (const meeting of meetings) {
    if (meeting.state === "closed") closedMeetings++;
  }
  const seenRolls = new Set();
  const students = [];
  let safeCount = 0;
  let warningCount = 0;
  let criticalCount = 0;
  let totalPresent = 0;
  let totalAbsent = 0;

  for (const rawStudent of course.data.students) {
    const roll = normalizeRoll(rawStudent?.rollNumber);
    if (!roll || seenRolls.has(roll)) continue;
    seenRolls.add(roll);
    const report = evaluateStudentWithMeetings(
      rawStudent,
      meetings,
      closedMeetings,
      options,
    );
    students.push(report);
    if (report.riskLevel === RISK_SAFE) safeCount++;
    else if (report.riskLevel === RISK_WARNING) warningCount++;
    else if (report.riskLevel === RISK_CRITICAL) criticalCount++;
    totalPresent += report.presentCount;
    totalAbsent += report.absentCount;
  }

  const overallAttendanceRate =
    totalPresent + totalAbsent > 0
      ? totalPresent / (totalPresent + totalAbsent)
      : null;

  return {
    classId: course.id || course.data.id || "",
    courseCode: course.data.courseCode || "",
    classCode: course.data.classCode || "",
    totalStudents: students.length,
    totalMeetings: meetings.length,
    closedMeetings,
    safeCount,
    warningCount,
    criticalCount,
    overallAttendanceRate,
    students,
  };
}

function escapeCsvCell(value) {
  const raw = String(value ?? "");
  const safe = /^(?:[\t\r]|[\t\r\n ]*[=+\-@])/.test(raw) ? `'${raw}` : raw;
  return `"${safe.replaceAll('"', '""')}"`;
}

export function exportClassAttendanceCsv(course, options = {}) {
  const analytics = buildCourseAttendanceAnalytics(course, options);
  const header = [
    "course_code",
    "class_code",
    "roll_number",
    "member_code",
    "full_name",
    "email",
    "present",
    "absent",
    "unmarked",
    "total_scheduled",
    "absence_rate",
    "risk_level",
    "remaining_allowance",
  ];
  const rows = analytics.students.map((student) => [
    analytics.courseCode,
    analytics.classCode,
    student.rollNumber,
    student.memberCode,
    student.fullName,
    student.email,
    student.presentCount,
    student.absentCount,
    student.unmarkedCount,
    student.totalScheduled,
    student.absenceRate.toFixed(4),
    student.riskLevel,
    student.remainingAbsenceAllowance,
  ]);
  return [header, ...rows]
    .map((row) => row.map(escapeCsvCell).join(","))
    .join("\r\n");
}
