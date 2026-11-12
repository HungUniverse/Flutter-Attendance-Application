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
const window = new Window({
  url: "http://localhost/student?session=test-session",
});
for (const key of [
  "document",
  "location",
  "FormData",
  "HTMLElement",
  "HTMLDialogElement",
])
  globalThis[key] = window[key];
globalThis.window = window;
const auth = { currentUser: null };
let listener, submitted;
const subscriptions = new Map();
mock.module("firebase/auth", {
  namedExports: {
    onAuthStateChanged: (_auth, fn) => {
      listener = fn;
    },
    signInWithPopup: async () => {},
    signOut: async () => {
      auth.currentUser = null;
      listener(null);
    },
  },
});
mock.module("firebase/firestore", {
  namedExports: {
    collection: (_db, name) => name,
    where: (field) => field,
    query: (name, field) => `${name}/${field}`,
    doc: () => {},
    onSnapshot: (key, next) => {
      subscriptions.set(key, next);
      return () => subscriptions.delete(key);
    },
    getDocFromServer: async () => ({ data: () => ({ label: "PRM393 · SE1" }) }),
  },
});
mock.module(new URL("../src/firebase-client.js", import.meta.url).href, {
  namedExports: { auth, db: {}, googleProvider: {} },
});
mock.module(new URL("../src/student/repository.js", import.meta.url).href, {
  namedExports: {
    createRequest: async (_db, user, input) => {
      submitted = { user, input };
    },
  },
});
await import("../src/student/app.js");
const settle = async () => {
  for (let i = 0; i < 4; i++)
    await new Promise((resolve) => setImmediate(resolve));
};
const emit = (key, rows = []) =>
  subscriptions.get(key)({
    docs: rows.map((data, i) => ({ id: `row${i}`, data: () => data })),
  });
test("student inbox waits for every account-scoped query before showing empty state", async () => {
  listener(null);
  assert.ok(document.getElementById("login"));
  auth.currentUser = { uid: "student", email: "student@example.com" };
  listener(auth.currentUser);
  emit("attendanceRequests/uid");
  emit("attendanceRequests/uid");
  emit("attendanceRequests/uid");
  assert.match(document.body.textContent, /Đang tải hộp thư/);
  emit("announcements/recipientUid");
  emit("announcements/recipientEmail");
  assert.match(document.body.textContent, /Hộp thư đang trống/);
});
test("student notifications render stored text without executable HTML", () => {
  emit("announcements/recipientEmail", [
    {
      title: "<img src=x>",
      body: "Nội dung riêng",
      recipientEmail: "student@example.com",
    },
  ]);
  assert.match(document.body.textContent, /<img src=x>/);
  assert.equal(document.querySelector(".notice-list img"), null);
});
test("request form carries session context and submits the signed-in identity", async () => {
  document.getElementById("new-request").click();
  const form = document.querySelector("dialog form");
  assert.equal(form.elements.session.value, "test-session");
  form.elements.reason.value = "Đề nghị đối chiếu";
  form.dispatchEvent(
    new window.Event("submit", { bubbles: true, cancelable: true }),
  );
  await settle();
  assert.equal(submitted.user.uid, "student");
  assert.equal(submitted.input.status, "P");
  assert.equal(document.querySelector("dialog"), null);
});
test("switching student accounts removes previous inbox contents and listeners", async () => {
  document.getElementById("logout").click();
  await settle();
  assert.ok(document.getElementById("login"));
  assert.equal(subscriptions.size, 0);
  assert.doesNotMatch(document.body.textContent, /Nội dung riêng/);
  await window.happyDOM.close();
});
