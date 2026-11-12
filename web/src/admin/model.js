export class AdminError extends Error {
  constructor(message, code = "validation") { super(message); this.code = code; }
}
export function required(value, label, max = 160) {
  const text = String(value ?? "").trim();
  if (!text || text.length > max) throw new AdminError(`${label}: cần từ 1 đến ${max} ký tự.`);
  return text;
}
export function semesterCode(value) {
  const code = required(value, "Học kỳ", 16).toUpperCase();
  if (!/^[A-Z0-9]+$/.test(code)) throw new AdminError("Học kỳ chỉ gồm chữ và số, ví dụ FA26.");
  return code;
}
export function parseRoster(text, previous = []) {
  const members = new Map(previous.map(s => [s.rollNumber, s.memberCode || ""]));
  const rolls = new Set(), emails = new Set();
  const rows = String(text).split(/\r?\n/).filter(line => line.trim());
  if (!rows.length || rows.length > 200) throw new AdminError("Danh sách cần từ 1 đến 200 sinh viên.");
  return rows.map((line, index) => {
    const cells = line.split(line.includes("\t") ? "\t" : "|").map(v => v.trim());
    if (cells.length !== 3) throw new AdminError(`Dòng ${index + 1}: dùng MSSV | Họ tên | Email hoặc ba cột từ Excel.`);
    const [roll, name, address] = cells;
    const rollNumber = required(roll, `MSSV dòng ${index + 1}`, 40).toUpperCase();
    const fullName = required(name, `Họ tên dòng ${index + 1}`, 160);
    const email = required(address, `Email dòng ${index + 1}`, 254).toLowerCase();
    if (!/^[A-Z0-9_-]+$/.test(rollNumber) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      throw new AdminError(`Dòng ${index + 1}: MSSV hoặc email không hợp lệ.`);
    if (rolls.has(rollNumber) || emails.has(email)) throw new AdminError(`Dòng ${index + 1}: trùng MSSV hoặc email.`);
    rolls.add(rollNumber); emails.add(email);
    return { rollNumber, fullName, email, memberCode: members.get(rollNumber) || "" };
  });
}
export const rosterText = students => (students || []).map(s => `${s.rollNumber} | ${s.fullName} | ${s.email}`).join("\n");
export const rosterMap = students => Object.fromEntries(students.map(s => [s.email, s.rollNumber]));
export function localIso(date) {
  const pad = n => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:00.000`;
}
export function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || "")) throw new AdminError("Chọn ngày bắt đầu hợp lệ.");
  const d = new Date(`${value}T00:00:00`);
  if (!Number.isFinite(+d) || localIso(d).slice(0,10) !== value) throw new AdminError("Ngày bắt đầu không tồn tại.");
  return d;
}
export function generateMeetings(localId, scheduleCode, start, weeks, perWeek) {
  if (!/^[1-3][1-4]$/.test(scheduleCode)) throw new AdminError("Mã lịch phải từ 11 đến 34.");
  if (!Number.isInteger(weeks) || weeks < 1 || weeks > 52 || ![1,2].includes(perWeek)) throw new AdminError("Chọn 1–52 tuần và 1–2 buổi mỗi tuần.");
  const date = validDate(start), days = [[1,4],[2,5],[3,6]][Number(scheduleCode[0])-1].slice(0,perWeek);
  const [hour, minute, endHour, endMinute] = [[7,0,9,15],[9,30,11,45],[12,30,14,45],[15,0,17,15]][Number(scheduleCode[1])-1];
  const meetings = [];
  for (let day = 0; day < weeks * 7; day++) {
    const d = new Date(date); d.setDate(d.getDate() + day);
    if (!days.includes(d.getDay())) continue;
    const endDay = new Date(d); endDay.setDate(endDay.getDate()+1);
    const begin = new Date(d); begin.setHours(hour,minute);
    const end = new Date(d); end.setHours(endHour,endMinute);
    const number = meetings.length + 1;
    meetings.push({ id: `${localId}-m${number}`, number, startAt: localIso(begin), endAt: localIso(end), state: "upcoming", dayStart: d, dayEnd: endDay, records: {}, auditEvents: [] });
  }
  return meetings;
}
export function protectHistory(students, meetings) {
  const rolls = new Set(students.map(s => s.rollNumber));
  for (const m of meetings) for (const roll of Object.keys(m.records || {})) {
    if (!rolls.has(roll)) throw new AdminError(`Không thể bỏ ${roll}: sinh viên đã có kết quả điểm danh. Giữ MSSV để bảo toàn lịch sử.`);
  }
}
export function correction(meeting, rollNumber, status, reason, id, now = new Date()) {
  reason = required(reason, "Lý do duyệt", 1000);
  const oldValue = meeting.records?.[rollNumber]?.status;
  if (meeting.state !== "closed" || !["A","P"].includes(oldValue)) throw new AdminError("Buổi học phải được chốt và có kết quả hiện tại.");
  if (!["A","P"].includes(status) || status === oldValue) throw new AdminError("Kết quả đề nghị trùng kết quả hiện tại. Hãy từ chối hoặc kiểm tra lại yêu cầu.");
  const at = now.toISOString();
  return {
    records: { ...meeting.records, [rollNumber]: { status, source: "manual", recordedAt: at, note: reason } },
    auditEvents: [...(meeting.auditEvents || []), { id, createdAt: at, action: "attendance_override", reason, rollNumber, meetingId: meeting.id, oldValue, newValue: status }],
  };
}
export function attendanceSummary(classes) {
  return classes.map(course => {
    let present = 0, absent = 0, unmarked = 0, closed = 0;
    for (const m of course.meetings || []) {
      if (m.state === "closed") closed++;
      if (m.state === "upcoming") continue;
      for (const s of course.data.students || []) {
        const status = m.records?.[s.rollNumber]?.status;
        if (status === "P") present++; else if (status === "A") absent++; else unmarked++;
      }
    }
    return { id: course.id, label: `${course.data.courseCode} · ${course.data.classCode}`, present, absent, unmarked, closed };
  });
}
export async function hashId(value) {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map(b => b.toString(16).padStart(2,"0")).join("");
}
