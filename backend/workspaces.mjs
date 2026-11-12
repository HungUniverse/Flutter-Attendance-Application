import { createHash } from 'node:crypto';

export class WorkspaceConflict extends Error { constructor() { super('Dữ liệu đã thay đổi trên thiết bị khác. Tải bản mới trước khi sửa tiếp.'); this.status = 409; } }
const key = value => createHash('sha256').update(value).digest('hex');
export class FileWorkspaceStore {
  constructor(store) { this.store = store; }
  async read(uid, semester) {
    return this.store.transaction(state => {
      const rows = Object.values(state.workspaces?.[key(uid)] ?? {});
      return (semester ? rows.find(r => r.workspace.semester === semester) : rows.sort((a,b) => b.updatedAt.localeCompare(a.updatedAt))[0]) ?? null;
    });
  }
  async write(uid, input) {
    return this.store.transaction(state => {
      state.workspaces ??= {}; const rows = state.workspaces[key(uid)] ??= {};
      const id = key(input.workspace.semester); const previous = rows[id];
      if (previous?.mutationId === input.mutationId) return previous;
      if ((previous?.revision ?? 0) !== input.revision) throw new WorkspaceConflict();
      return rows[id] = { workspace: input.workspace, revision: input.revision + 1,
        mutationId: input.mutationId, updatedAt: new Date().toISOString() };
    });
  }
}

// Admin access is server-only. Client rules deny direct writes.
export class FirestoreWorkspaceStore {
  constructor(db) { this.db = db; }
  collection(uid) { return this.db.collection('teachers').doc(uid).collection('workspaces'); }
  async read(uid, semester) {
    if (semester) return (await this.collection(uid).doc(key(semester)).get()).data() ?? null;
    const result = await this.collection(uid).orderBy('updatedAt', 'desc').limit(1).get();
    return result.docs[0]?.data() ?? null;
  }
  async write(uid, input) {
    const ref = this.collection(uid).doc(key(input.workspace.semester));
    return this.db.runTransaction(async transaction => {
      const previous = (await transaction.get(ref)).data();
      if (previous?.mutationId === input.mutationId) return previous;
      if ((previous?.revision ?? 0) !== input.revision) throw new WorkspaceConflict();
      const result = { workspace: input.workspace, revision: input.revision + 1,
        mutationId: input.mutationId, updatedAt: new Date().toISOString() };
      transaction.set(ref, result); return result;
    });
  }
}

export function validateWorkspace(input) {
  const w = input?.workspace;
  if (!w || !/^[A-Za-z0-9_-]{1,32}$/.test(w.semester) || typeof w.id !== 'string'
      || !Array.isArray(w.classes) || !Number.isSafeInteger(input.revision) || input.revision < 0
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
