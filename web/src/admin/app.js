import "./style.css";
import { onAuthStateChanged, signInWithPopup, signOut } from "firebase/auth";
import { auth, db, googleProvider } from "../firebase-client.js";
import { AdminRepository } from "./repository.js";
import { rosterField } from "./class-fields.js";
import { openMarkbookImport } from "./markbook-form.js";
import {
  parseRoster,
  attendanceSummary,
  semesterCode,
} from "./model.js";
import { escapeHtml as h, dateText, messageFor, showDialog } from "../ui.js";
import { startWebTelemetry, track, webSettings } from "../telemetry.js";

document.title = "Quản lý giảng viên · FAP Attendance";
document.body.className = "admin-body";
document.body.innerHTML = '<div id="admin-root" class="admin-root"></div>';
const root = document.getElementById("admin-root");
const tabs = {
  dashboard: ["Tổng quan", "Nhịp học trong tầm tay"],
  classes: ["Lớp học", "Danh sách lớp & lịch học"],
  requests: ["Yêu cầu sửa điểm danh", "Xem xét từng yêu cầu, giữ rõ lịch sử"],
  announcements: ["Thông báo", "Kết nối với lớp học"],
};
const icons = {
  dashboard:
    '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  classes: '<path d="M3 5h7l2 2h9v13H3z"/><path d="M3 10h18"/>',
  requests: '<path d="M9 3H5v18h14V3h-4M9 2h6v4H9zM8 12l2 2 5-5M8 18h7"/>',
  announcements: '<path d="M4 10v5h4l10 5V5L8 10zM8 15l2 6M21 10v5"/>',
};
const icon = (key) =>
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true">${icons[key] || icons.classes}</svg>`;
let user,
  repo,
  stops = [],
  generation = 0,
  loadGeneration = 0;
let workspaces = [],
  selected = "",
  workspace,
  classes = [],
  requests = [],
  announcements = [];
let counts,
  loadError = "",
  loading = false,
  tab = route(),
  search = "",
  requestFilter = "pending";
let dataRevision = "";
let importingMarkbook = false;
function route() {
  const key = location.hash.slice(1);
  return Object.hasOwn(tabs, key) ? key : "dashboard";
}
const sorted = (values) =>
  [...values].sort(
    (a, b) =>
      (b.createdAt?.toMillis?.() || b.at?.toMillis?.() || 0) -
      (a.createdAt?.toMillis?.() || a.at?.toMillis?.() || 0),
  );
function feedback(text, error = false) {
  const node = document.getElementById("feedback");
  if (node) {
    node.textContent = text;
    node.className = `feedback ${error ? "error" : "success"}`;
    node.hidden = !text;
  }
}
function gate(
  message = "Đăng nhập bằng tài khoản giảng viên để quản lý lớp và theo dõi điểm danh.",
  denied = false,
) {
  root.innerHTML = `<div class="login-layout"><section class="login-intro"><a class="wordmark" href="/">F<span>FAP Attendance</span></a><p class="overline">KHÔNG GIAN GIẢNG VIÊN</p><h1>Mỗi buổi học.<br>Một góc nhìn rõ ràng.</h1><p>Lớp học, kết quả và những yêu cầu cần bạn xem xét — cùng một nơi.</p><span class="login-note">Đồng bộ cùng ứng dụng Android và Windows</span></section><section class="login-card"><span class="pill">DÀNH CHO GIẢNG VIÊN</span><h2>${denied ? "Tài khoản chưa có quyền" : "Chào mừng trở lại"}</h2><p>${h(message)}</p>${user ? `<p class="signed-email">${h(user.email)}</p>` : ""}<button id="login" class="primary">${user ? "Đổi tài khoản Google" : "Đăng nhập bằng Google"}</button><p id="login-error" class="form-error" role="alert"></p><a href="/student">Bạn là sinh viên? Mở hộp thư & yêu cầu →</a><a href="/">Về trang điểm danh</a></section></div>`;
  document.getElementById("login").onclick = async (e) => {
    e.currentTarget.disabled = true;
    try {
      if (auth.currentUser) await signOut(auth);
      await signInWithPopup(auth, googleProvider);
    } catch (error) {
      const el = document.getElementById("login-error");
      if (el) el.textContent = messageFor(error);
    } finally {
      const el = document.getElementById("login");
      if (el) el.disabled = false;
    }
  };
}
function shell() {
  root.innerHTML = `<a href="#content" class="skip-link">Đến nội dung</a><aside class="sidebar"><a class="wordmark" href="/admin">F<span>FAP Attendance<small>KHÔNG GIAN GIẢNG VIÊN</small></span></a><p class="nav-label">QUẢN LÝ</p><nav aria-label="Điều hướng chính">${Object.entries(
    tabs,
  )
    .map(
      ([key, [label]]) =>
        `<a href="#${key}" data-tab="${key}">${icon(key)}<span>${label}</span>${key === "requests" ? '<b id="queue-badge" hidden>0</b>' : ""}</a>`,
    )
    .join(
      "",
    )}</nav><div class="sidebar-bottom"><p>Một nguồn dữ liệu.<br>Liền mạch giữa các thiết bị.</p><a href="/student">Trang sinh viên ↗</a><div class="sidebar-account"><span class="account-initial">${h((user.displayName || user.email || "G")[0])}</span><div><strong>${h(user.displayName || "Giảng viên")}</strong><small>${h(user.email)}</small></div></div><button id="logout" class="text-button">Đăng xuất</button></div></aside><div class="admin-main"><header class="topbar"><div><span class="live-dot"></span> Không gian giảng viên <span class="topbar-divider">/</span> <strong id="topbar-tab"></strong></div><div class="topbar-tools"><label for="semester">Học kỳ</label><select id="semester" aria-label="Học kỳ"></select><button id="mobile-logout" class="text-button">Đăng xuất</button><button id="refresh" class="secondary small">↻ Tải lại</button></div></header><main id="content" tabindex="-1"><div class="page-heading"><div><p class="overline">FAP ATTENDANCE / GIẢNG VIÊN</p><h1 id="page-title"></h1><p id="page-subtitle" class="muted"></p></div><div id="page-actions"></div></div><p id="feedback" class="feedback" role="status" aria-live="polite" hidden></p><div id="page-body"></div></main><footer class="admin-footer">FAP Attendance <span>Dữ liệu riêng theo tài khoản · ${new Date().getFullYear()}</span></footer></div>`;
  document.getElementById("logout").onclick = async () => {
    try {
      await signOut(auth);
    } catch (e) {
      feedback(messageFor(e), true);
    }
  };
  document.getElementById("mobile-logout").onclick =
    document.getElementById("logout").onclick;
  document.querySelector(".skip-link").onclick = (event) => {
    event.preventDefault();
    document.getElementById("content").focus();
  };
  document.getElementById("refresh").onclick = () => refresh();
  document.getElementById("semester").onchange = (e) => {
    selected = e.target.value;
    dataRevision = "";
    refresh();
  };
  renderSemester();
  render();
}
function renderSemester() {
  const select = document.getElementById("semester");
  if (!select) return;
  select.innerHTML = workspaces.length
    ? workspaces
        .map(
          (w) =>
            `<option value="${h(w.id)}">${h(w.data?.semester || "Học kỳ")}</option>`,
        )
        .join("")
    : '<option value="">Chưa có học kỳ</option>';
  select.value = selected;
}
async function refresh() {
  if (!repo) return;
  const current = ++loadGeneration,
    owner = generation,
    activeRepo = repo;
  loading = true;
  loadError = "";
  render();
  try {
    const [data, newCounts] = await Promise.all([
      selected
        ? activeRepo.loadWorkspace(selected)
        : Promise.resolve({ workspace: undefined, classes: [] }),
      activeRepo.counts(),
    ]);
    if (current !== loadGeneration || owner !== generation) return;
    workspace = data.workspace;
    classes = data.classes;
    counts = newCounts;
    dataRevision = `${workspace?.id}/${workspace?.revision}`;
  } catch (e) {
    if (current === loadGeneration && owner === generation) {
      loadError = messageFor(e);
      workspace = undefined;
      classes = [];
      counts = undefined;
    }
  } finally {
    if (current === loadGeneration && owner === generation) {
      loading = false;
      render();
    }
  }
}
function empty(title, description, action = "") {
  return `<div class="empty-state"><span class="empty-icon">${icon(tab)}</span><h3>${h(title)}</h3><p>${h(description)}</p>${action}</div>`;
}
function render() {
  if (!document.getElementById("page-body")) return;
  const [title, subtitle] = tabs[tab];
  document.getElementById("page-title").textContent = title;
  document.getElementById("page-subtitle").textContent = subtitle;
  document.getElementById("topbar-tab").textContent = title;
  document.querySelectorAll("[data-tab]").forEach((el) => {
    const active = el.dataset.tab === tab;
    el.classList.toggle("active", active);
    if (active) el.setAttribute("aria-current", "page");
    else el.removeAttribute("aria-current");
  });
  const pending = requests.filter((r) => r.state === "pending").length,
    badge = document.getElementById("queue-badge");
  badge.textContent = pending;
  badge.hidden = !pending;
  document.getElementById("page-actions").innerHTML =
    tab === "classes"
      ? '<div class="detail-actions"><button class="secondary" data-action="import-markbook">Nạp Markbook</button><button class="primary" data-action="create-class">＋ Thêm lớp học</button></div>'
      : tab === "announcements"
        ? '<button class="primary" data-action="compose">＋ Soạn thông báo</button>'
        : '<span class="date-label">' +
          h(
            new Intl.DateTimeFormat("vi-VN", { dateStyle: "full" }).format(
              new Date(),
            ),
          ) +
          "</span>";
  const body = document.getElementById("page-body");
  if (loading) {
    body.innerHTML =
      '<div class="loading" role="status"><span class="spinner"></span> Đang lấy dữ liệu mới nhất…</div>';
    return;
  }
  if (loadError) {
    body.innerHTML = `<div class="error-panel" role="alert"><h3>Chưa tải được dữ liệu</h3><p>${h(loadError)}</p><button class="secondary" data-action="retry">Thử lại</button></div>`;
    return;
  }
  body.innerHTML =
    tab === "dashboard"
      ? dashboard()
      : tab === "classes"
        ? classList()
        : tab === "requests"
          ? requestList()
          : noticeList();
}
function dashboard() {
  const summary = attendanceSummary(classes),
    present = summary.reduce((s, c) => s + c.present, 0),
    absent = summary.reduce((s, c) => s + c.absent, 0);
  const rate =
    present + absent ? Math.round((100 * present) / (present + absent)) : null;
  const max = Math.max(
    1,
    ...summary.map((c) => c.present + c.absent + c.unmarked),
  );
  const stats = [
    [
      "Lớp đang quản lý",
      counts?.classes ?? 0,
      "Trong tất cả học kỳ",
      "classes",
    ],
    [
      "Yêu cầu chờ duyệt",
      counts?.pending ?? 0,
      "Cần giảng viên xem xét",
      "requests",
    ],
    [
      "Báo cáo đã xuất",
      counts?.reports ?? 0,
      "PDF, CSV và JSON trên ứng dụng",
      "reports",
    ],
  ];
  return `<section class="stat-grid" aria-label="Số liệu tổng hợp">${stats.map(([label, value, note, key]) => `<article class="stat-card"><span class="stat-label">${label}</span><span class="stat-value">${value}<span class="stat-icon">${icon(key)}</span></span><small>${note}</small></article>`).join("")}</section><div class="dashboard-grid"><section class="panel"><div class="panel-heading"><div><h2>Điểm danh theo lớp</h2><p>Các buổi đang mở và đã chốt · ${h(workspace?.data.semester || "Chưa chọn học kỳ")}</p></div><span class="pill">${rate === null ? "Chưa có kết quả" : `${rate}% có mặt`}</span></div><div class="chart-legend"><span><i class="present"></i>Có mặt</span><span><i class="absent"></i>Vắng</span><span><i class="unmarked"></i>Chưa ghi</span></div>${
    summary.length
      ? `<div class="bar-chart" role="img" aria-label="Biểu đồ số lượt điểm danh theo lớp">${summary
          .map(
            (c) =>
              `<div class="chart-row"><span class="chart-label">${h(c.label)}</span><div class="bar-track">${[
                ["present", c.present],
                ["absent", c.absent],
                ["unmarked", c.unmarked],
              ]
                .map(
                  ([key, v]) =>
                    `<span class="bar ${key}" style="width:${(v / max) * 100}%"></span>`,
                )
                .join(
                  "",
                )}</div><span class="chart-value">${c.present} P · ${c.absent} A · ${c.unmarked} ?</span></div>`,
          )
          .join("")}</div>`
      : empty(
          "Chưa có dữ liệu điểm danh",
          "Thêm lớp trên web hoặc import danh sách bằng ứng dụng để bắt đầu.",
        )
  }<p class="panel-footnote">Số lượt theo từng sinh viên trong mỗi buổi. Buổi sắp diễn ra chưa được tính.</p></section><section class="panel queue-panel"><div class="panel-heading"><div><h2>Cần xem xét</h2><p>Yêu cầu mới từ sinh viên</p></div><a href="#requests">Xem tất cả →</a></div>${
    sorted(requests.filter((r) => r.state === "pending"))
      .slice(0, 4)
      .map(
        (r) =>
          `<button class="queue-item" data-action="review" data-id="${h(r.id)}"><span class="queue-avatar">${h(r.email[0].toUpperCase())}</span><span><strong>${h(r.email)}</strong><small>Đề nghị: ${r.requestedStatus === "P" ? "Có mặt" : "Vắng"} · ${dateText(r.createdAt)}</small></span><span>↗</span></button>`,
      )
      .join("") || empty("Đã xử lý hết", "Yêu cầu mới sẽ xuất hiện tại đây.")
  }<div class="soft-note">Duyệt yêu cầu sẽ cập nhật kết quả trên cả Android và Windows.</div></section></div><section class="panel"><div class="panel-heading"><div><h2>Lớp học trong kỳ</h2><p>${classes.length} lớp · ${classes.reduce((s, c) => s + c.data.students.length, 0)} lượt ghi danh</p></div><a href="#classes">Quản lý lớp →</a></div>${classTable(classes.slice(0, 5))}</section>`;
}
function classTable(items) {
  if (!items.length)
    return empty(
      "Chưa có lớp học",
      "Thêm lớp với email sinh viên thật hoặc import ODS/XLSX trên ứng dụng.",
    );
  return `<div class="table-wrap"><table><thead><tr><th>Lớp / Môn học</th><th>Lịch</th><th>Sinh viên</th><th>Đã chốt</th><th><span class="sr-only">Thao tác</span></th></tr></thead><tbody>${items.map((c) => `<tr><td><strong>${h(c.data.classCode)}</strong><small>${h(c.data.courseCode)}</small></td><td><span class="schedule-badge">${h(c.data.scheduleCode)}</span></td><td>${c.data.students.length}</td><td>${c.meetings.filter((m) => m.state === "closed").length}<span class="muted"> / ${c.meetings.length}</span></td><td><button class="text-button" data-action="class-detail" data-id="${h(c.id)}">Chi tiết →</button></td></tr>`).join("")}</tbody></table></div>`;
}
function classList() {
  const items = classes.filter((c) =>
    `${c.data.classCode} ${c.data.courseCode}`
      .toLowerCase()
      .includes(search.toLowerCase()),
  );
  return `<section class="panel"><div class="panel-heading"><div><h2>Danh sách lớp học <span class="count">${classes.length}</span></h2><p>${h(workspace?.data.semester || "Thêm lớp để tạo học kỳ đầu tiên")}</p></div><label class="search-field"><span class="sr-only">Tìm lớp hoặc môn</span><input id="class-search" type="search" placeholder="Tìm lớp hoặc môn học…" value="${h(search)}"></label></div><div id="class-results">${classTable(items)}</div></section><p class="help-note">Lưu trữ lớp giữ nguyên lịch sử. Tạo lớp trên web bằng danh sách dán từ Excel; import file ODS/XLSX trong ứng dụng Android hoặc Windows.</p>`;
}
const stateLabels = {
  pending: "Chờ duyệt",
  approved: "Đã duyệt",
  rejected: "Đã từ chối",
};
function requestList() {
  const items = sorted(
    requests.filter(
      (r) => requestFilter === "all" || r.state === requestFilter,
    ),
  );
  return `<section class="panel"><div class="panel-heading"><div><h2>Hàng chờ xử lý</h2><p>Tất cả học kỳ · Mỗi quyết định được lưu cùng lý do</p></div><label><span class="sr-only">Lọc trạng thái yêu cầu</span><select id="request-filter">${[
    ["pending", "Chờ duyệt"],
    ["approved", "Đã duyệt"],
    ["rejected", "Đã từ chối"],
    ["all", "Tất cả"],
  ]
    .map(
      ([k, v]) =>
        `<option value="${k}" ${k === requestFilter ? "selected" : ""}>${v}</option>`,
    )
    .join(
      "",
    )}</select></label></div>${items.length ? `<div class="table-wrap"><table><thead><tr><th>Sinh viên</th><th>Đề nghị</th><th>Lý do</th><th>Trạng thái</th><th></th></tr></thead><tbody>${items.map((r) => `<tr><td><strong>${h(r.email)}</strong><small>${dateText(r.createdAt)}</small></td><td><span class="status-mark ${r.requestedStatus === "P" ? "present" : "absent"}">${r.requestedStatus}</span></td><td class="reason-cell">${h(r.reason)}</td><td><span class="pill ${r.state}">${stateLabels[r.state] || h(r.state)}</span></td><td><button class="text-button" data-action="review" data-id="${h(r.id)}">${r.state === "pending" ? "Xem xét" : "Chi tiết"} →</button></td></tr>`).join("")}</tbody></table></div>` : empty("Chưa có yêu cầu trong mục này", "Sinh viên gửi yêu cầu từ link điểm danh sau khi buổi học được chốt.")}</section>`;
}
function noticeList() {
  const groups = new Map();
  for (const n of sorted(announcements)) {
    const key = `${n.at?.toMillis?.()}|${n.classId}|${n.meetingId}|${n.title}|${n.body}`;
    if (!groups.has(key)) groups.set(key, { ...n, recipients: [] });
    groups.get(key).recipients.push(n.recipientEmail || n.recipientUid);
  }
  return `<section class="panel"><div class="panel-heading"><div><h2>Thông báo đã gửi</h2><p>Hộp thư trong ứng dụng và trang sinh viên</p></div><span class="pill">${groups.size} thông báo</span></div>${groups.size ? `<div class="notice-list">${[...groups.values()].map((n) => `<article class="notice-item"><span class="notice-symbol">${icon("announcements")}</span><div><div class="notice-meta">${dateText(n.at)}<span>${n.recipients.length} người nhận</span></div><h3>${h(n.title)}</h3><p>${h(n.body)}</p><small>${h(n.recipients.length === 1 ? (n.recipientUid === user.uid ? "Hộp thư giảng viên" : n.recipients[0]) : "Sinh viên trong danh sách lớp")}</small></div></article>`).join("")}</div>` : empty("Chưa gửi thông báo", "Soạn thông báo cho sinh viên trong lớp hoặc gửi vào hộp thư giảng viên.")}</section><p class="help-note">Thông báo được lưu trong Firestore. Sinh viên đọc tại /student; giảng viên đọc trong hộp thư Android. Chưa gửi push FCM từ web.</p>`;
}
function classForm(course) {
  const initial = course?.data,
    captured = workspace?.revision || 0;
  const known = new Map(workspaces.map((w) => [w.data.semester, w.revision]));
  const today = new Date();
  today.setMinutes(today.getMinutes() - today.getTimezoneOffset());
  const content = `<div class="form-grid"><label>Mã môn<input name="courseCode" required maxlength="32" value="${h(initial?.courseCode)}" placeholder="PRM393"></label><label>Mã lớp<input name="classCode" required maxlength="40" value="${h(initial?.classCode)}" placeholder="SE1933"></label></div>${course ? `<p class="soft-note">Lịch ${h(initial.scheduleCode)} · ${course.meetings.length} buổi. Lịch sử và mã buổi được giữ nguyên khi sửa thông tin lớp.</p>` : `<div class="form-grid"><label>Học kỳ<input name="semester" required maxlength="16" value="${h(workspace?.data.semester || "FA26")}"></label><label>Ngày bắt đầu<input name="start" type="date" required value="${h((workspace?.data.semester === "FA26" || !workspace ? "2026-09-07" : workspace.data.semesterStart?.slice(0, 10)))}"></label><label>Mã lịch<select name="scheduleCode">${[1, 2, 3].flatMap((group) => [1, 2, 3, 4].map((slot) => `<option value="${group}${slot}">${group}${slot} · ${["T2 / T5", "T3 / T6", "T4 / T7"][group - 1]} · ${["07:30", "09:30", "12:30", "15:00"][slot - 1]}</option>`)).join("")}</select></label><label>Số tuần<input name="weeks" type="number" min="1" max="52" value="10" required></label><label>Buổi mỗi tuần<select name="perWeek"><option value="2">2 buổi</option><option value="1">1 buổi (ngày đầu trong nhóm)</option></select></label></div>`}${rosterField(initial)}`;
  showDialog(
    course ? "Chỉnh sửa lớp học" : "Thêm lớp học",
    content,
    async (input) => {
      const students = parseRoster(input.roster, initial?.students, input.classCode);
      if (course) {
        await repo.editClass(course, students, input, captured);
        track("admin_class_updated");
      } else {
        const key = semesterCode(input.semester);
        const result = await repo.createClass(
          input,
          students,
          known.get(key) || 0,
        );
        selected = result.workspaceId;
        track("admin_class_created");
      }
      await refresh();
      feedback(
        course
          ? "Đã lưu thông tin lớp và danh sách sinh viên."
          : "Đã tạo lớp. Mở ứng dụng để bắt đầu buổi học và tạo QR.",
      );
    },
  );
}
function classDetail(id) {
  const c = classes.find((c) => c.id === id);
  if (!c) return;
  const d = showDialog(
    `${c.data.courseCode} · ${c.data.classCode}`,
    `<div class="detail-actions"><button type="button" class="secondary" data-edit>Chỉnh sửa lớp</button><button type="button" class="text-button danger-text" data-archive>Lưu trữ lớp</button></div><h3>Danh sách sinh viên · ${c.data.students.length}</h3><div class="table-wrap compact-table"><table><thead><tr><th>MSSV</th><th>Họ tên</th><th>Email Google</th></tr></thead><tbody>${c.data.students.map((s) => `<tr><td>${h(s.rollNumber)}</td><td>${h(s.fullName)}</td><td>${h(s.email)}</td></tr>`).join("")}</tbody></table></div><h3>Buổi học · ${c.meetings.length}</h3><div class="meeting-list">${c.meetings.map((m) => `<details><summary>Buổi ${m.number} · ${dateText(m.startAt)} <span class="pill">${{ closed: "Đã chốt", active: "Đang điểm danh", upcoming: "Sắp diễn ra" }[m.state]}</span></summary><div class="table-wrap"><table><thead><tr><th>Sinh viên</th><th>Kết quả</th><th>Nguồn / Ghi chú</th></tr></thead><tbody>${c.data.students.map((s) => `<tr><td>${h(s.rollNumber)} · ${h(s.fullName)}</td><td>${h(m.records?.[s.rollNumber]?.status || "Chưa ghi")}</td><td>${h(m.records?.[s.rollNumber]?.note || m.records?.[s.rollNumber]?.source || "—")}</td></tr>`).join("")}</tbody></table></div>${m.auditEvents?.length ? `<p class="help-note">Lịch sử chỉnh sửa</p><ul class="audit-list">${m.auditEvents.map((a) => `<li>${dateText(a.createdAt)} · ${h(a.rollNumber)}: ${h(a.oldValue)} → ${h(a.newValue)}<br>${h(a.reason)}</li>`).join("")}</ul>` : ""}</details>`).join("")}</div>`,
    async () => {},
    { label: "Đóng" },
  );
  d.querySelector("[data-edit]").onclick = () => {
    d.close();
    classForm(c);
  };
  d.querySelector("[data-archive]").onclick = () => {
    const revision = workspace.revision;
    d.close();
    showDialog(
      "Lưu trữ lớp học",
      `<p>Lưu trữ <strong>${h(c.data.courseCode)} · ${h(c.data.classCode)}</strong>? Lớp được gỡ khỏi danh sách hiện tại trên các thiết bị; kết quả và lịch sử vẫn được giữ.</p><label>Nhập mã lớp để xác nhận<input name="confirmation" required pattern="${h(c.data.classCode.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))}" placeholder="${h(c.data.classCode)}"></label>`,
      async () => {
        await repo.archiveClass(c, revision);
        track("admin_class_archived");
        await refresh();
        feedback("Đã lưu trữ lớp và giữ lịch sử.");
      },
      { label: "Lưu trữ lớp", danger: true },
    );
  };
}
async function review(id) {
  const r = requests.find((r) => r.id === id);
  if (!r) return;
  let course, meeting;
  const current = generation;
  try {
    ({ course, meeting } = await repo.requestContext(r));
  } catch (e) {
    if (current === generation) feedback(messageFor(e), true);
    return;
  }
  if (current !== generation) return;
  const content = `<dl class="request-details"><dt>Sinh viên</dt><dd>${h(r.email)}</dd><dt>Lớp học</dt><dd>${h(course ? `${course.data.courseCode} · ${course.data.classCode}` : r.classId)}</dd><dt>Buổi học</dt><dd>${h(r.meetingId)}</dd><dt>Đề nghị</dt><dd>${r.requestedStatus === "P" ? "Có mặt (P)" : "Vắng (A)"}</dd><dt>Lý do sinh viên</dt><dd class="preserve-lines">${h(r.reason)}</dd><dt>Gửi lúc</dt><dd>${dateText(r.createdAt)}</dd></dl>`;
  const roll = course?.roster?.[r.email];
  const currentStatus = meeting?.records?.[roll]?.status;
  const currentInfo = `<div class="soft-note">Kết quả hiện tại: <strong>${h(currentStatus || "Chưa có")}</strong> · ${course?.archived ? "Lớp đã lưu trữ" : "Buổi " + h(meeting?.number || "")}<br>Đề nghị của sinh viên: <strong>${h(r.requestedStatus)}</strong></div>`;
  if (r.state !== "pending") {
    showDialog(
      "Chi tiết yêu cầu",
      content +
        currentInfo +
        `<div class="soft-note"><strong>${stateLabels[r.state]}</strong><p>${h(r.decisionReason)}</p><small>${dateText(r.decidedAt)}</small></div>`,
      async () => {},
      { label: "Đóng" },
    );
    return;
  }
  showDialog(
    "Xem xét yêu cầu sửa điểm danh",
    content +
      currentInfo +
      `<label>Quyết định<select name="decision"><option value="approved">Duyệt và sửa kết quả</option><option value="rejected">Từ chối yêu cầu</option></select></label><label>Lý do xử lý<textarea name="reason" required maxlength="1000" rows="3" placeholder="Ghi kết quả đối chiếu minh chứng…"></textarea></label><p class="help-note">Khi duyệt, kết quả hiện tại và lịch sử sẽ được đọc lại trong transaction để tránh xử lý trùng.</p>`,
    async (input) => {
      await repo.decide(id, input.decision, input.reason);
      track("admin_request_decided", { decision: input.decision });
      await refresh();
      feedback("Đã xử lý yêu cầu và gửi kết quả vào hộp thư sinh viên.");
    },
    { label: "Xác nhận xử lý" },
  );
}
function compose() {
  if (!webSettings.announcementEnabled) {
    feedback(
      "Tính năng gửi thông báo đang tạm tắt theo cấu hình hệ thống.",
      true,
    );
    return;
  }
  if (!classes.length) {
    feedback("Thêm hoặc chọn học kỳ có lớp trước khi gửi thông báo.", true);
    return;
  }
  const d = showDialog(
    "Soạn thông báo",
    `<label>Lớp học<select name="classId">${classes.map((c) => `<option value="${h(c.id)}">${h(c.data.courseCode)} · ${h(c.data.classCode)}</option>`).join("")}</select></label><label>Người nhận<select name="audience"><option value="class">Tất cả sinh viên trong danh sách lớp</option><option value="self">Hộp thư giảng viên trên Android</option></select></label><label>Buổi liên quan<select name="meetingId"><option value="">Toàn lớp</option></select></label><label>Tiêu đề<input name="title" required maxlength="160" placeholder="Thông tin buổi học sắp tới"></label><label>Nội dung<textarea name="body" required maxlength="3000" rows="5"></textarea></label><p class="help-note">Gửi vào hộp thư trong hệ thống. Sinh viên đăng nhập /student bằng email có trong danh sách để đọc.</p>`,
    async (input) => {
      const c = classes.find((c) => c.id === input.classId);
      const count = await repo.sendAnnouncement(c, input);
      track("admin_announcement_sent", {
        audience: input.audience,
        recipients: count,
      });
      feedback(`Đã gửi thông báo đến ${count} người nhận.`);
    },
    { label: "Gửi thông báo" },
  );
  const select = d.querySelector('[name="classId"]'),
    meetings = d.querySelector('[name="meetingId"]');
  const update = () => {
    const c = classes.find((c) => c.id === select.value);
    meetings.innerHTML =
      '<option value="">Toàn lớp</option>' +
      c.meetings
        .map(
          (m) =>
            `<option value="${h(m.id)}">Buổi ${m.number} · ${dateText(m.startAt)}</option>`,
        )
        .join("");
  };
  select.onchange = update;
  update();
}
root.addEventListener("click", (e) => {
  const target = e.target.closest("[data-action]");
  if (!target) return;
  const action = target.dataset.action;
  if (action === "create-class") classForm();
  if (action === "import-markbook") {
    const current = generation;
    openMarkbookImport({repo,
      onBusy:value=>{if(current===generation)importingMarkbook=value;},
      onSaved:async result=>{if(current!==generation)return;selected=result.workspaceId;await refresh();feedback(`Đã lưu ${result.saved}/${result.total} lớp từ Markbook.`);},
    });
  }
  if (action === "class-detail") classDetail(target.dataset.id);
  if (action === "review") review(target.dataset.id);
  if (action === "compose") compose();
  if (action === "retry") refresh();
});
root.addEventListener("input", (e) => {
  if (e.target.id === "class-search") {
    search = e.target.value;
    document.getElementById("class-results").innerHTML = classTable(
      classes.filter((c) =>
        `${c.data.classCode} ${c.data.courseCode}`
          .toLowerCase()
          .includes(search.toLowerCase()),
      ),
    );
  }
});
root.addEventListener("change", (e) => {
  if (e.target.id === "request-filter") {
    requestFilter = e.target.value;
    render();
  }
});
window.addEventListener("hashchange", () => {
  tab = route();
  render();
  track("admin_view", { screen: tab });
});
onAuthStateChanged(auth, async (account) => {
  const current = ++generation;
  ++loadGeneration;
  stops.forEach((stop) => stop());
  stops = [];
  document.querySelectorAll("dialog").forEach((d) => d.close());
  user = account;
  repo = undefined;
  workspaces = [];
  workspace = undefined;
  classes = [];
  requests = [];
  announcements = [];
  counts = undefined;
  selected = "";
  dataRevision = "";
  loadError = "";
  loading = false;
  if (!user) {
    gate();
    return;
  }
  gate("Đang kiểm tra quyền giảng viên…");
  document.getElementById("login").disabled = true;
  const candidate = new AdminRepository(db, user.uid, user.email);
  try {
    await candidate.requireTeacher();
    if (current !== generation) return;
    repo = candidate;
    shell();
    const failure = (e) => {
      if (current !== generation) return;
      loadError = messageFor(e);
      loading = false;
      render();
    };
    stops.push(
      repo.watch(
        "workspaces",
        (rows) => {
          if (current !== generation) return;
          workspaces = rows.sort(
            (a, b) =>
              (b.updatedAt?.toMillis?.() || 0) -
              (a.updatedAt?.toMillis?.() || 0),
          );
          if (!workspaces.some((w) => w.id === selected))
            selected = workspaces[0]?.id || "";
          renderSemester();
          const next = workspaces.find((w) => w.id === selected);
          if (!importingMarkbook && `${next?.id}/${next?.revision}` !== dataRevision) refresh();
        },
        failure,
      ),
    );
    stops.push(
      repo.watch(
        "attendanceRequests",
        (rows) => {
          if (current === generation) {
            requests = rows;
            render();
            repo
              .counts()
              .then((v) => {
                if (current === generation) {
                  counts = v;
                  render();
                }
              })
              .catch(failure);
          }
        },
        failure,
      ),
    );
    stops.push(
      repo.watch(
        "announcements",
        (rows) => {
          if (current === generation) {
            announcements = rows;
            render();
          }
        },
        failure,
      ),
    );
    await startWebTelemetry();
    if (current === generation) {
      document.querySelector(".admin-footer span").textContent =
        webSettings.helpText;
      track("admin_view", { screen: tab });
    }
  } catch (e) {
    if (current === generation) gate(messageFor(e), true);
  }
});
window.addEventListener("pagehide", (event) => {
  if (!event.persisted) stops.forEach((stop) => stop());
});
