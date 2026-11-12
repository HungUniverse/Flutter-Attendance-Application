import test from 'node:test';
import assert from 'node:assert/strict';
import { analyzeScheduleInsights, scheduleInsightsToCsv } from './schedule-insights.mjs';

function schedule() {
  return [
    { id: 'A', title: '=Morning lesson', start: '2026-11-02T09:00:00Z', end: '2026-11-02T10:00:00Z',
      roomId: 'R1', groupId: 'G1', instructorId: 'T1', resources: ['PROJECTOR'], attendees: 31 },
    { id: 'B', title: 'Second lesson', start: '2026-11-02T10:05:00Z', end: '2026-11-02T11:00:00Z',
      roomId: 'R1', groupId: 'G2', instructorId: 'T2', resources: ['PROJECTOR'], attendees: 10 },
    { id: 'C', title: 'Overlapping lesson', start: '2026-11-02T09:30:00Z', end: '2026-11-02T10:30:00Z',
      roomId: 'R2', groupId: 'G1', instructorId: 'T3', resources: ['PROJECTOR'], attendees: 12 },
    { id: 'D', title: 'Next day', start: '2026-11-03T14:00:00Z', end: '2026-11-03T15:30:00Z',
      roomId: 'R2', groupId: 'G2', instructorId: 'T1', resources: [], attendees: 18 },
  ];
}

test('summarizes duration, weekly load and resource types without mutating the schedule', () => {
  const input = schedule();
  const before = JSON.stringify(input);
  const report = analyzeScheduleInsights(input, { resourceCatalog: [
    { id: 'R1', kind: 'room', capacity: 25 }, { id: 'R2', kind: 'room', capacity: 20 },
    { id: 'G1', kind: 'group' }, { id: 'G2', kind: 'group' },
    { id: 'T1', kind: 'instructor' }, { id: 'T2', kind: 'instructor' }, { id: 'T3', kind: 'instructor' },
    { id: 'PROJECTOR', kind: 'equipment' },
  ] });
  assert.equal(report.format, 'attendance-schedule-insights');
  assert.equal(report.summary.sessions, 4);
  assert.equal(report.summary.daysUsed, 2);
  assert.equal(report.summary.conflicts, 2);
  assert.equal(report.summary.totalMinutes, 265);
  assert.equal(report.summary.scheduledAttendees, 71);
  assert.equal(report.resources.find((resource) => resource.id === 'R1').kind, 'room');
  assert.equal(report.resources.find((resource) => resource.id === 'PROJECTOR').sessions, 3);
  assert.equal(JSON.stringify(input), before);
});

test('reports shared-resource overlaps with exact intersection intervals', () => {
  const report = analyzeScheduleInsights(schedule());
  assert.equal(report.conflicts.length, 2);
  assert.deepEqual(report.conflicts[0], {
    firstId: 'A', secondId: 'C', start: '2026-11-02T09:30:00.000Z', end: '2026-11-02T10:00:00.000Z', resources: ['G1', 'PROJECTOR'],
  });
  assert.deepEqual(report.conflicts[1], {
    firstId: 'C', secondId: 'B', start: '2026-11-02T10:05:00.000Z', end: '2026-11-02T10:30:00.000Z', resources: ['PROJECTOR'],
  });
  assert.equal(report.warnings[0].code, 'shared_resource_overlap');
  assert.equal(report.warnings[0].severity, 'error');
});

test('computes interval unions, overlap minutes and room capacity warnings', () => {
  const report = analyzeScheduleInsights(schedule(), { resourceCatalog: [
    { id: 'R1', kind: 'room', capacity: 25 }, { id: 'PROJECTOR', kind: 'equipment' },
  ] });
  const projector = report.resources.find((resource) => resource.id === 'PROJECTOR');
  assert.equal(projector.assignedMinutes, 175);
  assert.equal(projector.unionOccupiedMinutes, 120);
  assert.equal(projector.overlapMinutes, 55);
  assert.equal(report.warnings.filter((warning) => warning.code === 'room_capacity_exceeded').length, 1);
  assert.deepEqual(report.warnings.find((warning) => warning.code === 'room_capacity_exceeded'), {
    code: 'room_capacity_exceeded', severity: 'warning', sessionId: 'A', roomId: 'R1', attendees: 31, capacity: 25, excess: 6,
  });
});

test('detects short turnarounds between consecutive resource bookings', () => {
  const report = analyzeScheduleInsights(schedule(), { minimumBufferMinutes: 15 });
  const short = report.warnings.filter((warning) => warning.code === 'short_resource_turnaround');
  assert.ok(short.some((warning) => warning.resourceId === 'R1' && warning.gapMinutes === 5));
  assert.equal(short.some((warning) => warning.resourceId === 'T1'), false);
  assert.equal(short.some((warning) => warning.resourceId === 'PROJECTOR'), false,
    'the overlapping C booking keeps the projector occupied beyond the apparent A-to-B five-minute gap');
});

test('reports availability-based utilization and minutes outside recurring UTC windows', () => {
  const report = analyzeScheduleInsights(schedule(), {
    window: { start: '2026-11-02T00:00:00Z', end: '2026-11-04T00:00:00Z' },
    availability: [
      { resourceId: 'R1', weekdays: [1], start: '09:00', end: '12:00' },
      { resourceId: 'R2', weekdays: [1, 2], start: '09:00', end: '16:00' },
    ],
  });
  const r1 = report.resources.find((resource) => resource.id === 'R1');
  const r2 = report.resources.find((resource) => resource.id === 'R2');
  assert.equal(r1.availableMinutes, 180);
  assert.equal(r1.utilization, 115 / 180);
  assert.equal(r1.outsideAvailabilityMinutes, 0);
  assert.equal(r2.availableMinutes, 840);
  assert.equal(r2.outsideAvailabilityMinutes, 0);
  assert.equal(report.window.days, 2);
});

test('clips recurring availability to the requested window and handles unused availability days', () => {
  const report = analyzeScheduleInsights(schedule(), {
    window: { start: '2026-11-02T09:30:00Z', end: '2026-11-02T10:30:00Z' },
    availability: [{ resourceId: 'R1', weekdays: [1], start: '09:00', end: '12:00' }],
  });
  const r1 = report.resources.find((resource) => resource.id === 'R1');
  assert.equal(r1.availableMinutes, 60);
  assert.equal(r1.sessions, 2);
  assert.equal(r1.outsideAvailabilityMinutes, 0);
  assert.equal(report.summary.sessions, 3);
});

test('calculates daily and weekly load histograms and enforces optional workload limits', () => {
  const report = analyzeScheduleInsights(schedule(), { maximumDailySessions: 2, maximumDailyMinutes: 150 });
  const monday = report.daily.find((day) => day.date === '2026-11-02');
  assert.equal(monday.weekday, 1);
  assert.equal(monday.sessions, 3);
  assert.equal(monday.totalMinutes, 175);
  assert.equal(monday.earliestStart, '2026-11-02T09:00:00.000Z');
  assert.equal(monday.latestEnd, '2026-11-02T11:00:00.000Z');
  assert.ok(report.warnings.some((warning) => warning.code === 'daily_session_limit_exceeded'));
  assert.ok(report.warnings.some((warning) => warning.code === 'daily_minutes_limit_exceeded'));
  assert.equal(report.weekdays[1].sessions, 3);
  assert.equal(report.hours[9].sessionsStarting, 2);
});

test('caps timeline rows and supports summary-only output', () => {
  const limited = analyzeScheduleInsights(schedule(), { maximumTimelineRows: 2 });
  assert.equal(limited.timeline.length, 2);
  assert.equal(limited.summary.timelineTruncated, 2);
  const summary = analyzeScheduleInsights(schedule(), { includeTimeline: false });
  assert.equal(summary.timeline, null);
  assert.equal(summary.summary.timelineTruncated, null);
  assert.throws(() => scheduleInsightsToCsv(summary, 'timeline'), /not included/);
});

test('exports formula-safe resource, daily, conflict, warning, timeline and histogram CSV', () => {
  const report = analyzeScheduleInsights(schedule());
  assert.match(scheduleInsightsToCsv(report), /"resourceId","label","kind","capacity"/);
  assert.match(scheduleInsightsToCsv(report, 'daily'), /"date","weekday","sessions"/);
  assert.match(scheduleInsightsToCsv(report, 'conflicts'), /"firstId","secondId"/);
  assert.match(scheduleInsightsToCsv(report, 'warnings'), /"code","severity"/);
  assert.match(scheduleInsightsToCsv(report, 'timeline'), /'=Morning lesson/);
  assert.match(scheduleInsightsToCsv(report, 'weekdays'), /"weekday","sessions","minutes"/);
  assert.match(scheduleInsightsToCsv(report, 'hours'), /"hourUtc","sessionsStarting"/);
  assert.throws(() => scheduleInsightsToCsv({ format: 'wrong', version: 1 }, 'resources'), /invalid/);
  assert.throws(() => scheduleInsightsToCsv(report, 'raw'), /section must be/);
});

test('validates schedule, UTC windows, resource capacities and availability declarations', () => {
  assert.throws(() => analyzeScheduleInsights(null), /schedule must be an array/);
  assert.throws(() => analyzeScheduleInsights([{ id: 'A', start: '2026-02-30T09:00:00Z', end: '2026-02-30T10:00:00Z', resources: [] }]), /not a valid timestamp/);
  assert.throws(() => analyzeScheduleInsights([{ id: 'A', start: '2026-11-02T09:00:00Z', end: '2026-11-02T10:00:00Z' }]), /resources must be an array/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { window: { start: 'bad', end: '2026-11-04T00:00:00Z' } }), /explicit offset/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { maximumDailySessions: 0 }), /from 1 to 1000/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { minimumBufferMinutes: 1441 }), /from 0 to 1440/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { resourceCatalog: [{ id: 'R1' }, { id: 'R1' }] }), /duplicate resource/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { resourceCatalog: [{ id: 'R1', capacity: -1 }] }), /from 0 to 1000000/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { availability: [{ resourceId: 'UNKNOWN', weekdays: [1], start: '09:00', end: '10:00' }] }), /not used in the schedule/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { availability: [{ resourceId: 'R1', weekdays: [7], start: '09:00', end: '10:00' }] }), /from 0 to 6/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { availability: [{ resourceId: 'R1', weekdays: [1], start: '12:00', end: '09:00' }] }), /end later/);
});

test('rejects oversized time windows and malformed resource metadata', () => {
  assert.throws(() => analyzeScheduleInsights([], { window: {
    start: '2026-01-01T00:00:00Z', end: '2027-01-10T00:00:00Z',
  } }), /must not exceed 366 days/);
  assert.throws(() => analyzeScheduleInsights([{ id: 'A', start: '2026-11-02T09:00:00Z', end: '2026-11-02T10:00:00Z',
    resources: [], attendees: -1 }]), /from 0 to 1000000/);
  assert.throws(() => analyzeScheduleInsights(schedule(), { maximumTimelineRows: 100_001 }), /from 1 to 100000/);
});

test('handles an empty schedule without creating resource or daily records', () => {
  const report = analyzeScheduleInsights([]);
  assert.equal(report.summary.sessions, 0);
  assert.equal(report.summary.resources, 0);
  assert.deepEqual(report.daily, []);
  assert.equal(report.conflicts.length, 0);
  assert.equal(report.timeline.length, 0);
});
