# Reset dữ liệu lớp ngày 13/11/2026

Đã reset dữ liệu lớp trên Firebase project `fap-attendance-71655` theo yêu cầu người dùng, giữ nguyên tài khoản và quyền.

- Xóa 20 lớp, 400 buổi học, 1 phiên điểm danh và 1 metadata báo cáo: tổng cộng 422 document.
- Xác minh các collection lớp, phiên, yêu cầu sửa, thông báo và metadata báo cáo đều rỗng; không còn buổi/lượt gửi trong các đường dẫn con đã kiểm kê.
- Hai workspace Final và năm workspace Lab 3 được làm rỗng danh sách lớp, tăng revision để ngăn outbox cũ ghi lại dữ liệu.
- Dấu kiểm tra nội dung trước/sau của `users`, `teacherDirectory`, `teacherAudit`, `system` và document gốc `teachers` khớp hoàn toàn: giữ 3 hồ sơ người dùng, 2 hồ sơ giảng viên và toàn bộ quyền/audit quản trị. Không gọi API sửa/xóa Authentication.
- Snapshot phục hồi trước khi reset được lưu riêng ngoài repo. Lô xóa đầu bị Firebase từ chối; đã chia nhỏ thành các lô 50 document và kiểm tra lại các đường dẫn con, sau đó hoàn tất reset.

Thao tác chỉ reset cloud. File Markbook, bản sao lưu, PDF xuất và bản nháp trên thiết bị được giữ. App cần đồng bộ/nhận bản máy chủ để hiện danh sách rỗng; bản nháp cũ trên điện thoại có thể bỏ riêng qua **Xem bản nháp → Bỏ bản nháp này** trước khi nhập lại cùng Markbook.
