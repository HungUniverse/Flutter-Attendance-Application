import { cliAccessToken, projectId } from "./admin-client.mjs";

const { access_token } = await cliAccessToken();
const headers = { Authorization: `Bearer ${access_token}`, "Content-Type": "application/json" };
const url = `https://firebaseremoteconfig.googleapis.com/v1/projects/${projectId}/remoteConfig`;
const defaults = {
  web_admin_announcements_enabled: "true",
  web_admin_help_text: "Dữ liệu riêng theo tài khoản · Đồng bộ Android và Windows",
};
for (let attempt = 0; attempt < 3; attempt++) {
  const current = await fetch(url, { headers });
  if (!current.ok) throw new Error(`Cannot read Remote Config (${current.status}).`);
  const template = await current.json();
  template.parameters ||= {};
  for (const [name,value] of Object.entries(defaults)) template.parameters[name] ||= { defaultValue: { value } };
  const saved = await fetch(url, { method:"PUT", headers:{...headers,"If-Match":current.headers.get("etag")}, body:JSON.stringify(template) });
  if (saved.status === 412 && attempt < 2) continue;
  if (!saved.ok) throw new Error(`Cannot update Remote Config (${saved.status}).`);
  const verified = await fetch(url,{headers});
  if(!verified.ok) throw new Error(`Cannot verify Remote Config (${verified.status}).`);
  const result = await verified.json();
  if(!Object.keys(defaults).every(name=>result.parameters?.[name]?.defaultValue)) throw new Error("Web defaults missing after save.");
  console.log("Verified teacher web parameters in Remote Config; existing values preserved.");
  break;
}
