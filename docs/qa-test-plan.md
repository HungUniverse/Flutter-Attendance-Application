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

Trong quá trình kiểm thử hộp trắng (White-box QA) và kiểm thử biên (Boundary/Negative Testing), các lỗi thực tế đã được phát hiện và khắc phục triệt để:

| Mã lỗi | Thành phần | Mô tả lỗi gốc (Root Cause) | Giải pháp khắc phục (Fix) |
| :--- | :--- | :--- | :--- |
| **BUG-01** | `packages/core/lib/src/models.dart` (`ScheduleRule`) | Getter `dayGroup` và `dailySlot` gọi trực tiếp `scheduleCode.substring(0, 1)` và `scheduleCode.substring(1, 2)` mà không kiểm tra độ dài chuỗi, gây lỗi `RangeError` khi `scheduleCode` rỗng hoặc chỉ có 1 ký tự. | Kiểm tra `scheduleCode.isEmpty` và `scheduleCode.length < 2` trước khi cắt chuỗi, trả về `0` an toàn. Chuẩn hóa thêm `attendanceStatusFromCode` với `.trim().toUpperCase()`. |
| **BUG-02** | `lib/domain/qr_protocol.dart` (`QrPayload.decode`) | Giải mã chuỗi QR Base64 chứa JSON thiếu trường, `version < 1`, `certificateFingerprint` rỗng hoặc sai kiểu dữ liệu làm phát sinh `TypeError` / `ArgumentError` thay vì `FormatException`. | Kiểm tra chuỗi rỗng, xác thực cấu trúc JSON Map, `version >= 1` và các trường bắt buộc (`endpoint`, `classId`, `meetingId`, `token`, `certificateFingerprint`, `mode`), chuẩn hóa mọi lỗi cấu trúc thành `FormatException`. |
| **BUG-03** | `lib/data/roster_importer.dart` (`RosterImporter`) | Tách phần mở rộng bằng `fileName.toLowerCase().split('.').last` khiến tên file không có dấu chấm (ví dụ `'ods'`) hoặc dotfile (`C:\dir\.ods`) bị nhận nhầm là `.ods`; đồng thời file `.ods`/`.xlsx` rỗng hoặc hỏng cấu trúc ZIP/XML gây rò rỉ ngoại lệ hoặc trả về bảng rỗng. | Tách `baseName` trước khi kiểm tra dấu chấm cuối (`lastIndexOf('.')`), kiểm tra chữ ký ZIP (`PK`) và bảng rỗng cho `.xlsx`, bọc toàn bộ lỗi giải nén ZIP/XML/XLSX thành `RosterImportException`. |
| **BUG-04** | `lib/domain/attendance_reconciliation_service.dart` & `workspace_integrity_validator.dart` | Khi gộp hoặc sửa dữ liệu điểm danh có khóa MSSV khác hoa/thường (`se194673` vs `SE194673`) hoặc buổi học mới từ bản ghi đồng bộ, bản ghi cũ bị trùng khóa hoặc tạo bản ghi mồ côi (`ORPHANED_MEETING_ATTENDANCE`). | Hợp nhất danh sách `meetings` theo tiến trình trạng thái, chuẩn hóa khóa MSSV không phân biệt hoa/thường về mã chuẩn của sinh viên, tự động hạ cấp các buổi active dư thừa và điền lý do mặc định cho bản ghi audit trống. |
| **BUG-05** | `lib/domain/session_recovery_planner.dart` & `attendance_analytics_service.dart` | `scheduleMakeupMeeting` chấp nhận `customMeetingId` rỗng hoặc trùng với mã buổi học đã có; `AttendanceAnalyticsService` tra cứu MSSV phân biệt hoa/thường và chưa bọc giá trị chứa `\r` khi xuất CSV. | Kiểm tra `customMeetingId` không rỗng và không trùng lặp; bổ sung tra cứu MSSV không phân biệt hoa/thường và thoát chuỗi CSV an toàn với `\r`, `\t` và công thức có khoảng trắng đầu dòng. |
| **BUG-06** | `test/qa_*.dart` & `integration_test/qa_app_e2e_test.dart` | Khi chạy kiểm thử giao diện headless, font mặc định Ahem có độ rộng ký tự lớn gây sai lệch bố cục ở kích thước màn hình hẹp (412px). | Nạp font tỷ lệ thực `assets/fonts/Roboto.ttf` (kèm fallback hệ thống) trong `setUpAll` cho toàn bộ bộ test UI/E2E. |
| **BUG-07** | `extension/src/csv.ts`, `attendance_json.ts`, `fap_adapter.ts` | Extension chưa loại bỏ tiền tố CSV Formula Injection (`'`), chưa kiểm tra ngày lịch tràn (ví dụ `2026-02-30`) và `endAt <= startAt`, regex mã lớp `/\b[A-Z]{2,5}\d{4}/g` bắt nhầm tiền tố của MSSV 6 chữ số (`SE000001`), và nối chuỗi `<option>` thiếu khoảng trắng khiến nhãn tiếng Việt (`CÓ MẶT`/`VẮNG`) không khớp. | Bổ sung `stripFormulaPrefix`, `isValidIsoDateTime`, hậu tố `\b` cho regex mã lớp, chuẩn hóa `roll_number`/`member_code` không phân biệt hoa/thường và hỗ trợ đầy đủ `<select>` tiếng Việt. |
| **BUG-08** | `web/src/admin/markbook.js` & `model.js` | `DOMParser` trong môi trường trình duyệt/happy-dom báo lỗi `<parsererror>` khi gặp khai báo XML nháy đơn (`<?xml version='1.0'?>` trong `FA26_Markbook.ods`); dòng sinh viên thiếu trường lẻ làm hủy toàn bộ bảng; `model.js` phân biệt hoa/thường khi đối chiếu `rollNumber`. | Cắt bỏ khai báo `<?xml ...?>` đầu file, hỗ trợ bỏ qua dòng thiếu dữ liệu kèm cảnh báo (`warnings`), điền đầy mảng cột thưa của XLSX và chuẩn hóa `rollNumber` viết hoa trong `parseRoster`, `protectHistory`, `correction`. |
| **BUG-09** | `backend/relay.mjs`, `attendance-merge.mjs`, `workspaces.mjs` | `relay.mjs` gặp lỗi `TypeError` (HTTP 500) khi mảng `students` chứa phần tử `null` và chưa chuẩn hóa chữ thường cho email; `resolveAttendanceConflicts` chưa `.trim()` khóa `studentId`/`sessionId`; `validateWorkspace` chấp nhận `c.id` chỉ chứa khoảng trắng. | Kiểm tra phần tử object hợp lệ, chuẩn hóa `.trim().toLowerCase()` cho email sinh viên, cắt khoảng trắng khóa xung đột và từ chối `c.id` rỗng. |
| **BUG-10** | `demo-fap/app.js` & `tools/attendance-workbench/isolation.test.mjs` | `demo-fap/app.js` lỗi `JSON.parse` khi nạp file JSON có BOM UTF-8 (`\uFEFF`) và chưa chuẩn hóa hoa/thường khi khôi phục trạng thái chốt; `isolation.test.mjs` quét đệ quy cả thư mục `web/node_modules`. | Loại bỏ `\uFEFF` trước khi `JSON.parse`, chuẩn hóa `rollNumber`/`status` viết hoa và bỏ qua `node_modules`/`dist` trong `isolation.test.mjs`. |
| **BUG-11** | `firebase/test/firestore.test.mjs` | Bộ kiểm thử Firestore Rules Emulator chỉ khởi tạo `users/teacher` mà thiếu `users/admin` và `teacherDirectory/{email}` (`status: 'active'`) sau khi hệ thống chuyển sang phân quyền qua `teacherDirectory`, khiến 18/40 ca kiểm thử bị từ chối quyền (`PERMISSION_DENIED` / `teacher-required`). | Khởi tạo đầy đủ `users/admin` và `teacherDirectory` cho giảng viên hoạt động trong `beforeEach`, đồng thời bổ sung ca kiểm thử `teacherDirectory`, `teacherAudit` và `rules-static-contract.test.mjs` (45/45 PASS trên Firestore Emulator). |
| **BUG-12** | `packages/core/lib/src/attendance_service.dart` & `schedule_service.dart` | `markPresent`, `markManual` và `closeMeeting` ghi bản ghi mới vào khóa MSSV chuẩn hóa nhưng không xóa khóa MSSV khác hoa/thường tồn tại trước đó (ví dụ `'se194673': unmarked`), khiến `course.recordFor(meetingId, 'se194673')` trả về bản ghi cũ; `ScheduleRule` chưa `.trim()` chuỗi `scheduleCode`. | Xóa mọi khóa trùng lặp khác hoa/thường trước khi ghi trong `markPresent`, `markManual`, `closeMeeting` và chuẩn hóa `.trim()` cho `ScheduleRule`. |
| **BUG-13** | `extension/src/attendance_json.ts` & `popup.ts` | `parseAttendanceJson` chưa chuẩn hóa viết hoa cho `semester`, `courseCode`, `classCode`, `scheduleCode` và chưa cắt tiền tố công thức (`'`) ở trường văn bản; `popup.ts` truy cập `tab.url` và `result.error` không có kiểm tra null khi không có tab hoặc content script chưa phản hồi. | Chuẩn hóa viết hoa metadata phiên học, áp dụng `stripFormulaPrefix` đồng nhất giữa CSV/JSON và bổ sung kiểm tra an toàn cho `tab?.id`, `tab?.url` và `result` trong `popup.ts`. |
| **BUG-14** | `web/src/admin/markbook.js` | File `.xlsx` có đường dẫn `Target="xl/worksheets/sheet1.xml"` hoặc `Target="/xl/worksheets/sheet1.xml"` trong `workbook.xml.rels` bị ghép trùng thành `xl/xl/worksheets/sheet1.xml`; thẻ phiên âm `<rPh><t>` trong `sharedStrings.xml`/`inlineStr` bị nối dính vào tên sinh viên. | Chuẩn hóa tiền tố `/xl/` hoặc `xl/` trước khi phân giải đường dẫn sheet và lọc bỏ các thẻ `<t>` nằm trong `<rPh>`. |
| **BUG-15** | `web/src/admin/model.js`, `web/src/ui.js`, `web/src/system-admin/repository.js` | `attendanceSummary` tra cứu `m.records[s.rollNumber]` phân biệt hoa/thường; `rosterMap` chưa chuẩn hóa email/MSSV; `dateText(null)` và `dateText("")` trả về `"07:00 1/1/1970"` (epoch 0) thay vì `"—"`; `TeacherDirectoryRepository` chưa chuẩn hóa `previous.email`. | Bổ sung tra cứu không phân biệt hoa/thường trong `attendanceSummary`, chuẩn hóa `rosterMap` & `previous.email`, và chặn giá trị rỗng/`null`/`boolean` trong `dateText`. |
| **BUG-16** | `backend/relay.mjs` & `backend/workspaces.mjs` | Gửi JSON body là `null`, `[]` hoặc kiểu nguyên thủy tới các endpoint `POST` trong `relay.mjs` làm phát sinh `TypeError` (HTTP 500) thay vì HTTP 400; `FileWorkspaceStore` và `FirestoreWorkspaceStore` phân biệt hoa/thường khi tra cứu `semester`. | Kiểm tra `parsed` là plain object hợp lệ trong `body(req)` (trả về HTTP 400 nếu sai) và chuẩn hóa `semester.trim().toUpperCase()` khi đọc/ghi workspace. |

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

### 3.6. Full-Stack Subprojects QA Suite (`extension/`, `web/`, `backend/`, `demo-fap/`, `tools/attendance-workbench/`, `firebase/`, `packages/core/`)

- **Chrome Extension (`extension/test/qa_extension_suite.test.ts` & `demo_page.test.ts` — 22/22 PASS)**:
  - Kiểm thử parsing CSV/JSON với UTF-8 BOM, chuẩn hóa viết hoa metadata (`semester`, `course_code`, `class_code`, `schedule_code`), loại bỏ tiền tố CSV Formula Injection, từ chối ngày không tồn tại (`2026-02-30`) và `endAt <= startAt`.
  - Kiểm thử `FapPageAdapter` với checkbox, radio, `<select>` tiếng Việt (`Có mặt`/`Vắng`), đối chiếu theo `member_code` và ngăn chặn nhận nhầm MSSV 6 chữ số làm mã lớp.
- **Web Admin, System Admin & Student App (`web/test/*.test.mjs`, `web/test-dom/*.test.mjs` — 32/32 PASS)**:
  - Kiểm thử đọc trực tiếp tệp thực tế `test/fixtures/FA26_Markbook.ods`, xử lý bảng XLSX có đường dẫn `xl/worksheets/...`, thẻ `<rPh>` và ô thưa, suy luận học kỳ từ đường dẫn đầy đủ, mô-đun thống kê `web/src/admin/analytics.js`, và bộ kiểm thử Unit + DOM cho `system-admin` (`teacherDirectory` & `teacherAudit`).
- **Node.js Backend Services (`backend/test/*.test.mjs` — 83/83 PASS)**:
  - Kiểm thử `attendance-fpt-policy.mjs` (đánh giá điều kiện dự thi FPT 15%/20% và số buổi tối đa còn được phép vắng), bảo vệ `relay.mjs` trước JSON body không phải object (`null`/`[]`/primitive) và phần tử `null` trong `students`, chuẩn hóa khóa trong `attendance-merge.mjs` & `workspaces.mjs`.
- **Attendance Workbench CLI (`tools/attendance-workbench/*.test.mjs` — 137/137 PASS)**:
  - Kiểm thử `anomaly-detector.mjs` (`anomaly-scan`, `anomaly-scan-csv`) phát hiện buổi vắng 100%, sụt giảm chuyên cần đột ngột, suy giảm nửa cuối kỳ và chuỗi trạng thái đan xen `P/A`.
- **Firebase Security Rules & E2E Repository Flow (`firebase/test/*.test.mjs` — 45/45 PASS)**:
  - Kiểm thử trực tiếp trên Firebase Firestore Emulator cho `firestore.rules` (bao gồm `teacherDirectory`, `teacherAudit`, thu hồi quyền tức thì khi `suspended`, luồng `web/e2e/admin-flow.mjs`) và kiểm thử hợp đồng tĩnh cho `storage.rules` & `firestore.indexes.json`.
- **Shared Core Package (`test/qa_core_package_test.dart` — 5/5 PASS)**:
  - Kiểm thử `CourseClass.recordFor`, `markPresent`, `markManual`, `overrideStatus` và `closeMeeting` không phân biệt hoa/thường cho `rollNumber` và tự động dọn khóa trùng lặp khác hoa/thường.
