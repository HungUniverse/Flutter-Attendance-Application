import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sessionState, errorMessage, desktopCallback } from '../src/check-in.js';

test('session distinguishes missing, closed, expired, and open', () => {
  assert.equal(sessionState(null), 'missing');
  const s = {receiving: false, expiresAt: {toMillis: () => 200}};
  assert.equal(sessionState(s, 100), 'closed');
  s.receiving = true;
  assert.equal(sessionState(s, 200), 'expired');
  assert.equal(sessionState(s, 199), 'open');
});
test('desktop credential callback is restricted to loopback and a valid random state', () => {
  const state = 'a'.repeat(43) + '=';
  assert.deepEqual(desktopCallback(`?port=43210&state=${encodeURIComponent(state)}`), {url: 'http://127.0.0.1:43210/callback', state});
  for (const value of ['?port=80&state=x', '?port=65536', '?port=evil.com', '?port=1234.5']) assert.equal(desktopCallback(value), null);
});
test('errors provide recovery for role denial and blocked Google sign-in', () => {
  assert.match(errorMessage({code: 'permission-denied'}), /danh sách lớp/);
  assert.match(errorMessage({code: 'auth/popup-blocked'}), /cửa sổ/);
  assert.match(errorMessage({code: 'unknown'}), /Kiểm tra mạng/);
});
