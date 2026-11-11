# Lab 3 Android - Kết quả kiểm tra

Ngày kiểm tra: 03/11/2026. Flutter 3.47.2 / Dart 3.13.2, Windows, Android SDK 36.

## Đồng bộ desktop/mobile - 05/11/2026

- Flutter: **54 Pass, 1 Skip**. Bao phủ QR desktop dùng backend với mã xác nhận,
  rời màn không dừng phiên, nhận cùng ID lớp/buổi, outbox sau mất mạng/mất cache,
  xung đột revision không ghi đè, giữ backup khi nhận bản server và đổi tài khoản
  trong lúc có thao tác đang chờ. Log: `artifacts/lab3-validation/tests-shared-account.txt`.
- Backend: **11 Pass**: quyền giảng viên/UID, CAS/idempotency, phiên dùng chung,
  mã xác nhận hết hạn và browser login ticket/secret dùng một lần/đăng xuất.
  Log: `artifacts/lab3-validation/backend-shared-account.txt`.
- Backend đã cài đủ Firestore Admin dependencies, import adapter thành công.
  Override bản vá glob/minimatch; npm install/audit báo **0 vulnerabilities**.
  Log: `artifacts/lab3-validation/backend-audit-shared-account.txt`.
- Windows debug build **Pass**, bản desktop dùng HTTPS và không đăng ký SDK
  FlutterFire native. Log: `artifacts/lab3-validation/windows-build-shared-account-http.txt`.
  Lần build đầu tải Firebase C++ bị reset kết nối; giữ log cũ để đối chiếu.
- Android debug build **Pass** sau khi tải NDK/SDK/CMake còn thiếu.
  Log: `artifacts/lab3-validation/android-build-shared-account.txt`.
- Flutter analyze **No issues found**.
  Log: `artifacts/lab3-validation/analyze-shared-account.txt`.
- Người dùng xác nhận chưa có backend. Chưa deploy Docker/HTTPS, chưa xác minh
  credential/Firestore transaction và Google browser login trên server thật.
  Bản build chưa có `ATTENDANCE_API_URL` vẫn chạy chế độ local; không coi test
  client giả/FileWorkspaceStore là bằng chứng hai thiết bị đã đồng bộ thật.
- Hướng dẫn cấu hình và triển khai: [DESKTOP_MOBILE_SYNC.md](DESKTOP_MOBILE_SYNC.md).

## Cập nhật cấu trúc Firebase Storage - 04/11/2026

- Đã đổi đích sao lưu thành
  `reports/{uid}/{học kỳ}/{môn}/{lớp}/{ngày}_Slot-{số buổi}/{tên tệp}`.
  Đường dẫn được chụp tại thời điểm xuất; thử lại không lấy lớp/học kỳ hiện tại.
- Flutter tests: **49 Pass, 1 Skip**, bao gồm phân biệt tài khoản/lớp/buổi,
  giữ đường dẫn sau khi đổi workspace, tải lại sau lỗi và xóa đích tạm khi đăng xuất.
  Log: `artifacts/lab3-validation/flutter-tests-storage-layout.txt`.
- Flutter analyze: **No issues found**.
  Log: `artifacts/lab3-validation/flutter-analyze-storage-layout.txt`.
- APK debug build thành công, đã cài cập nhật bằng `adb install -r` và mở app
  trên `emulator-5554`, không xóa dữ liệu ứng dụng.
  Log build: `artifacts/lab3-validation/android-build-storage-layout.txt`.
- Rules mới đã có trong source; **chưa Publish lên Firebase hoặc kiểm thử quyền
  trên project thật**. Các ca tải lên trong Flutter tests dùng dịch vụ giả lập.
  Xem [STORAGE_LAYOUT.md](STORAGE_LAYOUT.md) để áp dụng và kiểm tra trên Console.
- Người dùng đã cung cấp ảnh đăng nhập Google thành công và xuất báo cáo buổi
  đã chốt trên máy ảo. Đây là quan sát bổ sung sau mốc khởi động bên dưới;
  không thay cho bằng chứng kiểm thử sáu dịch vụ Firebase.

## Cập nhật chạy Android - 04/11/2026

- Đã mở AVD `Medium_Phone_API_37.0`, thiết bị `emulator-5554`, Android 17/API 37,
  x86_64; image Google Play và Google Play services có sẵn.
- Android boot hoàn tất, cài APK debug thành công và mở
  `vn.edu.fpt.fap_attendance/.MainActivity`.
- Đã quan sát màn **Đăng nhập với Google** của app. Ảnh chạy thật trên máy ảo:
  `artifacts/lab3-validation/android-runtime-2026-11-04/start.png`.
- Thiết bị dùng UTC+7. Chưa thao tác đăng nhập tài khoản, xác nhận quyền Google
  hoặc kiểm chứng các dịch vụ trên Firebase Console.

Đây là bằng chứng cài và khởi động app, không phải kết quả hoàn tất ba flow hoặc
kiểm thử ARTEMIS.

## Đã chạy

| Kiểm tra | Kết quả | Bằng chứng local |
| --- | --- | --- |
| flutter analyze | Pass, No issues found sau cập nhật lưu trữ | artifacts/lab3-validation/flutter-analyze-without-drive.txt |
| flutter test | 45 Pass, 1 Skip sau cập nhật lưu trữ | artifacts/lab3-validation/flutter-tests-without-drive.txt |
| Backend relay unit/API | 6 Pass | artifacts/lab3-validation/relay-tests.txt |
| Backend dependency audit, omit optional | 0 lỗ hổng ở dependency dùng khi chạy | artifacts/lab3-validation/backend-audit.txt |
| Build Android debug | Thành công; xem log build mới nhất | artifacts/lab3-validation/android-build.txt |
| Build Android với cấu hình Firebase được cung cấp | Pass; chưa thử đăng nhập Google thật | artifacts/lab3-validation/android-build-firebase.txt |
| Build Android sau cập nhật giao diện/lưu trữ | Pass, APK debug với cấu hình Firebase mới | artifacts/lab3-validation/android-build-without-drive.txt |

Extension: `npm test` đã chạy 10 ca đạt và `npm run build` thành công sau khi bỏ
chức năng chọn tệp đám mây cùng quyền OAuth/identity không còn dùng. Raw log của
lượt extension này chưa lưu thành tệp riêng.

Các đường dẫn `artifacts/` và `build/` trỏ tới log và bản dựng trên máy kiểm thử. Một ca bỏ qua là
`quick_tunnel_live_test.dart`, chỉ chạy khi chủ động bật
`RUN_PUBLIC_TUNNEL_TEST=1`; không gộp ca này vào Pass.

Kiểm thử mới bao phủ ghi thủ công, gửi link lặp/ưu tiên P/A của giảng viên,
đóng nhận rồi tải lượt cuối trước chốt, không chốt giả khi offline, sửa có lý do
và audit, lỗi ghi tệp, lỗi tracking không phá nghiệp vụ, lỗi upload giữ file,
từ chối thông báo, Remote Config fallback, tách dữ liệu tài khoản, khôi phục
lượt đã gửi qua ngày, import lỗi và khôi phục workspace chứa metadata phiên cũ.

Widget tests kiểm tra các màn nghiệp vụ ở chiều rộng 360/412, lịch tuần không
tràn, ghi P/A không đổi màn, validation lý do, hủy và auth guard sau đăng xuất.
Ảnh tại `build/lab3-previews/` là render widget bằng tài khoản/dịch vụ giả lập và
font xem trước trên máy phát triển, **không phải ảnh chạy Firebase thật**. Đã xem
ảnh màn điểm danh và các lựa chọn P/A. Đây không phải đánh giá accessibility
toàn diện hoặc kết quả ARTEMIS.

APK debug ở `build/app/outputs/flutter-apk/app-debug.apk`. Build còn cảnh báo từ
toolchain về các plugin Kotlin cần theo dõi khi nâng Flutter; cảnh báo không làm
build hiện tại thất bại. Chưa cấu hình khóa ký release. Không coi debug APK là bản
đã phát hành.

## Chưa thể xác nhận

Đã thêm `android/app/google-services.json` từ người dùng cho project
`fap-attendance-71655`, đúng package `vn.edu.fpt.fap_attendance`, và build APK
thành công sau khi thêm file. File mới nhất đã có Android/Web OAuth client và
fingerprint khớp debug keystore. Cấu hình biên dịch đã có đủ thông tin cho Google
Sign-In; vẫn cần thử đăng nhập trên thiết bị. Tên bucket trong file không chứng
minh Storage đã được tạo.
Tại mốc 03/11 chưa có thiết bị/máy ảo Android kết nối. Ngày 04/11 đã chạy được
màn đăng nhập trên máy ảo như ghi nhận ở trên; các bước dưới đây vẫn chưa xác nhận:

- Chưa đăng nhập Google thật hoặc xác nhận SHA/provider bằng app trên điện thoại.
- Chưa tạo default bucket hoặc publish/thử Storage rules trên project của bạn.
- Chưa gửi FCM thật ở ba trạng thái, chụp DebugView hoặc Crashlytics Console.
- Chưa publish và đổi Remote Config trên Console thật.
- Relay đã có source và unit/API tests với verifier giả, **chưa được đưa lên
  host HTTPS** hoặc thử Firebase Admin identity thật giữa hai thiết bị.
- Chưa chạy ARTEMIS ba lượt/ca, kiểm thử khám phá, tạo PR review hay bằng chứng
  sửa nhận xét AI. Chưa tạo báo cáo/slide/video Lab 3 từ kết quả chạy thật.

Không ghi những mục trên thành Pass. Làm tiếp theo
[FIREBASE_ANDROID_SETUP.md](FIREBASE_ANDROID_SETUP.md),
[backend README](../backend/README.md) và
[LAB3_ACCEPTANCE.md](LAB3_ACCEPTANCE.md).

Các adapter Firebase đã viết và biên dịch được không thay cho việc xác nhận cả
sáu dịch vụ chạy thật. Các lỗi dịch vụ trong ViewModel tests là lỗi giả lập có
chủ đích để kiểm tra phản hồi, cần thêm bằng chứng tích hợp theo yêu cầu Lab 3.
