# Báo cáo kiểm thử Firebase Final

## Môi trường ngày 12/11/2026

Windows 10, Flutter 3.47.4, Dart 3.13.3, Node.js 24.19.0, Java 21.0.10 và Android SDK 36. Firebase Emulator dùng project `demo-fap-final`. Project triển khai là `fap-attendance-71655`.

## Kết quả đã chạy

| Kiểm tra | Kết quả | Phạm vi |
| --- | --- | --- |
| `flutter analyze` | Không có lỗi hoặc lint | Flutter app, core và test |
| `flutter test` | 83 pass, 1 skip | Nghiệp vụ, lưu trữ, UI, xuất PDF, AI fallback, khôi phục phiên, quyền và callback đăng nhập Windows |
| Firebase Rules Emulator | 32/32 pass | Người chưa đăng nhập, giảng viên sở hữu, giảng viên khác, sinh viên hợp lệ và ngoài lớp |
| Web unit test | 3/3 pass | Trạng thái phiên, callback Windows và thông báo lỗi |
| Native integration test | 3/3 lượt luồng pass | SDK JavaScript → Flutter Windows, dữ liệu Auth/Firestore Emulator |
| Backend Lab 3 | 11/11 pass | Giữ khả năng đối chiếu relay cũ |
| Chrome Extension Lab 3 | 10/10 pass | JSON, CSV và adapter |
| Web production build | Thành công | Vite static bundle cho Firebase Hosting |
| Android debug APK | Thành công | Bản có Firebase config và App Check demo |
| Windows debug build | Thành công | Entry point giảng viên mặc định, native Firebase plugins |
| PDF | Kiểm tra render trang đầu và cuối | Roster 120 sinh viên, bốn trang, giữ sinh viên cuối và chữ tiếng Việt |
| App Check | Token trao đổi thành công | Project triển khai, enforcement Firestore và AI Logic đã đọc lại để xác minh |
| AI Logic thật | HTTP 429 | Project hết credit trả trước, fallback trả quyền tiếp tục chốt |

Test bị skip là kiểm tra Quick Tunnel thật theo lựa chọn môi trường của bộ Lab 3. Luồng Final dùng Hosting và Firestore.

Extension có sẵn chênh lệch giữa manifest Vitest 5 và lockfile Vitest 3. `npm ci --prefix extension` bị chặn vì lockfile chưa đồng bộ. Đã kiểm tra bộ test bằng phiên bản trong lockfile với lệnh cài tạm dưới đây. Manifest và lockfile Extension được giữ theo checkout ban đầu.

```powershell
npm install --prefix extension --no-save --package-lock=false vitest@3.2.7 vite@7.3.6
npm test --prefix extension
```

## Ba lượt liên vai trò

Native integration test dùng SDK Windows thật và Firebase JavaScript SDK, chạy qua Emulator. Mỗi lượt kiểm tra import một lớp, mở buổi, ghi thủ công A, nhận check-in của chính sinh viên đó và sinh viên khác, giữ lựa chọn thủ công, gửi trùng, từ chối ngoài lớp, dừng nhận, chốt, từ chối lượt đến sau chốt, sửa có lý do, xuất PDF và metadata. Ca này cũng mở lại dữ liệu bằng `AttendanceController.initialize()` của Windows và kiểm tra target hộp thư.

| Lượt | Thời gian client JavaScript → số đếm native | Kết quả |
| --- | --- | --- |
| 1 | 672 ms | Pass |
| 2 | 706 ms | Pass |
| 3 | 549 ms | Pass |

Số đo bao gồm khởi động client JavaScript và đăng nhập emulator. Dữ liệu gốc nằm trong [cross-role-emulator.json](../evidence/final/cross-role-emulator.json). Các tài khoản `example.com` trong test là dữ liệu tổng hợp.

## Rà soát mã bằng Codex

Đây là lượt tự rà soát mã của Codex trong quá trình triển khai.

| Nhận xét | Quyết định và thay đổi | Kiểm chứng |
| --- | --- | --- |
| Catch lỗi đồng bộ tổng quát có thể mở bản cache khi tài khoản bị từ chối quyền | Đưa `WorkspaceAccessDenied` qua toàn bộ luồng restore, cung cấp nút đổi tài khoản trên Android | `test/final/recovery_test.dart` |
| App mở lại thiếu handle local có thể chốt trước khi nhập hết check-in | Dùng ID phiên xác định theo lớp/buổi, khôi phục đúng phiên trước lúc dừng và lấy kết quả | Recovery test và ba lượt native integration |
| Rules đọc metadata chưa tồn tại làm hỏng transaction xuất báo cáo lần đầu | Cho giảng viên đọc trạng thái document chưa tồn tại, kiểm tra chủ sở hữu với document đã có | Native PDF export và metadata integration |
| Cấu hình CMake Lab 3 loại Firebase plugins khỏi Windows | Bật native Auth, Firestore và App Check | Windows build và native integration |
| Tài khoản Windows đã đăng nhập nhưng chưa gắn sync có thể thiếu nút kết nối sau khi mở lại | Phục hồi tài khoản trong initialize, giữ đường thử lại khi kết nối lỗi | Native kiểm tra entry point Windows qua ba lượt |
| Editor AI cần sống cùng dialog và lưu nội dung giảng viên sửa | Dùng controller thuộc state của dialog, cập nhật review và lưu xác nhận local | `test/final/ai_review_ui_test.dart` |
| ID lớp Firestore khác ID nghiệp vụ dùng trong route Android | Chuẩn hóa target hộp thư qua workspace hiện tại | Native inbox target assertion |
| Callback Windows yêu cầu Origin chính xác, chặn form HTTPS → loopback khi trình duyệt gửi `Origin: null` | Chấp nhận Origin bị ẩn khi state riêng của phiên hợp lệ, giữ kiểm tra POST/form, nguồn tường minh và xử lý callback một lần | Bảy test HTTP loopback trong `test/final/desktop_login_callback_test.dart` |

Bản sửa callback đã tái hiện HTTP 403 bằng request có `Origin: null` và request thiếu Origin trước khi sửa. Bảy test mới dùng HTTP server thật trên loopback, giả lập bước trao đổi Google credential để kiểm tra callback. Các ca gồm Origin Hosting hợp lệ, Origin bị ẩn, sai state, token rỗng, nguồn khác, method/path/content type sai, dữ liệu quá lớn và hai callback đồng thời. Toàn bộ 83 test Flutter và `flutter analyze` đã chạy lại sau bản sửa.

## Bằng chứng

- [PDF đã sửa có lý do](../evidence/final/attendance-corrected.pdf).
- [Trang PDF roster tiếng Việt](../evidence/final/pdf-vietnamese-roster.png).
- [Lỗi AI thực tế từ SDK](../evidence/final/ai-quota-error.json).
- Kết quả đầy đủ được sinh trong `build/final-previews/`, gồm roster 120 sinh viên và các lần gọi AI thật.

## Các phần cần thu tiếp

- Ba lượt với Google thật trên Android và trình duyệt đã deploy, gồm đăng nhập Windows qua trình duyệt hệ thống.
- Ảnh web ở các trạng thái thành công, sai vai trò, rỗng và lỗi. Computer Use dừng vì không xác định được URL trình duyệt Windows để thực thi chính sách.
- Ba cặp input/output AI thành công sau khi chủ project bổ sung credit. Ba yêu cầu SDK trong phiên kiểm tra hiện tại đều trả thông báo hết credit, được ghi trong thư mục bằng chứng local.
- ARTEMIS, mã số nộp bài, báo cáo PDF, slide PDF và video demo theo tiêu chí bàn giao.

Web quản lý giảng viên được hoãn theo phạm vi người dùng xác nhận. Windows dùng App Check debug provider cho bản demo. Cách setup và tái chạy kiểm thử nằm trong [FINAL_SETUP.md](FINAL_SETUP.md).
