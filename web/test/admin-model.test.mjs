import { test } from "node:test";
import assert from "node:assert/strict";
import {
  AdminError,
  parseRoster,
  generateMeetings,
  protectHistory,
  correction,
  attendanceSummary,
  hashId,
  validDate,
} from "../src/admin/model.js";
import { parseSessionId } from "../src/student/repository.js";
import { escapeHtml, messageFor } from "../src/ui.js";

test("roster accepts Excel columns, normalizes identity and retains member codes", () => {
  const students = parseRoster(
    "se1\tNguyễn Văn An\tAN@GMAIL.COM\nSE2 | Trần Bình | binh@gmail.com",
    [{ rollNumber: "SE1", memberCode: "M1" }],
  );
  assert.deepEqual(students[0], {
    rollNumber: "SE1",
    memberCode: "M1",
    fullName: "Nguyễn Văn An",
    email: "an@gmail.com",
  });
  for (const text of [
    "",
    "SE1 | An | invalid",
    "SE1 | An | a@gmail.com\nse1 | B | b@gmail.com",
    "SE1 | An | a@gmail.com\nSE2 | B | A@gmail.com",
    "SE1 | An | a@gmail.com | extra",
  ])
    assert.throws(() => parseRoster(text), AdminError);
});
test("web schedule mirrors native group and slot conventions across a month boundary", () => {
  const meetings = generateMeetings("c", "24", "2026-10-26", 2, 2);
  assert.equal(meetings.length, 4);
  assert.deepEqual(
    meetings.map((m) => m.startAt),
    [
      "2026-10-27T15:00:00.000",
      "2026-10-30T15:00:00.000",
      "2026-11-03T15:00:00.000",
      "2026-11-06T15:00:00.000",
    ],
  );
  assert.equal(meetings[0].endAt, "2026-10-27T17:15:00.000");
  assert.equal(generateMeetings("c", "11", "2026-10-26", 2, 1).length, 2);
  assert.throws(
    () => generateMeetings("c", "41", "2026-10-26", 2, 2),
    AdminError,
  );
  assert.throws(
    () => generateMeetings("c", "11", "2026-10-26", 53, 2),
    AdminError,
  );
  assert.throws(() => validDate("2026-02-30"), AdminError);
});
test("history protection and corrections retain unrelated results and audits", () => {
  const old = {
    state: "closed",
    id: "m1",
    records: { S1: { status: "A" }, S2: { status: "P" } },
    auditEvents: [{ id: "old" }],
  };
  assert.throws(
    () => protectHistory([{ rollNumber: "S1" }], [old]),
    AdminError,
  );
  assert.throws(
    () =>
      protectHistory(
        [{ rollNumber: "S1" }, { rollNumber: "S2" }, { rollNumber: "S3" }],
        [old],
        [{ rollNumber: "S1" }, { rollNumber: "S2" }],
      ),
    AdminError,
  );
  assert.doesNotThrow(() =>
    protectHistory(
      [{ rollNumber: "S1" }, { rollNumber: "S2" }],
      [old],
      [{ rollNumber: "S1" }, { rollNumber: "S2" }],
    ),
  );
  const edited = correction(
    old,
    "S1",
    "P",
    "Đối chiếu minh chứng",
    "request1",
    new Date("2026-11-12T00:00:00Z"),
  );
  assert.deepEqual(edited.records.S2, old.records.S2);
  assert.deepEqual(edited.auditEvents[0], old.auditEvents[0]);
  assert.equal(edited.auditEvents[1].oldValue, "A");
  assert.equal(edited.records.S1.note, "Đối chiếu minh chứng");
  assert.throws(() => correction(old, "S1", "A", "reason", "id"), AdminError);
  assert.throws(() => correction(old, "S1", "P", " ", "id"), AdminError);
  assert.throws(
    () => correction({ ...old, state: "active" }, "S1", "P", "reason", "id"),
    AdminError,
  );
});
test("chart excludes future sessions and counts unmarked enrolled students", () => {
  const summary = attendanceSummary([
    {
      id: "c",
      data: {
        courseCode: "PRM393",
        classCode: "SE1",
        students: [{ rollNumber: "S1" }, { rollNumber: "S2" }],
      },
      meetings: [
        { state: "upcoming", records: {} },
        { state: "active", records: { S1: { status: "P" } } },
        {
          state: "closed",
          records: { S1: { status: "A" }, S2: { status: "P" } },
        },
      ],
    },
  ]);
  assert.deepEqual(summary[0], {
    id: "c",
    label: "PRM393 · SE1",
    present: 2,
    absent: 1,
    unmarked: 1,
    closed: 1,
  });
});
test("IDs match native SHA-256 and session links reject invalid paths", async () => {
  assert.equal(
    await hashId("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
  assert.equal(
    parseSessionId("https://fap-attendance-71655.web.app/join/abc-123"),
    "abc-123",
  );
  assert.equal(parseSessionId("abc-123"), "abc-123");
  assert.throws(() => parseSessionId("https://other.test/private"), AdminError);
});
test("rendering escapes stored HTML and validation messages remain actionable", () => {
  assert.equal(
    escapeHtml('<img src="x" onerror=alert(1)>'),
    "&lt;img src=&quot;x&quot; onerror=alert(1)&gt;",
  );
  assert.equal(messageFor(new AdminError("Email bị trùng")), "Email bị trùng");
});
