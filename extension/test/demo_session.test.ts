import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { parseAttendanceJson } from '../src/attendance_json';

const demo = readFileSync('../demo-fap/PRN232_SE1920_M01_2026-09-07_DEMO.json', 'utf8');

describe('PRN232 SE1920 demo attendance', () => {
  it('contains a finalized slot with 36 distinct students and synthetic P/A', () => {
    const rows = parseAttendanceJson(demo);
    expect(rows).toHaveLength(36);
    expect(new Set(rows.map((row) => row.roll_number)).size).toBe(36);
    expect(rows.every((row) => row.course_code === 'PRN232' &&
      row.class_code === 'SE1920' && row.schedule_code === '13' &&
      row.meeting_date === '2026-09-07')).toBe(true);
    expect(rows.filter((row) => row.status === 'P')).toHaveLength(30);
    expect(rows.filter((row) => row.status === 'A')).toHaveLength(6);
  });
});
