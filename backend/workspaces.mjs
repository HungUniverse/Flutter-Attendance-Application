import { createHash } from 'node:crypto';

export class WorkspaceConflict extends Error { constructor() { super('Dữ liệu đã thay đổi trên thiết bị khác. Tải bản mới trước khi sửa tiếp.'); this.status = 409; } }
const key = value => createHash('sha256').update(value).digest('hex');
const normalizeSemester = value => String(value ?? '').trim().toUpperCase();
export class FileWorkspaceStore {
  constructor(store) { this.store = store; }
  async read(uid, semester) {
    const target = typeof semester === 'string' ? normalizeSemester(semester) : '';
    return this.store.read(state => {
      const rows = state.workspaces?.[key(uid)] ?? {};
      if (target) {
        return rows[key(target)]
          ?? Object.values(rows).find(row => normalizeSemester(row.workspace.semester) === target)
          ?? null;
      }
      let latest = null;
      for (const row of Object.values(rows)) {
        if (!latest || row.updatedAt > latest.updatedAt) latest = row;
      }
      return latest;
    });
  }
  async write(uid, input) {
    const normalizedSemester = normalizeSemester(input.workspace.semester);
    return this.store.transaction(state => {
      state.workspaces ??= {}; const rows = state.workspaces[key(uid)] ??= {};
      const id = key(normalizedSemester); const previous = rows[id];
      if (previous?.mutationId === input.mutationId) return previous;
      if ((previous?.revision ?? 0) !== input.revision) throw new WorkspaceConflict();
      const normalizedWorkspace = { ...input.workspace, semester: normalizedSemester };
      return rows[id] = { workspace: normalizedWorkspace, revision: input.revision + 1,
        mutationId: input.mutationId, updatedAt: new Date().toISOString() };
    });
  }
}

// Admin access is server-only. Client rules deny direct writes.
export class FirestoreWorkspaceStore {
  constructor(db) { this.db = db; }
  collection(uid) { return this.db.collection('teachers').doc(uid).collection('workspaces'); }
  async read(uid, semester) {
    const target = typeof semester === 'string' ? normalizeSemester(semester) : '';
    if (target) return (await this.collection(uid).doc(key(target)).get()).data() ?? null;
    const result = await this.collection(uid).orderBy('updatedAt', 'desc').limit(1).get();
    return result.docs[0]?.data() ?? null;
  }
  async write(uid, input) {
    const normalizedSemester = normalizeSemester(input.workspace.semester);
    const ref = this.collection(uid).doc(key(normalizedSemester));
    return this.db.runTransaction(async transaction => {
      const previous = (await transaction.get(ref)).data();
      if (previous?.mutationId === input.mutationId) return previous;
      if ((previous?.revision ?? 0) !== input.revision) throw new WorkspaceConflict();
      const normalizedWorkspace = { ...input.workspace, semester: normalizedSemester };
      const result = { workspace: normalizedWorkspace, revision: input.revision + 1,
        mutationId: input.mutationId, updatedAt: new Date().toISOString() };
      transaction.set(ref, result); return result;
    });
  }
}

export function validateWorkspace(input) {
  const w = input?.workspace;
  if (!w || typeof w.semester !== 'string' || !/^[A-Za-z0-9_-]{1,32}$/.test(w.semester)
      || typeof w.id !== 'string' || !Array.isArray(w.classes)
      || !Number.isSafeInteger(input.revision) || input.revision < 0 || input.revision === Number.MAX_SAFE_INTEGER
      || typeof input.mutationId !== 'string' || !/^[a-f0-9-]{36}$/.test(input.mutationId)
      || Buffer.byteLength(JSON.stringify(w)) > 700000) {
    const error = new Error('Workspace không hợp lệ hoặc quá lớn (tối đa 700 KB).'); error.status = 400; throw error;
  }
  const ids = new Set();
  for (const c of w.classes) {
    if (!c || typeof c.id !== 'string' || !c.id.trim() || ids.has(c.id.trim()) || !Array.isArray(c.students)
        || !Array.isArray(c.meetings) || c.students.length > 1000 || c.meetings.length > 200) {
      const error = new Error('Danh sách lớp không hợp lệ.'); error.status = 400; throw error;
    }
    ids.add(c.id.trim());
  }
}
