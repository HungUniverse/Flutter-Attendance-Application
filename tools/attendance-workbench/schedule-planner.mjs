const maximumSearchNodes = 200_000;

function object(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${name} must be an object`);
  return value;
}

function id(value, name) {
  if (typeof value !== 'string' || !value.trim()) throw new TypeError(`${name} must be a non-empty string`);
  return value.trim();
}

function optionalId(value, name) {
  return value === undefined || value === null || value === '' ? null : id(value, name);
}

function stringList(value, name) {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new TypeError(`${name} must be an array`);
  const result = value.map((item, index) => id(item, `${name}[${index}]`));
  if (new Set(result).size !== result.length) throw new TypeError(`${name} must not contain duplicates`);
  return result;
}

function finiteDate(value, name) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw new TypeError(`${name} must be a valid ISO date-time`);
  return new Date(value).toISOString();
}

function uniqueById(items, name, normalize) {
  if (!Array.isArray(items)) throw new TypeError(`${name} must be an array`);
  const seen = new Set();
  return items.map((value, index) => {
    const item = normalize(object(value, `${name}[${index}]`), index);
    if (seen.has(item.id)) throw new TypeError(`${name} contains duplicate ID ${item.id}`);
    seen.add(item.id);
    return item;
  });
}

function normalizeTask(task, index) {
  const durationMinutes = task.durationMinutes;
  const size = task.size ?? 0;
  if (!Number.isSafeInteger(durationMinutes) || durationMinutes <= 0) throw new RangeError(`tasks[${index}].durationMinutes must be a positive integer`);
  if (!Number.isSafeInteger(size) || size < 0) throw new RangeError(`tasks[${index}].size must be a non-negative integer`);
  return {
    id: id(task.id, `tasks[${index}].id`),
    title: typeof task.title === 'string' ? task.title.trim().slice(0, 160) : '',
    durationMinutes,
    size,
    groupId: optionalId(task.groupId, `tasks[${index}].groupId`),
    instructorId: optionalId(task.instructorId, `tasks[${index}].instructorId`),
    resources: stringList(task.resources, `tasks[${index}].resources`),
    requiredFeatures: stringList(task.requiredFeatures, `tasks[${index}].requiredFeatures`),
    preferredSlotIds: stringList(task.preferredSlotIds, `tasks[${index}].preferredSlotIds`),
  };
}

function normalizeSlot(slot, index) {
  const start = finiteDate(slot.start, `slots[${index}].start`);
  const availableUntil = finiteDate(slot.end, `slots[${index}].end`);
  if (Date.parse(availableUntil) <= Date.parse(start)) throw new RangeError(`slots[${index}] must end after it starts`);
  const capacity = slot.capacity ?? Number.MAX_SAFE_INTEGER;
  if (!Number.isSafeInteger(capacity) || capacity < 0) throw new RangeError(`slots[${index}].capacity must be a non-negative integer`);
  return {
    id: id(slot.id, `slots[${index}].id`),
    start,
    end: availableUntil,
    roomId: id(slot.roomId, `slots[${index}].roomId`),
    capacity,
    features: stringList(slot.features, `slots[${index}].features`),
    resources: stringList(slot.resources, `slots[${index}].resources`),
  };
}

function normalizeBlocks(value) {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new TypeError('unavailable must be an array');
  return value.map((block, index) => {
    object(block, `unavailable[${index}]`);
    const slotId = id(block.slotId, `unavailable[${index}].slotId`);
    const groupId = optionalId(block.groupId, `unavailable[${index}].groupId`);
    const instructorId = optionalId(block.instructorId, `unavailable[${index}].instructorId`);
    if (!groupId && !instructorId) throw new TypeError(`unavailable[${index}] must name a group or instructor`);
    return { slotId, groupId, instructorId };
  });
}

function prepare(inputValue) {
  const input = object(inputValue, 'planner input');
  const tasks = uniqueById(input.tasks, 'tasks', normalizeTask);
  const slots = uniqueById(input.slots, 'slots', normalizeSlot);
  if (tasks.length > 200) throw new RangeError('tasks must contain at most 200 meetings');
  if (slots.length > 2_000) throw new RangeError('slots must contain at most 2000 options');
  const unavailable = normalizeBlocks(input.unavailable);
  const maxNodes = input.maxSearchNodes ?? 25_000;
  if (!Number.isSafeInteger(maxNodes) || maxNodes < 1 || maxNodes > maximumSearchNodes) {
    throw new RangeError(`maxSearchNodes must be between 1 and ${maximumSearchNodes}`);
  }
  const slotIds = new Set(slots.map((slot) => slot.id));
  for (const task of tasks) {
    for (const preferred of task.preferredSlotIds) {
      if (!slotIds.has(preferred)) throw new TypeError(`task ${task.id} prefers unknown slot ${preferred}`);
    }
  }
  for (const block of unavailable) if (!slotIds.has(block.slotId)) throw new TypeError(`unavailable rule references unknown slot ${block.slotId}`);
  return { tasks, slots, unavailable, maxNodes };
}

function candidateRejection(task, slot) {
  const reasons = [];
  const duration = Date.parse(slot.end) - Date.parse(slot.start);
  if (task.size > slot.capacity) reasons.push('room_capacity');
  if (task.durationMinutes * 60_000 > duration) reasons.push('slot_too_short');
  const availableFeatures = new Set(slot.features);
  if (!task.requiredFeatures.every((feature) => availableFeatures.has(feature))) reasons.push('missing_room_features');
  return reasons;
}

function isBlocked(task, slot, rules) {
  return rules.some((rule) => rule.slotId === slot.id &&
    ((rule.groupId && rule.groupId === task.groupId) ||
     (rule.instructorId && rule.instructorId === task.instructorId)));
}

function candidateCost(task, slot) {
  if (!task.preferredSlotIds.length) return 0;
  const index = task.preferredSlotIds.indexOf(slot.id);
  return index < 0 ? 1000 : index;
}

function intervalsOverlap(first, second) {
  return Date.parse(first.start) < Date.parse(second.end) && Date.parse(second.start) < Date.parse(first.end);
}

function shared(left, right) {
  const other = new Set(right);
  return left.some((item) => other.has(item));
}

function conflictWith(task, slot, end, existing) {
  const reasons = [];
  for (const assignment of existing) {
    if (!intervalsOverlap({ start: slot.start, end }, assignment)) continue;
    if (slot.roomId === assignment.roomId) reasons.push({ taskId: assignment.id, resource: `room:${slot.roomId}` });
    if (task.groupId && task.groupId === assignment.groupId) reasons.push({ taskId: assignment.id, resource: `group:${task.groupId}` });
    if (task.instructorId && task.instructorId === assignment.instructorId) reasons.push({ taskId: assignment.id, resource: `instructor:${task.instructorId}` });
    if (shared(task.resources, assignment.resources)) {
      const resources = task.resources.filter((resource) => assignment.resources.includes(resource));
      for (const resource of resources) reasons.push({ taskId: assignment.id, resource: `resource:${resource}` });
    }
  }
  return reasons;
}

function comparePlans(first, second) {
  if (!second) return true;
  if (first.count !== second.count) return first.count > second.count;
  if (first.cost !== second.cost) return first.cost < second.cost;
  return first.key < second.key;
}

function assignmentKey(assignments) {
  return assignments.map((item) => `${item.id}@${item.slotId}`).sort().join('|');
}

/**
 * Place as many meetings as possible into compatible time/room slots. A
 * deterministic bounded search prioritizes complete plans, then preferences.
 */
export function planSchedule(inputValue) {
  const { tasks, slots, unavailable, maxNodes } = prepare(inputValue);
  const slotById = new Map(slots.map((slot) => [slot.id, slot]));
  const optionsByTask = new Map();
  const rejectionByTask = new Map();
  for (const task of tasks) {
    const options = [];
    const rejected = new Set();
    for (const slot of slots) {
      const rejections = candidateRejection(task, slot);
      if (rejections.length) { rejections.forEach((rejection) => rejected.add(rejection)); continue; }
      if (isBlocked(task, slot, unavailable)) { rejected.add('unavailable'); continue; }
      const duration = task.durationMinutes * 60_000;
      options.push({ slotId: slot.id, cost: candidateCost(task, slot),
        start: slot.start, end: new Date(Date.parse(slot.start) + duration).toISOString() });
    }
    options.sort((a, b) => a.cost - b.cost || a.start.localeCompare(b.start) || a.slotId.localeCompare(b.slotId));
    optionsByTask.set(task.id, options);
    rejectionByTask.set(task.id, [...rejected].sort());
  }

  const orderedTasks = [...tasks].sort((left, right) => optionsByTask.get(left.id).length - optionsByTask.get(right.id).length || left.id.localeCompare(right.id));
  let nodesExplored = 0;
  let truncated = false;
  let best = null;
  const assigned = [];

  function visit(index, cost) {
    if (nodesExplored >= maxNodes) { truncated = true; return; }
    nodesExplored++;
    const remaining = orderedTasks.length - index;
    if (best && assigned.length + remaining < best.count) return;
    if (best && assigned.length + remaining === best.count && cost > best.cost) return;
    if (index === orderedTasks.length) {
      const candidate = { count: assigned.length, cost, assignments: [...assigned], key: assignmentKey(assigned) };
      if (comparePlans(candidate, best)) best = candidate;
      return;
    }
    const task = orderedTasks[index];
    const options = optionsByTask.get(task.id);
    for (const option of options) {
      const slot = slotById.get(option.slotId);
      const conflicts = conflictWith(task, slot, option.end, assigned);
      if (conflicts.length) continue;
      assigned.push({ id: task.id, title: task.title, slotId: slot.id, start: option.start, end: option.end,
        roomId: slot.roomId, groupId: task.groupId, instructorId: task.instructorId,
        resources: [...new Set([...task.resources, ...slot.resources])],
        preferenceCost: option.cost });
      visit(index + 1, cost + option.cost);
      assigned.pop();
      if (truncated && nodesExplored >= maxNodes) return;
    }
    visit(index + 1, cost);
  }

  visit(0, 0);
  best ??= { count: 0, cost: 0, assignments: [], key: '' };
  const plannedIds = new Set(best.assignments.map((item) => item.id));
  const unscheduled = tasks.filter((task) => !plannedIds.has(task.id)).map((task) => {
    const blockers = [];
    for (const option of optionsByTask.get(task.id)) {
      const slot = slotById.get(option.slotId);
      blockers.push(...conflictWith(task, slot, option.end, best.assignments).map((item) => ({ slotId: slot.id, ...item })));
    }
    return {
      id: task.id,
      title: task.title,
      reasons: blockers.length ? ['resource_conflict'] : rejectionByTask.get(task.id).length
        ? rejectionByTask.get(task.id) : ['search_limit_or_competing_choice'],
      blockers: [...new Map(blockers.map((item) => [`${item.slotId}:${item.taskId}:${item.resource}`, item])).values()],
      candidateCount: optionsByTask.get(task.id).length,
    };
  });
  const assignments = [...best.assignments].sort((a, b) => a.start.localeCompare(b.start) || a.roomId.localeCompare(b.roomId) || a.id.localeCompare(b.id));
  return {
    complete: assignments.length === tasks.length,
    score: best.cost,
    assignments,
    unscheduled,
    summary: {
      tasks: tasks.length,
      scheduled: assignments.length,
      unscheduled: unscheduled.length,
      complete: assignments.length === tasks.length,
      nodesExplored,
      maxNodes,
      searchLimitReached: truncated,
    },
  };
}
