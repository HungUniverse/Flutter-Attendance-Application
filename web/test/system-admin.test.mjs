import { test } from "node:test";
import assert from "node:assert/strict";
import { AdminError } from "../src/admin/model.js";
import {
  teacherFields,
  TeacherDirectoryRepository,
} from "../src/system-admin/repository.js";

test("teacherFields normalizes email and enforces field constraints", () => {
  const valid = teacherFields({
    email: "  Lecturer.One@FPT.EDU.VN ",
    displayName: "  Nguyễn Văn Giảng  ",
    staffCode: "  GV001 ",
    department: " Kỹ thuật phần mềm ",
    status: "active",
  });
  assert.deepEqual(valid, {
    email: "lecturer.one@fpt.edu.vn",
    displayName: "Nguyễn Văn Giảng",
    staffCode: "GV001",
    department: "Kỹ thuật phần mềm",
    status: "active",
  });

  const suspended = teacherFields({
    email: "teacher2@example.com",
    displayName: "Trần Thị B",
    status: "suspended",
  });
  assert.equal(suspended.status, "suspended");
  assert.equal(suspended.staffCode, "");
  assert.equal(suspended.department, "");
});

test("teacherFields rejects malformed emails, path characters, oversized fields, and invalid status", () => {
  for (const invalid of [
    { email: "", displayName: "An", status: "active" },
    { email: "not-an-email", displayName: "An", status: "active" },
    { email: "a/b@example.com", displayName: "An", status: "active" },
    { email: "a b@example.com", displayName: "An", status: "active" },
    { email: "teacher@example.c", displayName: "An", status: "active" },
    { email: "teacher@example.com", displayName: "   ", status: "active" },
    {
      email: "teacher@example.com",
      displayName: "An",
      staffCode: "X".repeat(41),
      status: "active",
    },
    {
      email: "teacher@example.com",
      displayName: "An",
      department: "D".repeat(161),
      status: "active",
    },
    { email: "teacher@example.com", displayName: "An", status: "pending" },
  ]) {
    assert.throws(() => teacherFields(invalid), AdminError);
  }
});

test("TeacherDirectoryRepository.checkCurrent detects concurrent modifications or deletions", () => {
  const repo = new TeacherDirectoryRepository(
    {},
    { uid: "admin-1", email: "admin@example.com" },
  );
  const stampA = { isEqual: (other) => other === stampA };
  const stampB = { isEqual: (other) => other === stampB };

  assert.doesNotThrow(() =>
    repo.checkCurrent(
      { exists: () => true, data: () => ({ updatedAt: stampA }) },
      { updatedAt: stampA },
    ),
  );
  assert.throws(
    () =>
      repo.checkCurrent(
        { exists: () => false, data: () => undefined },
        { updatedAt: stampA },
      ),
    AdminError,
  );
  assert.throws(
    () =>
      repo.checkCurrent(
        { exists: () => true, data: () => ({ updatedAt: stampB }) },
        { updatedAt: stampA },
      ),
    (err) => err instanceof AdminError && err.code === "conflict",
  );
});
