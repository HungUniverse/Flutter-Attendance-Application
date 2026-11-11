# Lab 3 - Kiểm tra trước khi nộp

Không phải kết quả đã chạy. Chỉ chuyển sang Pass khi có thiết bị, build, thời
điểm, ảnh/log và giá trị quan sát được. Mỗi ca ARTEMIS cần ít nhất ba lượt riêng.

| ID | Điều kiện / thao tác | Kết quả mong đợi | Lượt 1 / 2 / 3 |
| --- | --- | --- | --- |
| A01 | Android có Firebase; đăng nhập Google | Đúng tài khoản, vào workspace; Console Users có UID | Not run / Not run / Not run |
| A02 | Hủy Google Sign-In, thử Back | Ở màn đăng nhập; không mở màn dữ liệu | Not run / Not run / Not run |
| A03 | Chọn markbook hợp lệ; xem trước rồi import | Đúng lớp/sĩ số/lịch; file còn sau restart | Not run / Not run / Not run |
| A04 | Import lại cùng học kỳ | Giữ lịch sử, lịch riêng; không xóa sinh viên vắng trong tệp mới | Not run / Not run / Not run |
| A05 | Thủ công P/A, chuyển mode và offline | Tổng đúng, chưa chọn không thành A, dữ liệu không reset | Not run / Not run / Not run |
| A06 | Tạo link; Android share sheet; SV gửi từ thiết bị khác | Chia sẻ đúng link; chỉ ghi sau gửi, gửi lặp không tăng | Not run / Not run / Not run |
| A07 | SV không thuộc lớp / hết 2 phút / sau dừng nhận | Bị từ chối đúng nguyên nhân; không thêm P | Not run / Not run / Not run |
| A08 | Hủy xác nhận chốt, sau đó chốt | Hủy không đổi; chốt nhập đủ lượt cuối, ô thiếu thành A | Not run / Not run / Not run |
| A09 | Sửa với lý do trống; sau đó lý do hợp lệ | Giữ sheet khi lỗi; lưu trước/sau, lý do và tổng đúng | Not run / Not run / Not run |
| A10 | Xuất JSON/CSV; chia sẻ file | Đúng lớp/buổi, đủ P/A, tên/đuôi/nội dung đúng | Not run / Not run / Not run |
| A11 | Upload Storage; mất mạng hoặc tài khoản khác | Có progress/URL; rules chặn truy cập trái phép; local còn | Not run / Not run / Not run |
| A12 | FCM khi foreground/background/terminated, chạm | Inbox không trùng; đến đúng màn và có auth guard | Not run / Not run / Not run |
| A13 | Từ chối quyền thông báo | App vẫn dùng được; có trạng thái và cách thử lại | Not run / Not run / Not run |
| A14 | Remote Config đổi hai giá trị, refresh, thử offline | Hành vi/UI đổi không build; cache/default hoạt động | Not run / Not run / Not run |

Tách A12 thành các ca riêng khi viết kịch bản ARTEMIS. Kiểm thử Analytics lỗi qua
fake service không thay cho ảnh DebugView thật; từng event trong analytics-plan.md
phải có bằng chứng. Với Crashlytics cần non-fatal + native test crash + UID/key
trên Console, ngoài các ca trên.

## Nhật ký mỗi lượt

- Test ID, lần chạy, build/commit, thiết bị/API Android, tài khoản thử ẩn danh.
- Điều kiện đầu, dữ liệu giả, thao tác, kết quả thực tế, Pass/Fail/Blocked.
- Đường dẫn ảnh/log, lỗi phát hiện, commit sửa và kết quả retest.
- Chưa có đúng bản ARTEMIS do GV chỉ định thì ghi Blocked/Not run, không thay
  lượt widget test thành lượt ARTEMIS.

## Kiểm thử khám phá và review

- Khám phá 15–30 phút: ghi thời gian, phạm vi, vấn đề và retest. Chưa thực hiện.
- PR review: ít nhất 5 phát hiện ở file/dòng, ít nhất 2 nhóm; giải thích quyết
  định từng phát hiện và sửa ít nhất 3 mục chấp nhận có commit. Chưa tạo PR.
- Đối chiếu quyền mở GitHub, báo cáo PDF 8–12 trang, slide PDF 12–15 trang và
  video 5–10 phút sau khi có bằng chứng chạy thật.
