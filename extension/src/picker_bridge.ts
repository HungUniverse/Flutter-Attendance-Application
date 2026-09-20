declare const google: any;
declare const gapi: any;

window.addEventListener('message', async (event) => {
  if (event.data?.source !== 'fap-popup') return;
  try {
    await loadScript('https://apis.google.com/js/api.js');
    await new Promise<void>((resolve) => gapi.load('picker', resolve));
    const view = new google.picker.DocsView(google.picker.ViewId.DOCS)
      .setMimeTypes('text/csv');
    const picker = new google.picker.PickerBuilder()
      .setOAuthToken(event.data.accessToken)
      .setDeveloperKey(event.data.apiKey)
      .addView(view)
      .setCallback((data: any) => {
        if (data.action === google.picker.Action.PICKED) {
          window.opener.postMessage({ source: 'fap-picker', fileId: data.docs[0].id }, '*');
          window.close();
        }
        if (data.action === google.picker.Action.CANCEL) {
          window.opener.postMessage({ source: 'fap-picker', cancelled: true }, '*');
          window.close();
        }
      }).build();
    picker.setVisible(true);
  } catch (error) {
    window.opener.postMessage({ source: 'fap-picker', error: String(error) }, '*');
  }
});

function loadScript(source: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = source;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Không tải được Google Picker.'));
    document.head.appendChild(script);
  });
}
