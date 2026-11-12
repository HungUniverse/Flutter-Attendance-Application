import "./style.css";

const path = location.pathname.replace(/\/$/, "") || "/";
if (path === "/admin") {
  await import("./system-admin/app.js");
} else if (path === "/teacher") {
  await import("./admin/app.js");
} else if (path === "/student") {
  await import("./student/app.js");
} else {
  await import("./join-page.js");
}
