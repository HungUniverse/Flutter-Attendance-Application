# FAP Attendance

Hệ thống điểm danh local-first không dùng database:

- Flutter Windows: import markbook, sinh lịch, mở QR, quản lý P/A, lưu JSON, export CSV và đồng bộ Google Drive.
- Điện thoại sinh viên: quét QR bằng camera để mở trang web đăng nhập/check-in, không cần cài app; challenge hết hạn sau 2 phút.
- Chrome Extension Manifest V3: chọn JSON session/CSV local hoặc CSV từ Drive, đối chiếu hai chiều MSSV, fill P/A và tùy chọn tự Submit.

## Chạy Lab 1

```powershell
flutter pub get
flutter run -d windows
```

Import file `test/fixtures/FA26_Markbook.ods`. Workspace được lưu tại thư mục Documents của Windows:

```text
FAP Attendance/<semester>/
  workspace.json
  index.json
  source/<markbook>
  classes/<course>_<class>/class.json
  classes/<course>_<class>/sessions/M01_2026-09-07.json
  classes/<course>_<class>/exports/*.csv
```

Mỗi slot chỉ có một file JSON ổn định. File chuyển từ trạng thái `working` sang `final`; khi sửa sau chốt, app tăng `revision` và thêm `auditEvents` ngay trong cùng file. Mỗi lần ghi dùng file tạm và `.bak` local để phục hồi sự cố; `.bak` không được tải lên Drive. Khi nâng cấp từ bản cũ, các file `_working`/`_v001_final`/`_v002_correction` được gộp về file ổn định và chuyển vào `.recovery` ngoài thư mục đồng bộ.

## Sinh viên quét QR bằng trình duyệt

Khi GV mở slot điểm danh, desktop mở trang web check-in. QR là link web: sinh viên dùng camera điện thoại quét, trang mở ngay và bắt đầu đếm ngược **2 phút**. QR trên màn GV đổi mỗi 15 giây. Sinh viên nhập email trong roster, nhập OTP nếu GV bật chế độ QR + OTP, rồi Submit. Desktop nhận P ngay. Nếu đã hết 2 phút, sinh viên quét mã QR đang hiển thị để lấy lượt mới.

App tự thử tạo URL HTTPS công khai bằng Cloudflare Quick Tunnel qua `cloudflared`. Trên máy GV, cài `cloudflared.exe` hoặc đặt tại `%LOCALAPPDATA%\FAP Attendance Tools\cloudflared.exe`. Khi URL công khai xuất hiện trên màn QR, sinh viên ở Wi‑Fi/4G khác nhau đều có thể vào. Tunnel chỉ hoạt động khi máy GV, app và kết nối Internet vẫn chạy; mỗi lần mở lại có thể nhận URL khác. Nếu tunnel không chạy, app không hiển thị QR không dùng được: hãy thử lại bằng nút **Bật link công khai cho mọi mạng** hoặc dán một HTTPS origin từ tunnel riêng. Server mặc định chỉ nghe trên máy GV, không cần cấp quyền Firewall inbound.

Chế độ chưa cấu hình Firebase **chỉ đối chiếu email**, không chứng minh sinh viên sở hữu email đó; chỉ phù hợp demo Lab 2. Bật Firebase bên dưới trước khi dùng thật. Không cần mở cổng inbound trên router cho Quick Tunnel.

## Firebase Authentication — Lab 3

Bật Email/Password provider trong Firebase Authentication. Cả Windows và Android chạy với cùng cấu hình:

```powershell
flutter run -d windows --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
```

Khi có `FIREBASE_API_KEY`, trang check-in yêu cầu email/mật khẩu; desktop kiểm tra Firebase ID token và `emailVerified=true`. Trang browser được đưa ra Internet qua HTTPS tunnel; cổng HTTP local chỉ nghe loopback. Mã Flutter Android vẫn còn trong dự án nhưng không cần dùng cho luồng QR trình duyệt. Firestore và Realtime Database không được sử dụng.

## Google Drive

Tạo OAuth Client loại **Desktop app**, bật Drive API, rồi chạy desktop với:

```powershell
flutter run -d windows --dart-define=GOOGLE_OAUTH_CLIENT_ID=... --dart-define=GOOGLE_OAUTH_CLIENT_SECRET=...
```

Nút **Kết nối Drive** dùng system browser và scope `drive.file`. Refresh token được giữ trong Windows Credential Manager qua secure storage. Đồng bộ có debounce 10 giây, đồng bộ ngay khi chốt/export, tạo lease ba phút và gia hạn mỗi phút. Khi phát hiện hai phía cùng đổi, bản Drive được lưu local với đuôi `.drive-conflict` và app không ghi đè.

## Web FAP demo và Chrome Extension

Chạy trang demo độc lập:

```powershell
node demo-fap/server.mjs
```

Mở `http://localhost:4173/`. Dashboard đọc `D:\Fall2026\PRM393\FA26_Markbook.ods` (hoặc bản fixture cùng nội dung trong `test/fixtures`) và liệt kê 10 lớp. Bấm một lớp để chọn slot và mở danh sách điểm danh; sau khi Submit, trang báo **Đã chốt danh sách** và có nút **Về dashboard**. Các slot đã chốt được giữ trong `localStorage`, hiển thị tiến độ trên dashboard và không cho điền lại. Khi file markbook thay đổi, tải lại trang để cập nhật dữ liệu. Có thể đặt biến môi trường `FAP_MARKBOOK_PATH` trước khi chạy server để dùng file khác. Trang chỉ lấy MSSV/họ tên, không đưa email hay cột điểm lên web; chỉ nghe trên `localhost`. Thứ tự cột là **MSSV → Fullname → Ô điểm danh → Hình thẻ sinh viên**. Vì markbook không có ảnh thẻ, trang dùng hình thay thế. Có thể nạp JSON session thật bằng nút **Mở JSON để demo** trên dashboard. Nút Submit chỉ lưu trong trình duyệt demo, **không gửi tới FAP thật**.

Trong extension, chọn file `Mxx_yyyy-mm-dd.json` của slot đã chốt (`state: final`) hoặc CSV. Trên dashboard web demo, mở cùng lớp rồi chọn đúng ngày/slot; Extension đối chiếu MSSV và metadata trước khi cho điền. Mặc định chỉ điền ô Present, để GV kiểm tra và tự bấm Submit; đánh dấu **Tự bấm Submit** để extension bấm nút gốc và chờ thông báo thành công. Sau khi chốt, Extension sẽ từ chối điền lại slot đó. Nếu dùng fixture giả `demo-fap/sample-session.json` để kiểm thử Extension, hãy nạp chính file đó vào trang demo trước.

Google Picker là nguồn CSV tùy chọn. Để dùng Picker, trong `extension/public/manifest.json`, thay `REPLACE_WITH_EXTENSION_OAUTH_CLIENT_ID` bằng OAuth Client cho Chrome Extension; trong `extension/src/drive_picker.ts`, thay `REPLACE_WITH_GOOGLE_PICKER_API_KEY` bằng API key đã bật Google Picker API. Nạp JSON/CSV từ máy không cần hai cấu hình này.

```powershell
cd extension
npm install
npm run build
npm test
```

Mở `chrome://extensions`, bật Developer mode, chọn **Load unpacked** và trỏ tới `extension/dist`. Content script chạy trên trang FAP và localhost demo. Selector DOM tập trung trong `src/fap_adapter.ts`; **trang FAP thật vẫn cần HTML fixture đã ẩn danh để xác nhận selector và thao tác Submit**, còn demo đã có kiểm thử tự động.

## Kiểm thử

```powershell
flutter analyze
flutter test
cd extension
npm run build
npm test
```

Fixture ODS nguồn có vài dòng cuối thiếu Class/Email. Importer không làm hỏng cả sheet: các dòng roster đầy đủ vẫn được import và từng dòng lỗi được báo trong hộp cảnh báo.

## Giới hạn cấu hình máy hiện tại

Để build Windows cần Visual Studio workload **Desktop development with C++** (MSVC, CMake, Windows SDK). Để build Android cần Android SDK. Windows Developer Mode phải bật để Flutter tạo symlink cho plugin.
