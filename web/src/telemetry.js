import { app, emulator } from "./firebase-client.js";

let analytics;
export const webSettings = {
  announcementEnabled: true,
  helpText: "Dữ liệu riêng theo tài khoản · Đồng bộ Android và Windows",
};
export async function startWebTelemetry() {
  if (emulator) return webSettings;
  await Promise.allSettled([
    (async () => {
      const sdk = await import("firebase/analytics");
      if (await sdk.isSupported())
        analytics = { instance: sdk.getAnalytics(app), log: sdk.logEvent };
    })(),
    (async () => {
      const sdk = await import("firebase/remote-config");
      if (!(await sdk.isSupported())) return;
      const config = sdk.getRemoteConfig(app);
      config.defaultConfig = {
        web_admin_announcements_enabled: true,
        web_admin_help_text: webSettings.helpText,
      };
      config.settings = {
        fetchTimeoutMillis: 5000,
        minimumFetchIntervalMillis: 3600000,
      };
      try {
        await sdk.fetchAndActivate(config);
      } catch {
        /* Defaults keep the UI usable offline or when Remote Config is unavailable. */
      }
      webSettings.announcementEnabled = sdk.getBoolean(
        config,
        "web_admin_announcements_enabled",
      );
      webSettings.helpText =
        sdk.getString(config, "web_admin_help_text") || webSettings.helpText;
    })(),
  ]);
  return webSettings;
}
export function track(name, parameters = {}) {
  // Call sites pass only screen, decision, audience and counts, never roster or message text.
  try {
    if (analytics) analytics.log(analytics.instance, name, parameters);
  } catch {
    /* Telemetry never blocks a workspace operation. */
  }
}
