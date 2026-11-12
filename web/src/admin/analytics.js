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
  const meetings = [...(course.meetings || [])].sort(
    (a, b) =>
      String(a.startAt || "").localeCompare(String(b.startAt || "")) ||
      (Number(a.number) || 0) - (Number(b.number) || 0),
  );
  const totalScheduled = meetings.length;
  let presentCount = 0;
  let absentCount = 0;
  let unmarkedCount = 0;
  let completedMeetings = 0;
  let currentAbsenceStreak = 0;
  let maxAbsenceStreak = 0;
  let runningStreak = 0;

  for (const meeting of meetings) {
    if (meeting.state === "upcoming") {
      unmarkedCount++;
      continue;
    }
    if (meeting.state === "closed") completedMeetings++;
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
    rollNumber: normalizeRoll(student.rollNumber),
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

export function buildCourseAttendanceAnalytics(course, options = {}) {
  if (!course || !course.data || !Array.isArray(course.data.students)) {
    throw new AdminError("Dữ liệu lớp học không hợp lệ.");
  }
  const students = course.data.students.map((student) =>
    evaluateStudentCourseAttendance(course, student.rollNumber, options),
  );
  const safeCount = students.filter((s) => s.riskLevel === RISK_SAFE).length;
  const warningCount = students.filter(
    (s) => s.riskLevel === RISK_WARNING,
  ).length;
  const criticalCount = students.filter(
    (s) => s.riskLevel === RISK_CRITICAL,
  ).length;
  const totalPresent = students.reduce((sum, s) => sum + s.presentCount, 0);
  const totalAbsent = students.reduce((sum, s) => sum + s.absentCount, 0);
  const overallAttendanceRate =
    totalPresent + totalAbsent > 0
      ? totalPresent / (totalPresent + totalAbsent)
      : null;

  return {
    classId: course.id || course.data.id || "",
    courseCode: course.data.courseCode || "",
    classCode: course.data.classCode || "",
    totalStudents: students.length,
    totalMeetings: (course.meetings || []).length,
    closedMeetings: (course.meetings || []).filter((m) => m.state === "closed")
      .length,
    safeCount,
    warningCount,
    criticalCount,
    overallAttendanceRate,
    students,
  };
}

function escapeCsvCell(value) {
  const raw = String(value ?? "");
  const safe = /^[\t\r\n ]*[=+\-@]/.test(raw) ? `'${raw}` : raw;
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
