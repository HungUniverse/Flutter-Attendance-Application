import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import { serializeAttendanceSnapshot } from './attendance-snapshot.mjs';

// Hash the normalized representation used by the snapshot serializer. Array
// order is significant, including the chronological order of sessions.
function canonicalBytes(snapshot) {
  return Buffer.from(serializeAttendanceSnapshot(snapshot), 'utf8');
}

/** Return a SHA-256 digest for detecting accidental changes to a snapshot. */
export function digestAttendanceSnapshot(snapshot) {
  return createHash('sha256').update(canonicalBytes(snapshot)).digest('hex');
}

/** Authenticate a snapshot with a caller-provided secret key. */
export function signAttendanceSnapshot(snapshot, key) {
  if (!Buffer.isBuffer(key) || key.length < 32) {
    throw new TypeError('key must be a Buffer of at least 32 bytes');
  }
  return createHmac('sha256', key).update(canonicalBytes(snapshot)).digest('hex');
}

/** Verify an HMAC. The caller manages keys and their distribution separately. */
export function verifyAttendanceSnapshot(snapshot, key, signature) {
  if (typeof signature !== 'string' || !/^[0-9a-f]{64}$/.test(signature)) {
    throw new TypeError('signature must be a lowercase SHA-256 hex string');
  }
  const actual = Buffer.from(signAttendanceSnapshot(snapshot, key), 'hex');
  return timingSafeEqual(actual, Buffer.from(signature, 'hex'));
}
