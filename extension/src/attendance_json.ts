import { normalizeId } from './csv';
import type { AttendanceCsvRow, AttendanceStatus } from './types';

interface SessionStudent {
  rollNumber?: unknown;
  memberCode?: unknown;
  email?: unknown;
  fullName?: unknown;
  attendance?: { status?: unknown; recordedAt?: unknown; source?: unknown };
}

function requiredString(value: unknown, label: string): string {
  if (typeof value !== 'string' || !value.trim()) {
    throw new Error(`JSON thiếu ${label}.`);
  }
  return value.trim();
}

export function parseAttendanceJson(source: string): AttendanceCsvRow[] {
  let raw: unknown;
  try {
    raw = JSON.parse(source.replace(/^\uFEFF/, ''));
  } catch {
    throw new Error('File JSON không hợp lệ.');
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error('Hãy chọn file JSON của một slot, không phải workspace.json.');
  }
  const session = raw as Record<string, unknown>;
  if (session.state !== 'final') {
    throw new Error('Chỉ nhập file JSON của slot đã chốt (state: final).');
  }
  const meeting = session.meeting;
  if (!meeting || typeof meeting !== 'object' || Array.isArray(meeting)) {
    throw new Error('JSON thiếu thông tin slot.');
  }
  const slot = meeting as Record<string, unknown>;
  const startAt = requiredString(slot.startAt, 'meeting.startAt');
  const endAt = requiredString(slot.endAt, 'meeting.endAt');
  if (Number.isNaN(Date.parse(startAt)) || Number.isNaN(Date.parse(endAt))) {
    throw new Error('Ngày giờ slot trong JSON không hợp lệ.');
  }
  const students = session.attendance;
  if (!Array.isArray(students) || !students.length) {
    throw new Error('JSON không có sinh viên.');
  }
  const base = {
    schema_version: String(session.schemaVersion ?? ''),
    semester: requiredString(session.semester, 'semester'),
    course_code: requiredString(session.courseCode, 'courseCode'),
    class_code: requiredString(session.classCode, 'classCode'),
    schedule_code: requiredString(session.scheduleCode, 'scheduleCode'),
    meeting_id: requiredString(slot.id ?? session.sessionId, 'meeting.id'),
    meeting_number: String(slot.number ?? ''),
    meeting_date: startAt.slice(0, 10),
    start_time: startAt.slice(11, 16),
    end_time: endAt.slice(11, 16),
  };
  const seen = new Set<string>();
  return students.map((value: unknown, index: number) => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error(`Dòng sinh viên ${index + 1} không hợp lệ.`);
    }
    const student = value as SessionStudent;
    const roll = normalizeId(requiredString(student.rollNumber, `MSSV dòng ${index + 1}`));
    if (seen.has(roll)) throw new Error(`JSON trùng MSSV ${roll}.`);
    seen.add(roll);
    const status = student.attendance?.status;
    if (status !== 'P' && status !== 'A') {
      throw new Error(`Sinh viên ${roll} chưa có trạng thái P/A.`);
    }
    return {
      ...base,
      roll_number: roll,
      member_code: normalizeId(String(student.memberCode ?? '')),
      email: String(student.email ?? ''),
      full_name: requiredString(student.fullName, `họ tên ${roll}`),
      status: status as AttendanceStatus,
      recorded_at: String(student.attendance?.recordedAt ?? ''),
      source: String(student.attendance?.source ?? ''),
    };
  });
}
