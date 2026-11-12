# Attendance link relay

Máy chủ chung cho QR desktop, link mobile và đồng bộ workspace cùng tài khoản.
Workspace lưu Firestore bằng Admin SDK; phiên QR và lượt gửi lưu JSON trên
persistent volume. Chưa được triển khai công khai. Đọc
[hướng dẫn đồng bộ](../docs/DESKTOP_MOBILE_SYNC.md) trước khi build hai ứng dụng.

API mới: `GET/PUT /api/workspaces`, `GET /api/sessions/current`;
`POST /api/desktop-login`, `/api/desktop-login/complete`, `/api/desktop-login/poll`,
`/api/desktop-logout`. Workspace ghi bằng revision và mutationId để chặn ghi đè,
idempotent khi thử lại. Xung đột trả 409. Snapshot tối đa 700 KB mỗi học kỳ;
cần tách thành nhiều document nếu triển khai quy mô lớn. Server một process.
Test mặc định dùng FileWorkspaceStore trong thư mục tạm; `server.mjs` dùng Firestore.

## Cấu hình

- Node 22 trở lên, một process, một volume ghi bền vững; không chạy nhiều replica
  cùng ghi file. Chạy sau reverse proxy HTTPS.
- Cùng Firebase project với app Android. Firebase Authentication bật Google.
- Thêm Firebase Web app để lấy client config. Trong Auth > Settings > Authorized
  domains, thêm hostname HTTPS của relay cho Google popup.
- `TEACHER_EMAILS`: danh sách email giảng viên được phép tạo/đọc/dừng phiên. Mặc
  định không cho tất cả người đăng nhập trở thành giảng viên.
- Firebase Admin dùng Application Default Credentials trên host. Nếu dùng file
  service account cho môi trường phát triển, giữ **ngoài repo**, chỉ đặt đường dẫn
  trong biến môi trường. Không chép private key vào app Android.

Các biến môi trường cần có:

| Biến | Ý nghĩa |
| --- | --- |
| FIREBASE_PROJECT_ID | Project ID của Firebase |
| PUBLIC_ORIGIN | HTTPS origin của relay, không kèm path/query |
| TEACHER_EMAILS | Email giảng viên, ngăn cách bằng dấu phẩy |
| FIREBASE_WEB_CONFIG | JSON public client config của Web app: apiKey, authDomain, projectId, appId |
| GOOGLE_APPLICATION_CREDENTIALS | Đường dẫn file quản trị ngoài repo nếu host không có ADC |
| DATA_DIR | Thư mục volume lưu JSON, mặc định backend/data |
| PORT / HOST | Mặc định 8789 / 127.0.0.1 |

Chuẩn bị biến bằng công cụ quản lý secret/environment của host; không paste giá
trị quản trị vào terminal được quay video. Ví dụ origin trong tài liệu là chỗ thay
thế, không phải dịch vụ đã chạy.

```powershell
cd D:\Fall2026\PRM393\Project_PRM393\backend
npm ci --ignore-scripts
npm test
npm start
```

Backend dùng Firebase Admin Auth và Firestore. Cài đủ dependencies, bao gồm
`@google-cloud/firestore` đi kèm Firebase Admin; không dùng `--omit=optional`.
Kiểm tra `npm audit` khi cập nhật dependency.

## Kiểm thử và bảo trì

Chạy `npm test` từ `backend/` để kiểm thử thuật toán và relay qua HTTP localhost.
Khi môi trường giới hạn kết nối loopback, chạy cùng các ca kiểm thử relay trực
tiếp qua request handler bằng PowerShell:

```powershell
$env:RELAY_TEST_TRANSPORT = 'in-process'
npm test
Remove-Item Env:RELAY_TEST_TRANSPORT
```

Chế độ này vẫn dùng file tạm thật và kiểm tra được lỗi ghi đĩa, gửi lại và ghi đồng
thời. Dùng chế độ mặc định khi cần kiểm tra kết nối HTTP qua socket.

Các request đọc và cấp challenge vẫn đọc `sessions.json`, còn thao tác đổi dữ liệu
mới thay file. Nếu lưu điểm danh thất bại, client có thể gửi lại với challenge đó
trong thời hạn còn hiệu lực. Theo dõi dung lượng file và độ trễ polling nếu lưu
nhiều phiên trên cùng một volume.

## Kết nối Android

Sau khi cấu hình HTTPS thật, build/chạy app với:

```powershell
flutter run -d <ANDROID_DEVICE_ID> --dart-define=ATTENDANCE_API_URL=https://YOUR_RELAY_HOST
```

Không dùng localhost của máy tính làm URL cho điện thoại. Có thể dùng HTTPS proxy
hoặc tunnel trên **máy chủ phát triển** để demo, nhưng phải giữ máy đó chạy và cập
nhật origin/authorized domains khi URL đổi. Không chạy cloudflared desktop trong
Android. Không cần triển khai dịch vụ trả phí chỉ để kiểm thử các unit test.

## Quy trình và giới hạn

1. Teacher Firebase token + email allowlist tạo phiên đúng ngày học (Asia/Ho_Chi_Minh).
2. Link token ngẫu nhiên; mở link không ghi điểm danh.
3. Mỗi lượt có challenge hai phút. Google hoặc email/mật khẩu xác thực sinh viên
   qua Firebase; email phải verified và có trong roster. Nếu dùng email/password,
   bật provider và xác minh email trước; không nhận email tự khai làm danh tính.
4. Gửi lặp chỉ có một submission/email. App giữ ưu tiên kết quả thủ công.
5. Dừng/chốt vô hiệu hóa nhận mới. Giảng viên vẫn tải được submission đã nhận.
   App lấy lượt cuối trước khi điền Absent. Hết ngày, server tự ngừng nhận.

JSON trên volume chứa email và kết quả: giới hạn quyền đọc, sao lưu theo chính
sách của nhóm và không push lên Git. Token link là bí mật chia sẻ trong lớp.
Challenge và rate limit ở RAM; restart mất challenge, sinh viên mở lượt mới; các
submission đã ghi vẫn còn. Chưa có cam kết SLA hoặc chống gian lận vị trí/thiết bị.
Google popup cần trình duyệt hỗ trợ và authorized domain đúng. Không tự tạo dữ
liệu chứng minh trên Console.
