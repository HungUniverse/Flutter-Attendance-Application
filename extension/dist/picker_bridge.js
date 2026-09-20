"use strict";
(() => {
  // src/picker_bridge.ts
  window.addEventListener("message", async (event) => {
    if (event.data?.source !== "fap-popup") return;
    try {
      await loadScript("https://apis.google.com/js/api.js");
      await new Promise((resolve) => gapi.load("picker", resolve));
      const view = new google.picker.DocsView(google.picker.ViewId.DOCS).setMimeTypes("text/csv");
      const picker = new google.picker.PickerBuilder().setOAuthToken(event.data.accessToken).setDeveloperKey(event.data.apiKey).addView(view).setCallback((data) => {
        if (data.action === google.picker.Action.PICKED) {
          window.opener.postMessage({ source: "fap-picker", fileId: data.docs[0].id }, "*");
          window.close();
        }
        if (data.action === google.picker.Action.CANCEL) {
          window.opener.postMessage({ source: "fap-picker", cancelled: true }, "*");
          window.close();
        }
      }).build();
      picker.setVisible(true);
    } catch (error) {
      window.opener.postMessage({ source: "fap-picker", error: String(error) }, "*");
    }
  });
  function loadScript(source) {
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = source;
      script.onload = () => resolve();
      script.onerror = () => reject(new Error("Kh\xF4ng t\u1EA3i \u0111\u01B0\u1EE3c Google Picker."));
      document.head.appendChild(script);
    });
  }
})();
//# sourceMappingURL=picker_bridge.js.map
