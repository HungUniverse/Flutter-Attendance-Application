# Đồng bộ nền Android

## Check-in trực tiếp — Android 1.0.2+3

Đã cập nhật từ `origin/main` (`8dc8b70`) trước khi sửa. Tìm thấy một đường chờ trong Android: listener bỏ dữ liệu snapshot, đợi debounce/hàng đợi đồng bộ, đọc lại phiên rồi đọc lại check-in, sau đó ghi workspace trước khi báo màn hình. Một lượt check-in vì vậy có thể phải chờ nhiều lượt mạng và các thao tác đồng bộ đang chạy. Chưa có phép đo trên điện thoại để quy toàn bộ độ trễ hơn 5 giây người dùng gặp cho riêng nguyên nhân này.

Bản mới dùng trực tiếp snapshot phiên và danh sách check-in đã được máy chủ xác nhận. Màn hình nhận kết quả trong callback, không đợi timer 10 giây, hàng đợi workspace hoặc ghi toàn bộ học kỳ. Snapshot cache cũ và dữ liệu đang chờ xác nhận không được dùng để dựng lại kết quả trực tiếp sau reset/import.

- Check-in gốc vẫn lưu bền vững trong `attendanceSessions/{id}/checkIns`; bản hiển thị trong bộ nhớ được phủ lại khi workspace tải nền, nên không nhấp nháy mất P khi revision workspace chưa đổi.
- Kết quả đã công bố và lựa chọn P/A thủ công của giảng viên được ưu tiên. Bỏ bản nháp sẽ hiện lại check-in hợp lệ nếu có.
- Khi buổi còn mở, các bản hiển thị check-in không bị gửi kèm thao tác lưu workspace khác. Khi chốt, app vẫn dừng nhận trên máy chủ, đọc đủ check-in từ máy chủ rồi lưu kết quả cuối cùng.
- Bấm tải lại thủ công và chốt vẫn đọc trực tiếp máy chủ. Timer nền bỏ lượt poll check-in thừa khi stream đang hoạt động; nếu stream lỗi thì vẫn thử poll ở lượt nền tiếp theo.
- Đổi tài khoản, phiên, học kỳ hoặc buổi học sẽ loại bỏ callback/kết quả không còn phù hợp. Không có thay đổi schema hay Firestore Rules trong bản này.

Phạm vi tối ưu là luồng giảng viên Android. Windows vẫn dùng listener báo thay đổi và poll hiện có. Độ trễ mạng, thời gian gửi từ trình duyệt sinh viên và thời gian Firestore chuyển snapshot vẫn ảnh hưởng thời điểm hiển thị; chưa xác nhận thời gian cụ thể trên điện thoại thật. Không chạy test theo yêu cầu người dùng; hai tệp Dart thay đổi đã qua `flutter analyze` không có lỗi. APK debug `1.0.2+3` đã build thành công tại `build/app/outputs/flutter-apk/app-debug.apk`; cài cập nhật APK để dùng luồng mới.

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
