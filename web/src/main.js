import "./style.css";
import { initializeApp } from "firebase/app";
import {
  getAuth,
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut,
} from "firebase/auth";
import {
  getFirestore,
  doc,
  getDocFromServer,
  onSnapshot,
  runTransaction,
  serverTimestamp,
  connectFirestoreEmulator,
} from "firebase/firestore";
import { connectAuthEmulator } from "firebase/auth";
import {
  initializeAppCheck,
  ReCaptchaEnterpriseProvider,
} from "firebase/app-check";
import { firebaseConfig } from "./firebase-config.js";
import { sessionState, errorMessage, desktopCallback } from "./check-in.js";

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const googleProvider = new GoogleAuthProvider();
googleProvider.setCustomParameters({ prompt: "select_account" });
let desktopCredential;
const emulator =
  import.meta.env.DEV && import.meta.env.VITE_USE_EMULATORS === "true";
if (emulator) {
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  connectFirestoreEmulator(db, "127.0.0.1", 8080);
} else if (import.meta.env.VITE_RECAPTCHA_SITE_KEY) {
  initializeAppCheck(app, {
    provider: new ReCaptchaEnterpriseProvider(
      import.meta.env.VITE_RECAPTCHA_SITE_KEY,
    ),
    isTokenAutoRefreshEnabled: true,
  });
}

const $ = (id) => document.getElementById(id);
const sessionId = location.pathname.match(
  /^\/join\/([A-Za-z0-9_-]{1,128})\/?$/,
)?.[1];
const desktop = location.pathname === "/desktop-login";
let session,
  submitted = false,
  working = false,
  failed = false,
  unsubscribe,
  stopOwn;
let generation = 0;
function status(text, type = "") {
  $("status").textContent = text;
  $("status").className = type;
}
function render() {
  const user = auth.currentUser;
  $("account").hidden = !user;
  $("name").textContent = user?.displayName || "Tài khoản Google";
  $("email").textContent = user?.email || "";
  document.querySelector(".avatar").textContent = (user?.displayName ||
    user?.email ||
    "G")[0].toUpperCase();
  $("sign-out").hidden = !user;
  $("sign-in").hidden = Boolean(user) || (!sessionId && !desktop);
  $("retry").hidden = !failed || working;
  $("confirm").hidden =
    !user ||
    submitted ||
    failed ||
    (!desktop && sessionState(session) !== "open");
  for (const button of document.querySelectorAll("button"))
    button.disabled = working;
  if (working || failed) return;
  if (desktop) {
    $("context").textContent = "ĐĂNG NHẬP GIẢNG VIÊN";
    $("heading").textContent = "Kết nối ứng dụng Windows";
    $("description").textContent =
      "Đăng nhập Google, sau đó xác nhận kết nối với ứng dụng FAP Attendance trên máy này.";
    $("confirm").textContent = "Kết nối ứng dụng trên máy này";
    $("privacy").textContent =
      "Chỉ kết nối khi bạn vừa bấm Đăng nhập trong ứng dụng FAP Attendance trên máy tính này.";
    status(
      user
        ? "Kiểm tra đúng tài khoản giảng viên trước khi kết nối."
        : "Đăng nhập Google để tiếp tục.",
    );
    return;
  }
  $("session").hidden = !session;
  if (session) {
    $("class-label").textContent = session.label;
    $("deadline").textContent =
      `Nhận đến ${session.expiresAt.toDate().toLocaleTimeString("vi-VN")}`;
  }
  if (submitted)
    status(
      "Đã gửi điểm danh thành công. Giảng viên sẽ nhận lượt xác nhận của bạn.",
      "success",
    );
  else if (!sessionId)
    status("Hãy quét QR hoặc mở link điểm danh do giảng viên cung cấp.");
  else if (!user)
    status("Đăng nhập Google để xem và xác nhận phiên điểm danh.");
  else if (sessionState(session) === "closed")
    status("Giảng viên đã dừng nhận điểm danh.", "error");
  else if (sessionState(session) === "expired")
    status(
      "Phiên đã hết hạn. Hãy quét mã QR mới hoặc xin lại link từ giảng viên.",
      "error",
    );
  else if (!session) status("Không tìm thấy phiên điểm danh.", "error");
  else status("Bấm xác nhận để ghi nhận có mặt cho tài khoản của bạn.");
}
async function load(user) {
  const current = ++generation;
  unsubscribe?.();
  stopOwn?.();
  submitted = false;
  session = undefined;
  failed = false;
  if (!user || !sessionId) {
    render();
    return;
  }
  working = true;
  status("Đang tải phiên từ Firebase…");
  render();
  try {
    const ref = doc(db, "attendanceSessions", sessionId);
    const [snapshot, own] = await Promise.all([
      getDocFromServer(ref),
      getDocFromServer(doc(ref, "checkIns", user.uid)),
    ]);
    if (generation !== current) return;
    session = snapshot.data();
    submitted = own.exists();
    unsubscribe = onSnapshot(
      ref,
      (next) => {
        session = next.data();
        render();
      },
      (error) => {
        failed = true;
        status(errorMessage(error), "error");
        render();
      },
    );
    stopOwn = onSnapshot(
      doc(ref, "checkIns", user.uid),
      (next) => {
        submitted = next.exists();
        render();
      },
      (error) => {
        failed = true;
        status(errorMessage(error), "error");
        render();
      },
    );
  } catch (error) {
    if (generation === current) {
      failed = true;
      status(errorMessage(error), "error");
    }
  } finally {
    if (generation === current) {
      working = false;
      render();
    }
  }
}
async function connectDesktop() {
  const callback = desktopCallback(location.search);
  if (!callback) throw new Error("Invalid desktop callback");
  if (
    desktopCredential?.uid !== auth.currentUser.uid ||
    !desktopCredential.idToken
  ) {
    const result = await signInWithPopup(auth, googleProvider);
    desktopCredential = {
      uid: result.user.uid,
      idToken: GoogleAuthProvider.credentialFromResult(result)?.idToken,
    };
  }
  const profile = await getDocFromServer(
    doc(db, "users", auth.currentUser.uid),
  );
  if (profile.data()?.role !== "teacher") throw { code: "teacher-required" };
  // Keep the Google credential in memory only until the local handoff.
  const token = desktopCredential.idToken;
  if (!token) throw new Error("Missing Google credential");
  const form = document.createElement("form");
  form.method = "POST";
  form.action = callback.url;
  for (const [name, value] of Object.entries({
    state: callback.state,
    idToken: token,
  })) {
    const input = document.createElement("input");
    input.type = "hidden";
    input.name = name;
    input.value = value;
    form.append(input);
  }
  document.body.append(form);
  form.submit();
}
$("sign-in").addEventListener("click", async () => {
  working = true;
  failed = false;
  status("Đang đăng nhập Google…");
  render();
  try {
    const result = await signInWithPopup(auth, googleProvider);
    if (desktop)
      desktopCredential = {
        uid: result.user.uid,
        idToken: GoogleAuthProvider.credentialFromResult(result)?.idToken,
      };
  } catch (error) {
    failed = true;
    status(errorMessage(error), "error");
  } finally {
    working = false;
    render();
  }
});
$("sign-out").addEventListener("click", async () => {
  working = true;
  render();
  try {
    desktopCredential = undefined;
    await signOut(auth);
  } catch (error) {
    failed = true;
    status(errorMessage(error), "error");
  } finally {
    working = false;
    render();
  }
});
$("retry").addEventListener("click", () => {
  if (desktop) {
    failed = false;
    render();
  } else load(auth.currentUser);
});
$("confirm").addEventListener("click", async () => {
  if (working || !auth.currentUser) return;
  working = true;
  failed = false;
  render();
  status("Đang gửi xác nhận…");
  try {
    if (desktop) {
      await connectDesktop();
      return;
    }
    const user = auth.currentUser;
    const ref = doc(db, "attendanceSessions", sessionId, "checkIns", user.uid);
    const duplicate = await runTransaction(db, async (transaction) => {
      const own = await transaction.get(ref);
      if (own.exists()) return true;
      transaction.set(ref, {
        uid: user.uid,
        email: user.email.toLowerCase(),
        at: serverTimestamp(),
      });
      return false;
    });
    submitted = true;
    status(
      duplicate
        ? "Bạn đã gửi điểm danh cho buổi học này."
        : "Đã gửi điểm danh thành công.",
      "success",
    );
  } catch (error) {
    failed = true;
    status(errorMessage(error), "error");
  } finally {
    working = false;
    render();
  }
});
onAuthStateChanged(
  auth,
  (user) => {
    load(user);
  },
  (error) => {
    failed = true;
    status(errorMessage(error), "error");
    render();
  },
);
setInterval(() => {
  if (!working && !failed && !submitted) render();
}, 1000);
window.addEventListener("pagehide", () => {
  unsubscribe?.();
  stopOwn?.();
});
render();
