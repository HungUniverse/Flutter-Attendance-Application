import { createServer } from 'node:http';
import { randomBytes, randomUUID, createHmac } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { FileWorkspaceStore, validateWorkspace } from './workspaces.mjs';

export class RelayError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const fail = (status, text) => { throw new RelayError(status, text); };
const jsonHeaders = { 'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store', 'referrer-policy': 'no-referrer',
  'x-content-type-options': 'nosniff', 'x-frame-options': 'DENY' };

/** One process + one persistent volume. Atomic JSON files, no database. */
export class SessionStore {
  constructor(directory) { this.directory = directory; this.tail = Promise.resolve(); }
  async load(file) {
    try {
      return JSON.parse(await readFile(file, 'utf8'));
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      return { sessions: [] };
    }
  }

  enqueue(action) {
    const operation = this.tail.then(action);
    this.tail = operation.catch(() => {});
    return operation;
  }

  read(action) {
    const file = join(this.directory, 'sessions.json');
    return this.enqueue(async () => action(await this.load(file)));
  }

  transaction(action, afterCommit) {
    return this.enqueue(async () => {
      const file = join(this.directory, 'sessions.json');
      const state = await this.load(file);
      const result = await action(state);
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      const temporary = `${file}.tmp`;
      await writeFile(temporary, JSON.stringify(state), { mode: 0o600 });
      await rename(temporary, file);
      afterCommit?.();
      return result;
    });
  }
}

export function createRelay({ store, verifyIdentity, teachers, publicOrigin,
  studentHtml, desktopHtml = '', workspaceStore = new FileWorkspaceStore(store), webConfig = {}, clock = () => Date.now() }) {
  const origin = new URL(publicOrigin).origin;
  if (new URL(publicOrigin).protocol !== 'https:') throw new Error('PUBLIC_ORIGIN must use HTTPS');
  const allowed = new Set(teachers.map(email => email.trim().toLowerCase()).filter(Boolean));
  const challenges = new Map();
  const windows = new Map();
  const logins = new Map();
  const desktopTokens = new Map();
  function rateLimit(key, limit = 240) {
    const now = clock();
    if (windows.size > 20000) for (const [k, v] of windows) if (now - v.at > 60000) windows.delete(k);
    const entry = windows.get(key);
    if (!entry || now - entry.at >= 60000) windows.set(key, { at: now, count: 1 });
    else if (++entry.count > limit) fail(429, 'Thao tác quá nhanh. Hãy thử lại sau.');
  }
  async function identity(req) {
    const match = /^Bearer (\S+)$/.exec(req.headers.authorization ?? '');
    if (!match) fail(401, 'Vui lòng đăng nhập.');
    let user;
    const desktop = desktopTokens.get(match[1]);
    try { user = desktop && desktop.expiresAt > clock() ? desktop.user : await verifyIdentity(match[1]); } catch { fail(401, 'Phiên đăng nhập không hợp lệ.'); }
    if (!user?.uid || !user.email || user.email_verified !== true) fail(403, 'Cần tài khoản có email đã xác minh.');
    return { ...user, email: user.email.toLowerCase() };
  }
  async function body(req) {
    if (!req.headers['content-type']?.startsWith('application/json')) fail(415, 'Yêu cầu JSON.');
    let length = 0; const chunks = [];
    for await (const chunk of req) {
      length += chunk.length;
      if (length > 800 * 1024) fail(413, 'Dữ liệu quá lớn.');
      chunks.push(chunk);
    }
    let parsed;
    try { parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch { fail(400, 'Dữ liệu không hợp lệ.'); }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) fail(400, 'Dữ liệu không hợp lệ.');
    return parsed;
  }
  const open = s => s.receiving && new Date(s.expiresAt).getTime() > clock();
  const secretCode = (s, window = Math.floor(clock()/15000)) => String(createHmac('sha256',s.codeSecret).update(String(window)).digest().readUInt32BE(0)%1000000).padStart(6,'0');
  const summary = s => ({ id: s.id, classId: s.classId, meetingId: s.meetingId,
    url: `${origin}/join/${s.token}`, expiresAt: s.expiresAt, receiving: open(s),code:s.codeSecret ? secretCode(s) : null });
  const byToken = (state, token) => state.sessions.find(s => s.token === token) ?? fail(404, 'Không tìm thấy link.');
  const byOwner = (state, id, owner) => state.sessions.find(s => s.id === id && s.owner === owner) ?? fail(404, 'Không tìm thấy phiên của tài khoản.');
  const meetingDate = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Ho_Chi_Minh', year: 'numeric', month: '2-digit', day: '2-digit',
  });
  const today = () => meetingDate.format(clock());
  return createServer(async (req, res) => {
    const send = (status, value) => { res.writeHead(status, jsonHeaders); res.end(JSON.stringify(value)); };
    try {
      rateLimit(req.socket.remoteAddress ?? 'unknown', 1000);
      const path = new URL(req.url, 'http://localhost').pathname;
      if (req.headers.origin && req.headers.origin !== origin) fail(403, 'Nguồn yêu cầu không hợp lệ.');
      if (path === '/health' && req.method === 'GET') { send(200, { ready: true }); return; }
      if (path === '/web-config' && req.method === 'GET') { send(200, webConfig); return; }
      if (path === '/desktop-login' && req.method === 'GET') {
        res.writeHead(200, { ...jsonHeaders, 'content-type': 'text/html; charset=utf-8' }); res.end(desktopHtml); return;
      }
      if (path === '/api/desktop-login' && req.method === 'POST') {
        await body(req); rateLimit(`desktop-login:${req.socket.remoteAddress}`, 10);
        for (const [key, value] of logins) if (value.expiresAt < clock()) logins.delete(key);
        for (const [key, value] of desktopTokens) if (value.expiresAt < clock()) desktopTokens.delete(key);
        if (logins.size >= 1000 || desktopTokens.size >= 1000) fail(429, 'Hãy thử lại sau.');
        const ticket = randomBytes(32).toString('hex'), secret = randomBytes(32).toString('hex');
        logins.set(ticket, { secret, expiresAt: clock() + 120000 });
        send(200, { ticket, secret, url: `${origin}/desktop-login#${ticket}` }); return;
      }
      if (path === '/api/desktop-login/complete' && req.method === 'POST') {
        const user = await identity(req); if (!allowed.has(user.email)) fail(403, 'Tài khoản không có quyền giảng viên.');
        const input = await body(req), login = logins.get(input.ticket);
        if (!login || login.expiresAt <= clock() || login.user) fail(410, 'Lượt đăng nhập hết hạn hoặc đã dùng.');
        login.user = user; send(200, { completed: true }); return;
      }
      if (path === '/api/desktop-login/poll' && req.method === 'POST') {
        const input = await body(req), login = logins.get(input.ticket);
        if (!login || login.expiresAt <= clock() || login.secret !== input.secret) fail(410, 'Lượt đăng nhập không hợp lệ.');
        if (!login.user) { send(200, { pending: true }); return; }
        const token = randomBytes(32).toString('hex');
        desktopTokens.set(token, { user: login.user, expiresAt: clock() + 8 * 3600000 }); logins.delete(input.ticket);
        send(200, { token, uid: login.user.uid, email: login.user.email }); return;
      }
      if (path === '/api/desktop-logout' && req.method === 'POST') {
        const token = (req.headers.authorization ?? '').replace(/^Bearer /, '');
        desktopTokens.delete(token); send(200, { signedOut: true }); return;
      }
      if (path === '/api/workspaces' && ['GET', 'PUT'].includes(req.method)) {
        const user = await identity(req); if (!allowed.has(user.email)) fail(403, 'Tài khoản không có quyền giảng viên.');
        if (req.method === 'GET') {
          const semester = new URL(req.url, origin).searchParams.get('semester');
          if (semester && !/^[A-Za-z0-9_-]{1,32}$/.test(semester)) fail(400, 'Học kỳ không hợp lệ.');
          send(200, { data: await workspaceStore.read(user.uid, semester) });
        } else {
          const input = await body(req); validateWorkspace(input);
          send(200, { data: await workspaceStore.write(user.uid, input) });
        }
        return;
      }
      if (path === '/api/sessions/current' && req.method === 'GET') {
        const user = await identity(req); if (!allowed.has(user.email)) fail(403, 'Tài khoản không có quyền giảng viên.');
        const current = await store.read(state => {
          const date = today();
          const s = state.sessions.findLast(s => s.owner === user.uid && s.meetingDate === date);
          return s ? summary(s) : null;
        }); send(200, { session: current }); return;
      }
      const page = /^\/join\/([a-f0-9]{64})$/.exec(path);
      if (page && req.method === 'GET') {
        await store.read(state => { const s = byToken(state, page[1]); if (!open(s)) fail(410, 'Buổi học đã dừng nhận hoặc đã chốt.'); });
        res.writeHead(200, { ...jsonHeaders, 'content-type': 'text/html; charset=utf-8',
          'content-security-policy': "default-src 'self'; script-src 'self' 'unsafe-inline' https://www.gstatic.com https://apis.google.com; connect-src 'self' https://*.googleapis.com https://*.firebaseapp.com; frame-src https://*.firebaseapp.com https://accounts.google.com; style-src 'unsafe-inline'; base-uri 'none'; form-action 'self'" });
        res.end(studentHtml); return;
      }
      const student = /^\/api\/join\/([a-f0-9]{64})\/(challenge|submit)$/.exec(path);
      if (student && req.method === 'POST') {
        const token = student[1];
        if (student[2] === 'challenge') {
          await body(req);
          rateLimit(`challenge:${req.socket.remoteAddress}`, 120);
          const value = await store.read(state => {
            const s = byToken(state, token);
            if (!open(s)) fail(410, 'Link đã dừng nhận hoặc buổi học đã chốt.');
            for (const [id,c] of challenges) if (c.expiresAt <= clock()) challenges.delete(id);
            if (challenges.size >= 10000) fail(429, 'Hãy thử lại sau.');
            const id = randomBytes(24).toString('hex');
            const expiresAt = Math.min(clock() + 120000, new Date(s.expiresAt).getTime());
            challenges.set(id, { token, expiresAt });
            return { challengeId: id, expiresAt, label: s.label, number: s.number, meetingDate: s.meetingDate, requiresCode:!!s.codeSecret };
          });
          send(200, value); return;
        }
        const user = await identity(req);
        rateLimit(`student:${user.uid}`, 20);
        const input = await body(req);
        const result = await store.transaction(state => {
          const s = byToken(state, token);
          if (!open(s)) fail(410, 'Link đã dừng nhận hoặc buổi học đã chốt.');
          const challenge = challenges.get(input.challengeId);
          if (!challenge || challenge.token !== token || challenge.expiresAt <= clock()) fail(410, 'Lượt xác nhận hết hạn. Mở lượt mới và thử lại.');
          if (!s.emails.includes(user.email)) fail(403, 'Email không thuộc danh sách lớp.');
          if(s.codeSecret && input.code!==secretCode(s) && input.code!==secretCode(s,Math.floor(clock()/15000)-1)) fail(403,'Mã xác nhận không đúng hoặc đã hết hạn. Xem mã mới trên màn hình giảng viên.');
          s.submissions[user.email] ??= { email: user.email, at: new Date(clock()).toISOString() };
          return { accepted: true, message: 'Đã gửi điểm danh. Giảng viên sẽ xác nhận kết quả.' };
        }, () => challenges.delete(input.challengeId));
        send(200, result); return;
      }
      if (path === '/api/sessions' && req.method === 'POST') {
        const user = await identity(req);
        if (!allowed.has(user.email)) fail(403, 'Tài khoản chưa được cấp quyền giảng viên cho dịch vụ link.');
        rateLimit(`create:${user.uid}`, 20);
        const input = await body(req);
        const validId = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v);
        if (!validId(input.classId) || !validId(input.meetingId) || input.meetingDate !== today()
          || typeof input.label !== 'string' || input.label.length > 200
          || !Number.isSafeInteger(input.number) || input.number < 1 || input.number > 1000
          || !Array.isArray(input.students) || input.students.length < 1 || input.students.length > 1000) fail(400, 'Lớp hoặc buổi học không hợp lệ. Chỉ mở buổi học hôm nay.');
        const emails = [...new Set(input.students.map(s => typeof s?.email === 'string' ? s.email.trim().toLowerCase() : ''))];
        if (emails.some(e => !e || e.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e))) fail(400, 'Email không hợp lệ.');
        const value = await store.transaction(state => {
          const existing = state.sessions.find(s => s.owner === user.uid && open(s));
          if (existing) {
            if (existing.classId !== input.classId || existing.meetingId !== input.meetingId) fail(409, 'Đang có buổi học khác nhận điểm danh.');
            return summary(existing);
          }
          const s = { id: randomUUID(), owner: user.uid, token: randomBytes(32).toString('hex'),
            classId: input.classId, meetingId: input.meetingId, label: input.label,
            number: input.number, meetingDate: input.meetingDate, emails,
            receiving: true, codeSecret:input.mode==='otp' ? randomBytes(32).toString('hex') : null,
            expiresAt: new Date(`${input.meetingDate}T23:59:59.999+07:00`).toISOString(), submissions: {} };
          state.sessions.push(s);
          return summary(s);
        });
        send(200, value); return;
      }
      const teacher = /^\/api\/sessions\/([a-f0-9-]{36})$/.exec(path);
      if (teacher && ['GET','DELETE'].includes(req.method)) {
        const user = await identity(req);
        if (!allowed.has(user.email)) fail(403, 'Tài khoản không có quyền giảng viên.');
        const sessionDetails = state => {
          const s = byOwner(state, teacher[1], user.uid);
          if (req.method === 'DELETE') s.receiving = false;
          return { ...summary(s), submissions: Object.values(s.submissions) };
        };
        const result = req.method === 'DELETE'
          ? await store.transaction(sessionDetails)
          : await store.read(sessionDetails);
        send(200, result); return;
      }
      fail(404, 'Không tìm thấy nội dung.');
    } catch (error) {
      if (!res.headersSent) send(error.status ?? 500, { error: error.status ? error.message : 'Dịch vụ chưa sẵn sàng. Hãy thử lại.' });
      else res.end();
    }
  });
}
