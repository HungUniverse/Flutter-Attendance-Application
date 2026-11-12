import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { Window } from "happy-dom";

registerHooks({
  resolve(specifier, context, next) {
    if (specifier.endsWith(".css"))
      return {
        url: "data:text/javascript,export%20default%20undefined",
        shortCircuit: true,
      };
    return next(specifier, context);
  },
});

const window = new Window({ url: "http://localhost/admin" });
for (const key of [
  "document",
  "location",
  "FormData",
  "HTMLElement",
  "HTMLDialogElement",
])
  globalThis[key] = window[key];
globalThis.window = window;

let authListener,
  denied = false,
  teacherWatches = 0,
  auditWatches = 0,
  savedCalls = [],
  removedCalls = [];

const auth = { currentUser: null };
const adminUser = {
  uid: "admin-uid",
  email: "admin@example.com",
  displayName: "System Admin",
};

const initialTeachers = [
  {
    id: "teacher@example.com",
    email: "teacher@example.com",
    displayName: "Nguyễn Giảng Viên",
    staffCode: "GV01",
    department: "SE",
    status: "active",
    updatedAt: "2026-11-12T08:00:00Z",
  },
  {
    id: "locked@example.com",
    email: "locked@example.com",
    displayName: "Trần Tạm Khóa",
    staffCode: "GV02",
    department: "AI",
    status: "suspended",
    updatedAt: null,
  },
];

const initialAudit = [
  {
    id: "audit-1",
    action: "create",
    email: "teacher@example.com",
    at: "2026-11-12T08:00:00Z",
    before: {},
    after: { displayName: "Nguyễn Giảng Viên", status: "active" },
  },
];

class FakeTeacherDirectoryRepository {
  async requireAdmin() {
    if (denied)
      throw Object.assign(
        new Error("Tài khoản này không có quyền quản trị hệ thống."),
        { name: "AdminError", code: "admin-required" },
      );
  }
  watchTeachers(next) {
    teacherWatches++;
    next(initialTeachers);
    return () => {};
  }
  watchAudit(next) {
    auditWatches++;
    next(initialAudit);
    return () => {};
  }
  async save(previous, input) {
    savedCalls.push({ previous, input });
  }
  async remove(previous) {
    removedCalls.push(previous);
  }
}

mock.module("firebase/auth", {
  namedExports: {
    onAuthStateChanged: (_auth, listener) => {
      authListener = listener;
    },
    signInWithPopup: async () => {},
    signOut: async () => {
      auth.currentUser = null;
      await authListener(null);
    },
  },
});
mock.module(new URL("../src/firebase-client.js", import.meta.url).href, {
  namedExports: { auth, db: {}, googleProvider: {} },
});
mock.module(
  new URL("../src/system-admin/repository.js", import.meta.url).href,
  {
    namedExports: {
      TeacherDirectoryRepository: FakeTeacherDirectoryRepository,
    },
  },
);

await import("../src/system-admin/app.js");

const settle = async () => {
  for (let n = 0; n < 6; n++)
    await new Promise((resolve) => setImmediate(resolve));
};

async function account(user) {
  auth.currentUser = user;
  await authListener(user);
  await settle();
}

test("unauthenticated and non-admin accounts are gated before directory listeners start", async () => {
  await account(null);
  assert.ok(document.getElementById("system-login"));
  assert.equal(teacherWatches, 0);
  assert.equal(auditWatches, 0);

  denied = true;
  await account(adminUser);
  assert.match(document.body.textContent, /Không có quyền quản trị/);
  assert.equal(teacherWatches, 0);
  denied = false;
});

test("system-admin shell renders teacher stats, filters, and audit log tab", async () => {
  await account(adminUser);
  const cards = [...document.querySelectorAll(".stat-card .stat-value")].map(
    (n) => n.textContent,
  );
  assert.deepEqual(cards, ["2", "1", "1"]);
  assert.match(document.body.textContent, /Nguyễn Giảng Viên/);
  assert.match(document.body.textContent, /Trần Tạm Khóa/);

  const filterSelect = document.getElementById("teacher-filter");
  filterSelect.value = "suspended";
  filterSelect.dispatchEvent(new window.Event("change", { bubbles: true }));
  assert.doesNotMatch(
    document.getElementById("teacher-results").textContent,
    /Nguyễn Giảng Viên/,
  );
  assert.match(
    document.getElementById("teacher-results").textContent,
    /Trần Tạm Khóa/,
  );

  filterSelect.value = "all";
  filterSelect.dispatchEvent(new window.Event("change", { bubbles: true }));

  location.hash = "#audit";
  window.dispatchEvent(new window.HashChangeEvent("hashchange"));
  await settle();
  assert.match(document.body.textContent, /Nhật ký thay đổi giảng viên/);
  assert.match(document.body.textContent, /Thêm giảng viên/);

  location.hash = "#teachers";
  window.dispatchEvent(new window.HashChangeEvent("hashchange"));
  await settle();
});

test("add-teacher dialog blocks self-admin email and saves valid teacher profile", async () => {
  document.querySelector('[data-action="add-teacher"]').click();
  const form = document.querySelector("dialog form");
  assert.ok(form);

  form.elements.displayName.value = "Admin Tự Cấp";
  form.elements.email.value = "ADMIN@example.com";
  form.elements.status.value = "active";
  form.dispatchEvent(
    new window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await settle();
  assert.equal(savedCalls.length, 0);
  assert.match(
    form.querySelector(".form-error").textContent,
    /không thêm hoặc chuyển hồ sơ giảng viên sang chính tài khoản admin/,
  );

  form.elements.displayName.value = "Lê Giảng Viên Mới";
  form.elements.email.value = "new.teacher@fpt.edu.vn";
  form.elements.staffCode.value = "GV99";
  form.elements.department.value = "CNTT";
  form.dispatchEvent(
    new window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await settle();
  assert.equal(savedCalls.length, 1);
  assert.equal(savedCalls[0].previous, undefined);
  assert.equal(savedCalls[0].input.email, "new.teacher@fpt.edu.vn");
  assert.equal(document.querySelector("dialog"), null);
});

test("delete-teacher dialog requires exact email confirmation before removing", async () => {
  document
    .querySelector(
      '[data-action="delete-teacher"][data-email="teacher@example.com"]',
    )
    .click();
  const form = document.querySelector("dialog form");
  assert.ok(form);

  form.elements.confirmation.value = "wrong@example.com";
  form.dispatchEvent(
    new window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await settle();
  assert.equal(removedCalls.length, 0);
  assert.match(
    form.querySelector(".form-error").textContent,
    /Email xác nhận chưa khớp/,
  );

  form.elements.confirmation.value = "TEACHER@example.com";
  form.dispatchEvent(
    new window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await settle();
  assert.equal(removedCalls.length, 1);
  assert.equal(removedCalls[0].email, "teacher@example.com");
  await window.happyDOM.close();
});
