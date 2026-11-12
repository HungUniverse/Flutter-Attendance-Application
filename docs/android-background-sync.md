# Đồng bộ nền Android

## Bản sửa ngày 13/11/2026

Trước đây timer 10 giây và listener check-in gọi cùng bộ xử lý với thao tác người dùng. Dù có cờ `quiet`, bộ xử lý vẫn bật `busy`, hiện thanh tải và vô hiệu hóa nút. Mỗi lần đồng bộ còn đọc lại mọi lớp/buổi từ Firestore rồi ghi lại snapshot và các tệp lớp xuống thiết bị.

Bản sửa tách trạng thái chờ của thao tác người dùng khỏi tác vụ nền:

- Timer và listener không bật `busy`. Các thao tác sửa vẫn được xếp sau tác vụ đang chạy để tránh ghi đè snapshot mới; một thao tác ghi được người dùng bấm có thể phải đợi lượt đồng bộ đang chạy kết thúc.
- Không xếp chồng các lượt tự đồng bộ. Khi app rời foreground, timer/listener không khởi chạy lượt mới; lượt đã bắt đầu có thể tiếp tục hoàn tất. Khi trở lại, app làm mới nền thay vì bật trạng thái chờ của thao tác người dùng.
- Firestore vẫn đọc quyền giảng viên và revision trên máy chủ. Nếu cùng UID, workspace và revision, tái sử dụng snapshot trong bộ nhớ, không truy vấn lại toàn bộ lớp/buổi. Sau ghi thành công, cache được cập nhật theo revision đã xác nhận.
- Đồng bộ local bỏ qua việc ghi lại workspace khi revision không đổi và không còn pending. Hàng đợi pending vẫn được đẩy trước bước kiểm tra này. Trạng thái đồng bộ không đổi không phát thêm thông báo UI.
- Chỉ tìm phiên để khôi phục khi chưa có handle và workspace có buổi đang hoạt động. Hộp thư tự làm mới tối đa một lần/phút khi thành công; bấm tải lại thủ công vẫn lấy mới ngay.

Lần tải đầu, dữ liệu thay đổi từ thiết bị khác và thao tác lưu vẫn cần mạng/đọc ghi tương ứng. Bản sửa không bỏ kiểm tra quyền, revision hoặc lượt check-in cuối khi chốt.

## Phạm vi kiểm chứng

Đã pull code mới nhất trước khi sửa, mốc `8d2f45a`. `flutter analyze` trên bốn tệp thay đổi không có lỗi. Không chạy thêm test theo yêu cầu trước đó của người dùng. Chưa đo hiệu năng hoặc xác nhận trải nghiệm trên điện thoại thật trong lượt này.

Build APK debug với App Check demo như hướng dẫn [FINAL_SETUP.md](FINAL_SETUP.md). Sau khi build thành công, APK nằm ở `build/app/outputs/flutter-apk/app-debug.apk`; cài cập nhật bản này để nhận thay đổi, APK cũ không tự cập nhật từ GitHub.
