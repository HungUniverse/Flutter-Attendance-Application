import Papa from 'papaparse';
import type { AttendanceCsvRow } from './types';

const required = [
  'semester', 'course_code', 'class_code', 'meeting_id', 'meeting_date',
  'roll_number', 'status'
] as const;

export function parseAttendanceCsv(source: string): AttendanceCsvRow[] {
  const result = Papa.parse<AttendanceCsvRow>(source.replace(/^\uFEFF/, ''), {
    header: true,
    skipEmptyLines: true,
  });
  if (result.errors.length) throw new Error(result.errors[0].message);
  if (!result.meta.fields || required.some((key) => !result.meta.fields!.includes(key))) {
    throw new Error('CSV thiếu cột bắt buộc hoặc sai schema.');
  }
  if (!result.data.length) throw new Error('CSV không có sinh viên.');
  const first = result.data[0];
  const seen = new Set<string>();
  for (const row of result.data) {
    row.roll_number = normalizeId(row.roll_number);
    row.member_code = normalizeId(row.member_code ?? '');
    row.status = row.status?.trim().toUpperCase() as AttendanceCsvRow['status'];
    if (!row.roll_number || !['P', 'A'].includes(row.status)) {
      throw new Error('CSV chứa MSSV hoặc trạng thái không hợp lệ.');
    }
    if (seen.has(row.roll_number)) throw new Error(`CSV trùng MSSV ${row.roll_number}.`);
    seen.add(row.roll_number);
    if (row.class_code !== first.class_code || row.meeting_id !== first.meeting_id ||
        row.meeting_date !== first.meeting_date || row.schedule_code !== first.schedule_code) {
      throw new Error('Một CSV chỉ được chứa một lớp và một buổi.');
    }
  }
  return result.data;
}

export const normalizeId = (value: string): string => value.trim().toUpperCase();
