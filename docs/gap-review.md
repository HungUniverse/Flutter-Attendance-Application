# Tiến độ chuyển Firebase Final

## Phạm vi đang triển khai

Android giảng viên dùng Firebase Auth và Firestore trực tiếp. Web sinh viên dùng Google Sign-In, chỉ check-in cho tài khoản có email đã xác minh trong roster. Dữ liệu Lab 3 giữ nguyên để đối chiếu và phục hồi.

## Phạm vi đã xác nhận

Người dùng chọn Android và web check-in trước, chuyển cả Windows sang Firebase, sau đó yêu cầu triển khai tiếp web quản lý. Theo đính chính tiếp theo, `/admin` dành cho chủ hệ thống quản lý giảng viên; `/teacher` dành cho giảng viên quản lý lớp, hàng chờ, dashboard và thông báo. Admin có CRUD hồ sơ và khóa/mở lại quyền giảng viên, kèm lịch sử. Project là `fap-attendance-71655`. Admin ban đầu được cấp và đọc lại để xác minh theo email chủ hệ thống cung cấp riêng; tài khoản test cũ giữ vai trò giảng viên.

## Còn cần bổ sung

- Tài khoản Google sinh viên demo có thể đăng nhập thực tế.
- Quota AI để lấy ba phản hồi thành công. Project hiện trả HTTP 429 do hết credit trả trước.
- Ba lượt trên Android/web đã triển khai, ảnh trình duyệt và video demo.
- Mã số nộp bài, đề gốc, video và minh chứng ARTEMIS thực tế.

## Điều kiện nghiệm thu

- Chạy Rules trên Emulator, có ca cho phép và từ chối cho từng collection.
- Android đăng nhập, import, ghi thủ công, mở lại, chốt, sửa có lý do và xuất PDF.
- Web check-in hợp lệ, trùng, ngoài lớp, hết hạn, đã đóng và tranh chấp lúc đóng.
- Đo ba lượt đồng bộ trên hệ thống triển khai bằng tài khoản demo.
- AI dùng dữ liệu tổng hợp, có thể sửa và xác nhận, lỗi AI vẫn chốt được.
- Ghi rõ phần kiểm chứng tự động và phần cần thiết bị, tài khoản hoặc thao tác thực tế.

Mỗi thay đổi được commit nhỏ trên `main` theo yêu cầu trực tiếp của người dùng. Hoàn thành triển khai và triển khai lên Firebase được ghi nhận riêng.
