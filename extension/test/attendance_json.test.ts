import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { parseAttendanceJson } from '../src/attendance_json';

const sample = readFileSync('../demo-fap/sample-session.json', 'utf8');

describe('session JSON import', () => {
  it('maps a finalized desktop session to P/A rows', () => {
    const rows = parseAttendanceJson(sample);
    expect(rows).toHaveLength(3);
    expect(rows.map((row) => row.status)).toEqual(['P', 'A', 'P']);
    expect(rows[0]).toMatchObject({
      class_code: 'SE1917',
      meeting_date: '2026-09-07',
      roll_number: 'SE000001',
    });
  });

  it('rejects an open or incomplete session', () => {
    const open = JSON.parse(sample);
    open.state = 'working';
    expect(() => parseAttendanceJson(JSON.stringify(open))).toThrow(/đã chốt/);
    open.state = 'final';
    open.attendance[0].attendance.status = '';
    expect(() => parseAttendanceJson(JSON.stringify(open))).toThrow(/P\/A/);
  });

  it('rejects duplicate student IDs', () => {
    const duplicate = JSON.parse(sample);
    duplicate.attendance[1].rollNumber = duplicate.attendance[0].rollNumber;
    expect(() => parseAttendanceJson(JSON.stringify(duplicate))).toThrow(/trùng MSSV/);
  });
});
