import { cliAccessToken, projectId } from "./admin-client.mjs";

const { access_token } = await cliAccessToken();
const headers = {
  Authorization: `Bearer ${access_token}`,
  "Content-Type": "application/json",
};
const enable = await fetch(
  `https://serviceusage.googleapis.com/v1/projects/455582118878/services/generativelanguage.googleapis.com:enable`,
  { method: "POST", headers, body: "{}" },
);
if (!enable.ok)
  throw new Error(`Cannot enable Gemini Developer API (${enable.status}).`);
const url = `https://firebaseremoteconfig.googleapis.com/v1/projects/${projectId}/remoteConfig`;
const defaults = {
  enable_attendance_ai: "true",
  attendance_ai_model: "gemini-3.1-flash-lite",
  attendance_ai_prompt:
    "Dựa trên số lượng tổng hợp, viết gợi ý ngắn bằng tiếng Việt để giảng viên kiểm tra trước khi chốt. Không suy đoán danh tính hoặc tự thay đổi kết quả. Trả JSON gồm summary và checks.",
};
for (let attempt = 0; attempt < 3; attempt++) {
  const current = await fetch(url, { headers });
  if (!current.ok)
    throw new Error(`Cannot read Remote Config (${current.status}).`);
  const template = await current.json();
  template.parameters ||= {};
  for (const [name, value] of Object.entries(defaults))
    template.parameters[name] ||= { defaultValue: { value } };
  template.parameters.export_help_message = {
    defaultValue: {
      value: "Lưu PDF, JSON hoặc CSV trên thiết bị và chia sẻ tệp.",
    },
  };
  const saved = await fetch(url, {
    method: "PUT",
    headers: { ...headers, "If-Match": current.headers.get("etag") },
    body: JSON.stringify(template),
  });
  if (saved.status === 412 && attempt < 2) continue;
  if (!saved.ok)
    throw new Error(`Cannot update Remote Config (${saved.status}).`);
  console.log(
    "Enabled Gemini Developer API and merged Final AI parameters into Remote Config.",
  );
  break;
}
