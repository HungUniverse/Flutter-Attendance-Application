import { createAttendanceSnapshot, parseAttendanceSnapshot } from '../../backend/attendance-snapshot.mjs';
import { buildAttendanceReport } from '../../backend/attendance-report.mjs';

const VERSION = 1;
const MAX_STUDENTS = 10_000;
const MAX_SESSIONS = 500;
const MAX_CELLS = 250_000;
const PROFILE_KEYS = ['steady', 'improving', 'declining', 'intermittent', 'atRisk', 'perfect', 'rare', 'unrecorded'];
const MISSING_PATTERNS = new Set(['random', 'early', 'recent', 'blocks']);

const PROFILE_DETAILS = Object.freeze({
  steady: { label: 'Ổn định', description: 'Tỷ lệ có mặt cao và ít biến động.', base: 0.88 },
  improving: { label: 'Tiến bộ', description: 'Tỷ lệ có mặt tăng dần theo thời gian.', base: 0.36 },
  declining: { label: 'Giảm dần', description: 'Tỷ lệ có mặt giảm dần theo thời gian.', base: 0.94 },
  intermittent: { label: 'Ngắt quãng', description: 'Có mặt và vắng theo các đợt xen kẽ.', base: 0.68 },
  atRisk: { label: 'Cần theo dõi', description: 'Tỷ lệ thấp, có xu hướng thành chuỗi vắng.', base: 0.5 },
  perfect: { label: 'Chuyên cần', description: 'Luôn có mặt ở mọi buổi được ghi nhận.', base: 1 },
  rare: { label: 'Vắng nhiều', description: 'Hầu như luôn vắng mặt.', base: 0.08 },
  unrecorded: { label: 'Thiếu dữ liệu', description: 'Có kết quả ở một số buổi và thiếu ở phần còn lại.', base: 0.76 },
});

const DEFAULT_MIX = Object.freeze({
  steady: 30, improving: 12, declining: 12, intermittent: 14,
  atRisk: 14, perfect: 8, rare: 4, unrecorded: 6,
});

function object(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${field} must be an object`);
  return value;
}

function integer(value, field, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new RangeError(`${field} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}

function fraction(value, field, maximum = 1) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > maximum) {
    throw new RangeError(`${field} must be a number from 0 to ${maximum}`);
  }
  return value;
}

function label(value, field, fallback, maximum = 48) {
  const result = value ?? fallback;
  if (typeof result !== 'string' || !result.trim() || result.trim().length > maximum) {
    throw new TypeError(`${field} must be a non-empty string of at most ${maximum} characters`);
  }
  return result.trim();
}

function normalizeSeed(value) {
  const seed = value ?? 20261112;
  if (typeof seed === 'number' && Number.isSafeInteger(seed)) return String(seed);
  if (typeof seed === 'string' && seed.trim() && seed.length <= 120) return seed.trim();
  throw new TypeError('seed must be a safe integer or a non-empty string of at most 120 characters');
}

function hashSeed(value) {
  let hash = 0x811c9dc5;
  for (const char of value) {
    hash ^= char.codePointAt(0);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0 || 0x6d2b79f5;
}

function randomSource(seedText) {
  let state = hashSeed(seedText);
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 0x1_0000_0000;
  };
}

function normalizeMix(value) {
  if (value === undefined) return { ...DEFAULT_MIX };
  object(value, 'profileMix');
  const mix = Object.fromEntries(PROFILE_KEYS.map((key) => [key, 0]));
  for (const [key, weight] of Object.entries(value)) {
    if (!PROFILE_KEYS.includes(key)) throw new TypeError(`unknown synthetic profile: ${key}`);
    if (typeof weight !== 'number' || !Number.isFinite(weight) || weight < 0 || weight > 1_000_000) {
      throw new RangeError(`profileMix.${key} must be a number from 0 to 1000000`);
    }
    mix[key] = weight;
  }
  if (!Object.values(mix).some((weight) => weight > 0)) throw new RangeError('profileMix must include a positive weight');
  return mix;
}

function normalizeOptions(value = {}) {
  object(value, 'options');
  const students = integer(value.students ?? 40, 'students', 1, MAX_STUDENTS);
  const sessions = integer(value.sessions ?? 16, 'sessions', 1, MAX_SESSIONS);
  const cells = students * sessions;
  if (cells > MAX_CELLS) throw new RangeError(`students × sessions must not exceed ${MAX_CELLS} cells`);
  const missingPattern = value.missingPattern ?? 'random';
  if (typeof missingPattern !== 'string' || !MISSING_PATTERNS.has(missingPattern)) {
    throw new TypeError(`missingPattern must be one of: ${[...MISSING_PATTERNS].join(', ')}`);
  }
  const requestedAbsenceRate = fraction(value.absenceRate ?? 0.22, 'absenceRate');
  const missingRate = fraction(value.missingRate ?? 0.04, 'missingRate', 0.95);
  const profileMix = normalizeMix(value.profileMix);
  const groupCount = integer(value.groupCount ?? 1, 'groupCount', 1, Math.min(100, students));
  const groupPrefix = label(value.groupPrefix, 'groupPrefix', 'NHOM', 32);
  const studentPrefix = label(value.studentPrefix, 'studentPrefix', 'DEMO', 24);
  const sessionPrefix = label(value.sessionPrefix, 'sessionPrefix', 'BUOI', 24);
  const sectionName = label(value.sectionName, 'sectionName', 'Lop gia lap', 80);
  const seed = normalizeSeed(value.seed);
  const missingBlockLength = integer(value.missingBlockLength ?? Math.max(1, Math.ceil(sessions * missingRate * 1.6)),
    'missingBlockLength', 1, sessions);
  const baseAttendance = fraction(value.baseAttendance ?? (1 - requestedAbsenceRate), 'baseAttendance');
  const absenceRate = Number((1 - baseAttendance).toFixed(6));
  const streakiness = fraction(value.streakiness ?? 0.42, 'streakiness');
  return {
    version: VERSION, seed, students, sessions, cells, missingRate, missingPattern, missingBlockLength,
    absenceRate, baseAttendance, streakiness, groupCount, groupPrefix, studentPrefix, sessionPrefix,
    sectionName, profileMix,
  };
}

function chooseWeighted(mix, draw) {
  const total = Object.values(mix).reduce((sum, weight) => sum + weight, 0);
  let cursor = draw * total;
  for (const [key, weight] of Object.entries(mix)) {
    cursor -= weight;
    if (cursor < 0) return key;
  }
  return Object.keys(mix).find((key) => mix[key] > 0);
}

function profileRate(profile, progress, phase, baseAttendance) {
  const details = PROFILE_DETAILS[profile];
  switch (profile) {
    case 'steady': return details.base * 0.7 + baseAttendance * 0.3;
    case 'improving': return 0.25 + progress * 0.68;
    case 'declining': return 0.94 - progress * 0.62;
    case 'intermittent': return 0.56 + (Math.sin(progress * Math.PI * 4 + phase) + 1) * 0.2;
    case 'atRisk': return Math.min(0.68, details.base * 0.62 + baseAttendance * 0.28);
    case 'perfect': return 0.985;
    case 'rare': return 0.07;
    case 'unrecorded': return details.base * 0.7 + baseAttendance * 0.3;
    default: throw new TypeError(`unknown synthetic profile: ${profile}`);
  }
}

function isMissing(options, random, studentIndex, sessionIndex, blockStart, profile) {
  if (!options.missingRate) return false;
  if (options.missingPattern === 'random') {
    const rate = profile === 'unrecorded' ? Math.max(0.4, options.missingRate) : options.missingRate;
    return random() < rate;
  }
  const patternedSessions = Math.ceil(options.sessions * options.missingRate);
  if (options.missingPattern === 'early') return sessionIndex < patternedSessions;
  if (options.missingPattern === 'recent') return sessionIndex >= options.sessions - patternedSessions;
  const start = blockStart[studentIndex];
  return start !== null && sessionIndex >= start && sessionIndex < start + options.missingBlockLength;
}

function makeRoster(options, random) {
  return Array.from({ length: options.students }, (_, index) => {
    const number = String(index + 1).padStart(String(options.students).length, '0');
    const groupIndex = index % options.groupCount;
    const groupNumber = String(groupIndex + 1).padStart(2, '0');
    return {
      id: `${options.studentPrefix}-${number}`,
      name: `Demo Student ${number}`,
      email: `student-${number}@example.invalid`,
      // Keep cohort data outside the validated application snapshot.
      syntheticGroup: `${options.groupPrefix}-${groupNumber}`,
      syntheticPhase: random() * Math.PI * 2,
    };
  });
}

function snapshotRoster(roster) {
  return roster.map(({ id, name, email }) => ({ id, name, email }));
}

function fnvFingerprint(snapshot) {
  let hash = 0x811c9dc5;
  const mix = (text) => {
    for (let index = 0; index < text.length; index++) {
      hash ^= text.charCodeAt(index);
      hash = Math.imul(hash, 0x01000193);
    }
  };
  mix(JSON.stringify(snapshot));
  return (hash >>> 0).toString(16).padStart(8, '0');
}

function summarize(snapshot, profiles, options) {
  const reports = buildAttendanceReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
  const present = snapshot.records.filter((record) => record.status === 'present').length;
  const absent = snapshot.records.length - present;
  const missing = options.cells - snapshot.records.length;
  const bySession = snapshot.sessionIds.map((sessionId, index) => {
    const rows = reports.map((student) => student.sessions[index]);
    const sessionPresent = rows.filter((row) => row.status === 'present').length;
    const sessionAbsent = rows.filter((row) => row.status === 'absent').length;
    return { sessionId, present: sessionPresent, absent: sessionAbsent,
      missing: options.students - sessionPresent - sessionAbsent,
      attendanceRate: sessionPresent + sessionAbsent ? sessionPresent / (sessionPresent + sessionAbsent) : null };
  });
  const byProfile = Object.fromEntries(PROFILE_KEYS.map((profile) => [profile, { students: 0, present: 0, absent: 0, missing: 0 }]));
  reports.forEach((student, index) => {
    const target = byProfile[profiles[index]];
    target.students++;
    target.present += student.present;
    target.absent += student.absent;
    target.missing += student.missing;
  });
  return {
    version: VERSION,
    synthetic: true,
    fingerprint: fnvFingerprint(snapshot),
    configuration: options,
    dimensions: { students: options.students, sessions: options.sessions, cells: options.cells,
      records: snapshot.records.length, present, absent, missing, coverage: options.cells ? snapshot.records.length / options.cells : null },
    profileCounts: Object.fromEntries(PROFILE_KEYS.map((key) => [key, profiles.filter((profile) => profile === key).length])),
    byProfile,
    bySession,
    students: reports.map((student, index) => {
      const firstRecorded = student.sessions.find((item) => item.status !== 'missing');
      const lastRecorded = [...student.sessions].reverse().find((item) => item.status !== 'missing');
      return {
        studentId: student.student.id,
        profile: profiles[index],
        group: `${options.groupPrefix}-${String(index % options.groupCount + 1).padStart(2, '0')}`,
        present: student.present,
        absent: student.absent,
        missing: student.missing,
        attendanceRate: student.attendanceRate,
        firstSessionRate: firstRecorded ? Number(firstRecorded.status === 'present') : null,
        lastSessionRate: lastRecorded ? Number(lastRecorded.status === 'present') : null,
      };
    }),
  };
}

/** Return the documented synthetic behavior profiles and their meanings. */
export function listSyntheticProfiles() {
  return PROFILE_KEYS.map((id) => ({ id, label: PROFILE_DETAILS[id].label, description: PROFILE_DETAILS[id].description }));
}

/**
 * Generate a deterministic, schema-valid demo snapshot plus cohort analytics.
 * No filesystem, clock, network, or production datastore access occurs.
 */
export function generateSyntheticDataset(optionsValue = {}) {
  const options = normalizeOptions(optionsValue);
  const random = randomSource(options.seed);
  const rosterWithTraits = makeRoster(options, random);
  const roster = snapshotRoster(rosterWithTraits);
  const sessionIds = Array.from({ length: options.sessions }, (_, index) =>
    `${options.sessionPrefix}-${String(index + 1).padStart(String(options.sessions).length, '0')}`);
  const profiles = rosterWithTraits.map(() => chooseWeighted(options.profileMix, random()));
  const blockStart = profiles.map((profile) => {
    if (options.missingPattern !== 'blocks' || !options.missingRate) return null;
    const share = Math.max(options.missingRate * 2, profile === 'unrecorded' ? 0.7 : 0);
    if (random() >= Math.min(0.85, share)) return null;
    const latestStart = Math.max(0, options.sessions - options.missingBlockLength);
    return Math.floor(random() * (latestStart + 1));
  });
  const records = [];
  for (let studentIndex = 0; studentIndex < roster.length; studentIndex++) {
    let absenceStreak = 0;
    const profile = profiles[studentIndex];
    const phase = rosterWithTraits[studentIndex].syntheticPhase;
    for (let sessionIndex = 0; sessionIndex < sessionIds.length; sessionIndex++) {
      if (isMissing(options, random, studentIndex, sessionIndex, blockStart, profile)) continue;
      const progress = options.sessions === 1 ? 1 : sessionIndex / (options.sessions - 1);
      let probability = profileRate(profile, progress, phase, options.baseAttendance);
      probability -= Math.min(absenceStreak * options.streakiness * 0.12, 0.38);
      probability = Math.max(0.01, Math.min(0.995, probability));
      const status = profile === 'perfect' || random() < probability ? 'present' : 'absent';
      records.push({ studentId: roster[studentIndex].id, sessionId: sessionIds[sessionIndex], status });
      absenceStreak = status === 'absent' ? absenceStreak + 1 : 0;
    }
  }
  const snapshot = createAttendanceSnapshot(roster, sessionIds, records);
  const manifest = summarize(snapshot, profiles, options);
  return { version: VERSION, synthetic: true, snapshot, manifest };
}

/** Rebuild and validate the snapshot portion of a generated dataset envelope. */
export function parseSyntheticDataset(value) {
  let parsed = value;
  if (typeof value === 'string') {
    try { parsed = JSON.parse(value); }
    catch { throw new TypeError('synthetic dataset must contain valid JSON'); }
  }
  object(parsed, 'synthetic dataset');
  if (parsed.version !== VERSION || parsed.synthetic !== true) throw new TypeError('unsupported synthetic dataset envelope');
  const snapshot = parseAttendanceSnapshot(JSON.stringify(parsed.snapshot));
  object(parsed.manifest, 'manifest');
  if (parsed.manifest.fingerprint !== fnvFingerprint(snapshot)) throw new TypeError('synthetic dataset fingerprint does not match its snapshot');
  return { version: VERSION, synthetic: true, snapshot, manifest: structuredClone(parsed.manifest) };
}

/** Produce stable JSON for saving or passing a generated dataset to another tool. */
export function serializeSyntheticDataset(datasetValue) {
  const dataset = parseSyntheticDataset(datasetValue);
  return `${JSON.stringify({ version: VERSION, synthetic: true, snapshot: dataset.snapshot, manifest: dataset.manifest }, null, 2)}\n`;
}

/** Summarize an arbitrary valid snapshot without making synthetic-data claims. */
export function summarizeDatasetSnapshot(snapshotValue) {
  const snapshot = parseAttendanceSnapshot(JSON.stringify(snapshotValue));
  const reports = buildAttendanceReport(snapshot.roster, snapshot.sessionIds, snapshot.records);
  const recordCount = snapshot.records.length;
  const expected = snapshot.roster.length * snapshot.sessionIds.length;
  return {
    students: snapshot.roster.length,
    sessions: snapshot.sessionIds.length,
    expected,
    recorded: recordCount,
    missing: expected - recordCount,
    coverage: expected ? recordCount / expected : null,
    present: reports.reduce((sum, student) => sum + student.present, 0),
    absent: reports.reduce((sum, student) => sum + student.absent, 0),
    studentRates: reports.map(({ student, present, absent, missing }) => ({
      studentId: student.id,
      present,
      absent,
      missing,
      rate: present + absent ? present / (present + absent) : null,
    })),
  };
}

/** Return the maximum accepted synthetic dimensions for UI and CLI callers. */
export function syntheticDatasetLimits() {
  return { students: MAX_STUDENTS, sessions: MAX_SESSIONS, cells: MAX_CELLS };
}
