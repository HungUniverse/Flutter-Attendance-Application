import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("firestore.rules enforces Google sign-in, teacherDirectory active check, and append-only audits", async () => {
  const rules = await readFile(
    new URL("../firestore.rules", import.meta.url),
    "utf8",
  );
  assert.match(rules, /rules_version = '2';/);
  assert.match(rules, /request\.auth\.token\.firebase\.sign_in_provider == 'google\.com'/);
  assert.match(
    rules,
    /teacherDirectory\/\$\(request\.auth\.token\.email\.lower\(\)\)/,
  );
  assert.match(rules, /match \/teacherDirectory\/\{email\}/);
  assert.match(rules, /match \/teacherAudit\/\{id\}/);
  assert.match(rules, /allow update, delete: if false;/);
});

test("storage.rules restricts report paths, extensions, size limits, and ownerUid metadata", async () => {
  const storage = await readFile(
    new URL("../storage.rules", import.meta.url),
    "utf8",
  );
  assert.match(storage, /rules_version = '2';/);
  assert.match(
    storage,
    /match \/reports\/\{uid\}\/\{semester\}\/\{course\}\/\{classCode\}\/\{meeting\}\/\{filename\}/,
  );
  assert.match(storage, /request\.resource\.size < 20 \* 1024 \* 1024/);
  assert.match(storage, /request\.resource\.metadata\.ownerUid == uid/);
  assert.match(
    storage,
    /request\.resource\.contentType\.matches\('\(application\/json\|text\/csv\)'\)/,
  );
});

test("firestore.indexes.json defines composite indexes for teacher-owned collections", async () => {
  const raw = await readFile(
    new URL("../firestore.indexes.json", import.meta.url),
    "utf8",
  );
  const parsed = JSON.parse(raw);
  assert.ok(Array.isArray(parsed.indexes));
  const groups = new Set(parsed.indexes.map((idx) => idx.collectionGroup));
  for (const expected of [
    "workspaces",
    "attendanceSessions",
    "classes",
    "attendanceRequests",
  ]) {
    assert.ok(groups.has(expected), `Missing index for ${expected}`);
  }
});
