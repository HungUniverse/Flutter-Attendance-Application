import { randomUUID } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { cliAccessToken, projectId } from "./admin-client.mjs";

const projectNumber = "455582118878";
const webApp = "1:455582118878:web:7d5a73f91cfe0ae062634f";
const androidApp = "1:455582118878:android:95f7109b9e1e54af62634f";
const { access_token } = await cliAccessToken();
async function api(url, method = "GET", body) {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${access_token}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json();
  if (!response.ok)
    throw new Error(
      `${response.status} ${data.error?.message || "Firebase configuration request failed"}`,
    );
  return data;
}
for (const service of [
  "firebaseappcheck.googleapis.com",
  "recaptchaenterprise.googleapis.com",
  "firebasevertexai.googleapis.com",
]) {
  await api(
    `https://serviceusage.googleapis.com/v1/projects/${projectNumber}/services/${service}:enable`,
    "POST",
    {},
  );
}
const base = `https://firebaseappcheck.googleapis.com/v1/projects/${projectNumber}/apps`;
const config = await api(`${base}/${webApp}/recaptchaEnterpriseConfig`);
let siteKey = config.siteKey;
if (!siteKey) {
  let keys;
  for (let attempt = 0; attempt < 20; attempt++) {
    try {
      keys = await api(
        `https://recaptchaenterprise.googleapis.com/v1/projects/${projectId}/keys`,
      );
      break;
    } catch (error) {
      if (attempt === 19) throw error;
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }
  let key = keys.keys?.find(
    (item) => item.displayName === "FAP Attendance check-in",
  );
  if (!key)
    key = await api(
      `https://recaptchaenterprise.googleapis.com/v1/projects/${projectId}/keys`,
      "POST",
      {
        displayName: "FAP Attendance check-in",
        webSettings: {
          allowedDomains: [
            `${projectId}.web.app`,
            `${projectId}.firebaseapp.com`,
            "localhost",
          ],
          integrationType: "SCORE",
        },
      },
    );
  siteKey = key.name.split("/").at(-1);
  await api(
    `${base}/${webApp}/recaptchaEnterpriseConfig?updateMask=siteKey,tokenTtl`,
    "PATCH",
    { name: config.name, siteKey, tokenTtl: "3600s" },
  );
}
await writeFile(
  new URL("../web/.env.production", import.meta.url),
  `VITE_RECAPTCHA_SITE_KEY=${siteKey}\n`,
);
const localConfig = new URL("../mobile/firebase-debug.json", import.meta.url);
await mkdir(new URL("../mobile/", import.meta.url), { recursive: true });
let token;
try {
  token = JSON.parse(
    await readFile(localConfig, "utf8"),
  ).FIREBASE_APPCHECK_DEBUG_TOKEN;
} catch {
  /* First local setup. */
}
token ||= randomUUID();
for (const app of [webApp, androidApp]) {
  const tokens = await api(`${base}/${app}/debugTokens`);
  if (!tokens.debugTokens?.some((item) => item.token === token)) {
    await api(`${base}/${app}/debugTokens`, "POST", {
      displayName: "FAP local Final demo",
      token,
    });
  }
}
await writeFile(
  localConfig,
  JSON.stringify({ FIREBASE_APPCHECK_DEBUG_TOKEN: token }, null, 2) + "\n",
);
for (const service of [
  "firestore.googleapis.com",
  "firebaseml.googleapis.com",
]) {
  const name = `projects/${projectNumber}/services/${service}`;
  await api(
    `https://firebaseappcheck.googleapis.com/v1/${name}?updateMask=enforcementMode`,
    "PATCH",
    { name, enforcementMode: "ENFORCED" },
  );
  const verified = await api(
    `https://firebaseappcheck.googleapis.com/v1/${name}`,
  );
  if (verified.enforcementMode !== "ENFORCED")
    throw new Error(
      `App Check enforcement verification failed for ${service}.`,
    );
}
console.log(
  "Verified App Check enforcement for Firestore and AI Logic. Web reCAPTCHA and local demo tokens are configured. Local token is stored in ignored mobile/firebase-debug.json.",
);
