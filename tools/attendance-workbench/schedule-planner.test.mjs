import test from 'node:test';
import assert from 'node:assert/strict';
import { planSchedule } from './schedule-planner.mjs';

const slot = (id, start, end, roomId = 'R1', extra = {}) => ({ id, start, end, roomId, ...extra });
const task = (id, extra = {}) => ({ id, durationMinutes: 60, ...extra });

test('finds a complete non-overlapping plan and honors preferred slots', () => {
  const input = {
    tasks: [task('A', { groupId: 'G', instructorId: 'I', preferredSlotIds: ['morning'] }),
      task('B', { groupId: 'G', instructorId: 'I', preferredSlotIds: ['late'] })],
    slots: [slot('morning', '2026-01-01T09:00:00Z', '2026-01-01T10:00:00Z'),
      slot('late', '2026-01-01T11:00:00Z', '2026-01-01T12:00:00Z')],
  };
  const before = structuredClone(input);
  const result = planSchedule(input);
  assert.equal(result.complete, true);
  assert.deepEqual(result.assignments.map((item) => [item.id, item.slotId]), [['A', 'morning'], ['B', 'late']]);
  assert.equal(result.score, 0);
  assert.deepEqual(input, before);
});

test('prevents overlapping room, group, instructor and shared resource assignments', () => {
  const start = '2026-01-01T09:00:00Z';
  const end = '2026-01-01T11:00:00Z';
  const sharedTime = [slot('one', start, end, 'R1'), slot('two', start, end, 'R2')];
  const sameRoom = planSchedule({ tasks: [task('A'), task('B')], slots: [sharedTime[0]] });
  assert.equal(sameRoom.summary.scheduled, 1);
  assert.ok(sameRoom.unscheduled[0].blockers.some((item) => item.resource === 'room:R1'));
  const sameGroup = planSchedule({ tasks: [task('A', { groupId: 'G' }), task('B', { groupId: 'G' })], slots: sharedTime });
  assert.equal(sameGroup.summary.scheduled, 1);
  assert.ok(sameGroup.unscheduled[0].blockers.some((item) => item.resource === 'group:G'));
  const sameInstructor = planSchedule({ tasks: [task('A', { instructorId: 'I' }), task('B', { instructorId: 'I' })], slots: sharedTime });
  assert.ok(sameInstructor.unscheduled[0].blockers.some((item) => item.resource === 'instructor:I'));
  const sharedResource = planSchedule({ tasks: [task('A', { resources: ['projector'] }), task('B', { resources: ['projector'] })], slots: sharedTime });
  assert.ok(sharedResource.unscheduled[0].blockers.some((item) => item.resource === 'resource:projector'));
});

test('reports compatibility blockers for capacity, equipment and duration', () => {
  const result = planSchedule({ tasks: [task('A', { size: 40, requiredFeatures: ['lab'] })], slots: [
    slot('small', '2026-01-01T09:00:00Z', '2026-01-01T09:30:00Z', 'R1', { capacity: 20, features: [] }),
  ] });
  assert.equal(result.complete, false);
  assert.deepEqual(result.unscheduled[0].reasons, ['missing_room_features', 'room_capacity', 'slot_too_short']);
});

test('honors group and instructor unavailability', () => {
  const result = planSchedule({ tasks: [task('A', { groupId: 'G' })],
    slots: [slot('blocked', '2026-01-01T09:00:00Z', '2026-01-01T10:00:00Z')],
    unavailable: [{ groupId: 'G', slotId: 'blocked' }] });
  assert.deepEqual(result.unscheduled[0].reasons, ['unavailable']);
});

test('uses a deterministic node budget and exposes truncated searches', () => {
  const input = { tasks: [task('A')], slots: [slot('one', '2026-01-01T09:00:00Z', '2026-01-01T10:00:00Z')], maxSearchNodes: 1 };
  const first = planSchedule(input);
  const second = planSchedule(input);
  assert.equal(first.summary.searchLimitReached, true);
  assert.equal(first.summary.nodesExplored, 1);
  assert.deepEqual(first, second);
});

test('validates duplicate identifiers, malformed dates and search bounds', () => {
  assert.throws(() => planSchedule({ tasks: [task('A'), task('A')], slots: [] }), /duplicate ID/);
  assert.throws(() => planSchedule({ tasks: [], slots: [slot('x', 'bad', '2026-01-01T10:00:00Z')] }), /valid ISO/);
  assert.throws(() => planSchedule({ tasks: [], slots: [], maxSearchNodes: 0 }), /maxSearchNodes/);
  assert.throws(() => planSchedule({ tasks: [task('A', { preferredSlotIds: ['missing'] })], slots: [] }), /unknown slot/);
});
