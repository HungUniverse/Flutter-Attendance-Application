# Bản nháp điểm danh Android và thời hạn link

## Chọn P/A và chốt

Từ bản **1.0.1+2**, bấm P/A cho buổi đang mở cập nhật ngay trong bộ nhớ. Có thể đổi qua lại trước chốt mà không nhập lý do; app không bật `busy`, không chờ Firestore và không hiện snackbar thành công sau mỗi lần chọn.

Các lựa chọn được ghi nối tiếp, thay tệp nguyên tử tại `FAP Attendance Mobile/teachers/{uid}/attendance-drafts.json`. Mỗi nhóm có học kỳ, ID lớp/buổi, thời điểm bắt đầu và các lựa chọn theo MSSV. Journal này tách khỏi workspace và outbox đồng bộ, giữ bản nháp của nhiều học kỳ riêng biệt theo tài khoản. App nạp lại khi đăng nhập/mở ứng dụng. Nếu không ghi được tệp, app cảnh báo rõ; các lựa chọn trong bộ nhớ vẫn còn.

Workspace hiển thị là bản đã đồng bộ cộng bản nháp hợp lệ cho buổi đang mở. Tự đồng bộ, nhận bản máy chủ và nhập lượt qua link không xóa lựa chọn thủ công. Khi lưu các thay đổi khác, app gỡ lựa chọn nháp khỏi snapshot gửi đi, nên timer và check-in không vô tình đẩy P/A thủ công lên cloud trước chốt.

Khi **Chốt danh sách**, app dừng link và nhập đủ check-in nếu có, giữ lựa chọn thủ công, điền A cho người chưa ghi, rồi lưu kết quả đã chốt. Sau khi workspace/outbox đã lưu, journal của buổi đó được dọn. Đồng bộ thất bại được báo là chốt trên máy/chưa xác nhận Firebase. Buổi quá ngày vẫn theo quy tắc tự chốt hiện có.

Nếu máy chủ đã chốt buổi, xóa lớp hoặc thay ngày học, bản nháp không tự ghi đè kết quả đã chốt. Khóa journal bao gồm cả thời điểm bắt đầu để không trộn lựa chọn khi ID buổi được tái sử dụng. Journal được giữ để xem qua **Xem bản nháp**; áp dụng lại kết quả qua Lịch sử cần lý do chỉnh sửa. Có thể **Bỏ bản nháp này** sau khi xác nhận, không thay kết quả trên cloud. Sau chốt, việc sửa kết quả vẫn gửi theo luồng audit cũ. Giảng viên khác không thấy lựa chọn thủ công đang là bản nháp trên thiết bị này.

Thay đổi bản nháp áp dụng cho app Android/TeacherViewModel. Bảng điểm danh Windows dùng AttendanceController riêng, chưa chuyển sang thao tác nháp trong đợt này.

## Tạo link theo giờ Firebase

Code cũ lấy `DateTime.now() + 2 phút` trên điện thoại làm hạn gửi lên Firestore. Rules kiểm tra hạn này bằng `request.time`, nên đồng hồ điện thoại chạy nhanh có thể làm request bị từ chối.

Luồng mới:

1. Transaction xác nhận buổi đã mở, tạo/cập nhật phiên ở trạng thái **dừng nhận**, dùng `serverTimestamp` làm mốc và một `openingId` riêng cho lần mở.
2. Đọc lại mốc đã được Firebase xác nhận, tính hạn hai phút từ mốc đó và giới hạn trong ngày học.
3. Transaction thứ hai kiểm tra phiên chưa bị thiết bị khác thay đổi/dừng, rồi bật nhận. Lượt check-in cũ được giữ; URL vẫn xác định theo lớp/buổi.

Rules không cho sinh viên gửi trong giai đoạn chuẩn bị. Hạn mở phiên vẫn không vượt quá hai phút theo giờ máy chủ. Android hiển thị trạng thái link bằng giờ đã hiệu chỉnh từ mốc Firebase. Nếu bị gián đoạn giữa hai giai đoạn, phiên vẫn dừng nhận và có thể tạo lại.

Thông báo lỗi Firebase hiện kèm mã như `permission-denied`, `unavailable`, `deadline-exceeded`. Crashlytics ghi riêng mã/plugin; không ghi token, roster hoặc toàn bộ nội dung request.

## Giới hạn xác minh

Đã đọc trạng thái production để xác nhận quyền giảng viên và buổi đang active; tại thời điểm kiểm tra chưa có document phiên. Không lấy được log từ điện thoại vì chưa có thiết bị ADB kết nối, nên chưa kết luận thông báo chung trước đó chỉ có một nguyên nhân. Thay đổi loại bỏ phụ thuộc giờ điện thoại và cung cấp mã lỗi để chẩn đoán nếu còn trường hợp khác.

Không chạy thêm test theo yêu cầu trước đó. Chạy phân tích mã tĩnh và build trước khi giao APK; trải nghiệm và luồng Google trên điện thoại thật chưa được kiểm chứng trong lượt sửa này.
