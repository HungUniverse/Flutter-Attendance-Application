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
const response = await fetch(
  `${url}?updateMask.fieldPaths=role&updateMask.fieldPaths=email&updateMask.fieldPaths=provisionedAt`,
  {
    method: "PATCH",
    headers,
    body: JSON.stringify({
      fields: {
        role: { stringValue: "teacher" },
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
if (!verification.ok || profile.fields?.role?.stringValue !== "teacher")
  throw new Error("Teacher role verification failed.");
console.log(
  `Verified teacher role for ${email} in ${projectId}. Google Sign-In is required by Rules.`,
);
