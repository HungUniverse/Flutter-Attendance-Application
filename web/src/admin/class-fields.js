import { escapeHtml as h } from "../ui.js";
import { rosterText } from "./model.js";

export function rosterField(course) {
  return `<label>Danh sách theo mẫu Markbook
    <textarea name="roster" rows="9" required spellcheck="false" placeholder="SE1917 | SE123456 | sv@gmail.com | SV001 | Nguyễn Văn An">${h(rosterText(course?.students,course?.classCode || ""))}</textarea>
    <small>Đúng thứ tự: Class | RollNumber | Email | MemberCode | FullName. Có thể dán cả năm cột từ Excel, gồm dòng tiêu đề; các cột điểm phía sau được bỏ qua. Class phải khớp mã lớp ở trên.</small>
  </label>`;
}
