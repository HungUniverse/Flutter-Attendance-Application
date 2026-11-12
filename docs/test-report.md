# Báo cáo kiểm thử Firebase Final

## Môi trường ngày 12/11/2026

Windows 10, Flutter 3.47.4, Dart 3.13.3, Node.js 24.19.0, Java 21.0.10 và Android SDK 36. Firebase Emulator dùng project `demo-fap-final`. Project triển khai là `fap-attendance-71655`.

## Kết quả đã chạy

| Kiểm tra | Kết quả | Phạm vi |
| --- | --- | --- |
| `flutter analyze` | Không có lỗi hoặc lint | Flutter app, core và test |
| `flutter test` | 83 pass, 1 skip | Nghiệp vụ, lưu trữ, UI, xuất PDF, AI fallback, khôi phục phiên, quyền và callback đăng nhập Windows |
| Firebase Rules Emulator | 39/39 pass ở lượt chạy web admin trước các điều chỉnh cuối | Bao gồm yêu cầu sửa, quyết định nguyên tử, riêng tư hộp thư và luồng repository web |
| Web unit test | 9/9 pass | Trạng thái phiên, callback Windows, roster, lịch, lịch sử và nội dung hiển thị |
| Web DOM interaction test | 9/9 pass | Quyền giảng viên, dashboard, tạo lớp, xử lý yêu cầu, hộp thư sinh viên và xóa dữ liệu màn hình khi đổi tài khoản |
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

## Lượt triển khai web quản lý

Người dùng đã yêu cầu tiếp tục web quản lý giảng viên. Repository web đã chạy qua Firestore Emulator với Rules: tạo lớp và lịch, sửa roster, từ chối revision cũ, sinh viên gửi yêu cầu, giảng viên duyệt, giữ kết quả sinh viên khác và audit, từ chối xử lý lại, gửi thông báo và lưu trữ lớp. Lượt này dùng tài khoản tổng hợp `example.com`, không phải đăng nhập Google trên production.

Sau lượt Rules 39/39, mã được siết ID yêu cầu theo lớp/buổi/UID, bảo vệ roster khi có buổi chốt và gửi phản hồi theo UID. Có thêm một ca Rules cho hai link cùng buổi. Người dùng yêu cầu dừng chạy thêm test và đẩy bản hoàn tất, nên bộ Rules chưa chạy lại trên các điều chỉnh cuối. Web đã có thêm 9 DOM test qua; DOM test dùng dịch vụ giả và không thay cho việc kiểm chứng layout hay Google Sign-In thật.

Công cụ trình duyệt báo `The browser access host is unavailable` trong lượt web admin này; chưa kiểm tra trực quan dashboard, responsive và đăng nhập Google trên trình duyệt thật. Production bundle đã build thành công. Không có thay đổi mã Flutter trong lượt web admin.

Windows dùng App Check debug provider cho bản demo. Cách setup và tái chạy kiểm thử nằm trong [FINAL_SETUP.md](FINAL_SETUP.md), luồng web trong [admin-web.md](admin-web.md).

## Đính chính vai trò admin ngày 13/11/2026

Người dùng xác nhận admin là chủ hệ thống quản lý giảng viên. `/admin` được thay bằng CRUD hồ sơ giảng viên, khóa/mở lại và xóa quyền, có audit. Cổng quản lý lớp chuyển sang `/teacher`. Danh mục `teacherDirectory` thay quyền teacher cũ trong `users`; `users.role == admin` chỉ được cấp bằng công cụ chủ project. Công cụ bootstrap đã ghi và đọc lại tài khoản admin được chỉ định, chuyển hồ sơ giảng viên cũ một lần.

Không chạy thêm test theo yêu cầu trước đó; số liệu Rules/DOM ở trên thuộc lượt trước khi đổi mô hình phân quyền. Kiểm tra biên dịch Rules diễn ra khi deploy. Chưa kiểm chứng CRUD trên trình duyệt thật hoặc đăng nhập thiết bị thật trong lượt này.

## Bản nháp Android và mốc thời gian link

Bản 1.0.1+2 bổ sung journal P/A thủ công trên thiết bị, tách snapshot đã đồng bộ và lớp phủ bản nháp, gửi các lựa chọn khi chốt. Link dùng giai đoạn chuẩn bị dừng nhận để lấy server timestamp rồi mở trong transaction tiếp theo; Rules giữ giới hạn hai phút và chặn check-in trước khi mở. Xem [phạm vi và giới hạn](android-attendance-drafts.md).

Không chạy lại bộ test cũ; các kỳ vọng lưu ngay sau từng `mark()` của bộ TeacherViewModel trước đây không mô tả luồng nháp mới. Không có thiết bị ADB để xác nhận lỗi tạo link thực tế; mã lỗi Firebase nay được hiển thị để tiếp tục chẩn đoán khi cần. Phân tích mã tĩnh trên các tệp sửa không có lỗi.

## Cập nhật check-in Android 1.0.2+3

Đã pull `8dc8b70`, trong đó bộ kiểm thử upstream đã điều chỉnh kỳ vọng về bản nháp. Lượt tối ưu này không chạy test theo yêu cầu người dùng. `flutter analyze` trên `firestore_attendance_links.dart` và `teacher_view_model.dart` không có lỗi; build APK debug với cấu hình Firebase demo thành công.

Android hiển thị trực tiếp snapshot check-in từ máy chủ, không chờ hàng đợi đồng bộ hoặc ghi workspace. Kết quả trực tiếp được phủ lại khi tải workspace; P/A thủ công vẫn ưu tiên và chốt vẫn lấy kết quả sau khi dừng phiên. Xem [chi tiết và giới hạn](android-background-sync.md). Chưa đo độ trễ trên thiết bị thật; không dùng kết quả build/phân tích mã để khẳng định thời gian cập nhật cụ thể. Không thay đổi Rules/Hosting hay luồng poll Windows trong lượt này.

## Chuẩn hóa toàn dự án và mở rộng kiểm thử (13/11/2026)

- **Chuẩn hóa mã MSSV và lịch học (`packages/core`, `lib/domain`, `lib/data`)**:
  - `AttendanceService.closeMeeting` chuẩn hóa khóa bản ghi điểm danh về đúng `student.rollNumber` và dọn sạch các biến thể chữ hoa/thường hoặc khoảng trắng dư thừa.
  - `RosterMergeService` hợp nhất lịch sử điểm danh khi MSSV thay đổi chữ hoa/thường, loại bỏ dòng sinh viên trùng lặp trong file nhập và không ghi đè trạng thái `present` của buổi đã chốt.
  - `AttendanceCsvExporter`, `AttendancePdfExporter` và `WorkspaceStore._snapshot` truy xuất qua `courseClass.recordFor` và dùng helper chung `spreadsheetText` để thoát công thức bảng tính (`=`, `+`, `-`, `@`, `\t`, `\r`).
  - `WorkspaceIntegrityValidator` trim `scheduleCode` nhất quán với `ScheduleRule` và `ScheduleService`.
- **Khôi phục an toàn lưu trữ và đồng hồ server (`lib/data`, `lib/lab3`)**:
  - `WorkspaceStore` ghi file nguyên tử qua `writeReportAtomically`, giữ bản `.bak` và tự khôi phục `workspace.json` từ `workspace.json.bak` khi file chính bị lỗi/hỏng.
  - `TeacherViewModel.shareLink` và `_clearClosedLink` dùng `linkNow` (`ServerTimedAttendanceLinks`) thay vì giờ cục bộ trên máy, đảm bảo chia sẻ link không bị chặn sai khi đồng hồ thiết bị lệch so với Firebase server.
- **Tối ưu Backend, Web Admin, Extension và CLI Workbench**:
  - `backend/relay.mjs` tách hàng đợi đọc chỉ-đọc (`SessionStore.read`) và chỉ đánh dấu challenge đã dùng sau khi ghi điểm danh thành công (`afterCommit`).
  - `backend/attendance-analytics.mjs`, `backend/attendance-report.mjs`, `backend/attendance-matrix.mjs`, `backend/attendance-fpt-policy.mjs` và `web/src/admin/analytics.js` tối ưu duyệt một lượt và tính ngưỡng chính xác bằng tìm kiếm nhị phân.
  - `tools/attendance-workbench/cli.mjs` bổ sung lệnh `fpt-policy` và `fpt-policy-csv` đánh giá quy chế điểm danh FPT (cảnh báo 15%, cấm thi >20%).
