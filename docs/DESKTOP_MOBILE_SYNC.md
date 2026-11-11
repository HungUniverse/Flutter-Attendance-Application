# Dùng chung tài khoản trên desktop và Android

Desktop dùng QR khi giảng viên có laptop. Android dùng để xem nhanh, chia sẻ
link hoặc ghi Present/Absent khi không có laptop. Cả hai dùng UID Firebase của
cùng tài khoản Google. Google Drive đã được bỏ khỏi code ứng dụng.

## Cách hoạt động

- Desktop chưa đăng nhập vẫn dùng QR LAN/tunnel hiện có. Phiên này phụ thuộc laptop.
- Desktop đã đăng nhập dùng QR từ backend HTTPS: QR thường hoặc QR kèm mã xác nhận.
  Mã xác nhận thay đổi theo cửa sổ 15 giây; server chấp nhận cửa sổ hiện tại và
  cửa sổ liền trước. Sinh viên đăng nhập email thuộc roster và xác nhận trong 2 phút.
- Đóng desktop không dừng phiên trên backend. Mobile cùng tài khoản tải dữ liệu
  và tìm lại phiên khi refresh; có thể tiếp tục nhận link hoặc ghi thủ công.
- Desktop đọc lại kết quả mỗi 5 giây khi đang mở màn QR chung. Mobile refresh mỗi
  10 giây khi app đang chạy; có nút đồng bộ và kéo xuống làm mới ở trang lịch.
- Học kỳ, lớp, sinh viên, lịch, kết quả và audit dùng cùng mã định danh từ máy chủ.
  Workspace trên Firestore nằm trong `teachers/{uid}/workspaces/{mã học kỳ băm}`;
  trường `workspace.semester` lưu tên học kỳ dễ đọc. Storage chỉ giữ báo cáo xuất.
- Mỗi lần ghi có revision và mutationId. Ghi lại cùng thao tác không nhân đôi;
  bản cũ không ghi đè bản mới. Hiện kiểm tra xung đột ở mức toàn học kỳ, nên sửa
  hai sinh viên khác nhau đồng thời cũng có thể cần đối chiếu.
- Khi mất mạng, bản trên máy và hàng chờ được lưu theo UID. Khi refresh/mở lại,
  app thử gửi lại. Khi có xung đột, giữ bản trên máy; chọn **Xử lý xung đột →
  Nhận bản máy chủ** sau khi kiểm tra. Hàng chờ được giữ trong `sync.json.backup-*`
  để đối chiếu; chưa có giao diện tự gộp từng bản ghi. Trước khi nhận bản mới nên
  xuất báo cáo của buổi đã chốt để dễ đối chiếu.

## Thiết lập Firebase

1. Trong project `fap-attendance-71655`, tạo Firestore **Standard**, production mode.
2. Publish file `firebase/firestore.rules` ở tab **Firestore Rules**. Đây là file
   khác với Storage Rules. Client không truy cập Firestore trực tiếp; backend dùng
   Admin SDK và tự kiểm tra UID, email đã xác minh và allowlist giảng viên.
3. Giữ Google provider đang bật. Thêm Web app, lấy Firebase Web config.
4. Trong Authentication → Settings → Authorized domains, thêm hostname backend.
5. Cấp quyền Firestore cho tài khoản dịch vụ chạy backend theo môi trường triển
   khai. Credential quản trị nằm trên máy chủ, ngoài source/app và ngoài Git.

## Chạy backend trên máy chủ

Đọc `backend/README.md` để thiết lập `FIREBASE_PROJECT_ID`, `PUBLIC_ORIGIN`,
`TEACHER_EMAILS`, `FIREBASE_WEB_CONFIG`, Application Default Credentials.

`server.mjs` dùng Firestore cho workspace. Phiên QR và lượt gửi sinh viên vẫn
được ghi vào volume bền vững ở `DATA_DIR`; chạy một process, không nhiều replica.
Không dùng ổ đĩa tạm của dịch vụ hosting. Cần HTTPS reverse proxy trỏ tới port
8789. `/health` chỉ kiểm tra HTTP, chưa chứng minh credential/Firestore hoạt động.

```powershell
cd backend
npm ci
npm start
```

Sau khi có địa chỉ HTTPS, kiểm tra `/health`, trang `/desktop-login`, đăng nhập
và API workspace. Không đặt `PUBLIC_ORIGIN` là localhost trong bản chạy thật.

### Bộ triển khai Docker được chuẩn bị sẵn

Thư mục `backend` có `Dockerfile`, `compose.yaml`, `Caddyfile`, `.env.example`.
Trên máy chủ Linux có Docker Compose và một tên miền trỏ đúng IP:

1. Chép source backend lên máy chủ. Sao chép `.env.example` thành `.env`, điền
   tên miền, email giảng viên và Firebase Web config của project.
2. Đặt credential Firebase Admin trong `backend/secrets/firebase-admin.json`,
   chỉ trên máy chủ. Cho UID 1000 của container quyền đọc file; không đưa vào Git.
3. Cho phép cổng 80/443 và chạy `docker compose up -d --build` trong `backend`.
4. Caddy nhận chứng chỉ HTTPS; kiểm tra `https://<tên miền>/health` và đăng nhập.
5. Giữ volume `attendance-data`: dữ liệu phiên không phụ thuộc laptop giảng viên.
   Sao lưu volume và Firestore theo môi trường vận hành. Không chạy lệnh xóa volume.

Bộ cấu hình này chưa được đưa lên một máy chủ thật hoặc thử bằng Docker trong
phiên này. Không dùng tunnel từ laptop làm bằng chứng laptop hỏng mà phiên vẫn chạy.

## Build hai ứng dụng với cùng máy chủ

Thay `YOUR_HOST` bằng hostname backend đã triển khai:

```powershell
flutter build windows --debug --dart-define=ATTENDANCE_API_URL=https://YOUR_HOST
flutter build apk --debug --dart-define=ATTENDANCE_API_URL=https://YOUR_HOST
```

Không truyền biến này: mobile tiếp tục dùng dữ liệu local và xuất Storage như
trước, desktop giữ QR LAN. Nút đăng nhập desktop sẽ báo thiếu cấu hình HTTPS.

Desktop mở trình duyệt Google khi bấm đăng nhập, chờ tối đa 2 phút. Browser chỉ
chấp nhận tài khoản trong allowlist. Desktop giữ phiên trong bộ nhớ tối đa 8 giờ;
mở lại ứng dụng hoặc backend khởi động lại cần đăng nhập lại. Không lưu token
vào workspace. Khi đổi tài khoản phải đăng xuất trước; dữ liệu local tách theo UID.

Bản Windows giao tiếp Firebase qua backend HTTPS, không khởi tạo SDK Firebase
native trên Windows. CMake tạo bản đăng ký plugin riêng trong thư mục build,
loại FlutterFire native khỏi executable desktop; file generated của Flutter được
giữ nguyên. Android vẫn dùng các plugin Firebase native như trước.

## Chuyển dữ liệu đang có

Workspace desktop cũ vẫn nằm ở thư mục `FAP Attendance`, không tự gán cho tài
khoản mới. Sau đăng nhập lần đầu, nếu tài khoản chưa có dữ liệu, chọn **Chuyển
dữ liệu desktop cũ** và xác nhận tài khoản để chuyển học kỳ đang mở cùng lịch sử.
App kiểm tra máy chủ trước; tài khoản đã có dữ liệu sẽ không bị ghi đè. Bản desktop
cũ vẫn được giữ. Hoặc import markbook mới; import không thay thế di chuyển lịch sử.

Mobile có cache cũ và chưa có sync metadata: nếu máy chủ đã có workspace, app
giữ tệp `before-sync-*.json` trước khi nhận bản máy chủ. Không tự gộp hai bộ dữ liệu.

## Kịch bản kiểm tra thật

1. Đăng nhập cùng Google trên hai máy; desktop import lớp, bấm Đồng bộ ngay.
2. Mobile tải dữ liệu tài khoản: lớp, lịch và ID buổi phải khớp, không import lại.
3. Desktop mở QR; sinh viên gửi thử, desktop/mobile thấy kết quả.
4. Đóng desktop; mobile refresh và tiếp tục cùng phiên, ghi P/A rồi chốt.
5. Mở lại desktop, đăng nhập và đồng bộ: thấy buổi đã chốt và kết quả mobile.
6. Thử offline rồi reconnect, mở lại app với hàng chờ, sửa đồng thời và xử lý
   xung đột, đăng nhập tài khoản khác không thấy dữ liệu của nhau.

Chưa có host HTTPS, cấu hình Web và credential server trong phiên làm việc này;
chưa chứng minh kịch bản hai thiết bị trên Firebase thật. Test local dùng HTTP
client/identity giả hoặc file store riêng, không thay cho kiểm thử tích hợp thật.
