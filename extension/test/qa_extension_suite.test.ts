import { JSDOM } from 'jsdom';
import { describe, expect, it } from 'vitest';
import { parseAttendanceJson } from '../src/attendance_json';
import { normalizeId, parseAttendanceCsv } from '../src/csv';
import { FapPageAdapter } from '../src/fap_adapter';
import type { AttendanceCsvRow } from '../src/types';

const validCsvHeader =
  'schema_version,semester,course_code,class_code,schedule_code,meeting_id,meeting_number,meeting_date,start_time,end_time,roll_number,member_code,email,full_name,status,recorded_at,source';

describe('QA Extension Suite — CSV Parser', () => {
  it('parses valid attendance CSV with BOM, whitespace lines, and formula-escaped cells', () => {
    const csv = [
      `\uFEFF${validCsvHeader}`,
      `1,fa26,prm393,se1917,11,m1,1,2026-09-07,07:30,09:15,se000001,mem001,s1@fpt.edu.vn,"'=Nguyen Van A",p,2026-09-07T07:35:00Z,scan`,
      `1,FA26,PRM393,SE1917,11,m1,1,2026-09-07,07:30,09:15,SE000002,MEM002,s2@fpt.edu.vn,"'+Tran Thi B",a,2026-09-07T09:15:00Z,finalize`,
      '   ',
    ].join('\r\n');

    const rows = parseAttendanceCsv(csv);
    expect(rows).toHaveLength(2);
    expect(rows[0].semester).toBe('FA26');
    expect(rows[0].course_code).toBe('PRM393');
    expect(rows[0].class_code).toBe('SE1917');
    expect(rows[0].roll_number).toBe('SE000001');
    expect(rows[0].member_code).toBe('MEM001');
    expect(rows[0].full_name).toBe('=Nguyen Van A');
    expect(rows[0].status).toBe('P');
    expect(rows[1].full_name).toBe('+Tran Thi B');
    expect(rows[1].status).toBe('A');
  });

  it('rejects missing required headers or empty student rows', () => {
    expect(() => parseAttendanceCsv('roll_number,status\nSE000001,P')).toThrow(/thiếu cột bắt buộc/);
    expect(() => parseAttendanceCsv(`${validCsvHeader}\n   \n`)).toThrow(/không có sinh viên/);
  });

  it('rejects blank class/meeting metadata, invalid status, duplicate roll, and mixed meetings', () => {
    const blankClass = [
      validCsvHeader,
      '1,FA26,PRM393, ,11,m1,1,2026-09-07,07:30,09:15,SE000001,,s1@fpt.edu.vn,An,P,,scan',
    ].join('\n');
    expect(() => parseAttendanceCsv(blankClass)).toThrow(/thiếu thông tin lớp/);

    const badStatus = [
      validCsvHeader,
      '1,FA26,PRM393,SE1917,11,m1,1,2026-09-07,07:30,09:15,SE000001,,s1@fpt.edu.vn,An,X,,scan',
    ].join('\n');
    expect(() => parseAttendanceCsv(badStatus)).toThrow(/không hợp lệ/);

    const duplicateRoll = [
      validCsvHeader,
      '1,FA26,PRM393,SE1917,11,m1,1,2026-09-07,07:30,09:15,SE000001,,s1@fpt.edu.vn,An,P,,scan',
      '1,FA26,PRM393,SE1917,11,m1,1,2026-09-07,07:30,09:15,se000001,,s2@fpt.edu.vn,Binh,A,,scan',
    ].join('\n');
    expect(() => parseAttendanceCsv(duplicateRoll)).toThrow(/trùng MSSV SE000001/);

    const mixedMeetings = [
      validCsvHeader,
      '1,FA26,PRM393,SE1917,11,m1,1,2026-09-07,07:30,09:15,SE000001,,s1@fpt.edu.vn,An,P,,scan',
      '1,FA26,PRM393,SE1917,11,m2,2,2026-09-10,07:30,09:15,SE000002,,s2@fpt.edu.vn,Binh,A,,scan',
    ].join('\n');
    expect(() => parseAttendanceCsv(mixedMeetings)).toThrow(/một lớp và một buổi/);
  });

  it('normalizes IDs by trimming and uppercasing', () => {
    expect(normalizeId('  se193324 ')).toBe('SE193324');
  });
});

describe('QA Extension Suite — JSON Parser Edge Cases', () => {
  const baseSession = () => ({
    schemaVersion: 1,
    state: 'final',
    semester: 'FA26',
    courseCode: 'PRM393',
    classCode: 'SE1917',
    scheduleCode: '11',
    meeting: {
      id: 'SE1917-m1',
      number: 1,
      startAt: '2026-09-07T07:30:00.000',
      endAt: '2026-09-07T09:15:00.000',
    },
    attendance: [
      {
        rollNumber: 'se000001',
        memberCode: 'mem01',
        email: 's1@fpt.edu.vn',
        fullName: 'Nguyen Van A',
        attendance: { status: ' p ', recordedAt: '2026-09-07T07:35:00.000', source: 'scan' },
      },
    ],
  });

  it('accepts lowercase/trimmed status and BOM-prefixed JSON', () => {
    const rows = parseAttendanceJson(`\uFEFF${JSON.stringify(baseSession())}`);
    expect(rows).toHaveLength(1);
    expect(rows[0].roll_number).toBe('SE000001');
    expect(rows[0].member_code).toBe('MEM01');
    expect(rows[0].status).toBe('P');
  });

  it('rejects non-existent calendar dates and inverted slot intervals', () => {
    const feb30 = baseSession();
    feb30.meeting.startAt = '2026-02-30T07:30:00.000';
    feb30.meeting.endAt = '2026-02-30T09:15:00.000';
    expect(() => parseAttendanceJson(JSON.stringify(feb30))).toThrow(/Ngày giờ slot/);

    const inverted = baseSession();
    inverted.meeting.startAt = '2026-09-07T09:15:00.000';
    inverted.meeting.endAt = '2026-09-07T07:30:00.000';
    expect(() => parseAttendanceJson(JSON.stringify(inverted))).toThrow(/Ngày giờ slot/);
  });

  it('rejects malformed JSON, arrays, missing meeting, and empty attendance arrays', () => {
    expect(() => parseAttendanceJson('{bad')).toThrow(/không hợp lệ/);
    expect(() => parseAttendanceJson('[]')).toThrow(/workspace\.json/);
    const noMeeting = baseSession() as Record<string, unknown>;
    delete noMeeting.meeting;
    expect(() => parseAttendanceJson(JSON.stringify(noMeeting))).toThrow(/thiếu thông tin slot/);
    const emptyStudents = baseSession();
    emptyStudents.attendance = [];
    expect(() => parseAttendanceJson(JSON.stringify(emptyStudents))).toThrow(/không có sinh viên/);
  });
});

describe('QA Extension Suite — FapPageAdapter Controls & Warnings', () => {
  const makeRow = (overrides: Partial<AttendanceCsvRow> = {}): AttendanceCsvRow => ({
    schema_version: '1',
    semester: 'FA26',
    course_code: 'PRM393',
    class_code: 'SE1917',
    schedule_code: '11',
    meeting_id: 'm1',
    meeting_number: '1',
    meeting_date: '2026-09-07',
    start_time: '07:30',
    end_time: '09:15',
    roll_number: 'SE000001',
    member_code: 'MEM001',
    email: 's1@fpt.edu.vn',
    full_name: 'Student One',
    status: 'P',
    recorded_at: '',
    source: 'finalize',
    ...overrides,
  });

  it('handles empty CSV preview gracefully without throwing', () => {
    const dom = new JSDOM('<table><tr><td>SE000001</td></tr></table>');
    const adapter = new FapPageAdapter(dom.window.document);
    const preview = adapter.preview([]);
    expect(preview.csvCount).toBe(0);
    expect(preview.pageCount).toBe(1);
    expect(preview.metadataWarnings).toContain('Danh sách điểm danh trống.');
  });

  it('does not confuse 6-digit student roll numbers with 4-digit class codes', () => {
    const dom = new JSDOM(`
      <main>
        <table>
          <tr><td>SE000001</td><td><input type="checkbox" value="P"></td></tr>
        </table>
      </main>
    `);
    const adapter = new FapPageAdapter(dom.window.document);
    const preview = adapter.preview([makeRow({ class_code: 'SE1917-G1' })]);
    expect(preview.metadataWarnings).toEqual([]);
  });

  it('supports select dropdown controls and member_code fallback matching', () => {
    const dom = new JSDOM(`
      <main data-attendance-class="SE1917" data-attendance-date="2026-09-07" data-attendance-slot="1">
        <table>
          <tr>
            <td>HE190001</td>
            <td>
              <select>
                <option value="">--</option>
                <option value="Present">Có mặt</option>
                <option value="Absent">Vắng</option>
              </select>
            </td>
          </tr>
        </table>
      </main>
    `);
    Object.assign(globalThis, { Event: dom.window.Event });
    const adapter = new FapPageAdapter(dom.window.document);
    const rows = [
      makeRow({
        roll_number: 'SE000001',
        member_code: 'he190001',
        status: 'A',
      }),
    ];
    expect(adapter.preview(rows).missingOnPage).toEqual([]);
    expect(adapter.preview(rows).missingInCsv).toEqual([]);
    adapter.apply(rows);
    const select = dom.window.document.querySelector('select')!;
    expect(select.value).toBe('Absent');
  });

  it('detects class, date, slot, and finalized metadata warnings', () => {
    const dom = new JSDOM(`
      <main
        data-attendance-class="SE1999"
        data-attendance-date="2026-09-08"
        data-attendance-slot="3"
        data-attendance-finalized="true">
        <table>
          <tr><td>SE000001</td><td><input type="checkbox" value="P"></td></tr>
        </table>
      </main>
    `);
    const adapter = new FapPageAdapter(dom.window.document);
    const preview = adapter.preview([makeRow()]);
    expect(preview.metadataWarnings).toHaveLength(4);
    expect(preview.metadataWarnings.join(' ')).toMatch(/đã chốt/);
    expect(preview.metadataWarnings.join(' ')).toMatch(/SE1999/);
    expect(preview.metadataWarnings.join(' ')).toMatch(/2026-09-08/);
    expect(preview.metadataWarnings.join(' ')).toMatch(/slot 3/);
  });
});
