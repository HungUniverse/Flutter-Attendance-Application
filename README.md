# FAP Attendance

Ứng dụng điểm danh cho giảng viên bằng Flutter Android và Windows, kết hợp web check-in cho sinh viên. Bản Final dùng Firebase Authentication, Firestore và Firebase Hosting. Android và Windows đọc/ghi trực tiếp bằng Firebase SDK, giữ hàng đợi ghi trên máy khi mất mạng và phát hiện xung đột giữa thiết bị.

## Firebase Final

- Web check-in tại [FAP Attendance](https://fap-attendance-71655.web.app). Sinh viên mở link `/join/{sessionId}` do giảng viên tạo.
- [Admin hệ thống](https://fap-attendance-71655.web.app/admin): thêm, sửa, khóa/mở lại và xóa hồ sơ giảng viên. [Không gian giảng viên](https://fap-attendance-71655.web.app/teacher): lớp học, dashboard, duyệt yêu cầu sửa điểm danh và soạn thông báo. [Trang sinh viên](https://fap-attendance-71655.web.app/student) có hộp thư và theo dõi yêu cầu.
- Giảng viên dùng Google Sign-In và hồ sơ quyền được chủ project cấp. Sinh viên đăng nhập Google với email đã xác minh trong roster.
- Có điểm danh thủ công, link/QR, cập nhật lượt gửi, chốt, sửa có lý do, xuất PDF/CSV/JSON trên thiết bị và metadata Firestore.
- Android duy trì Analytics, Remote Config, Crashlytics, hộp thư Firestore và gợi ý AI có thể sửa/xác nhận.
- [Cách chạy và deploy Final](docs/FINAL_SETUP.md), [mô hình dữ liệu](docs/data-model.md), [luồng liên vai trò](docs/cross-role-flow.md), [báo cáo kiểm thử](docs/test-report.md).
- AI Logic hiện trả HTTP 429 do project hết credit trả trước. Chốt điểm danh vẫn hoạt động. Tình trạng thực tế được ghi trong [AI feature](docs/ai-feature.md).
- [Hướng dẫn web quản lý](docs/admin-web.md). Bản báo cáo/slide PDF và video nộp bài cần bổ sung theo mã số sinh viên và minh chứng thực tế.
- [Định dạng Markbook và lịch giảng viên](docs/markbook-format.md): nạp ODS/XLSX, giữ năm cột danh tính và nhận lịch theo tên sheet. FA26 bắt đầu 07/09/2026, slot 1 lúc 07:30.

```powershell
flutter pub get
npm ci --prefix firebase
npm ci --prefix web
node firebase/configure-app-check.mjs
flutter run -d windows --dart-define-from-file=mobile/firebase-debug.json
flutter run -d <ANDROID_DEVICE_ID> --dart-define-from-file=mobile/firebase-debug.json
```

Các lệnh setup Firebase cần chủ project đăng nhập Firebase CLI. Trên máy mới, tải `google-services.json` theo hướng dẫn Final trước khi chạy Android. Token App Check demo nằm trong file local bị Git bỏ qua. Windows demo dùng debug attestation.

Các phần Lab 3 dưới đây mô tả mốc trước chuyển đổi tại commit `0b53f31`. Desktop local có thể chạy bằng `--dart-define=LAB3_LEGACY=true`. Công cụ AI dùng trong đợt Final là OpenAI Codex để triển khai, tự rà soát mã và chạy kiểm thử. Video demo và hồ sơ ARTEMIS đang chờ thu.

## Android Lab 3

- Hướng dẫn từng bước: [Firebase và chạy Android](docs/FIREBASE_ANDROID_SETUP.md).
- Chạy trên laptop: [Tạo máy ảo Android](docs/ANDROID_EMULATOR.md).
- Kiến trúc: [architecture.md](architecture.md); [đối chiếu thiết kế](docs/design-traceability.md).
- [Kế hoạch Analytics](docs/analytics-plan.md), [kết quả kiểm thử](docs/test-results.md) và [hướng dẫn demo Lab 3](docs/LAB3_EVIDENCE_GUIDE.md).
- Điểm vào Android mặc định là app **giảng viên**. Luồng scanner sinh viên cũ giữ ở `lib/main_student.dart`.
- Cấu hình relay HTTPS và đồng bộ trên laptop: [Hướng dẫn đồng bộ Windows và Android](docs/DESKTOP_MOBILE_SYNC.md).

```powershell
flutter pub get
flutter run -d <ANDROID_DEVICE_ID>
flutter build apk --debug
```

Thêm `android/app/google-services.json` đúng project trước khi chạy tính năng Firebase. APK chưa cấu hình chỉ mở hướng dẫn thiết lập. Build debug dùng keystore phát triển; không phải bản release nộp lên cửa hàng.

Dự án còn có một **web FAP mô phỏng** và Chrome Extension để trình diễn quy trình nhập điểm danh. Web mô phỏng không phải trang FAP thật và không gửi dữ liệu đến FAP thật.

## Thành phần và tiến độ

| Thành phần | Chức năng hiện có |
| --- | --- |
| Flutter Android Lab 3 | Giao diện giảng viên S01–S10, hai chế độ Qua link và Thủ công, MVVM/Provider và sáu dịch vụ Firebase. |
| Flutter Windows | Import ODS/XLSX, dashboard lớp và lịch hôm nay, cấu hình lịch từng lớp, bảng P/A, QR, chốt/sửa slot, export CSV, lưu local. |
| Trang check-in trên điện thoại | Mở bằng QR trong trình duyệt, nhập email và OTP nếu được yêu cầu, gửi điểm danh trong thời hạn 2 phút. |
| Firebase Authentication | Đăng nhập Google cho luồng Android và Windows qua backend HTTPS, xác minh tài khoản sinh viên khi mở link điểm danh. |
| Web FAP mô phỏng | Dashboard các lớp từ markbook, danh sách điểm danh theo slot, một ô Present cho mỗi sinh viên, Submit và xem trạng thái đã chốt. |
| Chrome Extension | Đọc JSON session hoặc CSV, đối chiếu MSSV với trang đang mở, điền điểm danh; giảng viên chọn có tự bấm Submit hay không. |

## Yêu cầu môi trường

- Flutter SDK/Dart SDK và Windows Developer Mode.
- Visual Studio với workload **Desktop development with C++** để chạy/build Flutter Windows.
- Node.js và npm để chạy web demo, build Extension.
- Google Chrome để nạp Extension.
- Android SDK và thiết bị/máy ảo có Google Play để chạy app giảng viên Lab 3. Sinh viên mở link bằng trình duyệt, không bắt buộc cài app.

Kiểm tra môi trường Flutter:

```powershell
flutter doctor -v
```

## Chạy ứng dụng giảng viên trên Windows

Tại thư mục gốc dự án:

```powershell
flutter pub get
flutter run -d windows
```

Để tạo bản `.exe`:

```powershell
flutter build windows
```

File chạy nằm trong `build/windows/x64/runner/Release/fap_attendance.exe`. Khi chuyển sang máy khác, hãy sao chép **toàn bộ thư mục `Release`**, không chỉ riêng file `.exe`.

### Import và điểm danh

1. Ở màn chào, nhập email giảng viên rồi chọn file `test/fixtures/FA26_Markbook.ods` hoặc một file `.ods`/`.xlsx` cùng cấu trúc.
2. Chọn học kỳ, ngày bắt đầu, số tuần và số slot mỗi tuần. Sau import, có thể chỉnh lịch **riêng cho từng lớp** trước khi bắt đầu điểm danh lớp đó.
3. Dashboard hiển thị các lớp và lịch dạy hôm nay. Mở một lớp để xem bảng sinh viên, các slot, tổng P/A và tỷ lệ vắng.
4. Chọn slot thuộc ngày hiện tại rồi mở QR thường hoặc QR + mã bí mật. QR thay mỗi 15 giây; mã bí mật giữ nguyên trong lần bật chế độ này và được tạo mới khi tắt rồi bật lại. Sinh viên dùng điện thoại quét QR để điểm danh.
5. Sau khi sinh viên điểm danh, bấm **Chốt danh sách**. Các ô chưa có P trở thành A. Slot đã qua ngày cũng được chốt A cho những sinh viên chưa điểm danh; không thể mở QR lại cho slot đã chốt.
6. Nếu cần sửa sau chốt, nhập lý do để tạo audit event và tăng revision trong JSON của slot. Ô P/A đã sửa có biểu tượng ghi chú; bấm vào ô để xem lý do, lịch sử chỉnh sửa hoặc chọn **Sửa tiếp**, kể cả khi slot đã qua ngày. Chỉ export CSV cho slot đã chốt.

Import lại markbook **cùng học kỳ** sẽ cập nhật lớp/sinh viên và giữ lịch sử điểm danh hiện có. Xóa lớp khỏi workspace sẽ chuyển dữ liệu lớp vào thư mục `trash/classes` trên máy, thay vì xóa vĩnh viễn ngay.

### Lưu trữ trên máy

Workspace nằm trong thư mục Documents của Windows:

```text
FAP Attendance/
  <semester>/
    workspace.json
    index.json
    source/<markbook>
    classes/<course>_<class>/
      class.json
      sessions/M01_yyyy-mm-dd.json
      exports/*.csv
    trash/classes/
```

**Một slot có một file JSON**. File đó đi từ `working` sang `final`; khi sửa sau chốt, nội dung được cập nhật với `revision` và `auditEvents`. App ghi file tạm rồi thay file chính, giữ `.bak` local để phục hồi. CSV là dữ liệu xuất ra, không phải nguồn lịch sử chính. Các file phiên bản cũ được chuyển vào `.recovery` khi app nâng cấp định dạng.

## Sinh viên quét QR trên mạng khác

Desktop phục vụ trang check-in và tự tạo HTTPS URL công khai bằng **Cloudflare Quick Tunnel**. Cài `cloudflared.exe` trong PATH hoặc đặt tại `%LOCALAPPDATA%\FAP Attendance Tools\cloudflared.exe`. Khi màn hình báo **Sẵn sàng**, sinh viên dùng Wi-Fi hoặc 4G khác mạng với giảng viên đều có thể quét QR. Máy giảng viên phải đang mở app, có Internet và giữ tunnel hoạt động trong suốt lúc điểm danh. Nếu kết nối lỗi, giao diện chỉ hiển thị nút **Thử lại**; Quick Tunnel không cần mở cổng trên router.

Sau khi quét QR, sinh viên có **2 phút** để hoàn tất đăng nhập/check-in. Hết hạn phải quét lại QR đang hiển thị. Ở chế độ QR + OTP, sinh viên còn phải nhập mã sáu chữ số. Khi chưa cấu hình Firebase, hệ thống chỉ đối chiếu email với danh sách lớp, **chưa xác minh người dùng thực sự sở hữu email đó**; chỉ nên dùng chế độ này để demo.

### Bật xác minh email bằng Firebase

Tạo Firebase project, bật Authentication → Email/Password, rồi chạy desktop với cấu hình của cùng project:

```powershell
flutter run -d windows --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
```

Khi có `FIREBASE_API_KEY`, trang check-in yêu cầu email/mật khẩu. Desktop kiểm tra Firebase ID token, trạng thái email đã xác minh và email phải khớp roster. Không lưu mật khẩu hoặc ID token vào lịch sử điểm danh.

## Web FAP mô phỏng

Từ thư mục gốc dự án:

```powershell
node demo-fap/server.mjs
```

Mở [http://localhost:4173/](http://localhost:4173/). Server cần Node.js và Dart SDK. Danh sách mặc định lấy từ `../FA26_Markbook.ods` hoặc `test/fixtures/FA26_Markbook.ods`. Bấm **Nạp danh sách lớp** để chọn tệp ODS/XLSX khác cho lượt demo hiện tại. Biến `FAP_MARKBOOK_PATH` cho phép đặt tệp mặc định khác trước khi chạy server. Trang chạy trên localhost và chỉ dùng mã lớp, mã lịch, MSSV và họ tên từ bảng tính.

Luồng demo:

1. Dashboard hiển thị danh sách lớp và số slot đã chốt.
2. Bấm lớp, chọn slot, xem các cột **MSSV → Fullname → Ô điểm danh → Hình thẻ sinh viên**. Markbook không có ảnh thẻ nên trang dùng hình thay thế.
3. Đánh dấu **Present** cho sinh viên có mặt; không đánh dấu nghĩa là Absent.
4. Bấm **Submit điểm danh**. Trang hiện **Đã chốt danh sách**, khóa slot và có nút **Về dashboard**. Mở lại slot sẽ thấy kết quả đã chốt.

Kết quả của **web demo** nằm trong `localStorage` của trình duyệt. Muốn demo một file session JSON, dùng nút **Mở JSON điểm danh** ở dashboard, sau đó nạp cùng file vào Extension để điền P/A. File `demo-fap/PRN232_SE1920_M01_2026-09-07_DEMO.json` dùng sinh viên giả lập trùng với lớp tương ứng trong tệp mẫu. Để diễn lại từ đầu, bấm **Xóa dữ liệu demo** trên dashboard.

## Chrome Extension

Build Extension:

```powershell
cd extension
npm install
npm run build
```

Mở `chrome://extensions` → bật **Developer mode** → **Load unpacked** → chọn thư mục `extension/dist`. Sau khi sửa hoặc build lại mã Extension, bấm **Reload** trên trang Extensions và tải lại tab web demo/FAP.

Để demo an toàn, mở lớp và slot tương ứng trên web mô phỏng, bấm Extension, chọn file JSON session đã chốt hoặc CSV từ máy. Extension preview số P/A và đối chiếu MSSV, lớp, ngày, slot với trang. Nếu có sinh viên thiếu, thừa hoặc trùng, thao tác sẽ bị chặn. Xác nhận để điền; mặc định **không tự Submit** để giảng viên kiểm tra. Có thể bật **Tự bấm Submit** trước khi xác nhận. Slot đã chốt trên web demo sẽ không cho điền lại.

Extension chỉ nhận JSON/CSV từ máy, không yêu cầu đăng nhập hoặc cấp quyền lưu trữ bên ngoài.

Extension có adapter cho trang FAP thật, nhưng selector và hành vi Submit **chưa được xác nhận bằng HTML trang điểm danh FAP thật**. Chỉ dùng trên tài khoản/trang thử nghiệm sau khi đã kiểm tra preview và kết quả; đừng mặc định rằng demo thành công đồng nghĩa với FAP thật đã lưu điểm danh.

## Kiểm thử

```powershell
flutter analyze
flutter test
cd extension
npm test
npm run build
```

Tệp mẫu `test/fixtures/FA26_Markbook.ods` dùng dữ liệu giả lập, gồm 10 lớp và một dòng thiếu email để kiểm tra cảnh báo khi nạp danh sách.
