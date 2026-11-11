# Thiết lập Firebase và chạy app Android

Xem [hướng dẫn thu minh chứng Lab 3](LAB3_EVIDENCE_GUIDE.md) để chạy bản demo trên laptop và kiểm tra từng dịch vụ trên Firebase Console.

## 1. Tạo project và ứng dụng Android

1. Mở https://console.firebase.google.com/ và tạo project. Bật Google Analytics.
2. Thêm ứng dụng Android, package name **vn.edu.fpt.fap_attendance**.
3. Thêm fingerprint của debug keystore trên máy này:

```text
SHA-1
96:CE:E1:A2:77:B9:FC:C0:D5:86:63:89:AB:9F:F0:B0:16:B5:8E:51

SHA-256
F7:2A:A9:BF:89:B8:0F:59:73:3B:00:6A:A7:E8:78:09:55:A0:32:C6:5D:57:35:C7:01:9C:3A:1D:2E:CC:57:3B
```

Đây là fingerprint debug của máy phát triển, không phải khóa release. Nếu đổi
máy hoặc keystore, lấy lại fingerprint tương ứng.

4. Vào Authentication > Sign-in method, bật Google, chọn email hỗ trợ.
5. Tải lại **google-services.json sau khi bật Google và thêm SHA**. Lưu tại:
   `android/app/google-services.json` ở source Flutter. Không lấy file của Web/iOS
   hoặc ứng dụng có package name khác.

Source đã khai báo các plugin Flutter/Firebase và Gradle. Khi có JSON đúng,
Gradle tự áp dụng Google Services/Crashlytics. Không có JSON, APK chỉ mở trang
hướng dẫn cấu hình; không tạo tài khoản hoặc báo đồng bộ giả.

App Android dùng cấu hình native từ JSON; không bắt buộc thêm firebase_options.dart
trong cách thiết lập này. Có thể dùng FlutterFire CLI nếu cần cấu hình đa nền tảng,
nhưng tránh khởi tạo default Firebase app hai lần.

## 2. Cài và chạy trên thiết bị

Kết nối điện thoại Android, bật Developer options/USB debugging và cho phép máy
truy cập. Hoặc dùng máy ảo có Google Play. Điện thoại phải có Google Play services
để kiểm tra Google Sign-In/FCM theo luồng này.

```powershell
cd D:\Fall2026\PRM393\Project_PRM393
flutter doctor -v
flutter devices
flutter pub get
flutter run -d <ID_THIET_BI_ANDROID>
```

Nếu doctor báo license, chạy `flutter doctor --android-licenses`, đọc và tự chấp
nhận nếu đồng ý. Bổ sung JSON hoặc thay thông tin build cần build/cài lại app.

```powershell
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`. Đây là bản debug, chưa phải bản
phát hành ký bằng khóa riêng.

## 3. Storage

Cloud Storage hiện cần Blaze có liên kết thanh toán. Chỉ nâng cấp sau khi chủ tài
khoản đồng ý; có thể phát sinh chi phí. Cảnh báo ngân sách không tự chặn chi tiêu.
Nếu chưa muốn bật, vẫn làm được phần local, Auth và UI; phần Storage chưa hoàn tất.

1. Tạo default bucket trong Storage, chọn vị trí phù hợp.
2. Dán toàn bộ nội dung mới nhất của `firebase/storage.rules` vào tab Rules rồi
   Publish, kể cả khi đã từng cấu hình rules cho đường dẫn cũ.
3. Nếu tạo bucket sau khi tải JSON, tải lại cấu hình để có đúng storage bucket.
4. Trong app, chốt buổi học > Xuất file > chọn sao lưu Firebase Storage.
5. Kiểm tra tiến độ, URL và file tại
   `reports/{uid}/{học kỳ}/{môn}/{lớp}/{ngày}_Slot-{số buổi}/{tên tệp}`.
   App hiển thị thư mục đích sau khi xuất. Xem [STORAGE_LAYOUT.md](STORAGE_LAYOUT.md)
   để đối chiếu ví dụ và cách xử lý báo cáo cũ.
6. Thử tài khoản khác/không đăng nhập: phải bị từ chối. Khi mất mạng, file trên
   thiết bị phải còn và có thể tải lại sau.

## 4. Remote Config

Tạo và Publish hai tham số:

| Tên | Kiểu | Giá trị ví dụ |
| --- | --- | --- |
| enable_link_attendance | Boolean | true |
| export_help_message | String | Lưu trên máy trước khi sao lưu. |

Trong app: Tài khoản & cài đặt > Cập nhật cấu hình. Bản debug có khoảng fetch tối
thiểu một phút; nếu vừa fetch, chờ đủ khoảng này rồi thử lại. Thử `false` và đổi
nội dung hướng dẫn xuất: UI phải đổi mà không build lại, dữ liệu vẫn giữ nguyên.
Thử offline để kiểm tra cache/defaults.

## 5. FCM, Analytics và Crashlytics

Để hiện công cụ kiểm thử FCM/crash:

```powershell
flutter run -d <ID_THIET_BI_ANDROID> --dart-define=LAB3_DEMO_TOOLS=true
```

- FCM: vào Thông báo, cấp quyền. Trong khu vực kiểm thử có token để gửi test từ
  Firebase Console. Token nhạy cảm, không đưa công khai. Test app đang mở/chạy
  nền/đã đóng; force-stop là trường hợp khác. Data nên có `uid`, `classId`,
  `meetingId` đúng từ workspace. Chạm thông báo phải về đúng màn hoặc inbox nếu
  đích không có trên máy. Không gửi dữ liệu sinh viên trong push.
- Analytics: chạy `adb shell setprop debug.firebase.analytics.app
  vn.edu.fpt.fap_attendance`, dùng các flow trong app, chụp từng event/params ở
  DebugView theo analytics-plan.md. `adb` nằm trong Android SDK platform-tools nếu
  chưa có trong PATH. Tắt bằng `adb shell setprop debug.firebase.analytics.app .none.`
- Crashlytics: thử tạo link cho một buổi demo đang mở khi máy ảo mất mạng để ghi
  non-fatal. Bật lại mạng, dùng **Crash thử nghiệm** rồi mở lại app để gửi báo cáo.
  Kiểm tra UID và custom key `operation` trên Console.

## 6. Chạy điểm danh qua link

Đọc `backend/README.md`. Cần máy chủ HTTPS, allowlist giảng viên và cấu hình Firebase
Web trong cùng project. Chưa có máy chủ, app báo lỗi tạo link và vẫn cho Thủ công.

Sau khi có origin HTTPS:

```powershell
flutter run -d <ID_THIET_BI_ANDROID> --dart-define=ATTENDANCE_API_URL=https://YOUR_RELAY_HOST
```

Đăng nhập giảng viên, import markbook có buổi hôm nay, bắt đầu buổi học rồi tạo
link. Sinh viên mở link trên thiết bị khác, đăng nhập bằng email đã xác minh
khớp roster, xác nhận gửi. Không thay bằng toast hoặc URL giả trong demo nộp bài.

## Tài liệu chính thức

- https://firebase.google.com/docs/flutter/setup
- https://firebase.google.com/docs/auth/flutter/federated-auth
- https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
- https://firebase.google.com/docs/crashlytics/flutter/get-started
- https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024

Không gửi mật khẩu, service-account private key hoặc token qua hội thoại. Client
JSON định danh ứng dụng không thay cho rules và không chứa quyền quản trị máy chủ.
