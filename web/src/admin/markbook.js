import { unzip, strFromU8 } from "fflate";
import { AdminError, parseRoster } from "./model.js";

export const semesterFromFileName = (name) => {
  const base = String(name ?? "").split(/[/\\]/).pop() || "";
  return (
    base
      .match(/(?:^|[_ .-])(FA|SP|SU)\d{2}(?=[_ .-]|$)/i)?.[0]
      .replace(/^[_ .-]/, "")
      .toUpperCase() || ""
  );
};
const localOf = (name) => String(name || "").split(":").pop();
const elements = (node, local) => {
  const byNs = [...node.getElementsByTagNameNS("*", local)];
  if (byNs.length) return byNs;
  return [...node.getElementsByTagName("*")].filter(
    (n) => localOf(n.localName || n.tagName) === local,
  );
};
const children = (node, local) =>
  [...node.children].filter((n) => localOf(n.localName || n.tagName) === local);
const attr = (node, local) =>
  [...node.attributes].find((a) => localOf(a.localName || a.name) === local)
    ?.value;
const normalized = (text) =>
  String(text)
    .trim()
    .toLowerCase()
    .replace(/[^a-z]/g, "");
const columns = ["Class", "RollNumber", "Email", "MemberCode", "FullName"];
function xml(files, name) {
  if (!files[name])
    throw new AdminError(`Markbook thiếu ${name}. Hãy chọn file ODS/XLSX gốc.`);
  const source = strFromU8(files[name]).replace(
    /^\uFEFF?\s*<\?xml[^?]*\?>\s*/i,
    "",
  );
  const root = new DOMParser().parseFromString(source, "application/xml");
  if (elements(root, "parsererror").length)
    throw new AdminError("XML trong Markbook không hợp lệ.");
  return root;
}
function odsSheets(files) {
  return elements(xml(files, "content.xml"), "table").map((table) => ({
    name: attr(table, "name") || "",
    rows: elements(table, "table-row").map((row) => {
      const values = [];
      for (const cell of row.children) {
        if (
          !["table-cell", "covered-table-cell"].includes(
            localOf(cell.localName || cell.tagName),
          )
        )
          continue;
        const value = elements(cell, "p")
          .map((p) => p.textContent)
          .join(" ")
          .trim();
        const repeat = Math.min(
          100,
          Math.max(1, Number(attr(cell, "number-columns-repeated")) || 1),
        );
        values.push(...Array(repeat).fill(value));
      }
      return values;
    }),
  }));
}
function xlsxSheets(files) {
  const book = xml(files, "xl/workbook.xml"),
    rels = xml(files, "xl/_rels/workbook.xml.rels");
  const targets = new Map(
    elements(rels, "Relationship").map((r) => [
      attr(r, "Id"),
      attr(r, "Target"),
    ]),
  );
  const nonPhoneticText = (node) =>
    elements(node, "t")
      .filter(
        (t) => localOf(t.parentNode?.localName || t.parentNode?.tagName) !== "rPh",
      )
      .map((t) => t.textContent)
      .join("");
  const shared = files["xl/sharedStrings.xml"]
    ? elements(xml(files, "xl/sharedStrings.xml"), "si").map((si) =>
        nonPhoneticText(si),
      )
    : [];
  return elements(book, "sheet").map((sheet) => {
    const target = targets.get(attr(sheet, "id"));
    if (!target)
      throw new AdminError("Không tìm được nội dung sheet trong XLSX.");
    const cleanTarget = target.replace(/^\/?xl\//i, "");
    const resolved = new URL(
      cleanTarget,
      "https://markbook.invalid/xl/workbook.xml",
    );
    if (resolved.origin !== "https://markbook.invalid")
      throw new AdminError("Không hỗ trợ sheet liên kết ngoài.");
    return {
      name: attr(sheet, "name") || "",
      rows: elements(xml(files, resolved.pathname.slice(1)), "row").map(
        (row) => {
          const values = [];
          for (const cell of children(row, "c")) {
            const address = attr(cell, "r")?.match(/^([A-Z]+)\d+$/)?.[1];
            let index = 0;
            if (address) {
              for (const c of address)
                index = index * 26 + c.charCodeAt(0) - 64;
            } else {
              index = values.length + 1;
            }
            if (index > 100) continue;
            while (values.length < index - 1) values.push("");
            const type = attr(cell, "t"),
              raw = elements(cell, "v")[0]?.textContent || "";
            values[index - 1] =
              type === "s"
                ? shared[Number(raw)] || ""
                : type === "inlineStr"
                  ? nonPhoneticText(cell)
                  : raw;
          }
          return values;
        },
      ),
    };
  });
}
export function parseMarkbookSheets(sheets) {
  const courses = [],
    warnings = [];
  for (const sheet of sheets) {
    const match = sheet.name.match(
      /^([1-3][1-4])_([A-Za-z0-9]+)_([A-Za-z0-9_-]+)$/,
    );
    if (!match) {
      warnings.push(
        `Bỏ qua sheet ${sheet.name}: cần tên như 11_PRN232_SE1917.`,
      );
      continue;
    }
    const headerIndex = sheet.rows.findIndex((row) =>
      columns.every((c) => row.some((v) => normalized(v) === normalized(c))),
    );
    if (headerIndex < 0) {
      warnings.push(
        `Bỏ qua sheet ${sheet.name}: thiếu một trong năm cột ${columns.join(", ")}.`,
      );
      continue;
    }
    const header = sheet.rows[headerIndex],
      indices = columns.map((c) =>
        header.findIndex((v) => normalized(v) === normalized(c)),
      );
    const data = [];
    for (let i = headerIndex + 1; i < sheet.rows.length; i++) {
      const source = sheet.rows[i],
        values = indices.map((index) => String(source[index] ?? "").trim());
      if (!values[1] && !values[2] && !values[4]) continue;
      if (!values[0] || !values[1] || !values[2] || !values[4]) {
        warnings.push(
          `${sheet.name}: bỏ qua dòng ${i + 1} vì thiếu Class/MSSV/Email/Họ tên.`,
        );
        continue;
      }
      // Grades and exam comments never enter the attendance roster.
      data.push(values.join("\t"));
    }
    const classCode = match[3].toUpperCase();
    try {
      const students = parseRoster(data.join("\n"), [], classCode);
      courses.push({
        sheetName: sheet.name,
        scheduleCode: match[1],
        courseCode: match[2].toUpperCase(),
        classCode,
        students,
      });
    } catch (error) {
      throw new AdminError(`${sheet.name}: ${error.message}`);
    }
  }
  if (!courses.length)
    throw new AdminError(
      warnings.join("\n") || "Không có sheet lớp hợp lệ trong Markbook.",
    );
  const keys = courses.map((c) => `${c.courseCode}/${c.classCode}`);
  if (new Set(keys).size !== keys.length)
    throw new AdminError(
      "Có nhiều sheet trùng môn và lớp. Giữ một sheet cho mỗi lớp trước khi nhập.",
    );
  return { courses, warnings };
}
export async function readMarkbook(file) {
  const baseName = String(file?.name ?? "").trim().split(/[/\\]/).pop() || "";
  const dotIndex = baseName.lastIndexOf(".");
  const extension =
    dotIndex <= 0 || dotIndex === baseName.length - 1
      ? ""
      : baseName.slice(dotIndex + 1).toLowerCase();
  if (!["ods", "xlsx"].includes(extension))
    throw new AdminError("Chọn file .ods hoặc .xlsx của giảng viên.");
  if (file.size > 20 * 1024 * 1024)
    throw new AdminError("Markbook phải nhỏ hơn 20 MB.");
  const bytes = new Uint8Array(await file.arrayBuffer());
  const wanted = (name) =>
    name === "content.xml" ||
    /^xl\/(workbook.xml|_rels\/workbook.xml.rels|sharedStrings.xml|worksheets\/[^/]+\.xml)$/.test(
      name,
    );
  let rejected = false,
    total = 0;
  const files = await new Promise((resolve, reject) =>
    unzip(
      bytes,
      {
        filter: (entry) => {
          if (!wanted(entry.name)) return false;
          total += entry.originalSize;
          if (
            entry.originalSize > 8 * 1024 * 1024 ||
            total > 24 * 1024 * 1024
          ) {
            rejected = true;
            return false;
          }
          return true;
        },
      },
      (error, data) =>
        error
          ? reject(
              new AdminError(
                "Không giải nén được Markbook. Hãy chọn lại file gốc.",
              ),
            )
          : resolve(data),
    ),
  );
  if (rejected) throw new AdminError("Nội dung Markbook sau giải nén quá lớn.");
  const result = parseMarkbookSheets(
    extension === "ods" ? odsSheets(files) : xlsxSheets(files),
  );
  return { ...result, semester: semesterFromFileName(file.name) };
}
