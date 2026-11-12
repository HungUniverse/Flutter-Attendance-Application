# Mô hình dữ liệu Firebase Final

## Danh tính và quyền

Google Sign-In cung cấp Firebase UID, email đã xác minh và provider `google.com`. Admin cần `users/{uid}.role == admin`, cấp bằng `firebase/provision-admin.mjs`; client không được tự tạo hoặc sửa vai trò admin. Giảng viên cần `teacherDirectory/{email}.status == active`. Admin quản lý danh mục trên web; khóa hoặc xóa hồ sơ chặn quyền Firebase của giảng viên. Vai trò `teacher` cũ trong `users` không còn tự cấp quyền, nên xóa danh mục không làm sống lại quyền cũ.

Sinh viên dùng trang `/join/{sessionId}`. Rules đối chiếu email trong token Google với roster riêng của lớp. MSSV và email tự nhập không tham gia cấp quyền.

## Collections

| Đường dẫn | Trường và kiểu | Quyền CRUD từ client | Màn sử dụng |
| --- | --- | --- | --- |
| `users/{uid}` | `role` string, `email` string, `provisionedAt` timestamp | Người dùng đọc hồ sơ chính mình. Ghi bằng công cụ quản trị có credential của chủ project. | Đăng nhập, khôi phục workspace |
| `teacherDirectory/{email}` | `email`, `displayName`, `staffCode`, `department`, `status`, `createdBy`, `updatedBy` string; `createdAt`, `updatedAt` timestamp | Admin đọc/liệt kê/thêm/sửa/xóa. Tài khoản Google đọc hồ sơ theo email token của mình. Giảng viên không tự sửa quyền. | Admin CRUD, kiểm tra quyền Android/Windows/web |
| `teacherAudit/{id}` | `actorUid`, `email`, `action` string, `before`, `after` map, `at` server timestamp | Chỉ admin đọc và tạo. Cấm sửa/xóa từ client. | Lịch sử quản trị |
| `workspaces/{id}` | `ownerUid` string, `revision` int, `mutationId` string, `data` map, `layout` map, `updatedAt` server timestamp | Giảng viên chủ sở hữu đọc, tạo và cập nhật với revision tăng đúng một. | Import, dashboard, tải lại học kỳ |
| `classes/{id}` | `ownerUid` string, `workspaceId` string, `archived` bool, `data` map, `roster` map email → MSSV | Giảng viên chủ sở hữu đọc và ghi cùng transaction tăng revision workspace. Lưu trữ bằng `archived`. | Lớp, danh sách, lịch |
| `classes/{id}/meetings/{meetingId}` | `id`, `startAt`, `endAt` string ISO, `number` int, `state` string, `dayStart`, `dayEnd` timestamp, `records` map, `auditEvents` list | Giảng viên chủ sở hữu đọc và ghi theo chuyển trạng thái. Cập nhật đồng thời revision workspace. | Điểm danh, lịch sử, sửa kết quả |
| `attendanceSessions/{id}` | `ownerUid`, `classId`, `localClassId`, `meetingId`, `label` string, `receiving` bool, `expiresAt`, `createdAt`, `updatedAt` timestamp | Giảng viên của lớp tạo và dừng. Người đăng nhập Google đọc thông tin phiên bằng link. Chỉ giảng viên liệt kê phiên của mình. | QR Windows, link Android, web check-in |
| `attendanceSessions/{id}/checkIns/{studentUid}` | `uid`, `email` string, `at` server timestamp | Sinh viên tạo đúng UID của mình một lần, đọc lượt của mình. Giảng viên của lớp đọc danh sách. Cấm sửa và xóa. | Web xác nhận, lượt gửi trực tiếp |
| `attendanceRequests/{id}` | `uid`, `email`, `ownerUid`, `classId`, `meetingId`, `sessionId`, `requestedStatus`, `reason`, `state` string, `createdAt` server timestamp; khi xử lý thêm `reviewerUid`, `decisionReason`, `decidedAt` | Sinh viên tạo yêu cầu của mình cho buổi đã chốt. Sinh viên và giảng viên sở hữu đọc. Giảng viên xử lý đúng một lần; duyệt phải ghi kết quả và audit cùng transaction. Cấm xóa. | Web sinh viên, hàng chờ giảng viên |
| `announcements/{id}` | `ownerUid`, `recipientUid`, `title`, `body`, `classId`, `meetingId` string, `recipientEmail` string tùy chọn, `at` server timestamp | Giảng viên của lớp tạo. Chủ sở hữu và người nhận theo UID/email Google đọc. Email khi gửi phải thuộc roster. Cấm sửa và xóa từ client. | Hộp thư Android, web sinh viên, form thông báo |
| `reportMetadata/{id}` | `ownerUid`, `classId`, `meetingId`, `fileName`, `format` string, `bytes` int, `at` server timestamp | Giảng viên của lớp tạo cho buổi đã chốt, đọc metadata của mình. Cấm sửa và xóa. | Xuất PDF, CSV, JSON |

`classes.data` chứa mã môn, mã lớp, roster hiển thị và quy tắc lịch theo model `CourseClass`, tách khỏi danh sách buổi và kết quả. `workspaces.data` chứa metadata `TeacherWorkspace`, tách khỏi các lớp. `layout` ánh xạ ID Firestore của lớp tới danh sách ID buổi để đọc một snapshot workspace nhất quán.

Đợt này dùng map `classes.roster` riêng tư để Rules tra membership. Sinh viên không có quyền đọc document lớp, roster hoặc kết quả của lớp; được đọc yêu cầu và thông báo của chính mình. Mô hình này thay cho collection `members` đề xuất trong tài liệu bàn giao. Android và Windows dùng cùng `packages/core/`, schema và Rules. Web quản lý dùng cùng manifest/revision và đối chiếu quy tắc lịch của core.

ID workspace là SHA-256 của `uid/semester`. ID lớp là SHA-256 của `uid/semester/localClassId`, giữ nguyên ID nghiệp vụ cũ trong model. ID phiên là SHA-256 của `firestoreClassId/meetingId`. Tạo lại QR giữ lượt gửi của cùng buổi, tránh điểm danh lặp sau khi mở lại.

ID yêu cầu là `classId_meetingId_studentUid`, nên hai link cùng buổi không tạo hai yêu cầu. Sinh viên chỉ tạo trạng thái `pending`, với kết quả đề nghị khác hiện tại và lý do tối đa 1.000 ký tự. Chuyển sang `approved` hoặc `rejected` là quyết định cuối. Duyệt thêm audit có ID trùng ID yêu cầu; Rules kiểm tra giá trị mới và revision tăng cùng transaction. Phản hồi gửi theo UID đã xác minh; thông báo toàn lớp gửi theo email token, không cần truy vấn danh sách tài khoản Authentication.

## Chuyển trạng thái và kiểm soát ghi

- Buổi đi từ `upcoming` sang `active` trong ngày của buổi, rồi sang `closed`. Buổi quá ngày được chốt tự động sau khi lấy các lượt gửi còn thiếu.
- Buổi `closed` giữ trạng thái khi sửa. Rules yêu cầu thay đổi đúng một sinh viên, thêm audit có lý do, giá trị trước và sau khớp bản ghi. Audit cũ phải được giữ lại.
- Phiên nhận trong hai phút từ lần tạo hoặc mở lại. Check-in cần `receiving == true`, buổi đang `active`, thời gian máy chủ trong ngày học và trước `expiresAt`.
- Dừng phiên phải được Firestore xác nhận trước khi truy vấn server lấy toàn bộ lượt gửi và chốt. Nếu bước này lỗi, app giữ buổi đang mở để thử lại.
- Lựa chọn P/A của giảng viên được ưu tiên khi nhập lượt check-in. Khi chốt, ô chưa ghi được chuyển thành A bằng nghiệp vụ trong core.
- Transaction workspace kiểm tra revision và mutation ID. Hàng đợi trên máy giữ bản chưa đồng bộ khi offline, giữ bản đối chiếu khi xung đột. Hai thiết bị cần giải quyết xung đột trước khi tiếp tục ghi bản máy chủ.
- Báo cáo nằm trên thiết bị. Outbox metadata riêng có thể thử lại sau khi buổi đã đồng bộ. Document metadata không chứa nội dung tệp hoặc đường dẫn Storage.

App Check đã cấu hình cho Android debug, Windows demo và web reCAPTCHA Enterprise. Firestore và Firebase AI Logic bật enforcement. Windows dùng debug provider do SDK desktop hiện hỗ trợ provider này. Token demo chỉ nằm trong file local bị Git bỏ qua. Bản Android release cần cấu hình Play Integrity cho bản phát hành tương ứng.

Chi tiết provider desktop có trong tài liệu SDK. [Firebase App Check Flutter](https://firebase.google.com/docs/app-check/flutter/default-providers)
