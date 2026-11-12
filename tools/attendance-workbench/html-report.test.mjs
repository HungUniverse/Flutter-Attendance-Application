import test from 'node:test';
import assert from 'node:assert/strict';
import { createAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { renderHtmlReport } from './html-report.mjs';

test('renders coverage, attendance and missing results while escaping user input', () => {
  const snapshot = createAttendanceSnapshot([{ id: 'A', name: '<script>alert(1)</script>', email: 'a@example.com' }],
    ['1', '<session>'], [{ studentId: 'A', sessionId: '1', status: 'present' }]);
  const html = renderHtmlReport(snapshot, 'Class & report');
  assert.match(html, /Class &amp; report/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /&lt;session&gt;/);
  assert.match(html, /50\.0%/);
  assert.match(html, /100\.0%/);
});

test('renders empty datasets and validates snapshots and titles', () => {
  const snapshot = createAttendanceSnapshot([], [], []);
  const html = renderHtmlReport(snapshot);
  assert.match(html, /No students/);
  assert.match(html, /No sessions/);
  assert.throws(() => renderHtmlReport(snapshot, ' '), /title/);
  assert.throws(() => renderHtmlReport({ ...snapshot, version: 2 }), /version/);
});
