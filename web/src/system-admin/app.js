import "../admin/style.css";
import "./style.css";
import { onAuthStateChanged, signInWithPopup, signOut } from "firebase/auth";
import { auth, db, googleProvider } from "../firebase-client.js";
import { TeacherDirectoryRepository } from "./repository.js";
import { AdminError } from "../admin/model.js";
import { escapeHtml as h, dateText, messageFor, showDialog } from "../ui.js";

document.title = "Quản trị hệ thống · FAP Attendance";
document.body.className = "admin-body system-admin-body";
document.body.innerHTML =
  '<div id="system-admin-root" class="admin-root"></div>';
const root = document.getElementById("system-admin-root");
let user,
  repo,
  generation = 0,
  stops = [],
  teachers = [],
  audit = [],
  loading = true,
  error = "",
  auditError = "",
  search = "",
  filter = "all";
const actionLabel = {
  create: "Thêm giảng viên",
  update: "Sửa hồ sơ",
  suspend: "Tạm khóa",
  activate: "Mở lại quyền",
  delete: "Xóa giảng viên",
};
let notice = "", noticeError = false;
const activeTab = () => (location.hash === "#audit" ? "audit" : "teachers");
function feedback(text, failure = false) {
  notice = text;
  noticeError = failure;
  const node = document.getElementById("system-feedback");
  if (node) {
    node.hidden = false;
    node.className = `feedback ${failure ? "error" : "success"}`;
    node.textContent = text;
  }
}
function gate(
  message = "Đăng nhập bằng tài khoản được chủ hệ thống cấp quyền admin.",
  denied = false,
) {
  root.innerHTML = `<div class="login-layout"><section class="login-intro"><a class="wordmark" href="/">F<span>FAP Attendance</span></a><p class="overline">QUẢN TRỊ HỆ THỐNG</p><h1>Quản lý đội ngũ<br>giảng viên.</h1><p>Cấp quyền, cập nhật hồ sơ và kiểm soát quyền truy cập hệ thống điểm danh.</p></section><section class="login-card"><span class="pill">ADMIN</span><h2>${denied ? "Không có quyền quản trị" : "Đăng nhập quản trị"}</h2><p>${h(message)}</p>${user ? `<p class="signed-email">${h(user.email)}</p>` : ""}<button id="system-login" class="primary">${user ? "Đổi tài khoản Google" : "Đăng nhập bằng Google"}</button><p id="system-login-error" class="form-error" role="alert"></p><a href="/teacher">Không gian giảng viên →</a><a href="/student">Trang sinh viên →</a></section></div>`;
  document.getElementById("system-login").onclick = async (event) => {
    event.currentTarget.disabled = true;
    try {
      if (auth.currentUser) await signOut(auth);
      await signInWithPopup(auth, googleProvider);
    } catch (e) {
      const node = document.getElementById("system-login-error");
      if (node) node.textContent = messageFor(e);
    } finally {
      const node = document.getElementById("system-login");
      if (node) node.disabled = false;
    }
  };
}
function render() {
  if (!repo) return;
  const tab = activeTab(),
    active = teachers.filter((t) => t.status === "active").length;
  root.innerHTML = `<a href="#content" class="skip-link">Đến nội dung</a><aside class="sidebar"><a class="wordmark" href="/admin">F<span>FAP Attendance<small>QUẢN TRỊ HỆ THỐNG</small></span></a><p class="nav-label">QUẢN TRỊ</p><nav aria-label="Điều hướng quản trị"><a href="#teachers" class="${tab === "teachers" ? "active" : ""}">Giảng viên <b>${teachers.length}</b></a><a href="#audit" class="${tab === "audit" ? "active" : ""}">Lịch sử quản trị</a></nav><div class="sidebar-bottom"><p>Phân quyền theo email Google.<br>Mọi thay đổi được ghi lịch sử.</p><a href="/teacher">Không gian giảng viên ↗</a><div class="sidebar-account"><span class="account-initial">A</span><div><strong>Quản trị hệ thống</strong><small>${h(user.email)}</small></div></div><button id="system-logout" class="text-button">Đăng xuất</button></div></aside><div class="admin-main"><header class="topbar"><div><span class="live-dot"></span> Quản trị hệ thống <span class="topbar-divider">/</span><strong>${tab === "teachers" ? "Giảng viên" : "Lịch sử"}</strong></div><div class="topbar-tools"><span class="pill">ADMIN</span><span class="system-admin-email">${h(user.email)}</span><button id="system-mobile-logout" class="secondary small">Đăng xuất</button></div></header><main id="content" tabindex="-1"><div class="page-heading"><div><p class="overline">FAP ATTENDANCE / QUẢN TRỊ</p><h1>${tab === "teachers" ? "Quản lý giảng viên" : "Lịch sử quản trị"}</h1><p class="muted">${tab === "teachers" ? "Thêm hồ sơ và quản lý quyền truy cập giảng viên." : "50 thay đổi gần nhất, ghi cùng transaction với hồ sơ."}</p></div>${tab === "teachers" ? '<button class="primary" data-action="add-teacher">＋ Thêm giảng viên</button>' : ""}</div><p id="system-feedback" class="feedback" role="status" aria-live="polite" hidden></p><section class="stat-grid"><article class="stat-card"><span class="stat-label">Tổng giảng viên</span><span class="stat-value">${teachers.length}</span><small>Hồ sơ trong danh mục giảng viên</small></article><article class="stat-card"><span class="stat-label">Đang hoạt động</span><span class="stat-value">${active}</span><small>Được truy cập dữ liệu lớp của mình</small></article><article class="stat-card"><span class="stat-label">Đang tạm khóa</span><span class="stat-value">${teachers.length - active}</span><small>Quyền giảng viên bị chặn tại Rules</small></article></section><div id="system-content">${error ? `<div class="error-panel" role="alert">${h(error)}<p><button class="secondary" data-action="reload">Tải lại</button></p></div>` : loading ? '<div class="loading" role="status"><span class="spinner"></span>Đang tải danh mục giảng viên…</div>' : tab === "teachers" ? directoryView() : auditView()}</div></main><footer class="admin-footer">FAP Attendance<span>Admin quản lý quyền · Giảng viên quản lý lớp</span></footer></div>`;
  const logout = async () => {
    try {
      await signOut(auth);
    } catch (e) {
      feedback(messageFor(e), true);
    }
  };
  document.getElementById("system-logout").onclick = logout;
  document.getElementById("system-mobile-logout").onclick = logout;
  document.querySelector(".skip-link").onclick = (e) => {
    e.preventDefault();
    document.getElementById("content").focus();
  };
  if (notice) feedback(notice, noticeError);
}
function directoryView() {
  return `<section class="panel"><div class="panel-heading"><div><h2>Danh mục giảng viên</h2><p>Thêm bằng email Google; không cần tạo mật khẩu hay biết UID trước.</p></div><div class="system-filters"><label class="search-field"><span class="sr-only">Tìm giảng viên</span><input id="teacher-search" type="search" value="${h(search)}" placeholder="Tên, email, mã hoặc bộ môn…"></label><label><span class="sr-only">Lọc quyền giảng viên</span><select id="teacher-filter"><option value="all">Tất cả trạng thái</option><option value="active" ${filter === "active" ? "selected" : ""}>Đang hoạt động</option><option value="suspended" ${filter === "suspended" ? "selected" : ""}>Tạm khóa</option></select></label></div></div><div id="teacher-results">${teacherTable()}</div></section><p class="help-note">Giảng viên đăng nhập Google trên Android, Windows hoặc /teacher bằng email đã được cấp quyền. Xóa hồ sơ thu hồi quyền giảng viên và giữ dữ liệu lớp; không xóa tài khoản Google hay tài khoản Firebase Authentication.</p>`;
}
function teacherTable() {
  const items = teachers
    .filter(
      (t) =>
        (filter === "all" || t.status === filter) &&
        [t.email, t.displayName, t.staffCode, t.department]
          .join(" ")
          .toLowerCase()
          .includes(search.trim().toLowerCase()),
    )
    .sort((a, b) => a.displayName.localeCompare(b.displayName, "vi"));
  if (!items.length)
    return '<div class="empty-state"><h3>Chưa có giảng viên phù hợp</h3><p>Thêm giảng viên mới hoặc đổi điều kiện tìm kiếm.</p></div>';
  return `<div class="table-wrap"><table><thead><tr><th>Giảng viên</th><th>Mã / Bộ môn</th><th>Quyền giảng viên</th><th>Cập nhật</th><th>Thao tác</th></tr></thead><tbody>${items.map((t) => `<tr><td><strong>${h(t.displayName)}</strong><small>${h(t.email)}</small></td><td>${h(t.staffCode || "—")}<small>${h(t.department || "Chưa ghi bộ môn")}</small></td><td><span class="pill ${t.status === "active" ? "approved" : "rejected"}">${t.status === "active" ? "Hoạt động" : "Tạm khóa"}</span></td><td>${dateText(t.updatedAt)}</td><td><div class="teacher-actions"><button class="text-button" data-action="edit-teacher" data-email="${h(t.email)}">Sửa</button><button class="text-button" data-action="toggle-teacher" data-email="${h(t.email)}">${t.status === "active" ? "Tạm khóa" : "Mở lại"}</button><button class="text-button danger-text" data-action="delete-teacher" data-email="${h(t.email)}">Xóa</button></div></td></tr>`).join("")}</tbody></table></div>`;
}
function auditView() {
  if (auditError)
    return `<div class="error-panel" role="alert">${h(auditError)}</div>`;
  return `<section class="panel"><div class="panel-heading"><div><h2>Nhật ký thay đổi giảng viên</h2><p>Chỉ admin được đọc. Bản ghi không được sửa hoặc xóa từ web.</p></div></div>${audit.length ? `<div class="table-wrap"><table><thead><tr><th>Thời điểm</th><th>Thao tác</th><th>Email</th><th>Thay đổi</th></tr></thead><tbody>${audit.map((row) => `<tr><td>${dateText(row.at)}</td><td>${h(actionLabel[row.action] || row.action)}</td><td>${h(row.email)}</td><td class="reason-cell">${h(row.before?.displayName || "—")} → ${h(row.after?.displayName || "—")}<small>${h(row.before?.status || "Chưa có")} → ${h(row.after?.status || "Đã xóa")}</small></td></tr>`).join("")}</tbody></table></div>` : '<div class="empty-state"><h3>Chưa có thay đổi từ web</h3><p>Thao tác thêm, sửa, khóa và xóa sẽ được ghi tại đây.</p></div>'}</section>`;
}
function editTeacher(previous) {
  const actor = repo,
    owner = generation;
  showDialog(
    previous ? "Sửa giảng viên" : "Thêm giảng viên",
    `<label>Họ tên giảng viên<input name="displayName" required maxlength="160" value="${h(previous?.displayName)}" placeholder="Nguyễn Văn An"></label><label>Email Google<input name="email" type="email" required maxlength="254" value="${h(previous?.email)}" placeholder="giangvien@gmail.com"><small>${previous ? "Đổi email sẽ thu hồi quyền của email cũ. Dữ liệu lớp vẫn thuộc tài khoản Google cũ, không tự chuyển sang email mới." : "Giảng viên dùng đúng email này để đăng nhập Google; không gửi email hay tạo mật khẩu từ form."}</small></label><div class="form-grid"><label>Mã giảng viên<input name="staffCode" maxlength="40" value="${h(previous?.staffCode)}" placeholder="GV001"></label><label>Bộ môn<input name="department" maxlength="160" value="${h(previous?.department)}" placeholder="Công nghệ thông tin"></label></div><label>Quyền giảng viên<select name="status"><option value="active">Đang hoạt động</option><option value="suspended" ${previous?.status === "suspended" ? "selected" : ""}>Tạm khóa</option></select></label>`,
    async (input) => {
      if (input.email.trim().toLowerCase() === user.email.toLowerCase())
        throw new AdminError(
          "Tài khoản admin được quản lý riêng; không thêm hoặc chuyển hồ sơ giảng viên sang chính tài khoản admin.",
        );
      await actor.save(previous, input);
      if (owner === generation)
        feedback(
          previous
            ? "Đã cập nhật hồ sơ và quyền giảng viên."
            : "Đã thêm giảng viên. Tài khoản có thể đăng nhập Google bằng email đã cấp.",
        );
    },
  );
}
function toggleTeacher(teacher) {
  const actor = repo,
    owner = generation,
    status = teacher.status === "active" ? "suspended" : "active";
  showDialog(
    status === "suspended"
      ? "Tạm khóa quyền giảng viên"
      : "Mở lại quyền giảng viên",
    `<p>${h(teacher.displayName)} · <strong>${h(teacher.email)}</strong></p><p>${status === "suspended" ? "Quyền đọc/ghi dữ liệu lớp trên Firebase sẽ bị chặn. Dữ liệu lớp và lịch sử được giữ." : "Tài khoản này sẽ được truy cập lại dữ liệu lớp của mình."}</p>`,
    async () => {
      await actor.save(teacher, { ...teacher, status });
      if (owner === generation) feedback("Đã cập nhật quyền giảng viên.");
    },
    {
      label: status === "suspended" ? "Tạm khóa" : "Mở lại quyền",
      danger: status === "suspended",
    },
  );
}
function deleteTeacher(teacher) {
  const actor = repo,
    owner = generation;
  showDialog(
    "Xóa hồ sơ giảng viên",
    `<p>Xóa <strong>${h(teacher.displayName)}</strong> (${h(teacher.email)}) khỏi danh mục và thu hồi quyền giảng viên? Dữ liệu lớp và lịch sử vẫn được giữ.</p><label>Nhập lại email để xác nhận<input name="confirmation" type="email" required autocomplete="off"></label>`,
    async (input) => {
      if (input.confirmation.trim().toLowerCase() !== teacher.email)
        throw new AdminError("Email xác nhận chưa khớp.");
      await actor.remove(teacher);
      if (owner === generation)
        feedback("Đã xóa hồ sơ và thu hồi quyền giảng viên.");
    },
    { label: "Xóa giảng viên", danger: true },
  );
}
root.addEventListener("click", (event) => {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  if (button.dataset.action === "add-teacher") editTeacher();
  if (button.dataset.action === "reload") location.reload();
  const teacher = teachers.find((t) => t.email === button.dataset.email);
  if (!teacher) return;
  if (button.dataset.action === "edit-teacher") editTeacher(teacher);
  if (button.dataset.action === "toggle-teacher") toggleTeacher(teacher);
  if (button.dataset.action === "delete-teacher") deleteTeacher(teacher);
});
root.addEventListener("input", (e) => {
  if (e.target.id === "teacher-search") {
    search = e.target.value;
    document.getElementById("teacher-results").innerHTML = teacherTable();
  }
});
root.addEventListener("change", (e) => {
  if (e.target.id === "teacher-filter") {
    filter = e.target.value;
    document.getElementById("teacher-results").innerHTML = teacherTable();
  }
});
window.addEventListener("hashchange", render);
onAuthStateChanged(auth, async (account) => {
  const current = ++generation;
  stops.forEach((stop) => stop());
  stops = [];
  document.querySelectorAll("dialog").forEach((d) => d.close());
  user = account;
  notice = "";
  noticeError = false;
  repo = undefined;
  teachers = [];
  audit = [];
  error = "";
  auditError = "";
  loading = true;
  search = "";
  filter = "all";
  if (!user) {
    gate();
    return;
  }
  gate("Đang kiểm tra quyền admin…");
  document.getElementById("system-login").disabled = true;
  const candidate = new TeacherDirectoryRepository(db, user);
  try {
    await candidate.requireAdmin();
    if (current !== generation) return;
    repo = candidate;
    render();
    const fail = (e) => {
      if (current !== generation) return;
      if (e.code === "permission-denied") {
        stops.forEach((stop) => stop());
        stops = [];
        repo = undefined;
        teachers = [];
        audit = [];
        gate(
          "Quyền quản trị không còn hợp lệ. Hãy đổi tài khoản hoặc liên hệ chủ hệ thống.",
          true,
        );
      } else {
        error = messageFor(e);
        loading = false;
        render();
      }
    };
    stops.push(
      repo.watchTeachers((rows) => {
        if (current === generation) {
          teachers = rows;
          loading = false;
          render();
        }
      }, fail),
    );
    stops.push(
      repo.watchAudit(
        (rows) => {
          if (current === generation) {
            audit = rows;
            render();
          }
        },
        (e) => {
          if (current === generation) {
            auditError = messageFor(e);
            render();
          }
        },
      ),
    );
  } catch (e) {
    if (current === generation) gate(messageFor(e), true);
  }
});
window.addEventListener("pagehide", (e) => {
  if (!e.persisted) stops.forEach((stop) => stop());
});
