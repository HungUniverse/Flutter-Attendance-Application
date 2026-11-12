import { getAuth } from "firebase-admin/auth";
import { adminApp, projectId } from "./admin-client.mjs";

const email = process.argv[2]?.trim().toLowerCase();
if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
  throw new Error("Usage: npm run provision:teacher -- lecturer@example.com");
const app = adminApp();
const auth = getAuth(app);
let user;
try {
  user = await auth.getUserByEmail(email);
} catch (error) {
  if (error.code !== "auth/user-not-found") throw error;
  user = await auth.createUser({ email });
}
const { access_token } = await app.options.credential.getAccessToken();
const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/users/${user.uid}`;
const headers = {
  Authorization: `Bearer ${access_token}`,
  "Content-Type": "application/json",
};
const oldProfileResponse = await fetch(url, { headers });
if (!oldProfileResponse.ok && oldProfileResponse.status !== 404)
  throw new Error(`Cannot read existing profile (${oldProfileResponse.status}).`);
const oldProfile = oldProfileResponse.ok ? await oldProfileResponse.json() : undefined;
const role = oldProfile?.fields?.role?.stringValue === "admin" ? "admin" : "teacher";
const response = await fetch(
  `${url}?updateMask.fieldPaths=role&updateMask.fieldPaths=email&updateMask.fieldPaths=provisionedAt`,
  {
    method: "PATCH",
    headers,
    body: JSON.stringify({
      fields: {
        role: { stringValue: role },
        email: { stringValue: email },
        provisionedAt: { timestampValue: new Date().toISOString() },
      },
    }),
  },
);
if (!response.ok)
  throw new Error(`Teacher provisioning failed (${response.status}).`);
const verification = await fetch(url, { headers });
const profile = await verification.json();
if (!verification.ok || profile.fields?.role?.stringValue !== role)
  throw new Error("Teacher role verification failed.");
const directoryUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/teacherDirectory/${encodeURIComponent(email)}`;
const oldDirectoryResponse = await fetch(directoryUrl, { headers });
if (!oldDirectoryResponse.ok && oldDirectoryResponse.status !== 404)
  throw new Error(`Cannot read teacher directory (${oldDirectoryResponse.status}).`);
const old = oldDirectoryResponse.ok ? (await oldDirectoryResponse.json()).fields : {};
const at = { timestampValue: new Date().toISOString() };
const saved = await fetch(directoryUrl, { method: "PATCH", headers, body: JSON.stringify({ fields: {
  email: { stringValue: email }, displayName: old.displayName || { stringValue: user.displayName || email.split("@")[0] },
  staffCode: old.staffCode || { stringValue: "" }, department: old.department || { stringValue: "" },
  status: { stringValue: "active" }, createdAt: old.createdAt || at, updatedAt: at,
  createdBy: old.createdBy || { stringValue: "project-owner" }, updatedBy: { stringValue: "project-owner" },
} }) });
if (!saved.ok) throw new Error(`Teacher access provisioning failed (${saved.status}).`);
const access = await fetch(directoryUrl, { headers });
if (!access.ok || (await access.json()).fields?.status?.stringValue !== "active") throw new Error("Teacher access verification failed.");
console.log(
  `Verified teacher access for ${email} in ${projectId}; existing admin role preserved. Google Sign-In is required by Rules.`,
);
