# Minh chứng AI Code Review · PRM393 Lab 3

- [PR #2](https://github.com/HungUniverse/Flutter-Attendance-Application/pull/2) so sánh `codex/lab3-ai-review` với `main`.
- Công cụ review trên GitHub là CodeRabbit.
- [Lượt đầu](https://github.com/HungUniverse/Flutter-Attendance-Application/pull/2#issuecomment-6804560880) rà soát một tệp kiểm thử ở commit `3f3a57a` và không có nhận xét cần xử lý.
- [Lượt review mã ứng dụng](https://github.com/HungUniverse/Flutter-Attendance-Application/pull/2#pullrequestreview-5864220974) xem commit `72fa93f` và trả 3 nhận xét trực tiếp cùng 1 nhận xét bổ sung. Số dòng dưới đây thuộc commit được review.

| ID | Nhóm | File và dòng | Phát hiện của CodeRabbit | Quyết định và lý do | Commit sửa | Kiểm thử lại |
| --- | --- | --- | --- | --- | --- | --- |
| CR01 | Ổn định | `lib/lab3/viewmodels/teacher_view_model.dart:531` | Lỗi xóa tệp cache link có thể đưa app sang màn lỗi tải workspace. [Nhận xét](https://github.com/HungUniverse/Flutter-Attendance-Application/pull/2#discussion_r4542278882) | **Chấp nhận.** Lỗi dọn link được ghi riêng. Workspace đã tải vẫn dùng được và giao diện bỏ link của buổi đã chốt. | `cdc70ee` | Pass. Mô phỏng lỗi xóa tệp và xác nhận lớp vẫn mở, relay đã dừng và không hiển thị link cũ. |
| CR02 | Toàn vẹn dữ liệu | `lib/lab3/viewmodels/teacher_view_model.dart:531–533` | Xóa bản lưu khi relay còn nhận có thể để phiên cũ nhận lượt gửi hoặc chặn mở phiên khác. [Nhận xét](https://github.com/HungUniverse/Flutter-Attendance-Application/pull/2#discussion_r4542278886) | **Chấp nhận.** Android dừng nhận trên relay trước khi xóa bản lưu của link đang nhận. Nếu mất mạng, giữ thông tin phiên trên thiết bị để thử lại. | `cdc70ee` | Pass. Đồng bộ buổi đã chốt thì relay dừng và nạp được danh sách. Mô phỏng mất mạng rồi tải lại thành công khi có kết nối. |
| CR03 | Ổn định | `lib/lab3/viewmodels/teacher_view_model.dart:530–533` | Kết quả tải link đang chờ có thể khôi phục link cũ sau khi workspace đã tải lại. [Nhận xét](https://github.com/HungUniverse/Flutter-Attendance-Application/pull/2#discussion_r4542278891) | **Chấp nhận.** Kiểm tra phiên tải workspace và link hiện tại trước khi áp dụng kết quả. | `cdc70ee` | Pass. Giữ yêu cầu lấy link đang chờ, tải lại buổi đã chốt rồi trả kết quả cũ. Link, lịch sử và điểm danh vẫn giữ đúng trạng thái. |
| CR04 | Đọc dữ liệu | `lib/lab3/services/firebase_services.dart:289` | Đọc gộp có thể lỗi trước khi mã xử lý từng thông báo. Bot ghi nhận mục này là *Unverified finding* trong phần Additional comments. [Nhận xét bổ sung](https://github.com/HungUniverse/Flutter-Attendance-Application/pull/2#pullrequestreview-5864220974) | **Điều chỉnh.** Đối chiếu mã plugin Android trong bản khóa phụ thuộc và đổi sang đọc từng khóa. Lỗi đọc lịch sử vẫn được xử lý riêng với workspace. | `cdc70ee` | Pass trên dữ liệu mô phỏng. Giá trị sai kiểu và JSON hỏng được bỏ qua. Thông báo hợp lệ vẫn đọc được đúng thứ tự. |

Kiểm tra commit sửa bằng `flutter analyze --no-pub` và `flutter test --no-pub`. Analyzer không báo lỗi. Kết quả Flutter là 67 bài đạt và 1 bài bỏ qua. Các bài test dùng kho tệp tạm và dịch vụ mô phỏng.

Hiện có 3 phát hiện gắn trực tiếp với dòng mã đã sửa và 1 nhận xét bổ sung. Mục tiêu 5 phát hiện vẫn còn thiếu ít nhất 1 phát hiện thực tế.
