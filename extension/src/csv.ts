import Papa from 'papaparse';
import type { AttendanceCsvRow } from './types';

const required = [
  'semester', 'course_code', 'class_code', 'meeting_id', 'meeting_date',
  'roll_number', 'status'
] as const;

export function stripFormulaPrefix(value: string): string {
  const candidate = value.startsWith("'") ? value : value.trim();
  if (
    candidate.startsWith("'") &&
    /^'(?:[\t\r]|[\t\r\n ]*[=+\-@])/.test(candidate)
  ) {
    return candidate.slice(1).trim();
  }
  return candidate.trim();
}

export function parseAttendanceCsv(source: string): AttendanceCsvRow[] {
  const result = Papa.parse<AttendanceCsvRow>(source.replace(/^\uFEFF/, ''), {
    header: true,
    skipEmptyLines: 'greedy',
  });
  if (result.errors.length) throw new Error(result.errors[0].message);
  if (!result.meta.fields || required.some((key) => !result.meta.fields!.includes(key))) {
    throw new Error('CSV thiếu cột bắt buộc hoặc sai schema.');
  }
  if (!result.data.length) throw new Error('CSV không có sinh viên.');
  const seen = new Set<string>();
  for (const row of result.data) {
    row.semester = stripFormulaPrefix(String(row.semester ?? '')).toUpperCase();
    row.course_code = stripFormulaPrefix(String(row.course_code ?? '')).toUpperCase();
    row.class_code = stripFormulaPrefix(String(row.class_code ?? '')).toUpperCase();
    row.schedule_code = stripFormulaPrefix(String(row.schedule_code ?? ''));
    row.meeting_id = stripFormulaPrefix(String(row.meeting_id ?? ''));
    row.meeting_number = stripFormulaPrefix(String(row.meeting_number ?? ''));
    row.meeting_date = stripFormulaPrefix(String(row.meeting_date ?? ''));
    row.full_name = stripFormulaPrefix(String(row.full_name ?? ''));
    row.email = stripFormulaPrefix(String(row.email ?? ''));
    row.roll_number = normalizeId(stripFormulaPrefix(String(row.roll_number ?? '')));
    row.member_code = normalizeId(stripFormulaPrefix(String(row.member_code ?? '')));
    row.status = stripFormulaPrefix(String(row.status ?? '')).toUpperCase() as AttendanceCsvRow['status'];
    if (!row.semester || !row.course_code || !row.class_code || !row.meeting_id || !row.meeting_date) {
      throw new Error('CSV thiếu thông tin lớp hoặc buổi học bắt buộc.');
    }
    if (!row.roll_number || !['P', 'A'].includes(row.status)) {
      throw new Error('CSV chứa MSSV hoặc trạng thái không hợp lệ.');
    }
    if (seen.has(row.roll_number)) throw new Error(`CSV trùng MSSV ${row.roll_number}.`);
    seen.add(row.roll_number);
  }
  const first = result.data[0];
  for (const row of result.data) {
    if (row.class_code !== first.class_code || row.meeting_id !== first.meeting_id ||
        row.meeting_date !== first.meeting_date || row.schedule_code !== first.schedule_code) {
      throw new Error('Một CSV chỉ được chứa một lớp và một buổi.');
    }
  }
  return result.data;
}

export const normalizeId = (value: string): string => value.trim().toUpperCase();
