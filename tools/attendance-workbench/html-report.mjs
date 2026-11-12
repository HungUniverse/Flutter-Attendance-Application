import { parseAttendanceSnapshot, serializeAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { attendanceQualityReport } from '../../backend/attendance-quality-report.mjs';

function escapeHtml(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}

function percent(value) {
  return value === null ? '—' : `${(value * 100).toFixed(1)}%`;
}

/** Produce a self-contained HTML report without scripts or remote resources. */
export function renderHtmlReport(snapshot, title = 'Attendance report') {
  if (typeof title !== 'string' || !title.trim()) throw new TypeError('title must be a non-empty string');
  const data = parseAttendanceSnapshot(serializeAttendanceSnapshot(snapshot));
  const report = attendanceQualityReport(data.roster, data.sessionIds, data.records);
  const students = report.students.map(({ student, present, absent, missingSessionIds }) => {
    const rate = present + absent ? present / (present + absent) : null;
    const missing = missingSessionIds.length ? missingSessionIds.map(escapeHtml).join(', ') : '—';
    return `<tr><th scope="row">${escapeHtml(student.name)}</th><td>${escapeHtml(student.id)}</td>` +
      `<td>${present}</td><td>${absent}</td><td>${percent(rate)}</td><td>${missing}</td></tr>`;
  }).join('\n');
  const sessions = report.sessions.map(({ sessionId, present, absent, missingStudentIds }) =>
    `<tr><th scope="row">${escapeHtml(sessionId)}</th><td>${present}</td><td>${absent}</td>` +
    `<td>${missingStudentIds.length}</td></tr>`).join('\n');
  const heading = escapeHtml(title.trim());
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${heading}</title>
<style>
  :root { color-scheme: light; font-family: system-ui, sans-serif; color: #18242c; background: #f3f6f5; }
  body { max-width: 1100px; margin: 0 auto; padding: 2rem 1rem; line-height: 1.5; }
  h1, h2 { line-height: 1.2; }
  .summary { display: flex; flex-wrap: wrap; gap: 1rem; margin: 1.5rem 0; }
  .metric { background: white; border: 1px solid #d5e0dc; border-radius: .5rem; padding: 1rem; min-width: 8rem; }
  .metric strong { display: block; font-size: 1.5rem; }
  .table-wrap { overflow-x: auto; background: white; border: 1px solid #d5e0dc; }
  table { width: 100%; border-collapse: collapse; text-align: left; }
  th, td { padding: .65rem; border-bottom: 1px solid #e1e9e6; vertical-align: top; }
  thead { background: #e6f0ec; }
  caption { text-align: left; padding: .75rem; font-weight: 600; }
  @media print { body { max-width: none; padding: 0; } .table-wrap { overflow: visible; } }
</style>
</head>
<body>
<main>
<h1>${heading}</h1>
<p>Attendance rates use recorded results. Missing results are shown separately.</p>
<div class="summary">
  <div class="metric"><strong>${data.roster.length}</strong>Students</div>
  <div class="metric"><strong>${data.sessionIds.length}</strong>Sessions</div>
  <div class="metric"><strong>${report.recorded} / ${report.expected}</strong>Recorded results</div>
  <div class="metric"><strong>${percent(report.coverage)}</strong>Coverage</div>
</div>
<h2>Students</h2>
<div class="table-wrap"><table><caption>Attendance and missing sessions by student</caption>
<thead><tr><th scope="col">Name</th><th scope="col">ID</th><th scope="col">Present</th><th scope="col">Absent</th><th scope="col">Attendance</th><th scope="col">Missing sessions</th></tr></thead>
<tbody>${students || '<tr><td colspan="6">No students</td></tr>'}</tbody></table></div>
<h2>Sessions</h2>
<div class="table-wrap"><table><caption>Results by session</caption>
<thead><tr><th scope="col">Session</th><th scope="col">Present</th><th scope="col">Absent</th><th scope="col">Missing</th></tr></thead>
<tbody>${sessions || '<tr><td colspan="4">No sessions</td></tr>'}</tbody></table></div>
</main>
</body>
</html>\n`;
}
