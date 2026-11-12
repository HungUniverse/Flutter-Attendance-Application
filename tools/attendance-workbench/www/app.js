import { createAttendanceSnapshot, parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../../backend/attendance-snapshot.mjs';
import { compareAttendanceSnapshots, hasSnapshotChanges } from '../../../backend/attendance-snapshot-diff.mjs';
import { buildAttendanceReport } from '../../../backend/attendance-report.mjs';
import { attendanceQualityReport } from '../../../backend/attendance-quality-report.mjs';
import { rollingAttendance } from '../../../backend/attendance-trends.mjs';
import { findConsecutiveAbsences } from '../../../backend/attendance-streaks.mjs';
import { forecastRoster } from '../../../backend/attendance-forecast.mjs';
import { attendanceToCsv } from '../../../backend/attendance-analytics.mjs';
import { compareAttendanceSnapshots } from '../../../backend/attendance-snapshot-diff.mjs';
import { applyAttendanceBatch } from '../../../backend/attendance-batch.mjs';
import { importAttendanceCsv } from '../../../backend/attendance-csv-import.mjs';
import { importRosterCsv } from '../../../backend/roster-csv-import.mjs';
import { generateRecurringSessions } from '../../../backend/session-recurrence.mjs';
import { findScheduleConflicts } from '../../../backend/session-schedule.mjs';
import { sessionsToICalendar } from '../../../backend/session-icalendar.mjs';
import { evaluatePolicy } from '../policy.mjs';
import { renderHtmlReport } from '../html-report.mjs';
import { createBundle, parseBundle, putClass, removeClass, summarizeBundle, summarizeStudentsAcrossClasses } from '../bundle.mjs';
import { reviseSnapshot } from '../revise.mjs';

const labels = {
  overview: ['TỔNG QUAN', 'Tổng quan'],
  attendance: ['BẢNG ĐIỂM DANH', 'Điểm danh'],
  students: ['DANH SÁCH LỚP', 'Sinh viên'],
  sessions: ['LỊCH HỌC', 'Buổi học'],
  analysis: ['PHÂN TÍCH', 'Phân tích'],
};
const state = {
  snapshot: null,
  savedSnapshotText: null,
  history: [],
  future: [],
  view: 'overview',
  search: '',
  statusFilter: 'all',
  sort: 'name',
  page: 0,
  pageSize: 12,
  bundle: createBundle(),
  bundleCurrentId: null,
  schedule: [],
  policy: { minimumRate: 0.75, maximumAbsences: 2 },
};

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const esc = (value) => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
const initials = (name) => name.trim().split(/\s+/).slice(-2).map((part) => part[0]?.toUpperCase() ?? '').join('');
const ratePercent = (rate) => rate === null ? '—' : `${(rate * 100).toFixed(0)}%`;
const sessionName = (id) => id.length > 17 ? `${id.slice(0, 15)}…` : id;

function notify(message, type = 'success') {
  const item = document.createElement('div');
  item.className = `toast${type === 'error' ? ' error' : ''}`;
  item.textContent = message;
  $('#toast-region').append(item);
  setTimeout(() => item.remove(), 3600);
}

function showError(error) {
  notify(error instanceof Error ? error.message : String(error), 'error');
}

function download(filename, content, mime = 'application/json;charset=utf-8') {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function snapshotFilename() {
  const date = new Date().toISOString().slice(0, 10);
  return `attendance-snapshot-${date}.json`;
}

function loadSnapshot(value, message = 'Đã mở bản sao điểm danh.') {
  state.snapshot = parseAttendanceSnapshot(typeof value === 'string' ? value : JSON.stringify(value));
  state.savedSnapshotText = serializeAttendanceSnapshot(state.snapshot);
  state.history = [];
  state.future = [];
  state.page = 0;
  state.search = '';
  state.statusFilter = 'all';
  $('#empty-state').hidden = true;
  $('#loaded-workspace').hidden = false;
  $('#download-snapshot').disabled = false;
  updateHistoryControls();
  $('#page-subtitle').textContent = `${state.snapshot.roster.length} sinh viên · ${state.snapshot.sessionIds.length} buổi học`;
  render();
  notify(message);
}

function showDialog(content, afterRender = () => {}) {
  $('#modal-content').innerHTML = content;
  $('#modal').showModal();
  afterRender();
}

function closeDialog() {
  $('#modal').close();
}

function heading(title, description = '', right = '') {
  return `<div class="panel-heading"><div><h2>${esc(title)}</h2>${description ? `<p>${esc(description)}</p>` : ''}</div>${right}</div>`;
}

function panel(title, content, options = {}) {
  const headingHtml = title ? heading(title, options.description ?? '', options.right ?? '') : '';
  return `<section class="panel">${headingHtml}${content}</section>`;
}

function metric(title, value, suffix, symbol) {
  return `<article class="metric-card"><div class="metric-top"><span>${title}</span><span class="metric-symbol">${symbol}</span></div><strong>${value}<small>${suffix}</small></strong></article>`;
}

function personCell(student, subtitle = student.email) {
  return `<div class="table-person"><span class="avatar">${esc(initials(student.name))}</span><span class="person-copy"><strong>${esc(student.name)}</strong><small>${esc(subtitle)}</small></span></div>`;
}

function percentBar(rate) {
  if (rate === null) return '<span class="rate-cell"><span class="rate-value">—</span></span>';
  const value = Math.max(0, Math.min(100, rate * 100));
  return `<span class="rate-cell"><span class="rate-track"><span class="rate-fill${value < 60 ? ' is-low' : ''}" style="display:block;width:${value}%"></span></span><span class="rate-value">${value.toFixed(0)}%</span></span>`;
}

function statusBadge(status) {
  const names = { present: 'Có mặt', absent: 'Vắng', missing: 'Chưa ghi', pass: 'Đạt', fail: 'Chưa đạt', undetermined: 'Chưa đủ dữ liệu' };
  const key = ['present', 'absent', 'missing', 'pass', 'fail', 'undetermined'].includes(status) ? status : 'neutral';
  return `<span class="status-pill status-${key}">${names[status] ?? esc(status)}</span>`;
}

function emptyInline(message) {
  return `<div class="empty-inline">${esc(message)}</div>`;
}

function report() {
  const data = state.snapshot;
  return attendanceQualityReport(data.roster, data.sessionIds, data.records);
}

function attendanceReport() {
  return buildAttendanceReport(state.snapshot.roster, state.snapshot.sessionIds, state.snapshot.records);
}

function setView(view) {
  state.view = view;
  state.page = 0;
  $$('.nav-item').forEach((item) => item.classList.toggle('is-active', item.dataset.view === view));
  render();
}

function render() {
  if (!state.snapshot) return;
  const [eyebrow, title] = labels[state.view];
  $('#page-eyebrow').textContent = eyebrow;
  $('#page-title').textContent = title;
  $('#page-subtitle').textContent = `${state.snapshot.roster.length} sinh viên · ${state.snapshot.sessionIds.length} buổi học`;
  const content = $('#view-content');
  const renderers = {
    overview: renderOverview,
    attendance: renderAttendance,
    students: renderStudents,
    sessions: renderSessions,
    analysis: renderAnalysis,
  };
  content.innerHTML = renderers[state.view]();
  updateHistoryControls();
  bindViewActions(content);
}

function commitSnapshot(next, description) {
  const validated = parseAttendanceSnapshot(serializeAttendanceSnapshot(next));
  state.history.push({ snapshot: state.snapshot, description });
  if (state.history.length > 100) state.history.shift();
  state.future = [];
  state.snapshot = validated;
  updateHistoryControls();
}

function updateHistoryControls() {
  const dirty = state.snapshot && serializeAttendanceSnapshot(state.snapshot) !== state.savedSnapshotText;
  const indicator = $('#dirty-indicator');
  if (indicator) indicator.hidden = !dirty;
  const undo = $('#undo-action');
  const redo = $('#redo-action');
  if (undo) undo.disabled = !state.history.length;
  if (redo) redo.disabled = !state.future.length;
  const downloadButton = $('#download-snapshot');
  if (downloadButton) downloadButton.disabled = !state.snapshot;
}

function undo() {
  const previous = state.history.pop();
  if (!previous) return;
  state.future.push({ snapshot: state.snapshot, description: previous.description });
  state.snapshot = previous.snapshot;
  render();
  notify(`Đã hoàn tác: ${previous.description}`);
}

function redo() {
  const next = state.future.pop();
  if (!next) return;
  state.history.push({ snapshot: state.snapshot, description: next.description });
  state.snapshot = next.snapshot;
  render();
  notify(`Đã làm lại: ${next.description}`);
}

function renderOverview() {
  const current = report();
  const rate = current.recorded ? current.validRate ?? null : null;
  const totalPresent = current.students.reduce((sum, student) => sum + student.present, 0);
  const totalAbsences = current.students.reduce((sum, student) => sum + student.absent, 0);
  const actualRate = totalPresent + totalAbsences ? totalPresent / (totalPresent + totalAbsences) : null;
  const metrics = `<div class="metric-grid">${metric('Sinh viên', state.snapshot.roster.length, 'trong lớp', '♧')}${metric('Buổi học', state.snapshot.sessionIds.length, 'đã lên lịch', '▣')}${metric('Độ bao phủ', ratePercent(current.coverage), 'kết quả ghi nhận', '◉')}${metric('Vắng mặt', totalAbsences, `${current.missing} kết quả còn thiếu`, '⌁')}</div>`;
  const chart = current.sessions.length ? `<div class="chart">${current.sessions.map((session) => {
    const sessionRate = session.present + session.absent ? session.present / (session.present + session.absent) : null;
    const height = sessionRate === null ? 2 : Math.max(2, sessionRate * 100);
    return `<div class="chart-column"><b>${ratePercent(sessionRate)}</b><div class="chart-bar-track"><div class="chart-bar${height < 60 ? ' is-low' : ''}" style="height:${height}%"></div></div><small title="${esc(session.sessionId)}">${esc(sessionName(session.sessionId))}</small></div>`;
  }).join('')}</div>` : emptyInline('Thêm buổi học để xem thống kê.');
  const bottomStudents = [...current.students].sort((a, b) => (a.attendanceRate ?? 0) - (b.attendanceRate ?? 0)).slice(0, 5);
  const activity = bottomStudents.length ? `<div class="activity-list">${bottomStudents.map((student) => `<div class="activity-item"><span class="activity-avatar">${esc(initials(student.student.name))}</span><span class="activity-name">${esc(student.student.name)}</span><span class="activity-session">${student.absent} vắng · ${student.missing} thiếu</span></div>`).join('')}</div>` : emptyInline('Chưa có sinh viên trong lớp.');
  return `${metrics}<div class="panel-grid">${panel('Tỷ lệ có mặt theo buổi', `${chart}<div class="matrix-legend"><span class="legend-item">${actualRate === null ? 'Chưa có kết quả' : `Tỷ lệ chung ${ratePercent(actualRate)}`}</span></div>`, { description: 'Tỷ lệ tính trên số kết quả đã ghi nhận.' })}${panel('Cần theo dõi', activity, { description: 'Sinh viên có tỷ lệ thấp nhất.' })}</div>${panel('Thiếu dữ liệu', renderMissingPreview(current.missing))}`;
}

function renderMissingPreview(missing) {
  if (!missing.length) return emptyInline('Tất cả sinh viên đã có kết quả cho các buổi học.');
  const preview = missing.slice(0, 8);
  return `<div class="activity-list">${preview.map((item) => {
    const student = state.snapshot.roster.find((row) => row.id === item.studentId);
    return `<div class="activity-item"><span class="activity-avatar">${esc(initials(student?.name ?? item.studentId))}</span><span class="activity-name">${esc(student?.name ?? item.studentId)}</span><span class="activity-session">${esc(item.sessionId)}</span></div>`;
  }).join('')}</div>${missing.length > preview.length ? `<p class="pagination-info">Còn ${missing.length - preview.length} bản ghi. Mở bảng điểm danh để xem toàn bộ.</p>` : ''}`;
}

function filteredStudents() {
  const query = state.search.trim().toLocaleLowerCase();
  let students = [...state.snapshot.roster];
  if (query) students = students.filter((student) => [student.id, student.name, student.email].some((value) => value.toLocaleLowerCase().includes(query)));
  if (state.sort === 'name') students.sort((a, b) => a.name.localeCompare(b.name, 'vi'));
  if (state.sort === 'id') students.sort((a, b) => a.id.localeCompare(b.id));
  if (state.sort === 'rate') {
    const byId = new Map(attendanceReport().map((item) => [item.student.id, item.attendanceRate]));
    students.sort((a, b) => (byId.get(a.id) ?? -1) - (byId.get(b.id) ?? -1));
  }
  return students;
}

function pager(items, page, pageSize) {
  const pages = Math.max(1, Math.ceil(items / pageSize));
  return `<div class="pager"><span>${items ? `${page * pageSize + 1}–${Math.min(items, (page + 1) * pageSize)} / ${items}` : '0 kết quả'}</span><span class="pager-actions"><button class="icon-button" data-page="prev" aria-label="Trang trước" ${page <= 0 ? 'disabled' : ''}>‹</button><button class="icon-button" data-page="next" aria-label="Trang sau" ${page + 1 >= pages ? 'disabled' : ''}>›</button></span></div>`;
}

function renderStudents() {
  const all = filteredStudents();
  const start = state.page * state.pageSize;
  const pageRows = all.slice(start, start + state.pageSize);
  const summaries = new Map(attendanceReport().map((item) => [item.student.id, item]));
  const rows = pageRows.map((student) => {
    const summary = summaries.get(student.id);
    return `<tr><td>${personCell(student, student.id)}</td><td>${summary.present}</td><td>${summary.absent}</td><td>${summary.missing}</td><td>${percentBar(summary.attendanceRate)}</td><td><button class="icon-button" data-edit-student="${esc(student.id)}" aria-label="Sửa ${esc(student.name)}">⋯</button></td></tr>`;
  }).join('');
  const toolbar = `<div class="toolbar"><label class="search-field"><span>⌕</span><input data-search placeholder="Tìm tên, mã hoặc email" value="${esc(state.search)}"></label><select class="select-field" data-sort aria-label="Sắp xếp"><option value="name" ${state.sort === 'name' ? 'selected' : ''}>Tên A–Z</option><option value="id" ${state.sort === 'id' ? 'selected' : ''}>Mã sinh viên</option><option value="rate" ${state.sort === 'rate' ? 'selected' : ''}>Tỷ lệ điểm danh</option></select><span class="spacer"></span><button class="button button-secondary" data-import-roster>Nhập CSV</button><button class="button button-secondary" data-export-roster>Tải CSV</button></div>`;
  const table = pageRows.length ? `<div class="table-wrap"><table><thead><tr><th>SINH VIÊN</th><th>CÓ MẶT</th><th>VẮNG</th><th>THIẾU</th><th>TỶ LỆ</th><th></th></tr></thead><tbody>${rows}</tbody></table></div>` : emptyInline(state.search ? 'Không tìm thấy sinh viên phù hợp.' : 'Danh sách lớp đang trống.');
  return `${panel('Danh sách sinh viên', `${toolbar}<div style="height:12px"></div>${table}${pager(all.length, state.page, state.pageSize)}`, { description: `${state.snapshot.roster.length} sinh viên trong lớp` })}`;
}

function renderAttendance() {
  const current = report();
  const filtered = filteredStudents();
  const byId = new Map(current.students.map((item) => [item.student.id, item]));
  const statuses = ['present', 'absent', 'missing'];
  const rows = filtered.map((student) => {
    const summary = byId.get(student.id);
    if (state.statusFilter !== 'all' && !summary.sessions.some((item) => item.status === state.statusFilter)) return '';
    const cells = summary.sessions.map((session) => `<td class="matrix-session"><button class="matrix-mark ${session.status}" data-toggle-record="${esc(JSON.stringify([student.id, session.sessionId]))}" title="${esc(student.name)} · ${esc(session.sessionId)} · ${esc(session.status)}" aria-label="${esc(student.name)} ${esc(session.sessionId)} ${esc(session.status)}">${session.status === 'present' ? '✓' : session.status === 'absent' ? '×' : '·'}</button></td>`).join('');
    return `<tr><td class="matrix-name">${personCell(student, student.id)}</td>${cells}</tr>`;
  }).join('');
  const sessionHeaders = state.snapshot.sessionIds.map((id) => `<th class="matrix-session" title="${esc(id)}">${esc(sessionName(id))}</th>`).join('');
  const table = state.snapshot.sessionIds.length ? `<div class="table-wrap"><table class="matrix-table"><thead><tr><th class="matrix-name">SINH VIÊN</th>${sessionHeaders}</tr></thead><tbody>${rows || `<tr><td colspan="${state.snapshot.sessionIds.length + 1}">${emptyInline('Không có hàng phù hợp với bộ lọc.')}</td></tr>`}</tbody></table></div>` : emptyInline('Thêm buổi học để bắt đầu điểm danh.');
  const toolbar = `<div class="toolbar"><label class="search-field"><span>⌕</span><input data-search placeholder="Tìm sinh viên" value="${esc(state.search)}"></label><select class="select-field" data-status-filter aria-label="Lọc trạng thái"><option value="all">Tất cả trạng thái</option><option value="present" ${state.statusFilter === 'present' ? 'selected' : ''}>Có mặt</option><option value="absent" ${state.statusFilter === 'absent' ? 'selected' : ''}>Vắng</option><option value="missing" ${state.statusFilter === 'missing' ? 'selected' : ''}>Chưa ghi</option></select><span class="spacer"></span><div class="matrix-legend"><span class="legend-item"><i class="legend-swatch" style="background:#edf7f0"></i>Có mặt</span><span class="legend-item"><i class="legend-swatch" style="background:#fff0ee"></i>Vắng</span><span class="legend-item"><i class="legend-swatch" style="background:#fbf5e9"></i>Chưa ghi</span></div></div>`;
  return `${panel('Bảng điểm danh', `${toolbar}<div style="height:12px"></div>${table}`, { description: `${current.recorded} / ${current.expected} kết quả đã ghi nhận` })}<p class="pagination-info">Nhấn ô để chuyển giữa Có mặt → Vắng → Chưa ghi. Thay đổi chỉ nằm trong bản sao đang mở cho đến khi bạn tải xuống.</p>`;
}

function renderSessions() {
  const quality = report();
  const rows = quality.sessions.map((session, index) => {
    const attendance = session.present + session.absent;
    const rate = attendance ? session.present / attendance : null;
    return `<div class="session-row"><div><strong>${esc(session.sessionId)}</strong><small>Buổi ${index + 1} · ${session.present} có mặt · ${session.absent} vắng · ${session.missingStudentIds.length} chưa ghi</small></div><span class="session-count">${ratePercent(rate)}</span><button class="icon-button" data-remove-session="${esc(session.sessionId)}" aria-label="Xóa buổi ${esc(session.sessionId)}">×</button></div>`;
  }).join('');
  const conflicts = state.schedule.length ? findScheduleConflicts(state.schedule) : [];
  const schedulePanel = state.schedule.length ? panel('Lịch lặp đã tạo', `<div class="session-list">${state.schedule.map((session) => `<div class="session-row"><div><strong>${esc(session.id)}</strong><small>${esc(new Date(session.start).toLocaleString('vi-VN'))} – ${esc(new Date(session.end).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' }))}</small></div><span>${conflicts.some((conflict) => conflict.firstId === session.id || conflict.secondId === session.id) ? statusBadge('absent') : statusBadge('present')}</span><button class="icon-button" data-remove-schedule="${esc(session.id)}" aria-label="Xóa ${esc(session.id)}">×</button></div>`).join('')}</div><div class="toolbar" style="margin-top:12px"><button class="button button-secondary" data-add-schedule-to-class>Thêm vào danh sách buổi</button><button class="button button-secondary" data-download-calendar>Tải lịch iCalendar</button></div>`, { description: conflicts.length ? `${conflicts.length} xung đột tài nguyên` : 'Lịch được tạo trong trình duyệt.' }) : '');
  const actions = `<div class="toolbar"><button class="button button-primary" data-add-session>＋ Thêm buổi</button><button class="button button-secondary" data-generate-schedule>Tạo lịch lặp lại</button><button class="button button-secondary" data-import-schedule>Nhập lịch JSON</button></div>`;
  return `${panel('Các buổi học', `${actions}<div style="height:12px"></div>${rows ? `<div class="session-list">${rows}</div>` : emptyInline('Chưa có buổi học. Thêm một buổi hoặc tạo lịch lặp lại.')}`, { description: `${state.snapshot.sessionIds.length} buổi theo thứ tự hiện tại` })}${schedulePanel}`;
}

function renderAnalysis() {
  const absenceRuns = findConsecutiveAbsences(state.snapshot.roster, state.snapshot.sessionIds, state.snapshot.records, 2);
  const rolling = rollingAttendance(state.snapshot.roster, state.snapshot.sessionIds, state.snapshot.records,
    Math.max(1, Math.min(3, state.snapshot.sessionIds.length || 1)));
  const lowRows = [...attendanceReport()].sort((a, b) => (a.attendanceRate ?? -1) - (b.attendanceRate ?? -1)).slice(0, 8);
  const bars = lowRows.map((item) => {
    const value = item.attendanceRate === null ? 0 : item.attendanceRate * 100;
    return `<div class="bar-row"><span class="bar-label" title="${esc(item.student.name)}">${esc(item.student.name)}</span><span class="bar-track"><span class="bar-value${value < 60 ? ' low' : ''}" style="display:block;width:${value}%"></span></span><span class="bar-percent">${ratePercent(item.attendanceRate)}</span></div>`;
  }).join('');
  const streakRows = absenceRuns.map((item) => `<tr><td>${personCell(item.student, item.student.id)}</td><td>${esc(item.sessionIds.join(', '))}</td><td>${item.sessionIds.length}</td></tr>`).join('');
  const policyResults = evaluatePolicy(state.snapshot, state.policy);
  const policyRows = policyResults.map((item) => `<tr><td>${personCell(item.student, item.student.id)}</td><td>${statusBadge(item.status)}</td><td>${item.reasons.map(esc).join(', ') || '—'}</td><td>${item.minimumRate === null ? '—' : `${ratePercent(item.minimumRate)} – ${ratePercent(item.maximumRate)}`}</td></tr>`).join('');
  const windows = rolling.flatMap((student) => student.windows.map((window) => ({ student: student.student, ...window }))).slice(0, 12);
  const trendRows = windows.map((item) => `<tr><td>${esc(item.student.name)}</td><td>${esc(item.startSessionId)} – ${esc(item.endSessionId)}</td><td>${item.present} / ${item.present + item.absent}</td><td>${ratePercent(item.attendanceRate)}</td></tr>`).join('');
  const tools = `<div class="toolbar"><button class="button button-secondary" data-edit-policy>⚙ Điều kiện điểm danh</button><button class="button button-secondary" data-analysis-csv>Tải kết quả CSV</button><button class="button button-secondary" data-analysis-html>Tải báo cáo HTML</button></div>`;
  const summaries = `<div class="metric-grid">${metric('Chuỗi vắng từ 2 buổi', absenceRuns.length, 'chuỗi', '×')}${metric('Điều kiện đạt', policyResults.filter((item) => item.status === 'pass').length, 'sinh viên', '✓')}${metric('Chưa đạt', policyResults.filter((item) => item.status === 'fail').length, 'sinh viên', '！')}${metric('Chưa đủ dữ liệu', policyResults.filter((item) => item.status === 'undetermined').length, 'sinh viên', '…')}</div>`;
  return `${summaries}${tools}<div class="two-col">${panel('Tỷ lệ theo sinh viên', bars || emptyInline('Chưa có sinh viên.'), { description: 'Tính trên kết quả đã ghi nhận.' })}${panel('Điều kiện đang dùng', `<div class="activity-list"><div class="activity-item"><span class="activity-avatar">%</span><span class="activity-name">Tỷ lệ tối thiểu</span><span>${ratePercent(state.policy.minimumRate)}</span></div><div class="activity-item"><span class="activity-avatar">×</span><span class="activity-name">Số buổi vắng tối đa</span><span>${state.policy.maximumAbsences}</span></div><div class="activity-item"><span class="activity-avatar">?</span><span class="activity-name">Cách xử lý dữ liệu thiếu</span><span>Chưa kết luận</span></div></div>`)}</div>${panel('Chuỗi vắng liên tiếp', streakRows ? `<div class="table-wrap"><table><thead><tr><th>SINH VIÊN</th><th>CÁC BUỔI</th><th>SỐ BUỔI</th></tr></thead><tbody>${streakRows}</tbody></table></div>` : emptyInline('Không tìm thấy chuỗi vắng từ 2 buổi liên tiếp.'))}${panel('Xu hướng theo cửa sổ buổi học', trendRows ? `<div class="table-wrap"><table><thead><tr><th>SINH VIÊN</th><th>CỬA SỔ</th><th>CÓ MẶT</th><th>TỶ LỆ</th></tr></thead><tbody>${trendRows}</tbody></table></div>` : emptyInline('Thêm buổi học để xem xu hướng.'))}${panel('Đánh giá theo điều kiện', policyRows ? `<div class="table-wrap"><table><thead><tr><th>SINH VIÊN</th><th>KẾT QUẢ</th><th>LÝ DO</th><th>BIÊN TỶ LỆ</th></tr></thead><tbody>${policyRows}</tbody></table></div>` : emptyInline('Chưa có sinh viên.'))}`;
}

function bindViewActions(root) {
  const search = $('[data-search]', root);
  if (search) search.addEventListener('input', (event) => {
    const cursor = event.target.selectionStart;
    state.search = event.target.value;
    state.page = 0;
    render();
    const replacement = $('[data-search]');
    replacement?.focus();
    replacement?.setSelectionRange(cursor, cursor);
  });
  $('[data-sort]', root)?.addEventListener('change', (event) => { state.sort = event.target.value; render(); });
  $('[data-status-filter]', root)?.addEventListener('change', (event) => { state.statusFilter = event.target.value; render(); });
  $$('[data-page]', root).forEach((button) => button.addEventListener('click', () => {
    state.page = Math.max(0, state.page + (button.dataset.page === 'next' ? 1 : -1)); render();
  }));
  $$('[data-edit-student]', root).forEach((button) => button.addEventListener('click', () => editStudent(button.dataset.editStudent)));
  $('[data-import-roster]', root)?.addEventListener('click', () => $('#roster-file').click());
  $('[data-export-roster]', root)?.addEventListener('click', exportRosterCsv);
  $$('[data-toggle-record]', root).forEach((button) => button.addEventListener('click', () => toggleRecord(JSON.parse(button.dataset.toggleRecord))));
  $$('[data-remove-session]', root).forEach((button) => button.addEventListener('click', () => removeSession(button.dataset.removeSession)));
  $('[data-add-session]', root)?.addEventListener('click', addSession);
  $('[data-generate-schedule]', root)?.addEventListener('click', scheduleDialog);
  $('[data-import-schedule]', root)?.addEventListener('click', importSchedule);
  $('[data-add-schedule-to-class]', root)?.addEventListener('click', addScheduleToClass);
  $('[data-download-calendar]', root)?.addEventListener('click', downloadScheduleCalendar);
  $$('[data-remove-schedule]', root).forEach((button) => button.addEventListener('click', () => {
    state.schedule = state.schedule.filter((session) => session.id !== button.dataset.removeSchedule); render();
  }));
  $('[data-edit-policy]', root)?.addEventListener('click', policyDialog);
  $('[data-analysis-csv]', root)?.addEventListener('click', exportAnalysisCsv);
  $('[data-analysis-html]', root)?.addEventListener('click', exportHtml);
}

function toggleRecord([studentId, sessionId]) {
  const existing = state.snapshot.records.find((record) => record.studentId === studentId && record.sessionId === sessionId);
  const status = existing?.status ?? null;
  const next = status === null ? 'present' : status === 'present' ? 'absent' : null;
  try {
    const result = applyAttendanceBatch(state.snapshot, [{ studentId, sessionId, expected: status, status: next }]);
    if (result.conflicts.length) throw new Error('Bản ghi đã thay đổi, hãy tải lại bản sao.');
    commitSnapshot(result.snapshot, `điểm danh ${studentId} · ${sessionId}`);
    render();
  } catch (error) { showError(error); }
}

function addSession() {
  showDialog(`<div class="modal-head"><div><h2>Thêm buổi học</h2><p>Buổi mới sẽ được thêm cuối danh sách hiện tại.</p></div><button type="button" class="icon-button" data-close>×</button></div><div class="form-grid"><div class="form-field"><label for="session-id">Mã buổi học</label><input id="session-id" name="id" required maxlength="120" placeholder="Ví dụ: buổi-05"></div></div><div class="modal-actions"><button type="button" class="button button-secondary" data-close>Hủy</button><button class="button button-primary">Thêm buổi</button></div>`, () => {
    bindModalClose();
    $('#modal-form').onsubmit = (event) => {
      event.preventDefault();
      const id = $('#session-id').value.trim();
      if (!id) return;
      try {
        commitSnapshot(createAttendanceSnapshot(state.snapshot.roster, [...state.snapshot.sessionIds, id], state.snapshot.records), `thêm buổi ${id}`);
        closeDialog(); render(); notify('Đã thêm buổi học.');
      } catch (error) { showError(error); }
    };
  });
}

function addStudent() {
  showDialog(`<div class="modal-head"><div><h2>Thêm sinh viên</h2><p>Nhập thông tin sinh viên mới vào bản sao đang mở.</p></div><button type="button" class="icon-button" data-close>×</button></div><div class="form-grid"><div class="form-field"><label for="student-id">Mã sinh viên</label><input id="student-id" name="id" required maxlength="100"></div><div class="form-field"><label for="student-name">Họ và tên</label><input id="student-name" name="name" required maxlength="160"></div><div class="form-field"><label for="student-email">Email</label><input id="student-email" name="email" type="email" required maxlength="254"></div></div><div class="modal-actions"><button type="button" class="button button-secondary" data-close>Hủy</button><button class="button button-primary">Thêm sinh viên</button></div>`, () => {
    bindModalClose();
    $('#modal-form').onsubmit = (event) => {
      event.preventDefault();
      const student = { id: $('#student-id').value.trim(), name: $('#student-name').value.trim(), email: $('#student-email').value.trim() };
      try {
        commitSnapshot(createAttendanceSnapshot([...state.snapshot.roster, student], state.snapshot.sessionIds, state.snapshot.records), `thêm sinh viên ${student.id}`);
        closeDialog(); render(); notify('Đã thêm sinh viên.');
      } catch (error) { showError(error); }
    };
  });
}

function editStudent(id) {
  const student = state.snapshot.roster.find((item) => item.id === id);
  if (!student) return;
  showDialog(`<div class="modal-head"><div><h2>Sửa sinh viên</h2><p>Cập nhật thông tin cho ${esc(student.id)}.</p></div><button type="button" class="icon-button" data-close>×</button></div><div class="form-grid"><div class="form-field"><label for="student-name">Họ và tên</label><input id="student-name" required maxlength="160" value="${esc(student.name)}"></div><div class="form-field"><label for="student-email">Email</label><input id="student-email" type="email" required maxlength="254" value="${esc(student.email)}"></div></div><div class="modal-actions"><button type="button" class="button button-secondary" data-delete-student>Xóa sinh viên</button><span class="spacer"></span><button type="button" class="button button-secondary" data-close>Hủy</button><button class="button button-primary">Lưu thay đổi</button></div>`, () => {
    bindModalClose();
    $('[data-delete-student]').onclick = () => deleteStudent(id);
    $('#modal-form').onsubmit = (event) => {
      event.preventDefault();
      const updated = { ...student, name: $('#student-name').value.trim(), email: $('#student-email').value.trim() };
      const roster = state.snapshot.roster.map((item) => item.id === id ? updated : item);
      try {
        commitSnapshot(createAttendanceSnapshot(roster, state.snapshot.sessionIds, state.snapshot.records), `sửa sinh viên ${id}`);
        closeDialog(); render(); notify('Đã cập nhật sinh viên.');
      } catch (error) { showError(error); }
    };
  });
}

function deleteStudent(id) {
  const student = state.snapshot.roster.find((item) => item.id === id);
  const recordCount = state.snapshot.records.filter((record) => record.studentId === id).length;
  if (!confirm(`Xóa ${student.name}? Thao tác này cũng xóa ${recordCount} kết quả điểm danh khỏi bản sao trong bộ nhớ.`)) return;
  const roster = state.snapshot.roster.filter((item) => item.id !== id);
  const records = state.snapshot.records.filter((record) => record.studentId !== id);
  commitSnapshot(createAttendanceSnapshot(roster, state.snapshot.sessionIds, records), `xóa sinh viên ${id}`);
  closeDialog(); render(); notify('Đã xóa sinh viên và các kết quả liên quan.');
}

function removeSession(id) {
  const count = state.snapshot.records.filter((record) => record.sessionId === id).length;
  if (!confirm(`Xóa buổi ${id}? ${count} kết quả điểm danh liên quan sẽ bị loại khỏi bản sao trong bộ nhớ.`)) return;
  const sessions = state.snapshot.sessionIds.filter((sessionId) => sessionId !== id);
  const records = state.snapshot.records.filter((record) => record.sessionId !== id);
  commitSnapshot(createAttendanceSnapshot(state.snapshot.roster, sessions, records), `xóa buổi ${id}`);
  render(); notify('Đã xóa buổi học và các kết quả liên quan.');
}

function scheduleDialog() {
  const today = new Date().toISOString().slice(0, 10);
  const end = new Date(Date.now() + 28 * 86400000).toISOString().slice(0, 10);
  showDialog(`<div class="modal-head"><div><h2>Tạo lịch lặp lại</h2><p>Lịch được tạo theo UTC. Kiểm tra xung đột trước khi thêm vào lớp.</p></div><button type="button" class="icon-button" data-close>×</button></div><div class="form-grid"><div class="two-col"><div class="form-field"><label for="schedule-start">Từ ngày</label><input id="schedule-start" type="date" value="${today}" required></div><div class="form-field"><label for="schedule-end">Đến ngày</label><input id="schedule-end" type="date" value="${end}" required></div></div><div class="two-col"><div class="form-field"><label for="schedule-time">Giờ bắt đầu UTC</label><input id="schedule-time" type="time" value="09:00" required></div><div class="form-field"><label for="schedule-duration">Thời lượng (phút)</label><input id="schedule-duration" type="number" min="1" max="1440" value="90" required></div></div><div class="form-field"><label for="schedule-days">Ngày trong tuần (0–6, Chủ nhật = 0)</label><input id="schedule-days" value="1,3,5" required></div><div class="two-col"><div class="form-field"><label for="schedule-prefix">Tiền tố mã buổi</label><input id="schedule-prefix" value="class"></div><div class="form-field"><label for="schedule-resource">Phòng / tài nguyên</label><input id="schedule-resource" value="room-1"></div></div><div class="form-field"><label for="schedule-exceptions">Ngày nghỉ, cách nhau bằng dấu phẩy</label><input id="schedule-exceptions" placeholder="2026-01-01"></div></div><div class="modal-actions"><button type="button" class="button button-secondary" data-close>Hủy</button><button class="button button-primary">Tạo lịch</button></div>`, () => {
    bindModalClose();
    $('#modal-form').onsubmit = (event) => {
      event.preventDefault();
      try {
        const weekdays = $('#schedule-days').value.split(',').map((value) => Number(value.trim()));
        const exceptions = $('#schedule-exceptions').value.split(',').map((value) => value.trim()).filter(Boolean);
        const resources = $('#schedule-resource').value.split(',').map((value) => value.trim()).filter(Boolean);
        const schedule = generateRecurringSessions({ startDate: $('#schedule-start').value,
          endDate: $('#schedule-end').value, startTime: $('#schedule-time').value,
          durationMinutes: Number($('#schedule-duration').value), weekdays, resources,
          idPrefix: $('#schedule-prefix').value, exceptions });
        const conflicts = findScheduleConflicts([...state.schedule, ...schedule]);
        if (conflicts.length && !confirm(`Có ${conflicts.length} xung đột lịch. Bạn vẫn muốn xem lịch được tạo?`)) return;
        state.schedule = [...state.schedule, ...schedule];
        closeDialog(); render(); notify(`Đã tạo ${schedule.length} buổi.`);
      } catch (error) { showError(error); }
    };
  });
}

function importSchedule() {
  const input = document.createElement('input');
  input.type = 'file'; input.accept = '.json,application/json';
  input.onchange = async () => {
    const file = input.files?.[0]; if (!file) return;
    try {
      const schedule = JSON.parse(await file.text());
      const conflicts = findScheduleConflicts([...state.schedule, ...schedule]);
      if (conflicts.length) notify(`Lịch có ${conflicts.length} xung đột.`, 'error');
      state.schedule = [...state.schedule, ...schedule]; render();
    } catch (error) { showError(error); }
  };
  input.click();
}

function addScheduleToClass() {
  const conflicts = findScheduleConflicts(state.schedule);
  if (conflicts.length && !confirm(`Phát hiện ${conflicts.length} xung đột. Vẫn thêm toàn bộ buổi vào danh sách?`)) return;
  const existing = new Set(state.snapshot.sessionIds);
  const additions = state.schedule.filter((session) => !existing.has(session.id)).map((session) => session.id);
  try {
    commitSnapshot(createAttendanceSnapshot(state.snapshot.roster, [...state.snapshot.sessionIds, ...additions], state.snapshot.records), `thêm ${additions.length} buổi`);
    render(); notify(`Đã thêm ${additions.length} buổi mới vào lớp.`);
  } catch (error) { showError(error); }
}

function downloadScheduleCalendar() {
  try {
    const calendar = sessionsToICalendar(state.schedule, { uidDomain: 'attendance-workbench.local',
      generatedAt: new Date().toISOString().replace(/\.\d{3}/, ''), title: 'Class session' });
    download('class-schedule.ics', calendar, 'text/calendar;charset=utf-8');
  } catch (error) { showError(error); }
}

function policyDialog() {
  showDialog(`<div class="modal-head"><div><h2>Điều kiện điểm danh</h2><p>Chọn ngưỡng để phân loại. Dữ liệu thiếu sẽ được giữ ở trạng thái chưa xác định khi có thể đổi kết luận.</p></div><button type="button" class="icon-button" data-close>×</button></div><div class="form-grid"><div class="form-field"><label for="policy-rate">Tỷ lệ tối thiểu (%)</label><input id="policy-rate" type="number" min="0" max="100" step="1" value="${state.policy.minimumRate * 100}"></div><div class="form-field"><label for="policy-absences">Số buổi vắng tối đa</label><input id="policy-absences" type="number" min="0" step="1" value="${state.policy.maximumAbsences}"></div></div><div class="modal-actions"><button type="button" class="button button-secondary" data-close>Hủy</button><button class="button button-primary">Áp dụng</button></div>`, () => {
    bindModalClose();
    $('#modal-form').onsubmit = (event) => {
      event.preventDefault();
      const percentage = Number($('#policy-rate').value);
      const maximumAbsences = Number($('#policy-absences').value);
      if (!Number.isFinite(percentage) || percentage < 0 || percentage > 100 || !Number.isSafeInteger(maximumAbsences) || maximumAbsences < 0) {
        showError(new Error('Kiểm tra lại các điều kiện điểm danh.')); return;
      }
      state.policy = { minimumRate: percentage / 100, maximumAbsences };
      closeDialog(); render();
    };
  });
}

function bindModalClose() {
  $$('[data-close]').forEach((button) => button.addEventListener('click', closeDialog));
}

function exportRosterCsv() {
  const header = ['id', 'name', 'email'].map(csvCell).join(',');
  const rows = state.snapshot.roster.map((student) => [student.id, student.name, student.email].map(csvCell).join(','));
  download('roster.csv', [header, ...rows].join('\r\n'), 'text/csv;charset=utf-8');
}

function csvCell(value) {
  const safe = /^[\t\r\n ]*[=+\-@]/.test(value) ? `'${value}` : value;
  return `"${safe.replaceAll('"', '""')}"`;
}

function exportAnalysisCsv() {
  const content = ['studentId,name,present,absent,missing,attendanceRate,policyStatus',
    ...attendanceReport().map((item) => {
      const policyResult = evaluatePolicy(state.snapshot, state.policy).find((row) => row.student.id === item.student.id);
      return [item.student.id, item.student.name, item.present, item.absent, item.missing,
        item.attendanceRate ?? '', policyResult.status].map(csvCell).join(',');
    })].join('\r\n');
  download('attendance-analysis.csv', `${content}\r\n`, 'text/csv;charset=utf-8');
}

function exportHtml() {
  const html = renderHtmlReport(state.snapshot, 'Attendance report');
  download('attendance-report.html', html, 'text/html;charset=utf-8');
}

function importRoster() {
  $('#roster-file').click();
}

function handleRosterFile(file) {
  file.text().then((text) => {
    const result = importRosterCsv(text);
    if (result.errors.length) throw new Error(`CSV có ${result.errors.length} lỗi: ${JSON.stringify(result.errors.slice(0, 8))}`);
    const replacement = reviseSnapshot(state.snapshot, { roster: result.students });
    commitSnapshot(replacement.snapshot, `nhập ${result.students.length} sinh viên`);
    render(); notify(`Đã nhập ${result.students.length} sinh viên.`);
  }).catch(showError);
}

function loadDialog() {
  showDialog(`<div class="modal-head"><div><h2>Mở bản sao</h2><p>Chọn tệp JSON được tạo từ Attendance Workbench.</p></div><button type="button" class="icon-button" data-close>×</button></div><div class="file-drop"><p>Tệp không được gửi đi. Nội dung được đọc trong trình duyệt này.</p><button class="button button-primary" type="button" id="modal-pick-file">Chọn tệp JSON</button></div><div class="modal-actions"><button type="button" class="button button-secondary" data-close>Đóng</button></div>`, () => {
    bindModalClose();
    $('#modal-pick-file').onclick = () => { closeDialog(); $('#snapshot-file').click(); };
  });
}

function handleSnapshotFile(file) {
  file.text().then((content) => loadSnapshot(content, `Đã mở ${file.name}.`)).catch(showError);
}

function demoSnapshot() {
  const roster = [
    { id: 'SV001', name: 'Nguyễn Minh Anh', email: 'minhanh@example.edu.vn' },
    { id: 'SV002', name: 'Trần Gia Bảo', email: 'giabao@example.edu.vn' },
    { id: 'SV003', name: 'Lê Phương Chi', email: 'phuongchi@example.edu.vn' },
    { id: 'SV004', name: 'Phạm Tuấn Dũng', email: 'tuandung@example.edu.vn' },
    { id: 'SV005', name: 'Võ Thảo Hà', email: 'thaoha@example.edu.vn' },
    { id: 'SV006', name: 'Đặng Quốc Huy', email: 'quochuy@example.edu.vn' },
  ];
  const sessionIds = ['T01', 'T02', 'T03', 'T04', 'T05'];
  const statuses = [
    ['present', 'present', 'absent', 'present', 'present'],
    ['present', 'absent', 'absent', 'missing', 'present'],
    ['present', 'present', 'present', 'present', 'present'],
    ['absent', 'present', 'missing', 'absent', 'absent'],
    ['present', 'missing', 'present', 'present', 'missing'],
    ['absent', 'absent', 'absent', 'present', 'present'],
  ];
  const records = [];
  statuses.forEach((list, studentIndex) => list.forEach((status, sessionIndex) => {
    if (status !== 'missing') records.push({ studentId: roster[studentIndex].id, sessionId: sessionIds[sessionIndex], status });
  }));
  loadSnapshot(createAttendanceSnapshot(roster, sessionIds, records), 'Đã mở dữ liệu mẫu.');
}

function setBundle(bundle) {
  state.bundle = bundle;
  state.bundleCurrentId = null;
}

function showBundleManager() {
  const summary = summarizeBundle(state.bundle);
  const students = summarizeStudentsAcrossClasses(state.bundle);
  const rows = summary.map((item) => `<div class="session-row"><div><strong>${esc(item.name)}</strong><small>${esc(item.id)} · ${item.students} sinh viên · ${item.sessions} buổi · ${item.missing} chưa ghi</small></div><span class="session-count">${ratePercent(item.coverage)}</span><div><button class="icon-button" data-open-class="${esc(item.id)}" title="Mở lớp">↗</button><button class="icon-button" data-remove-class="${esc(item.id)}" title="Xóa lớp">×</button></div></div>`).join('');
  const conflictCount = students.filter((student) => student.identityConflict).length;
  showDialog(`<div class="modal-head"><div><h2>Quản lý nhiều lớp</h2><p>${summary.length} lớp · ${students.length} sinh viên duy nhất · ${conflictCount} mã có thông tin khác nhau</p></div><button type="button" class="icon-button" data-close>×</button></div><div class="toolbar"><button class="button button-primary" type="button" id="bundle-add-current" ${state.snapshot ? '' : 'disabled'}>Thêm lớp hiện tại</button><button class="button button-secondary" type="button" id="bundle-import">Nhập kho JSON</button><button class="button button-secondary" type="button" id="bundle-export" ${summary.length ? '' : 'disabled'}>Tải kho JSON</button><button class="button button-secondary" type="button" id="bundle-export-students" ${students.length ? '' : 'disabled'}>Tải tổng hợp CSV</button></div><div style="height:13px"></div>${rows ? `<div class="session-list">${rows}</div>` : emptyInline('Kho lớp đang trống. Thêm lớp từ bản sao đang mở hoặc nhập một kho đã lưu.')}`, () => {
    bindModalClose();
    $('#bundle-add-current').onclick = () => {
      if (!state.snapshot) return;
      const name = prompt('Tên lớp'); if (!name?.trim()) return;
      const id = prompt('Mã lớp', name.trim().toLocaleLowerCase().replace(/\s+/g, '-'));
      if (!id?.trim()) return;
      try {
        setBundle(putClass(state.bundle, id, name, state.snapshot));
        showBundleManager();
      } catch (error) { showError(error); }
    };
    $('#bundle-import').onclick = importBundle;
    $('#bundle-export').onclick = () => download('attendance-bundle.json', `${JSON.stringify(state.bundle, null, 2)}\n`);
    $('#bundle-export-students').onclick = () => {
      const csv = ['studentId,identityConflict,present,absent,missing,attendanceRate,classes', ...students.map((student) => [
        student.studentId, student.identityConflict, student.present, student.absent, student.missing,
        student.attendanceRate ?? '', student.classes.map((item) => item.classId).join(';'),
      ].map(csvCell).join(','))].join('\r\n');
      download('students-across-classes.csv', `${csv}\r\n`, 'text/csv;charset=utf-8');
    };
    $$('[data-open-class]').forEach((button) => button.onclick = () => {
      const id = button.dataset.openClass;
      const entry = state.bundle.classes.find((item) => item.id === id);
      if (!entry) return;
      state.snapshot = entry.snapshot;
      state.bundleCurrentId = id;
      state.savedSnapshotText = serializeAttendanceSnapshot(state.snapshot);
      state.history = [];
      state.future = [];
      closeDialog();
      $('#empty-state').hidden = true; $('#loaded-workspace').hidden = false; $('#download-snapshot').disabled = false;
      setView('overview');
      notify(`Đã mở lớp ${entry.name} từ kho trong bộ nhớ.`);
    });
    $$('[data-remove-class]').forEach((button) => button.onclick = () => {
      const entry = state.bundle.classes.find((item) => item.id === button.dataset.removeClass);
      if (!entry || !confirm(`Xóa lớp ${entry.name} khỏi kho đang mở?`)) return;
      try { setBundle(removeClass(state.bundle, entry.id)); showBundleManager(); } catch (error) { showError(error); }
    });
  });
}

function importBundle() {
  const input = document.createElement('input'); input.type = 'file'; input.accept = '.json,application/json';
  input.onchange = async () => {
    const file = input.files?.[0]; if (!file) return;
    try {
      const data = parseBundle(await file.text());
      setBundle(data); showBundleManager(); notify(`Đã mở kho ${file.name}.`);
    } catch (error) { showError(error); }
  };
  input.click();
}

function compareSnapshotFile() {
  if (!state.snapshot) {
    notify('Mở một bản sao trước khi so sánh.', 'error');
    return;
  }
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = '.json,application/json';
  input.onchange = async () => {
    const file = input.files?.[0];
    if (!file) return;
    try {
      const other = parseAttendanceSnapshot(await file.text());
      const diff = compareAttendanceSnapshots(state.snapshot, other);
      const counts = [
        ['Sinh viên mới', diff.roster.added.length],
        ['Sinh viên đã xóa', diff.roster.removed.length],
        ['Thông tin sinh viên đổi', diff.roster.changed.length],
        ['Buổi học mới', diff.sessions.added.length],
        ['Buổi học đã xóa', diff.sessions.removed.length],
        ['Kết quả mới', diff.attendance.added.length],
        ['Kết quả đã xóa', diff.attendance.removed.length],
        ['Kết quả đổi trạng thái', diff.attendance.changed.length],
      ];
      const rows = counts.map(([label, count]) => `<div class="activity-item"><span class="activity-avatar">${count}</span><span class="activity-name">${esc(label)}</span><span>${count ? 'Có thay đổi' : 'Không đổi'}</span></div>`).join('');
      const reordered = diff.sessions.reordered ? '<p class="status-pill status-undetermined">Thứ tự buổi học đã thay đổi</p>' : '<p class="pagination-info">Thứ tự các buổi chung không đổi.</p>';
      showDialog(`<div class="modal-head"><div><h2>So sánh bản sao</h2><p>Bản đang mở với ${esc(file.name)}. Bản gốc không bị thay đổi.</p></div><button type="button" class="icon-button" data-close>×</button></div><div class="activity-list">${rows}</div>${reordered}<div class="modal-actions"><button type="button" class="button button-secondary" data-close>Đóng</button></div>`, bindModalClose);
      if (hasSnapshotChanges(diff)) notify('Tìm thấy thay đổi giữa hai bản sao.');
      else notify('Hai bản sao không có thay đổi.');
    } catch (error) { showError(error); }
  };
  input.click();
}

function exportSnapshot() {
  if (!state.snapshot) return;
  download(snapshotFilename(), `${serializeAttendanceSnapshot(state.snapshot)}\n`);
  state.savedSnapshotText = serializeAttendanceSnapshot(state.snapshot);
  if (state.bundleCurrentId) {
    const entry = state.bundle.classes.find((item) => item.id === state.bundleCurrentId);
    if (entry) {
      state.bundle = putClass(state.bundle, entry.id, entry.name, state.snapshot);
      notify('Đã tải xuống bản sao và cập nhật lớp trong kho đang mở.');
    }
  }
  updateHistoryControls();
  if (!state.bundleCurrentId) notify('Đã tạo tệp bản sao mới.');
}

function loadEventBindings() {
  $('#open-snapshot').addEventListener('click', loadDialog);
  $('#sidebar-open').addEventListener('click', loadDialog);
  $('#empty-open').addEventListener('click', () => $('#snapshot-file').click());
  $('#snapshot-file').addEventListener('change', (event) => {
    const file = event.target.files?.[0]; if (file) handleSnapshotFile(file);
    event.target.value = '';
  });
  $('#roster-file').addEventListener('change', (event) => {
    const file = event.target.files?.[0]; if (file && state.snapshot) handleRosterFile(file);
    event.target.value = '';
  });
  $('#empty-open').addEventListener('keydown', () => {});
  $('#create-demo').addEventListener('click', demoSnapshot);
  $('#download-snapshot').addEventListener('click', exportSnapshot);
  $('#manage-bundle').addEventListener('click', showBundleManager);
  $('#compare-snapshot').addEventListener('click', compareSnapshotFile);
  $('#undo-action').addEventListener('click', undo);
  $('#redo-action').addEventListener('click', redo);
  $('#quick-add-student').addEventListener('click', addStudent);
  $('#add-session').addEventListener('click', addSession);
  $$('.nav-item').forEach((button) => button.addEventListener('click', () => setView(button.dataset.view)));
  $('#modal').addEventListener('click', (event) => {
    if (event.target === $('#modal')) closeDialog();
  });
  $('#modal').addEventListener('close', () => { $('#modal-content').innerHTML = ''; });
  window.addEventListener('keydown', (event) => {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'o') {
      event.preventDefault(); $('#snapshot-file').click();
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 's' && state.snapshot) {
      event.preventDefault(); exportSnapshot();
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'z') {
      event.preventDefault();
      if (event.shiftKey) redo(); else undo();
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'y') {
      event.preventDefault(); redo();
    }
    if (event.key === '/' && !['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) {
      event.preventDefault(); $('[data-search]')?.focus();
    }
  });
  // Drag and drop accepts a snapshot JSON file anywhere in the workbench.
  document.addEventListener('dragover', (event) => event.preventDefault());
  document.addEventListener('drop', (event) => {
    event.preventDefault();
    const file = [...(event.dataTransfer?.files ?? [])].find((item) => item.name.toLowerCase().endsWith('.json'));
    if (file) handleSnapshotFile(file);
  });
  window.addEventListener('beforeunload', (event) => {
    if (state.snapshot && serializeAttendanceSnapshot(state.snapshot) !== state.savedSnapshotText) {
      event.preventDefault();
      event.returnValue = '';
    }
  });
}

loadEventBindings();
