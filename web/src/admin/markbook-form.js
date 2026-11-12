import { AdminError, semesterCode, generateMeetings } from "./model.js";
import { readMarkbook } from "./markbook.js";
import { escapeHtml as h, messageFor, showDialog } from "../ui.js";

export function openMarkbookImport({ repo, onBusy, onSaved }) {
  let markbook,
    reading = false,
    fileGeneration = 0;
  const dialog = showDialog(
    "Nạp Markbook giảng viên",
    `
    <fieldset class="markbook-fields">
      <label>Markbook gốc (.ods / .xlsx)<input name="markbook" type="file" accept=".ods,.xlsx" required>
        <small>Tên sheet: 11_PRN232_SE1917. Năm cột nguồn: Class, RollNumber, Email, MemberCode, FullName. Không nhập điểm, ExamDate hoặc ghi chú thi.</small></label>
      <div class="form-grid">
        <label>Học kỳ<input name="semester" value="FA26" required maxlength="16"></label>
        <label>Mốc bắt đầu học kỳ<input name="start" type="date" value="2026-09-07" required></label>
        <label>Số tuần<input name="weeks" type="number" min="1" max="52" value="10" required></label>
        <label>Buổi mỗi tuần<select name="perWeek"><option value="2">2 buổi theo cặp ngày</option><option value="1">1 buổi, ngày đầu của cặp</option></select></label>
      </div>
      <p class="soft-note">Mã lịch được đọc từ tên từng sheet. Nhóm 1: T2 + T5; nhóm 2: T3 + T6; nhóm 3: T4 + T7. Slot 1: 07:30–09:15; slot 2: 09:30–11:45; slot 3: 12:30–14:45; slot 4: 15:00–17:15.</p>
      <div id="markbook-preview" role="status">Chọn file để xem danh sách lớp trước khi nạp.</div>
    </fieldset>
    <p id="markbook-progress" role="status" aria-live="polite"></p>
    <p class="help-note">Lớp đã có được cập nhật danh sách, giữ lịch và lịch sử điểm danh. Mỗi lớp lưu trong một transaction riêng; nếu một lớp lỗi, các lớp đã lưu vẫn được giữ và được báo rõ.</p>`,
    async (input) => {
      if (reading || !markbook)
        throw new AdminError("Chờ đọc xong Markbook trước khi nạp.");
      const chosen = [...dialog.querySelectorAll('[name="sheet"]:checked')].map(
        (box) => markbook.courses[Number(box.value)],
      );
      if (!chosen.length) throw new AdminError("Chọn ít nhất một lớp để nạp.");
      const semester = semesterCode(input.semester),
        weeks = Number(input.weeks),
        perWeek = Number(input.perWeek);
      for (const course of chosen)
        generateMeetings(
          "preview",
          course.scheduleCode,
          input.start,
          weeks,
          perWeek,
        );
      const fields = dialog.querySelector("fieldset"),
        progress = dialog.querySelector("#markbook-progress");
      fields.disabled = true;
      onBusy(true);
      let saved = 0,
        workspaceId;
      try {
        const latest = await repo.workspaceForSemester(semester);
        let revision = latest?.workspace.revision || 0;
        workspaceId = latest?.workspace.id;
        const existing = latest?.classes || [];
        for (const course of chosen) {
          progress.textContent = `Đang nạp ${saved + 1}/${chosen.length}: ${course.sheetName}…`;
          const current = existing.find(
            (c) =>
              c.data.courseCode === course.courseCode &&
              c.data.classCode === course.classCode,
          );
          if (current) {
            if (current.data.scheduleCode !== course.scheduleCode)
              throw new AdminError(
                `${course.sheetName}: mã lịch khác lớp đang có. Chỉnh lịch trong ứng dụng trước khi nhập lại.`,
              );
            await repo.editClass(current, course.students, course, revision);
            revision++;
          } else {
            const result = await repo.createClass(
              { ...course, semester, start: input.start, weeks, perWeek },
              course.students,
              revision,
            );
            revision = result.revision;
            workspaceId = result.workspaceId;
          }
          saved++;
        }
      } catch (error) {
        throw new AdminError(
          `Đã lưu ${saved}/${chosen.length} lớp. ${messageFor(error)} Có thể nạp lại file; lớp đã có sẽ được cập nhật, không tạo bản trùng.`,
        );
      } finally {
        fields.disabled = false;
        onBusy(false);
        if (saved) await onSaved({ workspaceId, saved, total: chosen.length });
      }
    },
    { label: "Nạp các lớp đã chọn" },
  );
  dialog
    .querySelector('[name="markbook"]')
    .addEventListener("change", async (event) => {
      const current = ++fileGeneration,
        file = event.target.files[0],
        preview = dialog.querySelector("#markbook-preview");
      markbook = undefined;
      if (!file) {
        reading = false;
        preview.textContent = "Chọn file để xem danh sách lớp.";
        return;
      }
      reading = true;
      preview.textContent = "Đang đọc các sheet trong Markbook…";
      try {
        const result = await readMarkbook(file);
        if (current !== fileGeneration || !dialog.isConnected) return;
        markbook = result;
        if (result.semester)
          dialog.querySelector('[name="semester"]').value = result.semester;
        if (result.semester === "FA26")
          dialog.querySelector('[name="start"]').value = "2026-09-07";
        preview.innerHTML = `<h3>${result.courses.length} lớp · ${result.courses.reduce((n, c) => n + c.students.length, 0)} lượt ghi danh</h3><div class="table-wrap markbook-selection"><table><thead><tr><th>Chọn</th><th>Sheet / Lớp</th><th>Lịch</th><th>Sinh viên</th></tr></thead><tbody>${result.courses.map((c, index) => `<tr><td><input type="checkbox" name="sheet" value="${index}" checked aria-label="Nạp ${h(c.sheetName)}"></td><td><strong>${h(c.sheetName)}</strong><small>${h(c.courseCode)} · ${h(c.classCode)}</small></td><td>${c.scheduleCode}</td><td>${c.students.length}</td></tr>`).join("")}</tbody></table></div>${result.warnings.length ? `<p class="form-error">${result.warnings.map(h).join("<br>")}</p>` : ""}`;
      } catch (error) {
        if (current === fileGeneration && dialog.isConnected)
          preview.textContent = messageFor(error);
      } finally {
        if (current === fileGeneration) reading = false;
      }
    });
  return dialog;
}
