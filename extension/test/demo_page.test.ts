import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { describe, expect, it } from 'vitest';
import { FapPageAdapter } from '../src/fap_adapter';
import { parseAttendanceJson } from '../src/attendance_json';

const html = readFileSync('../demo-fap/index.html', 'utf8');
const script = readFileSync('../demo-fap/app.js', 'utf8');
const session = JSON.parse(readFileSync('../demo-fap/sample-session.json', 'utf8'));
const secondSession = JSON.parse(readFileSync('../demo-fap/PRN232_SE1920_M01_2026-09-07_DEMO.json', 'utf8'));
const markbook = {
  classes: [session, secondSession].map((item) => ({
    courseCode: item.courseCode,
    classCode: item.classCode,
    scheduleCode: item.scheduleCode,
    students: item.attendance,
    meetings: [item.meeting],
  })),
};

function openClass(dom: JSDOM, index: number): void {
  dom.window.document.querySelectorAll<HTMLButtonElement>('.class-card')[index].click();
}

describe('FAP demo page', () => {
  it('counts every unmarked student as Absent when submitting', async () => {
    const dom = new JSDOM(html, { url: 'http://localhost:4173/', runScripts: 'outside-only' });
    dom.window.fetch = async () => ({ ok: true, json: async () => markbook } as Response);
    dom.window.eval(script);
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(dom.window.document.querySelector('#dashboardView')?.hasAttribute('hidden')).toBe(false);
    expect(dom.window.document.querySelectorAll('.class-card')).toHaveLength(2);
    openClass(dom, 0);
    const checkboxes = dom.window.document.querySelectorAll('#students input[type=checkbox]');
    expect(checkboxes).toHaveLength(session.attendance.length);
    expect(dom.window.document.querySelector('#summary')?.textContent).toBe(`P: 0 · A: ${session.attendance.length}`);
    dom.window.document.querySelector<HTMLButtonElement>('#submit')!.click();
    const submitted = JSON.parse(dom.window.localStorage.getItem('fap-demo-last-submit')!);
    expect(submitted.statuses.map((item: { status: string }) => item.status))
      .toEqual(Array(session.attendance.length).fill('A'));
    expect(dom.window.document.querySelector('#finalizedBanner')?.hasAttribute('hidden')).toBe(false);
    dom.window.document.querySelector<HTMLButtonElement>('#returnDashboard')!.click();
    expect(dom.window.document.querySelector('#dashboardView')?.hasAttribute('hidden')).toBe(false);
    expect(dom.window.document.querySelector('#classView')?.hasAttribute('hidden')).toBe(true);
    expect(dom.window.document.querySelector('#dashboardFinalizedCount')?.textContent).toBe('1');
    openClass(dom, 0);
    expect(dom.window.document.querySelector('#finalizedBanner')?.hasAttribute('hidden')).toBe(false);
    expect([...dom.window.document.querySelectorAll<HTMLInputElement>('#students input[type=checkbox]')]
      .every((item) => item.disabled)).toBe(true);
    dom.window.close();
  });

  it('opens each class from the dashboard', async () => {
    const dom = new JSDOM(html, { url: 'http://localhost:4173/', runScripts: 'outside-only' });
    dom.window.fetch = async () => ({ ok: true, json: async () => markbook } as Response);
    dom.window.eval(script);
    await new Promise((resolve) => setTimeout(resolve, 0));
    openClass(dom, 1);
    expect(dom.window.document.querySelector('#classHeading')?.textContent).toBe('PRN232 · SE1920');
    expect(dom.window.document.querySelectorAll('#students tr')).toHaveLength(36);
    dom.window.document.querySelector<HTMLButtonElement>('#backDashboard')!.click();
    expect(dom.window.document.querySelector('#dashboardView')?.hasAttribute('hidden')).toBe(false);
    dom.window.close();
  });

  it('fills and finalizes the 36-student PRN232 SE1920 demo slot', async () => {
    const dom = new JSDOM(html, { url: 'http://localhost:4173/', runScripts: 'outside-only' });
    dom.window.fetch = async () => ({ ok: true, json: async () => markbook } as Response);
    dom.window.eval(script);
    await new Promise((resolve) => setTimeout(resolve, 0));
    Object.assign(globalThis, {
      Event: dom.window.Event,
      MutationObserver: dom.window.MutationObserver,
    });
    openClass(dom, 1);
    const adapter = new FapPageAdapter(dom.window.document);
    const rows = parseAttendanceJson(JSON.stringify(secondSession));
    expect(adapter.preview(rows).metadataWarnings).toEqual([]);
    expect(adapter.preview(rows).missingOnPage).toEqual([]);
    adapter.apply(rows);
    expect(dom.window.document.querySelector('#summary')?.textContent).toBe('P: 30 · A: 6');
    expect(await adapter.submit()).toBe(true);
    expect(dom.window.document.querySelector('#finalizedBanner')?.hasAttribute('hidden')).toBe(false);
    expect(dom.window.document.querySelector('#dashboardFinalizedCount')?.textContent).toBe('1');
    dom.window.close();
  });

  it('builds columns in the requested order and fills JSON without submitting', async () => {
    const dom = new JSDOM(html, { url: 'http://localhost:4173/', runScripts: 'outside-only' });
    dom.window.fetch = async () => ({ ok: true, json: async () => markbook } as Response);
    dom.window.eval(script);
    await new Promise((resolve) => setTimeout(resolve, 0));
    openClass(dom, 0);
    Object.assign(globalThis, {
      Event: dom.window.Event,
      MutationObserver: dom.window.MutationObserver,
    });
    const headers = [...dom.window.document.querySelectorAll('th')].map((item) => item.textContent);
    expect(headers).toEqual(['MSSV', 'FULLNAME', 'Ô ĐIỂM DANH', 'HÌNH THẺ SINH VIÊN']);
    const adapter = new FapPageAdapter(dom.window.document);
    const rows = parseAttendanceJson(JSON.stringify(session));
    expect(adapter.preview(rows).missingOnPage).toEqual([]);
    expect(adapter.preview(rows).missingInCsv).toEqual([]);
    expect(adapter.preview(rows).metadataWarnings).toEqual([]);
    adapter.apply(rows);
    const checkboxes = [...dom.window.document.querySelectorAll<HTMLInputElement>('#students input[type=checkbox]')];
    expect(checkboxes.map((item) => item.checked)).toEqual([true, false, true]);
    expect(dom.window.document.querySelector('#summary')?.textContent).toBe('P: 2 · A: 1');
    expect(dom.window.localStorage.getItem('fap-demo-last-submit')).toBeNull();
    expect(await adapter.submit()).toBe(true);
    const submitted = JSON.parse(dom.window.localStorage.getItem('fap-demo-last-submit')!);
    expect(submitted.statuses.map((item: { status: string }) => item.status)).toEqual(['P', 'A', 'P']);
    expect(adapter.preview(rows).metadataWarnings).toContain('Slot này đã chốt danh sách; không thể điền lại.');
    dom.window.close();
  });
});
