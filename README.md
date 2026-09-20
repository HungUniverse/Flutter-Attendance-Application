# FAP Attendance

Ứng dụng điểm danh cho giảng viên, xây dựng bằng Flutter Windows. Sinh viên quét QR bằng camera điện thoại và điểm danh trên trình duyệt, không cần cài ứng dụng. Dữ liệu lớp và lịch sử điểm danh được lưu bằng file JSON/CSV trên máy giảng viên; Google Drive là nơi đồng bộ tùy chọn, **không sử dụng database**.

Dự án còn có một **web FAP mô phỏng** và Chrome Extension để trình diễn quy trình nhập điểm danh. Web mô phỏng không phải trang FAP thật và không gửi dữ liệu đến FAP thật.

## Thành phần và tiến độ

| Thành phần | Chức năng hiện có |
| --- | --- |
| Flutter Windows | Import ODS/XLSX, dashboard lớp và lịch hôm nay, cấu hình lịch từng lớp, bảng P/A, QR, chốt/sửa slot, export CSV, lưu local, kết nối Drive. |
| Trang check-in trên điện thoại | Mở bằng QR trong trình duyệt, nhập email và OTP nếu được yêu cầu, gửi điểm danh trong thời hạn 2 phút. |
| Firebase Authentication | Tùy chọn cấu hình để xác minh email sinh viên bằng email/mật khẩu và email verification; không dùng Firestore/Realtime Database. |
| Web FAP mô phỏng | Dashboard các lớp từ markbook, danh sách điểm danh theo slot, một ô Present cho mỗi sinh viên, Submit và xem trạng thái đã chốt. |
| Chrome Extension | Đọc JSON session hoặc CSV, đối chiếu MSSV với trang đang mở, điền điểm danh; giảng viên chọn có tự bấm Submit hay không. |

## Yêu cầu môi trường

- Flutter SDK/Dart SDK và Windows Developer Mode.
- Visual Studio với workload **Desktop development with C++** để chạy/build Flutter Windows.
- Node.js và npm để chạy web demo, build Extension.
- Google Chrome để nạp Extension.
- Android SDK chỉ cần nếu muốn chạy ứng dụng Flutter Android còn nằm trong mã nguồn; luồng sinh viên quét QR bằng trình duyệt **không cần Android SDK hoặc app Android**.

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

1. Ở màn chào, nhập email giảng viên rồi chọn file `test/fixtures/FA26_Markbook.ods` hoặc một file `.ods`/`.xlsx` cùng cấu trúc. Có thể import từ Google Drive sau khi kết nối Drive.
2. Chọn học kỳ, ngày bắt đầu, số tuần và số slot mỗi tuần. Sau import, có thể chỉnh lịch **riêng cho từng lớp** trước khi bắt đầu điểm danh lớp đó.
3. Dashboard hiển thị các lớp và lịch dạy hôm nay. Mở một lớp để xem bảng sinh viên, các slot, tổng P/A và tỷ lệ vắng.
4. Chọn slot thuộc ngày hiện tại rồi mở QR thường hoặc QR + OTP. QR thay mỗi 15 giây. Có thể dùng chức năng mô phỏng sinh viên trên desktop để demo không cần điện thoại.
5. Sau khi sinh viên điểm danh, bấm **Chốt danh sách**. Các ô chưa có P trở thành A. Slot đã qua ngày cũng được chốt A cho những sinh viên chưa điểm danh; không thể mở QR lại cho slot đã chốt.
6. Nếu cần sửa sau chốt, nhập lý do để tạo audit event và tăng revision trong JSON của slot. Chỉ export CSV cho slot đã chốt.

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

Desktop phục vụ trang check-in và thử tạo HTTPS URL công khai bằng **Cloudflare Quick Tunnel**. Cài `cloudflared.exe` trong PATH hoặc đặt tại `%LOCALAPPDATA%\FAP Attendance Tools\cloudflared.exe`. Khi màn QR hiển thị URL công khai, sinh viên dùng Wi-Fi hoặc 4G khác mạng với giảng viên vẫn truy cập được. Máy giảng viên phải đang mở app, có Internet và giữ tunnel hoạt động trong suốt lúc điểm danh. URL có thể đổi ở lần mở sau.

Nếu chưa có URL, dùng nút **Bật link công khai cho mọi mạng** hoặc cấu hình một HTTPS origin từ tunnel riêng. Server check-in mặc định chỉ nghe trên máy giảng viên; Quick Tunnel không cần mở cổng trên router.

Sau khi quét QR, sinh viên có **2 phút** để hoàn tất đăng nhập/check-in. Hết hạn phải quét lại QR đang hiển thị. Ở chế độ QR + OTP, sinh viên còn phải nhập mã sáu chữ số. Khi chưa cấu hình Firebase, hệ thống chỉ đối chiếu email với danh sách lớp, **chưa xác minh người dùng thực sự sở hữu email đó**; chỉ nên dùng chế độ này để demo.

### Bật xác minh email bằng Firebase

Tạo Firebase project, bật Authentication → Email/Password, rồi chạy desktop với cấu hình của cùng project:

```powershell
flutter run -d windows --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
```

Khi có `FIREBASE_API_KEY`, trang check-in yêu cầu email/mật khẩu. Desktop kiểm tra Firebase ID token, trạng thái email đã xác minh và email phải khớp roster. Không lưu mật khẩu hoặc ID token vào lịch sử điểm danh.

## Đồng bộ Google Drive (tùy chọn)

Trong Google Cloud Console, bật Google Drive API và tạo OAuth Client loại **Desktop app**. Chạy ứng dụng với Client ID; thêm Client Secret nếu cấu hình OAuth của bạn yêu cầu:

```powershell
flutter run -d windows --dart-define=GOOGLE_OAUTH_CLIENT_ID=...
```

Trong app bấm **Kết nối Drive**, hoàn tất đăng nhập bằng trình duyệt hệ thống rồi bấm **Đồng bộ ngay**. App dùng quyền `drive.file`; token được giữ trong Windows Credential Manager, không ghi vào JSON workspace. Dữ liệu được đưa vào folder `FAP Attendance/<semester>` của tài khoản giảng viên. Đồng bộ nhiều lần không tạo lại file không đổi: app chỉ cập nhật khi nội dung thay đổi. Nếu mất mạng, bản local vẫn được giữ để đồng bộ sau. Khi phát hiện hai bản cùng bị sửa, app lưu bản Drive thành `.drive-conflict` ở local và không tự ghi đè dữ liệu.

Không đưa Client Secret, token, file cấu hình cá nhân hoặc dữ liệu sinh viên thật vào Git.

## Web FAP mô phỏng

Từ thư mục gốc dự án:

```powershell
node demo-fap/server.mjs
```

Mở [http://localhost:4173/](http://localhost:4173/). Server cần Node.js và Dart SDK. Nó đọc `../FA26_Markbook.ods` nếu có, nếu không sẽ dùng `test/fixtures/FA26_Markbook.ods`. Muốn chọn file khác, đặt biến `FAP_MARKBOOK_PATH` trước khi chạy server. Trang chỉ chạy trên localhost; markbook chỉ được đọc để lấy lớp, MSSV và họ tên, không lấy cột điểm.

Luồng demo:

1. Dashboard hiển thị danh sách lớp và số slot đã chốt.
2. Bấm lớp, chọn slot, xem các cột **MSSV → Fullname → Ô điểm danh → Hình thẻ sinh viên**. Markbook không có ảnh thẻ nên trang dùng hình thay thế.
3. Đánh dấu **Present** cho sinh viên có mặt; không đánh dấu nghĩa là Absent.
4. Bấm **Submit điểm danh**. Trang hiện **Đã chốt danh sách**, khóa slot và có nút **Về dashboard**. Mở lại slot sẽ thấy kết quả đã chốt.

Kết quả của **web demo** nằm trong `localStorage` của chính trình duyệt đó; không đồng bộ với JSON workspace của desktop và không gửi đến FAP thật. Muốn demo một file session JSON, dùng nút **Mở JSON để demo** ở dashboard, sau đó nạp cùng file vào Extension để điền P/A. File `demo-fap/PRN232_SE1920_M01_2026-09-07_DEMO.json` dùng roster thật từ markbook nhưng trạng thái P/A là **dữ liệu giả**. Để diễn lại từ đầu, xóa khóa `fap-demo-finalized-v1` trong DevTools → Application → Local Storage của `http://localhost:4173`, rồi tải lại trang; thao tác này chỉ xóa trạng thái chốt của web demo trong trình duyệt đó.

## Chrome Extension

Build Extension:

```powershell
cd extension
npm install
npm run build
```

Mở `chrome://extensions` → bật **Developer mode** → **Load unpacked** → chọn thư mục `extension/dist`. Sau khi sửa hoặc build lại mã Extension, bấm **Reload** trên trang Extensions và tải lại tab web demo/FAP.

Để demo an toàn, mở lớp và slot tương ứng trên web mô phỏng, bấm Extension, chọn file JSON session đã chốt hoặc CSV từ máy. Extension preview số P/A và đối chiếu MSSV, lớp, ngày, slot với trang. Nếu có sinh viên thiếu, thừa hoặc trùng, thao tác sẽ bị chặn. Xác nhận để điền; mặc định **không tự Submit** để giảng viên kiểm tra. Có thể bật **Tự bấm Submit** trước khi xác nhận. Slot đã chốt trên web demo sẽ không cho điền lại.

Muốn dùng Google Picker trong Extension, cần thay Client ID trong `extension/public/manifest.json` và API key trong `extension/src/drive_picker.ts`, rồi build lại. Nạp JSON/CSV từ máy **không cần** hai cấu hình này.

Extension có adapter cho trang FAP thật, nhưng selector và hành vi Submit **chưa được xác nhận bằng HTML trang điểm danh FAP thật**. Chỉ dùng trên tài khoản/trang thử nghiệm sau khi đã kiểm tra preview và kết quả; đừng mặc định rằng demo thành công đồng nghĩa với FAP thật đã lưu điểm danh.

## Kiểm thử

```powershell
flutter analyze
flutter test
cd extension
npm test
npm run build
```

Fixture markbook có vài dòng thiếu Class/Email. Importer bỏ qua các dòng lỗi, vẫn import các sinh viên hợp lệ và hiển thị cảnh báo để giảng viên kiểm tra.
