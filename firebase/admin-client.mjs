import { createRequire } from "node:module";
import { applicationDefault, getApps, initializeApp } from "firebase-admin/app";

const require = createRequire(import.meta.url);
export const projectId = process.env.GCLOUD_PROJECT || "fap-attendance-71655";

// Keep login credentials inside the CLI's credential store. This helper never
// prints or copies refresh tokens, access tokens or service-account keys.
export async function cliAccessToken() {
  const {
    getGlobalDefaultAccount,
    getAccessToken,
  } = require("firebase-tools/lib/auth.js");
  const account = getGlobalDefaultAccount();
  if (!account)
    throw new Error(
      "Run firebase login first, or set GOOGLE_APPLICATION_CREDENTIALS for Admin SDK commands.",
    );
  const tokens = await getAccessToken(account.tokens.refresh_token, [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/firebase",
    "https://www.googleapis.com/auth/userinfo.email",
  ]);
  return {
    access_token: tokens.access_token,
    expires_in: Math.max(
      60,
      Math.floor((tokens.expires_at - Date.now()) / 1000),
    ),
  };
}

export function adminApp() {
  return (
    getApps()[0] ||
    initializeApp({
      projectId,
      credential: process.env.GOOGLE_APPLICATION_CREDENTIALS
        ? applicationDefault()
        : { getAccessToken: cliAccessToken },
    })
  );
}
