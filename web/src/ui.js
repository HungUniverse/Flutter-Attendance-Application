export const escapeHtml = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
export const dateText = (value) => {
  const d = value?.toDate ? value.toDate() : new Date(value);
  return Number.isFinite(+d)
    ? new Intl.DateTimeFormat("vi-VN", {
        dateStyle: "short",
        timeStyle: "short",
      }).format(d)
    : "—";
};
export function messageFor(error) {
  if (error?.name === "AdminError") return error.message;
  const code = error?.code || "";
  if (code.includes("popup-closed") || code.includes("cancelled-popup"))
    return "Bạn đã đóng cửa sổ Google. Hãy thử lại khi sẵn sàng.";
  if (code.includes("popup-blocked"))
    return "Cho phép cửa sổ bật lên để đăng nhập Google.";
  if (code.includes("permission-denied"))
    return "Không có quyền thao tác hoặc dữ liệu đã đổi. Kiểm tra tài khoản, danh sách lớp và trạng thái buổi học rồi tải lại.";
  if (code.includes("failed-precondition"))
    return "Firebase chưa sẵn sàng cho thao tác này. Hãy thử tải lại; nếu vẫn lỗi, kiểm tra chỉ mục và App Check.";
  if (code.includes("unavailable") || code.includes("network"))
    return "Mất kết nối Firebase. Kiểm tra mạng rồi thử lại. Thay đổi trên web cần mạng để lưu.";
  return "Không hoàn tất được thao tác. Hãy thử lại hoặc báo giảng viên kiểm tra kết nối Firebase.";
}
export function showDialog(
  title,
  content,
  submit,
  { label = "Lưu thay đổi", danger = false } = {},
) {
  const dialog = document.createElement("dialog");
  dialog.className = "app-dialog";
  dialog.innerHTML = `<form><header><h2>${escapeHtml(title)}</h2><button type="button" class="icon-button" data-close aria-label="Đóng biểu mẫu">×</button></header><div class="dialog-fields">${content}</div><p class="form-error" role="alert" hidden></p><footer><button type="button" class="secondary" data-close>Hủy</button><button class="${danger ? "danger" : "primary"}" type="submit">${escapeHtml(label)}</button></footer></form>`;
  document.body.append(dialog);
  dialog.addEventListener("close", () => dialog.remove(), { once: true });
  dialog
    .querySelectorAll("[data-close]")
    .forEach((b) => b.addEventListener("click", () => dialog.close()));
  let busy = false;
  dialog.addEventListener("cancel", (e) => {
    if (busy) e.preventDefault();
  });
  dialog.querySelector("form").addEventListener("submit", async (e) => {
    e.preventDefault();
    if (busy) return;
    const form = e.currentTarget,
      data = Object.fromEntries(new FormData(form));
    busy = true;
    form.querySelectorAll("button").forEach((b) => (b.disabled = true));
    const error = form.querySelector(".form-error");
    error.hidden = true;
    try {
      await submit(data);
      dialog.close();
    } catch (failure) {
      error.textContent = messageFor(failure);
      error.hidden = false;
    } finally {
      busy = false;
      form.querySelectorAll("button").forEach((b) => (b.disabled = false));
    }
  });
  dialog.showModal();
  return dialog;
}
