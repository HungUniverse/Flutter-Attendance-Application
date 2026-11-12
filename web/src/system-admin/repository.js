import {
  collection,
  doc,
  onSnapshot,
  query,
  orderBy,
  limit,
  runTransaction,
  serverTimestamp,
} from "firebase/firestore";
import { requireAdminAccess } from "../access.js";
import { AdminError, required } from "../admin/model.js";

const snapshotFields = (value) =>
  value
    ? Object.fromEntries(
        ["email", "displayName", "staffCode", "department", "status"].map(
          (key) => [key, value[key] || ""],
        ),
      )
    : {};
export function teacherFields(input) {
  const email = required(input.email, "Email Google", 254).toLowerCase();
  if (!/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(email))
    throw new AdminError(
      "Nhập email Google hợp lệ, không có dấu cách hoặc ký tự đường dẫn.",
    );
  const displayName = required(input.displayName, "Họ tên giảng viên", 160);
  const staffCode = String(input.staffCode || "").trim(),
    department = String(input.department || "").trim();
  if (staffCode.length > 40 || department.length > 160)
    throw new AdminError(
      "Mã giảng viên tối đa 40 ký tự; bộ môn tối đa 160 ký tự.",
    );
  if (!["active", "suspended"].includes(input.status))
    throw new AdminError("Chọn trạng thái hoạt động hoặc tạm khóa.");
  return { email, displayName, staffCode, department, status: input.status };
}
export class TeacherDirectoryRepository {
  constructor(db, user) {
    this.db = db;
    this.user = user;
  }
  requireAdmin() {
    return requireAdminAccess(this.db, this.user);
  }
  watchTeachers(next, error) {
    return onSnapshot(
      collection(this.db, "teacherDirectory"),
      (s) => next(s.docs.map((d) => ({ ...d.data(), id: d.id }))),
      error,
    );
  }
  watchAudit(next, error) {
    return onSnapshot(
      query(
        collection(this.db, "teacherAudit"),
        orderBy("at", "desc"),
        limit(50),
      ),
      (s) => next(s.docs.map((d) => ({ ...d.data(), id: d.id }))),
      error,
    );
  }
  checkCurrent(snapshot, previous) {
    if (
      !snapshot.exists() ||
      !snapshot.data().updatedAt?.isEqual(previous.updatedAt)
    )
      throw new AdminError(
        "Hồ sơ đã thay đổi hoặc bị xóa. Đóng biểu mẫu, tải lại và thử lại.",
        "conflict",
      );
  }
  async save(previous, input) {
    const value = teacherFields(input),
      ref = doc(this.db, "teacherDirectory", value.email);
    const prevEmail = previous
      ? String(previous.email ?? "")
          .trim()
          .toLowerCase()
      : "";
    const oldRef = previous
      ? doc(this.db, "teacherDirectory", prevEmail)
      : undefined;
    return runTransaction(this.db, async (tx) => {
      const current = oldRef ? await tx.get(oldRef) : undefined;
      const target = oldRef?.path === ref.path ? current : await tx.get(ref);
      if (previous) this.checkCurrent(current, previous);
      if (target.exists() && oldRef?.path !== ref.path)
        throw new AdminError(
          "Email này đã có hồ sơ giảng viên. Hãy sửa hồ sơ hiện có.",
        );
      const sameRecord = previous && prevEmail === value.email;
      const old = current?.data();
      const action = !previous
        ? "create"
        : previous.status !== value.status && prevEmail === value.email
          ? value.status === "active"
            ? "activate"
            : "suspend"
          : "update";
      tx.set(ref, {
        ...value,
        createdAt: sameRecord ? old.createdAt : serverTimestamp(),
        createdBy: sameRecord ? old.createdBy : this.user.uid,
        updatedAt: serverTimestamp(),
        updatedBy: this.user.uid,
      });
      if (oldRef && oldRef.path !== ref.path) tx.delete(oldRef);
      tx.set(doc(collection(this.db, "teacherAudit")), {
        actorUid: this.user.uid,
        email: value.email,
        action,
        before: snapshotFields(old),
        after: snapshotFields(value),
        at: serverTimestamp(),
      });
    });
  }
  async remove(previous) {
    const prevEmail = String(previous?.email ?? "")
      .trim()
      .toLowerCase();
    const ref = doc(this.db, "teacherDirectory", prevEmail);
    return runTransaction(this.db, async (tx) => {
      const current = await tx.get(ref);
      this.checkCurrent(current, previous);
      tx.delete(ref);
      tx.set(doc(collection(this.db, "teacherAudit")), {
        actorUid: this.user.uid,
        email: prevEmail,
        action: "delete",
        before: snapshotFields(current.data()),
        after: {},
        at: serverTimestamp(),
      });
    });
  }
}
