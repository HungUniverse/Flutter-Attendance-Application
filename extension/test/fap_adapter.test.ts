import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { describe, expect, it } from 'vitest';
import { FapPageAdapter } from '../src/fap_adapter';
import type { AttendanceCsvRow } from '../src/types';

const html = readFileSync('test/fixtures/fap-attendance.html', 'utf8');
const base = {
  schema_version: '1', semester: 'FA26', course_code: 'PRM393',
  class_code: 'SE1917', schedule_code: '11', meeting_id: 'm1',
  meeting_number: '1', meeting_date: '2026-09-07', start_time: '07:00',
  end_time: '09:15', member_code: '', email: '', full_name: '',
  recorded_at: '', source: 'finalize'
};

describe('FapPageAdapter', () => {
  it('matches two ways and fills P/A', () => {
    const dom = new JSDOM(html);
    Object.assign(globalThis, { Event: dom.window.Event });
    const adapter = new FapPageAdapter(dom.window.document);
    const rows = [
      { ...base, roll_number: 'SE000001', status: 'P' },
      { ...base, roll_number: 'SE000002', status: 'A' },
    ] as AttendanceCsvRow[];
    expect(adapter.preview(rows).missingOnPage).toEqual([]);
    adapter.apply(rows);
    const checked = [...dom.window.document.querySelectorAll<HTMLInputElement>('input:checked')];
    expect(checked.map((control) => control.value)).toEqual(['P', 'A']);
  });

  it('blocks a missing student', () => {
    const dom = new JSDOM(html);
    const adapter = new FapPageAdapter(dom.window.document);
    const rows = [{ ...base, roll_number: 'SE999999', status: 'P' }] as AttendanceCsvRow[];
    expect(adapter.preview(rows).missingOnPage).toEqual(['SE999999']);
    expect(() => adapter.apply(rows)).toThrow(/chưa khớp/);
  });
});
