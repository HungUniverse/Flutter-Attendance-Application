# Chạy demo FAP Attendance trên máy khác

Áp dụng cho bản Firebase hiện tại, mã nguồn `c4ea548`, APK `1.0.2+3`. Dùng máy Windows x64, điện thoại Android và Internet. Các lệnh dưới đây chạy trong **PowerShell**.

## 1. Mang đủ bộ demo sang máy mới

Chép mã nguồn dự án vào `C:\Demo\Flutter-Attendance-Application`, kèm các thành phần sau đúng vị trí:

| Thành phần | Đường dẫn trong dự án |
| --- | --- |
| APK đã build | `build\app\outputs\flutter-apk\app-debug.apk` |
| Windows đã build | **Toàn bộ** `build\windows\x64\runner\Debug\`, gồm EXE, DLL và thư mục `data` |
| Markbook giảng viên | `FA26_Markbook.ods` ở thư mục gốc |
| Web FAP giả lập | `demo-fap\` cùng mã nguồn/package của dự án |
| Extension đã build | `extension\dist\` |

APK, bản Windows và Markbook thật không tự có khi chỉ clone GitHub; lấy từ máy đã chuẩn bị bản build. Để chạy FAP giả lập với Markbook, cài **Node.js 24** và **Flutter SDK** (bản dự án dùng Flutter 3.47.4 / Dart 3.13.3), thêm `node` và `flutter` vào PATH. Cài **Google Chrome** để dùng Extension.

Bản Windows đang dùng là **Debug**; máy demo cần runtime C++ Debug tương ứng của Visual Studio, thường chuẩn bị bằng workload **Desktop development with C++** của Visual Studio 2022. Kiểm tra mở EXE ở bước 2 trước ngày trình bày.

## 2. Mở Windows và cài Android

```powershell
cd C:\Demo\Flutter-Attendance-Application
Start-Process .\build\windows\x64\runner\Debug\fap_attendance.exe
```

1. Chép `app-debug.apk` sang điện thoại, mở và cho phép cài từ nguồn vừa dùng. Nếu đã có bản cùng chữ ký, cài cập nhật.
2. Windows: bấm đăng nhập Google trong app → đăng nhập ở trình duyệt → xác nhận kết nối với ứng dụng → quay lại app. Android: đăng nhập Google ngay trong app.
3. Dùng cùng tài khoản giảng viên để thấy cùng dữ liệu giữa hai thiết bị. Bản build đã mang cấu hình Firebase/App Check; máy chỉ chạy demo không cần đăng nhập Firebase CLI hay tạo project mới.

## 3. Chuẩn bị tài khoản và lớp

| Vai trò | Trang / tài khoản |
| --- | --- |
| Admin quản lý giảng viên | <https://fap-attendance-71655.web.app/admin> — `razraz36623@gmail.com` |
| Giảng viên quản lý lớp | <https://fap-attendance-71655.web.app/teacher> — tài khoản đã được cấp quyền, ví dụ `khuugiabao36623@gmail.com` |
| Sinh viên | <https://fap-attendance-71655.web.app/student> — Google email khớp roster |

1. Admin đăng nhập và kiểm tra tài khoản giảng viên đang hoạt động; nếu dùng tài khoản mới thì thêm giảng viên tại `/admin`.
2. Giảng viên đăng nhập `/teacher` → **Nạp Markbook** → chọn `FA26_Markbook.ods` → xem trước, kiểm tra học kỳ/lịch rồi xác nhận. Có thể nhập trên app thay cho web; chỉ cần nhập một lần cho cùng tài khoản.
3. Chuẩn bị ít nhất một buổi học **đúng ngày trình bày**. Nếu lịch Markbook không có buổi hôm đó, tạo lớp demo riêng trên web: ngày bắt đầu là ngày demo, 1 tuần, 2 buổi/tuần; mã lịch bắt đầu bằng `1` cho T2/T5, `2` cho T3/T6, `3` cho T4/T7. Chữ số thứ hai là slot `1`–`4`. Cặp ngày hiện không có Chủ nhật.
4. Trong roster lớp demo, điền email Google thật của người đóng vai sinh viên. Các cột là `Class | RollNumber | Email | MemberCode | FullName`.
5. Làm mới Android/Windows để nhận lớp. Giữ giờ/ngày tự động trên thiết bị; buổi đã qua ngày sẽ bị khóa. Khi hai thiết bị cùng mở, thao tác trên một thiết bị rồi làm mới thiết bị kia trước khi sửa tiếp.

## 4. Trình diễn điểm danh và đồng bộ

1. Trên Android, mở lớp → buổi hôm nay → bắt đầu điểm danh → tạo link/QR.
2. Sinh viên quét QR bằng camera và mở trình duyệt → đăng nhập Google bằng email trong roster → gửi check-in trong thời hạn **2 phút**. Điện thoại có thể dùng 4G, không cần cùng Wi-Fi laptop.
3. Quan sát P cập nhật trên Android. Chọn thêm P/A thủ công: các lựa chọn là bản nháp, chưa gửi kết quả cuối lên cloud.
4. Bấm **Chốt danh sách**: app lấy đủ check-in đã được chấp nhận, giữ lựa chọn thủ công và chuyển ô chưa ghi thành A. Kiểm tra trạng thái đồng bộ thành công.
5. Trên Windows bấm đồng bộ/làm mới để xem kết quả đã chốt. Có thể sửa một kết quả kèm lý do để trình diễn lịch sử chỉnh sửa.
6. Xuất **PDF** để xem báo cáo; xuất **JSON của buổi đã chốt** và chuyển file về laptop để dùng ở bước 6. Có thể xuất CSV nếu muốn dùng Extension theo định dạng CSV.
7. Nếu cần trình diễn thêm: sinh viên mở lại link → gửi yêu cầu sửa kết quả tại trang sinh viên; giảng viên duyệt ở `/teacher` rồi sinh viên xem phản hồi.

## 5. Bật web FAP giả lập

Mở một cửa sổ PowerShell riêng và giữ cửa sổ này trong lúc demo:

```powershell
cd C:\Demo\Flutter-Attendance-Application
flutter pub get
$env:DART_EXECUTABLE = (Join-Path (Split-Path (Get-Command flutter).Source) 'cache\dart-sdk\bin\dart.exe')
$env:FAP_MARKBOOK_PATH = (Join-Path (Get-Location).Path 'FA26_Markbook.ods')
node demo-fap/server.mjs
```

Mở **<http://localhost:4173/>** trên Chrome của laptop. Dashboard tải các lớp từ Markbook; có thể bấm **Nạp danh sách lớp** để chọn ODS/XLSX khác. `localhost` chỉ trỏ về máy đang chạy server. Dừng server bằng `Ctrl+C` sau buổi demo.

## 6. Trình diễn Extension điền điểm danh

1. Mở `chrome://extensions` → bật **Developer mode** → **Load unpacked** → chọn `C:\Demo\Flutter-Attendance-Application\extension\dist`.
2. Trên FAP giả lập, bấm **Mở JSON điểm danh** và chọn JSON đã xuất ở bước 4; trang mở buổi tương ứng. Cách này giúp mã lớp, ngày, slot và MSSV khớp file xuất.
3. Mở Extension trên tab FAP giả lập → nạp **cùng file JSON** → kiểm tra preview P/A → xác nhận điền.
4. Kiểm tra các ô đã điền rồi bấm **Submit điểm danh** trên trang → thấy trạng thái đã chốt → về dashboard và mở lại để xem kết quả.

Nếu thiếu `extension/dist`, build trước khi nạp Extension:

```powershell
npm ci --prefix extension
npm run build --prefix extension
```

Muốn thử nhanh phần FAP/Extension mà chưa điểm danh thật, dùng cùng file `demo-fap\PRN232_SE1920_M01_2026-09-07_DEMO.json` cho cả trang và Extension. Kết quả FAP giả lập nằm trong `localStorage` của Chrome, tách khỏi Firebase; bấm **Xóa dữ liệu demo** trên dashboard để diễn lại. Luồng này chỉ mô phỏng thao tác trên FAP, chưa xác nhận Submit trên FAP thật.

## 7. Xử lý nhanh khi trình bày

| Hiện tượng | Cách xử lý |
| --- | --- |
| Windows báo thiếu `flutter_windows.dll` hoặc `data` | Chép lại toàn bộ thư mục `Debug`, không chỉ EXE. |
| Thiếu `VCRUNTIME140D.dll` / `ucrtbased.dll` | Chuẩn bị runtime Debug qua Visual Studio C++; VC++ Redistributable thông thường không cung cấp các DLL Debug này. |
| Google Windows quay về `/callback` lỗi | Đóng trang callback cũ, mở lại bản app mới và bắt đầu đăng nhập từ app. |
| Không có quyền / `permission-denied` | Kiểm tra đúng Google email, hồ sơ giảng viên đang hoạt động, email sinh viên khớp roster và buổi đã mở/đồng bộ. |
| QR hết hạn | Giảng viên tạo lại link/QR rồi sinh viên mở link mới. |
| Chưa thấy lớp hoặc dữ liệu cũ sau reset | Làm mới; nếu xung đột sau reset chủ động chọn **Nhận bản máy chủ**. Xem và bỏ bản nháp cũ trước khi nhập lại cùng Markbook. |
| `localhost:4173` không mở / báo không đọc được Markbook | Kiểm tra server còn chạy, `node`/Flutter đã vào PATH, `flutter pub get` đã xong và đường dẫn Markbook đúng. Nếu cổng đã được dùng bởi server demo, dùng lại cửa sổ đang chạy. |
| Extension chặn điền | Chọn cùng JSON cho trang và Extension; kiểm tra lớp/buổi chưa Submit. |
| Gợi ý AI / sao lưu báo lỗi dịch vụ | Tiếp tục điểm danh, chốt, xuất và chia sẻ file local; hai tính năng phụ này cần cấu hình/quota cloud riêng. |

**Thứ tự demo ngắn:** đăng nhập → xem lớp → QR/check-in → P/A thủ công → chốt → đồng bộ Windows → xuất PDF/JSON → Extension điền FAP giả lập → Submit. Chuẩn bị và mở thử toàn bộ trên máy đích trước ngày trình bày.
