import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { zipSync, strToU8 } from "fflate";
import { Window } from "happy-dom";
import { AdminError } from "../src/admin/model.js";
import {
  semesterFromFileName,
  parseMarkbookSheets,
  readMarkbook,
} from "../src/admin/markbook.js";

const window = new Window();
globalThis.DOMParser = window.DOMParser;

function fakeFile(name, bytes, sizeOverride) {
  return {
    name,
    size: sizeOverride ?? bytes.byteLength,
    arrayBuffer: async () =>
      bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
  };
}

test("semesterFromFileName extracts semester across paths and prefixes", () => {
  assert.equal(semesterFromFileName("FA26_Markbook.ods"), "FA26");
  assert.equal(semesterFromFileName("C:\\fakepath\\sp26-roster.xlsx"), "SP26");
  assert.equal(semesterFromFileName("/tmp/FPT_SU26_Markbook.ods"), "SU26");
  assert.equal(semesterFromFileName("Markbook.ods"), "");
});

test("parseMarkbookSheets validates sheet names, headers, and duplicate classes", () => {
  const result = parseMarkbookSheets([
    { name: "Overview", rows: [] },
    {
      name: "11_PRN232_SE1917",
      rows: [
        [" Lecturer Markbook "],
        ["Class", "RollNumber", "Email", "MemberCode", "FullName", "Midterm"],
        ["SE1917", "se001", "S1@FPT.EDU.VN", "M001", "Nguyễn Văn An", "9.5"],
        ["", "", "", "", ""],
      ],
    },
    {
      name: "12_PRN232_SE1918",
      rows: [["RollNumber", "FullName"]],
    },
  ]);

  assert.equal(result.courses.length, 1);
  assert.equal(result.warnings.length, 2);
  assert.equal(result.courses[0].scheduleCode, "11");
  assert.equal(result.courses[0].courseCode, "PRN232");
  assert.equal(result.courses[0].classCode, "SE1917");
  assert.deepEqual(result.courses[0].students, [
    {
      rollNumber: "SE001",
      memberCode: "M001",
      email: "s1@fpt.edu.vn",
      fullName: "Nguyễn Văn An",
    },
  ]);

  assert.throws(
    () =>
      parseMarkbookSheets([
        {
          name: "11_PRN232_SE1917",
          rows: [
            ["Class", "RollNumber", "Email", "MemberCode", "FullName"],
            ["SE1917", "SE1", "s1@fpt.edu.vn", "M1", "An"],
          ],
        },
        {
          name: "21_PRN232_SE1917",
          rows: [
            ["Class", "RollNumber", "Email", "MemberCode", "FullName"],
            ["SE1917", "SE2", "s2@fpt.edu.vn", "M2", "Bình"],
          ],
        },
      ]),
    AdminError,
  );
});

test("readMarkbook parses bundled FA26_Markbook.ods and synthetic XLSX workbooks", async () => {
  const odsBytes = new Uint8Array(
    await readFile(new URL("../../test/fixtures/FA26_Markbook.ods", import.meta.url)),
  );
  const odsResult = await readMarkbook(fakeFile("FA26_Markbook.ods", odsBytes));
  assert.equal(odsResult.semester, "FA26");
  assert.ok(odsResult.courses.length >= 1);
  assert.ok(odsResult.courses[0].students.length >= 1);

  const xlsxZip = zipSync({
    "xl/workbook.xml": strToU8(
      `<?xml version="1.0"?><workbook><sheets><sheet name="13_PRN232_SE1920" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/></sheets></workbook>`,
    ),
    "xl/_rels/workbook.xml.rels": strToU8(
      `<?xml version="1.0"?><Relationships><Relationship Id="rId1" Target="/xl/worksheets/sheet1.xml"/></Relationships>`,
    ),
    "xl/sharedStrings.xml": strToU8(
      `<?xml version="1.0"?><sst><si><t>Class</t><rPh><t>PHONETIC</t></rPh></si><si><t>RollNumber</t></si><si><t>Email</t></si><si><t>MemberCode</t></si><si><t>FullName</t></si></sst>`,
    ),
    "xl/worksheets/sheet1.xml": strToU8(
      `<?xml version="1.0"?><worksheet><sheetData>
        <row><c t="s"><v>0</v></c><c t="s"><v>1</v></c><c t="s"><v>2</v></c><c t="s"><v>3</v></c><c t="s"><v>4</v></c></row>
        <row>
          <c r="A2" t="inlineStr"><is><t>SE1920</t></is></c>
          <c r="B2" t="inlineStr"><is><t>SE190001</t></is></c>
          <c r="C2" t="inlineStr"><is><t>sv1@fpt.edu.vn</t></is></c>
          <c r="E2" t="inlineStr"><is><t>Lê Hoàng Nam</t><rPh><t>LE HOANG NAM</t></rPh></is></c>
        </row>
      </sheetData></worksheet>`,
    ),
  });
  const xlsxResult = await readMarkbook(
    fakeFile("SP26_Markbook.xlsx", xlsxZip),
  );
  assert.equal(xlsxResult.semester, "SP26");
  assert.equal(xlsxResult.courses.length, 1);
  assert.deepEqual(xlsxResult.courses[0].students[0], {
    rollNumber: "SE190001",
    memberCode: "",
    email: "sv1@fpt.edu.vn",
    fullName: "Lê Hoàng Nam",
  });
});

test("readMarkbook rejects dotfiles, unsupported extensions, and oversized files", async () => {
  const dummy = new Uint8Array([1, 2, 3]);
  for (const name of [".ods", ".xlsx", "roster.csv", "noext", "markbook."]) {
    await assert.rejects(() => readMarkbook(fakeFile(name, dummy)), AdminError);
  }
  await assert.rejects(
    () => readMarkbook(fakeFile("FA26.xlsx", dummy, 21 * 1024 * 1024)),
    AdminError,
  );
});
