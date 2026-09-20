const apiKey = 'REPLACE_WITH_GOOGLE_PICKER_API_KEY';

export async function pickCsvFromDrive(): Promise<string> {
  const token = await chrome.identity.getAuthToken({ interactive: true });
  const accessToken = typeof token === 'string' ? token : token.token;
  if (!accessToken) throw new Error('Không lấy được quyền Google Drive.');
  const fileId = await new Promise<string>((resolve, reject) => {
    const picker = window.open(chrome.runtime.getURL('picker.html'), 'fap-drive-picker', 'width=900,height=650');
    if (!picker) return reject(new Error('Trình duyệt đã chặn cửa sổ Google Picker.'));
    const listener = (event: MessageEvent) => {
      if (event.source !== picker || event.data?.source !== 'fap-picker') return;
      if (event.data.fileId) { cleanup(); resolve(event.data.fileId); }
      if (event.data.cancelled || event.data.error) {
        cleanup(); reject(new Error(event.data.error || 'Đã hủy chọn file.'));
      }
    };
    const cleanup = () => window.removeEventListener('message', listener);
    window.addEventListener('message', listener);
    setTimeout(() => picker.postMessage({ source: 'fap-popup', accessToken, apiKey }, '*'), 500);
  });
  const response = await fetch(`https://www.googleapis.com/drive/v3/files/${fileId}?alt=media`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) throw new Error('Không tải được CSV từ Drive.');
  return response.text();
}
