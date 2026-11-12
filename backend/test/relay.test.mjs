import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { once } from 'node:events';
import { createRelay, SessionStore } from '../relay.mjs';
import { randomUUID } from 'node:crypto';

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'fap-relay-'));
  let now = Date.parse('2026-11-03T03:00:00Z');
  const people = { teacher: { uid: 't1', email: 'teacher@example.com', email_verified: true },
    other: { uid: 't2', email: 'other@example.com', email_verified: true },
    student: { uid: 's1', email: 'sv@example.com', email_verified: true },
    stranger: { uid: 's2', email: 'stranger@example.com', email_verified: true },
    unverified: { uid: 's3', email: 'sv@example.com', email_verified: false } };
  const server = createRelay({ store: new SessionStore(directory), publicOrigin: 'https://attendance.example',
    teachers: ['teacher@example.com', 'other@example.com'], studentHtml: '<html>student</html>', clock: () => now,
    verifyIdentity: async token => { if (!people[token]) throw Error('Invalid token'); return people[token]; } });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); await rm(directory, { recursive: true, force: true }); });
  const base = `http://127.0.0.1:${server.address().port}`;
  async function request(path, { method = 'GET', user, data, headers = {} } = {}) {
    const hasBody = data !== undefined;
    const response = await fetch(`${base}${path}`, { method,
      headers: { ...(hasBody ? { 'content-type': 'application/json' } : {}),
        ...(user ? { authorization: `Bearer ${user}` } : {}), ...headers },
      ...(hasBody ? { body: JSON.stringify(data) } : {}) });
    return { status: response.status, data: await response.json() };
  }
  const create = async (user = 'teacher', overrides = {}) => request('/api/sessions', {
    method: 'POST', user, data: { classId: 'c1', meetingId: 'm1', label: 'PRM · Class', number: 1,
      meetingDate: '2026-11-03', students: [{ email: 'sv@example.com' }], ...overrides } });
  return { request, create, advance: ms => { now += ms; } };
}

test('requires verified teacher; rejects student, missing and invalid credentials', async t => {
  const f = await fixture(t);
  assert.equal((await f.create('student')).status, 403);
  assert.equal((await f.create('unverified')).status, 403);
  assert.equal((await f.create('invalid')).status, 401);
  assert.equal((await f.request('/api/sessions', { method: 'POST', data: {} })).status, 401);
});
test('create is idempotent; another teacher cannot poll or stop; one active session per owner', async t => {
  const f = await fixture(t); const first = await f.create(); const again = await f.create();
  assert.equal(first.status, 200); assert.equal(first.data.id, again.data.id);
  assert.equal((await f.request(`/api/sessions/${first.data.id}`, { user: 'other' })).status, 404);
  assert.equal((await f.request(`/api/sessions/${first.data.id}`, { method: 'DELETE', user: 'other' })).status, 404);
  assert.equal((await f.create('teacher', { meetingId: 'm2' })).status, 409);
});
test('opening/challenge is not attendance; duplicate valid submissions count once', async t => {
  const f = await fixture(t); const { data: session } = await f.create(); const token = session.url.split('/').pop();
  assert.deepEqual((await f.request(`/api/sessions/${session.id}`, { user: 'teacher' })).data.submissions, []);
  for (let i = 0; i < 2; i++) {
    const { data: challenge } = await f.request(`/api/join/${token}/challenge`, { method: 'POST', data: {} });
    assert.equal((await f.request(`/api/join/${token}/submit`, { method: 'POST', user: 'student', data: { challengeId: challenge.challengeId } })).status, 200);
  }
  const final = await f.request(`/api/sessions/${session.id}`, { user: 'teacher' });
  assert.equal(final.data.submissions.length, 1); assert.equal(final.data.submissions[0].email, 'sv@example.com');
});
test('roster membership, email verification, challenge expiry and token binding are enforced', async t => {
  const f = await fixture(t); const { data: s } = await f.create(); const token = s.url.split('/').pop();
  const { data: c } = await f.request(`/api/join/${token}/challenge`, { method: 'POST', data: {} });
  for (const user of ['stranger', 'unverified']) assert.equal((await f.request(`/api/join/${token}/submit`, { method: 'POST', user, data: { challengeId: c.challengeId } })).status, 403);
  assert.equal((await f.request(`/api/join/${token}/submit`, { method: 'POST', user: 'student', data: { challengeId: 'forged' } })).status, 410);
  f.advance(120001);
  assert.equal((await f.request(`/api/join/${token}/submit`, { method: 'POST', user: 'student', data: { challengeId: c.challengeId } })).status, 410);
});
test('stop freezes submissions and keeps accepted results readable for teacher', async t => {
  const f = await fixture(t); const { data: s } = await f.create(); const token = s.url.split('/').pop();
  const { data: c } = await f.request(`/api/join/${token}/challenge`, { method: 'POST', data: {} });
  await f.request(`/api/join/${token}/submit`, { method: 'POST', user: 'student', data: { challengeId: c.challengeId } });
  await f.request(`/api/sessions/${s.id}`, { method: 'DELETE', user: 'teacher' });
  assert.equal((await f.request(`/api/join/${token}/challenge`, { method: 'POST', data: {} })).status, 410);
  const frozen = await f.request(`/api/sessions/${s.id}`, { user: 'teacher' });
  assert.equal(frozen.data.receiving, false); assert.equal(frozen.data.submissions.length, 1);
});
test('expiry closes reception; cross-origin request is rejected', async t => {
  const f = await fixture(t); const { data: s } = await f.create(); f.advance(24 * 3600 * 1000);
  assert.equal((await f.request(`/api/sessions/${s.id}`, { user: 'teacher' })).data.receiving, false);
  assert.equal((await f.request('/health', { headers: { origin: 'https://evil.example' } })).status, 403);
});

const workspace = () => ({ id:'w1',semester:'FA26',classes:[] });
test('shared QR secret is required and old codes expire',async t=>{
  const f=await fixture(t);const session=(await f.create('teacher',{mode:'otp'})).data;
  const token=session.url.split('/').pop();
  const challenge=(await f.request(`/api/join/${token}/challenge`,{method:'POST',data:{}})).data;
  assert.equal(challenge.requiresCode,true);
  assert.equal((await f.request(`/api/join/${token}/submit`,{method:'POST',user:'student',data:{challengeId:challenge.challengeId}})).status,403);
  f.advance(31000);
  assert.equal((await f.request(`/api/join/${token}/submit`,{method:'POST',user:'student',data:{challengeId:challenge.challengeId,code:session.code}})).status,403);
  const current=(await f.request(`/api/sessions/${session.id}`,{user:'teacher'})).data;
  assert.equal((await f.request(`/api/join/${token}/submit`,{method:'POST',user:'student',data:{challengeId:challenge.challengeId,code:current.code}})).status,200);
});
test('workspace ownership, revision conflict and network retry idempotency',async t=>{
  const f=await fixture(t);
  const data={workspace:workspace(),revision:0,mutationId:randomUUID()};
  assert.equal((await f.request('/api/workspaces',{method:'PUT',user:'student',data})).status,403);
  const first=await f.request('/api/workspaces',{method:'PUT',user:'teacher',data});
  assert.equal(first.data.data.revision,1);
  assert.equal((await f.request('/api/workspaces',{method:'PUT',user:'teacher',data})).data.data.revision,1);
  assert.equal((await f.request('/api/workspaces',{method:'PUT',user:'teacher',data:{...data,mutationId:randomUUID()}})).status,409);
  assert.equal((await f.request('/api/workspaces',{user:'other'})).data.data,null);
  assert.equal((await f.request('/api/workspaces?semester=FA26',{user:'teacher'})).data.data.workspace.id,'w1');
});
test('desktop browser handoff requires separate polling secret, consumes once and logout revokes',async t=>{
  const f=await fixture(t);
  const login=(await f.request('/api/desktop-login',{method:'POST',data:{}})).data;
  assert.equal((await f.request('/api/desktop-login/poll',{method:'POST',data:{ticket:login.ticket,secret:'wrong'}})).status,410);
  assert.equal((await f.request('/api/desktop-login/complete',{method:'POST',user:'student',data:{ticket:login.ticket}})).status,403);
  assert.equal((await f.request('/api/desktop-login/complete',{method:'POST',user:'teacher',data:{ticket:login.ticket}})).status,200);
  const poll=await f.request('/api/desktop-login/poll',{method:'POST',data:login});
  assert.equal(poll.data.uid,'t1');
  assert.equal((await f.request('/api/workspaces',{user:poll.data.token})).status,200);
  assert.equal((await f.request('/api/desktop-login/poll',{method:'POST',data:login})).status,410);
  await f.request('/api/desktop-logout',{method:'POST',user:poll.data.token,data:{}});
  assert.equal((await f.request('/api/workspaces',{user:poll.data.token})).status,401);
});
test('mobile discovers the same desktop session, including stopped final results',async t=>{
  const f=await fixture(t);const session=(await f.create()).data;
  assert.equal((await f.request('/api/sessions/current',{user:'teacher'})).data.session.id,session.id);
  assert.equal((await f.request('/api/sessions/current',{user:'other'})).data.session,null);
  await f.request(`/api/sessions/${session.id}`,{method:'DELETE',user:'teacher'});
  assert.equal((await f.request('/api/sessions/current',{user:'teacher'})).data.session.receiving,false);
});
test('expired desktop authorization cannot be claimed',async t=>{
  const f=await fixture(t);const data=(await f.request('/api/desktop-login',{method:'POST',data:{}})).data;
  f.advance(120001);
  assert.equal((await f.request('/api/desktop-login/complete',{method:'POST',user:'teacher',data})).status,410);
});
test('rejects null student entries with 400 and normalizes case-variant student emails',async t=>{
  const f=await fixture(t);
  assert.equal((await f.create('teacher',{students:[null]})).status,400);
  const created=await f.create('teacher',{students:[{email:' SV@EXAMPLE.COM '},{email:'sv@example.com'}]});
  assert.equal(created.status,200);
  const blankClass={workspace:{id:'w1',semester:'FA26',classes:[{id:'   ',students:[],meetings:[]}]},revision:0,mutationId:randomUUID()};
  assert.equal((await f.request('/api/workspaces',{method:'PUT',user:'teacher',data:blankClass})).status,400);
});
test('rejects non-object JSON payloads with 400 and matches workspace semester case-insensitively',async t=>{
  const f=await fixture(t);
  for (const invalidPayload of [null, [], 'raw-string', 42, true]) {
    assert.equal((await f.request('/api/sessions',{method:'POST',user:'teacher',data:invalidPayload})).status,400);
    assert.equal((await f.request('/api/desktop-login/poll',{method:'POST',data:invalidPayload})).status,400);
    assert.equal((await f.request('/api/desktop-login/complete',{method:'POST',user:'teacher',data:invalidPayload})).status,400);
  }
  const data={workspace:{id:'w1',semester:'fa26',classes:[]},revision:0,mutationId:randomUUID()};
  assert.equal((await f.request('/api/workspaces',{method:'PUT',user:'teacher',data})).status,200);
  const readLower=await f.request('/api/workspaces?semester=fa26',{user:'teacher'});
  const readUpper=await f.request('/api/workspaces?semester=FA26',{user:'teacher'});
  assert.equal(readLower.data.data.workspace.semester,'FA26');
  assert.equal(readUpper.data.data.workspace.id,'w1');
});
