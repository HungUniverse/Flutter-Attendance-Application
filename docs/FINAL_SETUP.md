# Chạy Firebase Final

## Phạm vi đã chốt

Android, Windows và web quản lý dành cho giảng viên. Sinh viên dùng web check-in, hộp thư và yêu cầu sửa kết quả. Người dùng đã yêu cầu triển khai tiếp web quản lý. Repo Flutter tiếp tục build tại thư mục gốc, `packages/core/` chứa model và nghiệp vụ dùng chung.

Project là `fap-attendance-71655`. Web được phục vụ tại [FAP Attendance](https://fap-attendance-71655.web.app). Trang gốc hướng dẫn mở QR, link điểm danh cụ thể nằm ở `/join/{sessionId}`.

Giảng viên mở [/admin](https://fap-attendance-71655.web.app/admin). Sinh viên mở [/student](https://fap-attendance-71655.web.app/student) để xem hộp thư và yêu cầu. Chi tiết chức năng và luồng duyệt nằm trong [hướng dẫn web quản lý](admin-web.md).

## Chuẩn bị máy phát triển

Yêu cầu Flutter 3.47.4 / Dart 3.13.3, Node.js 24, Java 21 và Android SDK. Windows cần Visual Studio Build Tools với C++. Các phiên bản thực tế được ghi trong báo cáo kiểm thử.

```powershell
flutter pub get
npm ci --prefix firebase
npm ci --prefix web
node firebase/node_modules/firebase-tools/lib/bin/firebase.js login
node firebase/node_modules/firebase-tools/lib/bin/firebase.js apps:sdkconfig ANDROID 1:455582118878:android:95f7109b9e1e54af62634f --project fap-attendance-71655 --out android/app/google-services.json
node firebase/configure-app-check.mjs
node firebase/configure-ai.mjs
```

App Check setup tạo `mobile/firebase-debug.json` riêng trên máy, đăng ký token demo cho Android và Windows, ghi site key công khai vào `web/.env.production`, xác minh enforcement của Firestore và AI Logic. File token bị Git bỏ qua. Máy khác cần chạy lại setup để nhận token riêng.

Google Sign-In cần SHA-1 và SHA-256 của keystore dùng để ký APK. Đăng ký bằng `apps:android:sha:create`, rồi tải lại `google-services.json`. Hai fingerprint của APK debug trên máy triển khai đã được đăng ký và đối chiếu bằng `apksigner`.

Chủ project cấp tài khoản giảng viên bằng email Google cụ thể.

```powershell
npm run provision:teacher --prefix firebase -- lecturer@example.com
```

Lệnh xác định Firebase UID qua Authentication rồi ghi và đọc lại vai trò để xác minh. App yêu cầu đăng nhập bằng Google. Chủ project cung cấp email demo cho người kiểm thử qua kênh riêng.

## Android và Windows

```powershell
flutter run -d <ANDROID_DEVICE_ID> --dart-define-from-file=mobile/firebase-debug.json
flutter run -d windows --dart-define-from-file=mobile/firebase-debug.json
flutter build apk --debug --dart-define-from-file=mobile/firebase-debug.json
flutter build windows --debug --dart-define-from-file=mobile/firebase-debug.json
```

Windows mở trang Hosting `/desktop-login` trong trình duyệt hệ thống. Giảng viên đăng nhập Google, bấm kết nối với app trên máy. Listener loopback chỉ tồn tại hai phút, kiểm tra Origin và state ngẫu nhiên, sau đó Firebase SDK native xác thực Google credential. Mở app lại sẽ phục hồi tài khoản đã đăng nhập và tải workspace.

Trình duyệt có thể ẩn Origin khi gửi form từ HTTPS về HTTP loopback. Callback chấp nhận Origin của Hosting, `null` hoặc header bị lược bỏ, đồng thời kiểm tra state ngẫu nhiên riêng cho lần đăng nhập, POST dạng form và giới hạn dữ liệu. Origin khác bị từ chối. App nhận đúng một callback hợp lệ và gửi hết phản hồi cho trình duyệt trước khi đóng listener.

Nếu từng gặp HTTP 403 ở `/callback`, đóng app và trang callback cũ, chạy lại bản Windows đã build mới rồi bắt đầu đăng nhập từ app để tạo phiên mới.

APK nằm tại `build/app/outputs/flutter-apk/app-debug.apk`. Windows demo nằm tại `build/windows/x64/runner/Debug/fap_attendance.exe`. Chuyển toàn bộ thư mục Debug khi đưa sang máy khác. Đây là bản demo debug. Bản Android phát hành cần signing key và Play Integrity tương ứng.

Để đối chiếu desktop local Lab 3, dùng `flutter run -d windows --dart-define=LAB3_LEGACY=true`. Dữ liệu cũ chỉ được nhập vào tài khoản Firebase khi giảng viên chọn thao tác chuyển dữ liệu.

## Web và deploy

```powershell
npm run dev --prefix web
npm test --prefix web
npm run build --prefix web
node firebase/configure-web.mjs
node firebase/node_modules/firebase-tools/lib/bin/firebase.js deploy --project fap-attendance-71655 --only firestore,hosting --non-interactive
```

Muốn dùng dev server với Emulator, đặt `VITE_USE_EMULATORS=true` trong `web/.env.local`. Khi chạy với Firebase thật, thêm site key từ `web/.env.production` vào file local để web dev lấy App Check token. Có thể dùng `npm run build` và `npm run preview` để kiểm tra cấu hình production trên localhost.

## Kiểm thử

Đặt Java 21 trong `JAVA_HOME` và PATH trước khi chạy Emulator.

```powershell
flutter analyze
flutter test
npm test --prefix firebase
npm test --prefix web
node firebase/node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --project demo-fap-final --only auth,firestore "flutter test integration_test/firestore_flow_test.dart -d windows --dart-define=FAP_PROJECT_DIR=D:/Projects/Flutter-Attendance-Application --dart-define-from-file=mobile/firebase-debug.json"
```

Đổi `FAP_PROJECT_DIR` thành đường dẫn checkout trên máy đang chạy. Thêm `--dart-define=RUN_LIVE_AI=true` vào lệnh Flutter bên trong để thu phản hồi AI thật bằng ba bộ số đếm tổng hợp. Ca cross-role dùng dữ liệu tổng hợp trong Emulator. Yêu cầu AI và kiểm tra App Check dùng project đã triển khai.

Sau khi chạy integration test, build lại Windows bằng entry point mặc định để tệp `.exe` trở về ứng dụng giảng viên.
