import { parseAttendanceCsv } from './csv';
import { parseAttendanceJson } from './attendance_json';
import { pickCsvFromDrive } from './drive_picker';
import type { AttendanceCsvRow, MappingPreview } from './types';

const file = document.querySelector<HTMLInputElement>('#attendanceFile')!;
const drive = document.querySelector<HTMLButtonElement>('#driveFile')!;
const previewElement = document.querySelector<HTMLElement>('#preview')!;
const confirmRow = document.querySelector<HTMLElement>('#confirmRow')!;
const confirm = document.querySelector<HTMLInputElement>('#confirm')!;
const autoSubmitRow = document.querySelector<HTMLElement>('#autoSubmitRow')!;
const autoSubmit = document.querySelector<HTMLInputElement>('#autoSubmit')!;
const submit = document.querySelector<HTMLButtonElement>('#submit')!;
const status = document.querySelector<HTMLElement>('#status')!;
let rows: AttendanceCsvRow[] = [];

file.addEventListener('change', async () => {
  const selected = file.files?.[0];
  if (!selected) return;
  resetSelection();
  try {
    const source = await selected.text();
    await prepare(selected.name.toLowerCase().endsWith('.json')
      ? parseAttendanceJson(source) : parseAttendanceCsv(source));
  } catch (error) { fail(error); }
});
drive.addEventListener('click', async () => {
  resetSelection();
  try { await prepare(parseAttendanceCsv(await pickCsvFromDrive())); } catch (error) { fail(error); }
});
confirm.addEventListener('change', () => submit.disabled = !confirm.checked);
submit.addEventListener('click', async () => {
  submit.disabled = true;
  status.textContent = 'Đang điền và kiểm tra lại từng dòng…';
  try {
    const result = await send({ type: 'apply', rows, autoSubmit: autoSubmit.checked });
    if (result.error) throw new Error(result.error);
    status.textContent = !result.submitted
      ? 'Đã điền P/A và kiểm tra lại. Chưa bấm Submit; GV hãy kiểm tra rồi tự bấm trên trang.'
      : result.success
        ? 'Trang điểm danh đã báo lưu thành công.'
        : 'Đã bấm Submit nhưng chưa thấy xác nhận thành công; hãy kiểm tra trang.';
    status.className = result.success || !result.submitted ? 'ok' : '';
  } catch (error) { fail(error); }
});

async function prepare(parsedRows: AttendanceCsvRow[]): Promise<void> {
  status.textContent = '';
  status.className = '';
  rows = parsedRows;
  const result = await send({ type: 'preview', rows });
  if (result.error) throw new Error(result.error);
  const value = result as MappingPreview;
  const blocking = value.missingOnPage.length || value.missingInCsv.length ||
    value.duplicates.length || value.metadataWarnings.length;
  previewElement.hidden = false;
  previewElement.innerHTML = `
    <strong>${escape(rows[0].course_code)} · ${escape(rows[0].class_code)}</strong><br>
    Slot ${escape(rows[0].meeting_number)} · ${escape(rows[0].meeting_date)}<br>
    ${value.csvCount} sinh viên · P: ${value.present} · A: ${value.absent}<br>
    ${blocking ? '<b>Dữ liệu chưa khớp:</b> ' + escape([
      ...value.missingOnPage.map((id) => `thiếu trên FAP ${id}`),
      ...value.missingInCsv.map((id) => `thiếu trong file ${id}`),
      ...value.duplicates.map((id) => `trùng ${id}`),
      ...value.metadataWarnings,
    ].join('; ')) : 'Đối chiếu hai chiều thành công.'}`;
  confirmRow.hidden = Boolean(blocking);
  autoSubmitRow.hidden = Boolean(blocking);
  confirm.checked = false;
  autoSubmit.checked = false;
  submit.disabled = true;
}

async function send(message: unknown): Promise<any> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const url = tab.url ? new URL(tab.url) : null;
  const allowed = url && (url.origin === 'https://fap.fpt.edu.vn' ||
    (url.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(url.hostname)));
  if (!tab.id || !allowed) {
    throw new Error('Hãy mở trang điểm danh FAP hoặc trang demo localhost.');
  }
  return chrome.tabs.sendMessage(tab.id, message);
}

function fail(error: unknown): void {
  status.textContent = String(error).replace('Error: ', '');
  status.className = '';
}

function resetSelection(): void {
  rows = [];
  previewElement.hidden = true;
  confirmRow.hidden = true;
  autoSubmitRow.hidden = true;
  confirm.checked = false;
  autoSubmit.checked = false;
  submit.disabled = true;
}

function escape(value: string): string {
  const node = document.createElement('span');
  node.textContent = value;
  return node.innerHTML;
}
