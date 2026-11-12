export function sessionState(session, now = Date.now()) {
  if (!session) return 'missing';
  if (!session.receiving) return 'closed';
  if (session.expiresAt.toMillis() <= now) return 'expired';
  return 'open';
}

export function errorMessage(error) {
  const code = error?.code ?? '';
  if (code === 'permission-denied') return 'Tài khoản không có quyền check-in. Kiểm tra email trong danh sách lớp và thời hạn phiên với giảng viên.';
  if (code.includes('popup-closed') || code.includes('cancelled-popup')) return 'Bạn đã đóng cửa sổ đăng nhập. Có thể thử lại.';
  if (code.includes('popup-blocked')) return 'Trình duyệt đã chặn cửa sổ Google. Hãy cho phép cửa sổ bật lên rồi thử lại.';
  if (code.includes('unauthorized-domain')) return 'Tên miền chưa được bật đăng nhập Google trong Firebase. Hãy báo giảng viên.';
  if (code === 'failed-precondition') return 'Chưa xác minh được ứng dụng. Hãy báo giảng viên kiểm tra cấu hình App Check.';
  return 'Không thể kết nối Firebase. Kiểm tra mạng rồi thử lại.';
}

export function desktopCallback(search) {
  const params = new URLSearchParams(search);
  const port = Number(params.get('port'));
  const state = params.get('state') ?? '';
  if (!Number.isInteger(port) || port < 1024 || port > 65535 || !/^[A-Za-z0-9_-]{43}=$/.test(state)) return null;
  return {url: `http://127.0.0.1:${port}/callback`, state};
}
