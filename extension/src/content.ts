import { FapPageAdapter } from './fap_adapter';
import type { AttendanceCsvRow } from './types';

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  const adapter = new FapPageAdapter(document);
  const run = async () => {
    const rows = message.rows as AttendanceCsvRow[];
    if (message.type === 'preview') return adapter.preview(rows);
    if (message.type === 'apply') {
      adapter.apply(rows);
      if (message.autoSubmit === true) {
        const success = await adapter.submit();
        return { filled: true, submitted: true, success };
      }
      return { filled: true, submitted: false, success: false };
    }
    throw new Error('Yêu cầu extension không hợp lệ.');
  };
  run().then(sendResponse).catch((error) => sendResponse({ error: String(error) }));
  return true;
});
