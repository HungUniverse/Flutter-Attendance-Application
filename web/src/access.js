import { doc, getDocFromServer } from "firebase/firestore";
import { AdminError } from "./admin/model.js";

export async function requireAdminAccess(db, user) {
  if (!user) throw new AdminError("Vui lòng đăng nhập Google.");
  const profile = await getDocFromServer(doc(db, "users", user.uid));
  if (profile.data()?.role !== "admin")
    throw new AdminError(
      "Tài khoản này không có quyền quản trị hệ thống.",
      "admin-required",
    );
  return profile.data();
}
export async function requireTeacherAccess(db, user) {
  if (!user?.email) throw new AdminError("Vui lòng đăng nhập Google.");
  const directory = await getDocFromServer(
    doc(db, "teacherDirectory", user.email.toLowerCase()),
  );
  if (directory.data()?.status === "active") return directory.data();
  const profile = await getDocFromServer(doc(db, "users", user.uid));
  if (profile.data()?.role === "admin") return profile.data();
  throw new AdminError(
    "Quyền giảng viên chưa được cấp, đang tạm khóa hoặc đã bị thu hồi. Liên hệ admin hệ thống.",
    "teacher-required",
  );
}
