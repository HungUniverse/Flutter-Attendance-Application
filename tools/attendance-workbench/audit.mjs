import { attendanceQualityReport } from '../../backend/attendance-quality-report.mjs';
import { buildAttendanceReport } from '../../backend/attendance-report.mjs';
import { findConsecutiveAbsences } from '../../backend/attendance-streaks.mjs';
import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';

const severityOrder = { error: 0, warning: 1, info: 2 };

function rate(value, name) {
  if (!Number.isFinite(value) || value < 0 || value > 1) throw new RangeError(`${name} must be between 0 and 1`);
  return value;
}

function count(value, name, minimum = 0) {
  if (!Number.isSafeInteger(value) || value < minimum) throw new RangeError(`${name} must be an integer of at least ${minimum}`);
  return value;
}

function normalizeOptions(value = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError('options must be an object');
  return {
    minimumAttendanceRate: rate(value.minimumAttendanceRate ?? 0.6, 'minimumAttendanceRate'),
    lowSessionRate: rate(value.lowSessionRate ?? 0.4, 'lowSessionRate'),
    minimumRecordedSessions: count(value.minimumRecordedSessions ?? 2, 'minimumRecordedSessions', 1),
    maximumMissingPerStudent: count(value.maximumMissingPerStudent ?? 2, 'maximumMissingPerStudent'),
    absenceStreakLength: count(value.absenceStreakLength ?? 3, 'absenceStreakLength', 2),
  };
}

function normalized(value) {
  return String(value ?? '').normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('vi');
}

function issue(code, severity, subject, message, suggestion, details = {}) {
  return { id: `${code}:${subject}`, code, severity, subject, message, suggestion, ...details };
}

function duplicateGroups(items, keyOf) {
  const groups = new Map();
  for (const item of items) {
    const key = normalized(keyOf(item));
    if (!key) continue;
    const group = groups.get(key) ?? [];
    group.push(item);
    groups.set(key, group);
  }
  return [...groups.values()].filter((group) => group.length > 1);
}

function summarizeIssues(issues) {
  const result = { total: issues.length, error: 0, warning: 0, info: 0, byCode: {} };
  for (const item of issues) {
    result[item.severity]++;
    result.byCode[item.code] = (result.byCode[item.code] ?? 0) + 1;
  }
  return result;
}

/**
 * Review a validated attendance snapshot for incomplete data, duplicate
 * identities, low coverage and patterns a reviewer may want to inspect.
 * Findings are advisory and never modify the input snapshot.
 */
export function auditAttendanceSnapshot(snapshotValue, optionsValue = {}) {
  const snapshot = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshotValue));
  const options = normalizeOptions(optionsValue);
  const quality = attendanceQualityReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
  const reports = buildAttendanceReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
  const issues = [];

  if (snapshot.roster.length === 0) {
    issues.push(issue('empty_roster', 'warning', 'roster', 'Danh sách lớp đang trống.', 'Nhập danh sách sinh viên trước khi đối chiếu điểm danh.'));
  }
  if (snapshot.sessionIds.length === 0) {
    issues.push(issue('empty_schedule', 'warning', 'schedule', 'Chưa có buổi học nào trong bản sao.', 'Thêm buổi học hoặc nhập lịch buổi học trước khi đánh giá dữ liệu.'));
  }
  if (quality.expected > 0 && quality.recorded === 0) {
    issues.push(issue('no_recorded_results', 'warning', 'attendance', 'Chưa có kết quả điểm danh được ghi nhận.', 'Kiểm tra xem tệp điểm danh đã được nhập đúng lớp và đúng kỳ chưa.'));
  }
  if (quality.coverage !== null && quality.coverage < 1) {
    issues.push(issue('incomplete_coverage', quality.coverage < 0.5 ? 'warning' : 'info', 'attendance',
      `Còn ${quality.missing} kết quả chưa ghi trong ${quality.expected} ô điểm danh.`,
      'Xem danh sách các ô còn thiếu trước khi chốt báo cáo.',
      { missing: quality.missing, expected: quality.expected, coverage: quality.coverage }));
  }

  for (const group of duplicateGroups(snapshot.roster, (student) => student.name)) {
    const ids = group.map((student) => student.id).sort();
    issues.push(issue('duplicate_name', 'warning', ids.join(','),
      `${group.length} sinh viên có cùng tên sau khi chuẩn hóa khoảng trắng và chữ hoa.`,
      'Đối chiếu mã sinh viên và email trước khi gộp hoặc sửa hồ sơ.', { studentIds: ids, name: group[0].name }));
  }
  for (const student of quality.students) {
    const recorded = student.present + student.absent;
    if (student.missingSessionIds.length > options.maximumMissingPerStudent) {
      issues.push(issue('student_missing_results', 'warning', student.student.id,
        `${student.student.name} còn ${student.missingSessionIds.length} kết quả chưa ghi.`,
        'Đối chiếu riêng các buổi chưa có kết quả trước khi tính tỷ lệ.',
        { studentId: student.student.id, sessionIds: student.missingSessionIds, missing: student.missingSessionIds.length }));
    }
    if (recorded >= options.minimumRecordedSessions && student.present / recorded < options.minimumAttendanceRate) {
      issues.push(issue('low_student_rate', 'info', student.student.id,
        `${student.student.name} có tỷ lệ ${Math.round((student.present / recorded) * 100)}% trên kết quả đã ghi.`,
        'Kiểm tra chuỗi buổi và xác nhận các trạng thái với người phụ trách lớp.',
        { studentId: student.student.id, present: student.present, absent: student.absent,
          attendanceRate: student.present / recorded }));
    }
  }

  for (const run of findConsecutiveAbsences(snapshot.roster, snapshot.sessionIds, snapshot.records, options.absenceStreakLength)) {
    issues.push(issue('absence_streak', 'warning', `${run.student.id}:${run.sessionIds[0]}`,
      `${run.student.name} có chuỗi vắng ${run.sessionIds.length} buổi liên tiếp.`,
      'Xác nhận các buổi trong chuỗi trước khi liên hệ hoặc áp dụng quy định.',
      { studentId: run.student.id, sessionIds: run.sessionIds, length: run.sessionIds.length }));
  }

  for (const session of quality.sessions) {
    const recorded = session.present + session.absent;
    if (recorded === 0 && snapshot.roster.length > 0) {
      issues.push(issue('session_unrecorded', 'warning', session.sessionId,
        `Buổi ${session.sessionId} chưa có kết quả nào được ghi.`,
        'Kiểm tra tệp nhập và xác nhận buổi học này đã diễn ra chưa.',
        { sessionId: session.sessionId, missing: session.missingStudentIds.length }));
    } else if (recorded > 0 && session.present / recorded < options.lowSessionRate) {
      issues.push(issue('low_session_rate', 'info', session.sessionId,
        `Buổi ${session.sessionId} có tỷ lệ có mặt thấp hơn ngưỡng ${Math.round(options.lowSessionRate * 100)}%.`,
        'Kiểm tra lại trạng thái của buổi nếu số liệu khác thường.',
        { sessionId: session.sessionId, present: session.present, absent: session.absent,
          attendanceRate: session.present / recorded }));
    }
  }

  issues.sort((left, right) => severityOrder[left.severity] - severityOrder[right.severity] ||
    left.code.localeCompare(right.code) || left.subject.localeCompare(right.subject));
  return {
    version: 1,
    options,
    summary: summarizeIssues(issues),
    context: {
      students: snapshot.roster.length,
      sessions: snapshot.sessionIds.length,
      expected: quality.expected,
      recorded: quality.recorded,
      missing: quality.missing,
      coverage: quality.coverage,
    },
    issues,
  };
}

/** Export audit findings without embedding the full roster or attendance table. */
export function auditToCsv(report) {
  if (!report || report.version !== 1 || !Array.isArray(report.issues)) throw new TypeError('invalid audit report');
  const csvCell = (value) => {
    let textValue = String(value ?? '');
    if (/^[\t\r\n ]*[=+\-@]/.test(textValue)) textValue = `'${textValue}`;
    return `"${textValue.replaceAll('"', '""')}"`;
  };
  const header = ['severity', 'code', 'subject', 'message', 'suggestion', 'studentId', 'sessionId', 'sessionIds'];
  const rows = report.issues.map((item) => [item.severity, item.code, item.subject, item.message, item.suggestion,
    item.studentId ?? (item.studentIds ?? []).join(';'), item.sessionId ?? '', (item.sessionIds ?? []).join(';')]);
  return [header, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n') + '\r\n';
}
