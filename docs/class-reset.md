# Reset dữ liệu lớp ngày 13/11/2026

Đã reset dữ liệu lớp trên Firebase project `fap-attendance-71655` theo yêu cầu người dùng, giữ nguyên tài khoản và quyền.

- Xóa 20 lớp, 400 buổi học, 1 phiên điểm danh và 1 metadata báo cáo: tổng cộng 422 document.
- Xác minh các collection lớp, phiên, yêu cầu sửa, thông báo và metadata báo cáo đều rỗng; không còn buổi/lượt gửi trong các đường dẫn con đã kiểm kê.
- Hai workspace Final và năm workspace Lab 3 được làm rỗng danh sách lớp, tăng revision để ngăn outbox cũ ghi lại dữ liệu.
- Dấu kiểm tra nội dung trước/sau của `users`, `teacherDirectory`, `teacherAudit`, `system` và document gốc `teachers` khớp hoàn toàn: giữ 3 hồ sơ người dùng, 2 hồ sơ giảng viên và toàn bộ quyền/audit quản trị. Không gọi API sửa/xóa Authentication.
- Snapshot phục hồi trước khi reset được lưu riêng ngoài repo. Lô xóa đầu bị Firebase từ chối; đã chia nhỏ thành các lô 50 document và kiểm tra lại các đường dẫn con, sau đó hoàn tất reset.

Thao tác chỉ reset cloud. File Markbook, bản sao lưu, PDF xuất và bản nháp trên thiết bị được giữ. App cần đồng bộ/nhận bản máy chủ để hiện danh sách rỗng; bản nháp cũ trên điện thoại có thể bỏ riêng qua **Xem bản nháp → Bỏ bản nháp này** trước khi nhập lại cùng Markbook.

## Lần reset tiếp theo ngày 13/11/2026

Thực hiện lại theo yêu cầu người dùng sau bản Android `1.0.2+3`: xóa 10 lớp, 1 phiên điểm danh và 201 tài liệu con (buổi học/check-in), tổng cộng 212 document. Hai workspace Final và năm workspace cũ được làm rỗng, tăng revision. Đã lưu snapshot phục hồi riêng ngoài repository trước khi ghi.

Kiểm kê độc lập sau reset xác nhận `classes`, `attendanceSessions`, `attendanceRequests`, `announcements`, `reportMetadata` đều không còn document dữ liệu; các đường dẫn con buổi học/check-in cũng rỗng. Đối chiếu SHA-256 nội dung các collection được bảo vệ trước/sau khớp hoàn toàn: giữ nguyên 3 hồ sơ `users`, 2 hồ sơ `teacherDirectory`, 1 `teacherAudit` và 1 `system`. Các document gốc `teachers` không có fields; năm workspace legacy bên dưới đã được reset theo phạm vi lớp. Không gọi API thay đổi Authentication.

Chỉ reset dữ liệu trên Firebase; không xóa file hay bản nháp trên thiết bị. Sau khi mở app, đồng bộ/nhận bản máy chủ và bỏ các bản nháp cũ trước khi nhập lại cùng Markbook.
