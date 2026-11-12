# Kế Hoạch Kiểm Thử Toàn Diện (QA Test Plan & Defect Audit Report)

- **Dự án**: FAP Attendance Application (`fap_attendance`)
- **Học phần**: PRM393 — Mobile Programming (FPT University)
- **Người thực hiện QA & Kiểm thử**: Dương Thành Thanh Duy (`SE194673`)
- **Phạm vi kiểm thử**: Domain Core (`packages/core`), Data Layer (`lib/data`), Lab 3 Teacher Mobile App (`lib/lab3`), Analytics & Integrity Services (`lib/domain`), và End-to-End User Flows (`test/`, `integration_test/`).

---

## 1. Phân Tích Kiến Trúc & Phạm Vi Kiểm Thử (Test Scope)

Ứng dụng điểm danh FAP được tổ chức theo kiến trúc phân lớp rõ ràng:

1. **Domain Layer (`packages/core/lib/src` & `lib/domain`)**:
   - Models (`Student`, `ScheduleRule`, `Meeting`, `AttendanceRecord`, `AuditEvent`, `CourseClass`, `TeacherWorkspace`).
   - Services (`AttendanceService`, `ScheduleService`, `RollingQrIssuer`, `ChallengeStore`, `RosterMergeService`).
   - Analytics, Integrity & Reconciliation (`AttendanceAnalyticsService`, `WorkspaceIntegrityValidator`, `AttendanceReconciliationService`).
2. **Data Layer (`lib/data`)**:
   - Đọc/nhập danh sách lớp từ file `.ods` và `.xlsx` (`RosterImporter`).
   - Xuất báo cáo điểm danh chuẩn UTF-8 BOM CSV (`AttendanceCsvExporter`) và PDF (`AttendancePdfExporter`).
   - Lưu trữ cục bộ an toàn với cơ chế atomic write & `.bak` recovery (`WorkspaceStore`).
3. **Presentation & State Management Layer (`lib/lab3`)**:
   - `TeacherViewModel` (`ChangeNotifier`) quản lý trạng thái đăng nhập, mở buổi học, điểm danh qua link hoặc thủ công, chốt danh sách, sửa kết quả kèm lý do (Audit Trail), và đồng bộ đám mây.
   - Hệ thống màn hình Flutter Material 3 (`TeacherMobileApp`, `DashboardPage`, `AttendancePage`, `StudentPage`, `NotificationsPage`, `AccountPage`).

---

## 2. Phát Hiện & Sửa Lỗi Thực Tế (Bug Fixes & Defensive Hardening)

Trong quá trình kiểm thử hộp trắng (White-box QA) và kiểm thử biên (Boundary/Negative Testing), 4 lỗi thực tế đã được phát hiện và khắc phục triệt để:

| Mã lỗi | Thành phần | Mô tả lỗi gốc (Root Cause) | Giải pháp khắc phục (Fix) |
| :--- | :--- | :--- | :--- |
| **BUG-01** | `packages/core/lib/src/models.dart` (`ScheduleRule`) | Getter `dayGroup` và `dailySlot` gọi trực tiếp `scheduleCode.substring(0, 1)` và `scheduleCode.substring(1, 2)` mà không kiểm tra độ dài chuỗi, gây lỗi `RangeError` khi `scheduleCode` rỗng hoặc chỉ có 1 ký tự. | Kiểm tra `scheduleCode.isEmpty` và `scheduleCode.length < 2` trước khi cắt chuỗi, trả về `0` an toàn. Chuẩn hóa thêm `attendanceStatusFromCode` với `.trim().toUpperCase()`. |
| **BUG-02** | `lib/domain/qr_protocol.dart` (`QrPayload.decode`) | Giải mã chuỗi QR Base64 chứa JSON thiếu trường hoặc sai kiểu dữ liệu làm phát sinh `TypeError` / `ArgumentError` chưa được chuẩn hóa thay vì `FormatException`. | Kiểm tra chuỗi rỗng, xác thực cấu trúc JSON Map và các trường bắt buộc (`endpoint`, `classId`, `meetingId`, `token`, `mode`), chuẩn hóa mọi lỗi cấu trúc thành `FormatException`. |
| **BUG-03** | `lib/data/roster_importer.dart` (`RosterImporter`) | Tách phần mở rộng bằng `fileName.toLowerCase().split('.').last` khiến tên file không có dấu chấm (ví dụ `'ods'`) bị nhận nhầm là `.ods`; đồng thời file `.ods`/`.xlsx` rỗng hoặc hỏng cấu trúc ZIP/XML gây rò rỉ `ArchiveException` / `XmlException`. | Kiểm tra vị trí dấu chấm cuối cùng (`lastIndexOf('.')`) sau khi `.trim()`, kiểm tra byte rỗng và bọc toàn bộ lỗi giải nén ZIP/XML/XLSX thành `RosterImportException`. |
| **BUG-04** | `test/qa_*.dart` & `integration_test/qa_app_e2e_test.dart` | Khi chạy kiểm thử giao diện headless, font mặc định Ahem có độ rộng ký tự lớn gây sai lệch bố cục ở kích thước màn hình hẹp (412px). | Nạp font tỷ lệ thực `assets/fonts/Roboto.ttf` (kèm fallback hệ thống) trong `setUpAll` cho toàn bộ bộ test UI/E2E. |

---

## 3. Ma Trận Truy Xuất Ca Kiểm Thử (Test Case Traceability Matrix)

### 3.1. Unit Tests (`test/qa_unit_test.dart` & `test/qa_roster_schedule_edge_test.dart`)

| Mã TC | Mô tả ca kiểm thử | Thành phần mục tiêu | Kết quả mong đợi | Trạng thái |
| :--- | :--- | :--- | :--- | :---: |
| `UT-01` | Serialize & Deserialize `Student` và chuẩn hóa `normalizedEmail` | `Student` | Bảo toàn đầy đủ thuộc tính và cắt khoảng trắng, chuyển chữ thường cho email | PASS |
| `UT-02` | Serialize & Deserialize `Meeting` và kiểm tra `isOnDate`, `isBeforeDate`, `isAfterDate` | `Meeting` | So sánh ngày chính xác theo múi giờ cục bộ | PASS |
| `UT-03` | Roundtrip JSON cho `AttendanceRecord`, `AuditEvent`, `CourseClass`, `TeacherWorkspace` | `models.dart` | Dữ liệu sau khi giải mã trùng khớp 100% với bản gốc | PASS |
| `UT-04` | Chuyển đổi mã điểm danh `P`/`A`/trống và xử lý `ScheduleRule` chuỗi ngắn | `models.dart` | Không ném `RangeError` khi `scheduleCode` rỗng hoặc 1 ký tự | PASS |
| `UT-05` | Sinh lịch học tự động theo `ScheduleRule`, ngày nghỉ lễ và lịch học bù | `ScheduleService` | Tạo đúng 20 buổi (10 tuần x 2 buổi), loại trừ ngày nghỉ và sắp xếp đúng thứ tự | PASS |
| `UT-06` | Mã hóa, giải mã và xác thực chữ ký HMAC cho `QrPayload` | `RollingQrIssuer` | Token hợp lệ trong cửa sổ thời gian 20 giây và hỗ trợ chế độ OTP | PASS |
| `UT-07` | Xuất báo cáo CSV có BOM UTF-8 (`\uFEFF`) và đầy đủ 17 cột chuẩn | `AttendanceCsvExporter` | Chuỗi CSV bắt đầu bằng `\uFEFF` và khớp schema dữ liệu | PASS |
| `UT-08` | Quản lý trạng thái `TeacherViewModel`: khởi tạo, đổi chế độ, điểm danh, chốt buổi, sửa kèm lý do | `TeacherViewModel` | Cập nhật state, gọi `notifyListeners()` và lưu trữ qua `MobileWorkspaceRepository` | PASS |
| `UT-09` | Gộp danh sách lớp (`RosterMergeService`) khi sinh viên đổi MSSV hoặc thêm mới | `RosterMergeService` | Bảo toàn lịch sử điểm danh theo email và tự động điền `A` cho buổi đã chốt | PASS |

### 3.2. Widget Tests (`test/qa_widget_test.dart`)

| Mã TC | Mô tả ca kiểm thử | Thành phần UI | Kết quả mong đợi | Trạng thái |
| :--- | :--- | :--- | :--- | :---: |
| `WT-01` | Hiển thị `DashboardPage` và thanh điều hướng khi tải xong workspace | `TeacherMobileApp` | Render danh sách lớp `PRM393 · SE1901` và `NavigationBar` | PASS |
| `WT-02` | Render `SectionCard`, `StatusTag` và `AttendancePage` | `components.dart`, `screens.dart` | Hiển thị đúng nhãn trạng thái và danh sách sinh viên | PASS |
| `WT-03` | Hiển thị `CircularProgressIndicator` khi `loadingWorkspace = true` | `TeacherMobileApp` | Hiển thị vòng xoay tải dữ liệu, ẩn nội dung chính | PASS |
| `WT-04` | Hiển thị màn hình lỗi và khôi phục khi bấm nút `Thử lại` | `TeacherMobileApp` | Gọi `retryLoad()` và chuyển về `DashboardPage` thành công | PASS |
| `WT-05` | Tìm kiếm sinh viên theo tên/MSSV và xóa bộ lọc trên `AttendancePage` | `AttendancePage` | Lọc danh sách sinh viên theo thời gian thực khi nhập `TextField` | PASS |
| `WT-06` | Chuyển chế độ `Thủ công`, đánh dấu `P · Có mặt` và mở hộp thoại `Chốt danh sách` | `AttendancePage` | Cập nhật trạng thái sinh viên trong ViewModel và hiển thị `AlertDialog` xác nhận | PASS |
| `WT-07` | Cuộn danh sách sinh viên dài trên màn hình 412x700 mà không bị tràn bố cục | `AttendancePage` | Không phát sinh `RenderFlex overflowed` (`tester.takeException() == null`) | PASS |

### 3.3. Negative & Edge-Case Tests (`test/qa_negative_test.dart`)

| Mã TC | Mô tả ca kiểm thử | Tình huống lỗi | Kết quả mong đợi | Trạng thái |
| :--- | :--- | :--- | :--- | :---: |
| `NT-01` | Sửa kết quả điểm danh nhưng để trống hoặc chỉ nhập khoảng trắng ở ô lý do | Form Validation | Hiển thị thông báo lỗi `"Vui lòng nhập lý do chỉnh sửa."` | PASS |
| `NT-02` | Xuất báo cáo CSV khi buổi học chưa chốt hoặc còn sinh viên chưa điểm danh | Guardrail State | Ném `StateError` ngăn chặn xuất dữ liệu chưa hoàn chỉnh | PASS |
| `NT-03` | Giải mã QR payload rỗng, sai Base64, hoặc thiếu trường JSON | Malformed Input | Ném `FormatException` an toàn | PASS |
| `NT-04` | Nhập danh sách lớp với tên file không có phần mở rộng hoặc byte hỏng | Corrupted File | Ném `RosterImportException` với thông báo rõ ràng | PASS |
| `NT-05` | Lỗi ghi đĩa (`failSave`), lỗi tải lên Cloud (`upload.fail`), lỗi mất mạng (`links.fail`) | Storage / Network | Bắt lỗi an toàn, giữ nguyên dữ liệu cục bộ và ghi nhận telemetry | PASS |
| `NT-06` | Điểm danh bằng QR hết hạn, sai `deviceId`, hoặc sai mã OTP 6 chữ số | Security Guardrail | Từ chối yêu cầu với `StateError` tương ứng | PASS |
| `NT-07` | Tự động đóng phiên điểm danh qua link khi giảng viên đăng xuất | Session Security | Dừng nhận kết quả (`receiving == false`) ngay khi `signOut()` | PASS |

### 3.4. Analytics, Integrity & Reconciliation Tests

- **`test/qa_attendance_analytics_test.dart`**: Kiểm thử phân loại nguy cơ cấm thi theo ngưỡng vắng 15% (Warning) và >20% (Barred) của FPT University, chuỗi vắng liên tiếp (`longestAbsenceStreak`), tỷ lệ tham gia từng buổi học, và chống CSV Formula Injection.
- **`test/qa_workspace_integrity_test.dart`**: Kiểm thử phát hiện trùng MSSV/email, nhiều buổi active cùng lúc, buổi đã chốt còn ô trống, bản ghi mồ côi (orphaned records), và tự động sửa lỗi (`repairCourseClass`).
- **`test/qa_attendance_reconciliation_test.dart`**: Kiểm thử đối soát đa nguồn (`diffClasses`, `reconcile`) và giải quyết xung đột theo chiến lược ưu tiên quyết định thủ công của giảng viên (`preferTeacherManual`).

### 3.5. End-to-End Integration Tests (`test/qa_integration_test.dart` & `integration_test/qa_app_e2e_test.dart`)

- Kiểm thử luồng nghiệp vụ khép kín từ đầu đến cuối:
  `Đăng nhập Google` $\rightarrow$ `Xem lịch & lớp trên Dashboard` $\rightarrow$ `Kiểm tra tab Thông báo` $\rightarrow$ `Mở buổi học đang diễn ra` $\rightarrow$ `Chuyển sang chế độ Thủ công & điểm danh Có mặt (P)` $\rightarrow$ `Chốt danh sách (tự động đánh Vắng cho sinh viên chưa điểm danh)` $\rightarrow$ `Mở chi tiết sinh viên & sửa kết quả P/A kèm lý do kiểm toán (Audit Trail)` $\rightarrow$ `Đăng xuất an toàn`.
