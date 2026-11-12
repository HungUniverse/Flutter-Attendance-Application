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
  watches = 0,
  created,
  decision;
const auth = { currentUser: null };
const teacher = {
  uid: "teacher",
  email: "teacher@example.com",
  displayName: "Giảng viên",
};
const course = {
  id: "remote-c1",
  workspaceId: "w1",
  data: {
    id: "local1",
    courseCode: "PRM393",
    classCode: "SE1",
    scheduleCode: "11",
    students: [
      { rollNumber: "S1", email: "student@example.com", fullName: "Nguyễn An" },
    ],
  },
  roster: { "student@example.com": "S1" },
  meetings: [
    {
      id: "m1",
      number: 1,
      startAt: "2026-11-12T07:00:00",
      state: "closed",
      records: { S1: { status: "A" } },
      auditEvents: [],
    },
  ],
};
const manifest = {
  id: "w1",
  revision: 3,
  data: { semester: "FA26", semesterStart: "2026-11-09T00:00:00" },
  layout: { "remote-c1": ["m1"] },
};
const request = {
  id: "request1",
  uid: "student",
  email: "student@example.com",
  classId: "remote-c1",
  meetingId: "m1",
  requestedStatus: "P",
  reason: "Có mặt",
  state: "pending",
};
class FakeRepository {
  async requireTeacher() {
    if (denied)
      throw Object.assign(new Error("Tài khoản chưa có quyền"), {
        name: "AdminError",
      });
  }
  watch(name, next) {
    watches++;
    next(
      {
        workspaces: [manifest],
        attendanceRequests: [request],
        announcements: [],
      }[name],
    );
    return () => {};
  }
  async loadWorkspace() {
    return { workspace: manifest, classes: [course] };
  }
  async counts() {
    return { classes: 1, pending: 1, reports: 2 };
  }
  async createClass(input, students, revision) {
    created = { input, students, revision };
    return { workspaceId: "w1" };
  }
  async requestContext() {
    return { course, meeting: course.meetings[0] };
  }
  async decide(...args) {
    decision = args;
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
mock.module(new URL("../src/admin/repository.js", import.meta.url).href, {
  namedExports: { AdminRepository: FakeRepository },
});
mock.module(new URL("../src/telemetry.js", import.meta.url).href, {
  namedExports: {
    startWebTelemetry: async () => {},
    track: () => {},
    webSettings: {
      announcementEnabled: true,
      helpText: "Đồng bộ Android và Windows",
    },
  },
});
await import("../src/admin/app.js");
const settle = async () => {
  for (let n = 0; n < 6; n++)
    await new Promise((resolve) => setImmediate(resolve));
};
async function account(user) {
  auth.currentUser = user;
  await authListener(user);
  await settle();
}

test("unauthenticated and wrong-role screens never query teacher data", async () => {
  await account(null);
  assert.ok(document.getElementById("login"));
  assert.equal(watches, 0);
  denied = true;
  await account(teacher);
  assert.match(document.body.textContent, /chưa có quyền/);
  assert.equal(watches, 0);
  denied = false;
});
test("teacher shell mounts with aggregate cards chart and usable mobile logout", async () => {
  await account(teacher);
  assert.equal(document.querySelectorAll(".stat-card").length, 3);
  assert.ok(document.querySelector(".bar-chart"));
  assert.match(document.getElementById("page-body").textContent, /PRM393/);
  assert.ok(document.getElementById("mobile-logout"));
  assert.equal(document.querySelectorAll(".sidebar nav a").length, 4);
});
test("class form validates real fields and submits the captured workspace revision", async () => {
  location.hash = "classes";
  window.dispatchEvent(new window.HashChangeEvent("hashchange"));
  await settle();
  document.querySelector('[data-action="create-class"]').click();
  const form = document.querySelector("dialog form");
  assert.ok(form);
  form.elements.courseCode.value = "PRM393";
  form.elements.classCode.value = "SE2";
  form.elements.roster.value = "S1 | Nguyễn An | student@example.com";
  form.dispatchEvent(
    new window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await settle();
  assert.equal(created.revision, 3);
  assert.equal(created.students[0].email, "student@example.com");
  assert.equal(document.querySelector("dialog"), null);
});
test("review exposes current grade and saves a reasoned decision", async () => {
  location.hash = "requests";
  window.dispatchEvent(new window.HashChangeEvent("hashchange"));
  await settle();
  document.querySelector('[data-action="review"]').click();
  await settle();
  const form = document.querySelector("dialog form");
  assert.ok(form);
  assert.match(form.textContent, /Kết quả hiện tại: A/);
  form.elements.decision.value = "rejected";
  form.elements.reason.value = "Đã đối chiếu";
  form.dispatchEvent(
    new window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await settle();
  assert.deepEqual(decision, ["request1", "rejected", "Đã đối chiếu"]);
});
test("logout clears private workspace and open forms", async () => {
  document.getElementById("mobile-logout").click();
  await settle();
  assert.ok(document.getElementById("login"));
  assert.equal(document.querySelector("dialog"), null);
  assert.doesNotMatch(document.body.textContent, /student@example.com/);
  await window.happyDOM.close();
});
