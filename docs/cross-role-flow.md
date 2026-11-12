# Luồng liên vai trò Final

## Luồng đã triển khai

1. Giảng viên đăng nhập Google trên Android hoặc Windows. App kiểm tra hồ sơ giảng viên, đọc workspace thuộc UID đang đăng nhập.
2. Import ODS/XLSX tạo lớp và buổi trên Firestore trong transaction có revision. Mở buổi hôm nay chuyển trạng thái sang `active`.
3. Android tạo link, Windows chiếu QR cho cùng URL Hosting `/join/{sessionId}`. Phiên có thời hạn hai phút và có thể mở lại khi hết hạn.
4. Sinh viên đăng nhập Google trên web và bấm xác nhận. Rules đối chiếu token với roster, ghi đúng một document có ID là UID sinh viên và thời gian máy chủ.
5. Snapshot listener báo lượt mới cho app giảng viên. Model lấy bản server và áp dụng các lượt chưa có kết quả, giữ lựa chọn thủ công.
6. Chốt buổi dừng phiên, lấy lượt đã được nhận trước lúc dừng, sau đó chuyển ô trống thành A. Bản đã chốt lưu vào Firestore và trên thiết bị.
7. Sửa sau chốt cần lý do và audit. Xuất PDF trên máy, chia sẻ tệp và ghi metadata vào Firestore.

Rules tương ứng nằm ở `users`, `workspaces`, `classes`, `meetings`, `attendanceSessions`, `checkIns` và `reportMetadata`. Chi tiết schema và quyền ở [mô hình dữ liệu](data-model.md).

## Kiểm chứng tự động

`integration_test/firestore_flow_test.dart` chạy native Windows thật, gọi ViewModel và repository Final, kết hợp Firebase JavaScript SDK làm client sinh viên. Auth và Firestore nằm trên Emulator với project `demo-fap-final` và tài khoản tổng hợp `example.com`.

Mỗi lượt kiểm tra ghi thủ công A, gửi check-in cho cùng sinh viên, gửi cho sinh viên khác, gửi trùng, gửi ngoài lớp, chốt, gửi sau chốt, sửa có lý do, xuất PDF cùng metadata và tải lại kết quả bằng entry point Windows. Ca này cũng xác minh token App Check của project đã triển khai.

Kết quả từng lượt và số đo được sinh tại `build/final-previews/native-web-emulator-results.json`. Thời gian đo bắt đầu trước khi khởi chạy client JavaScript và kết thúc khi native nhận được số đếm mới, bao gồm khởi động tiến trình và đăng nhập emulator.

Lượt kiểm tra cuối ghi 672 ms, 706 ms và 549 ms. Bản lưu nằm trong [bằng chứng Emulator](../evidence/final/cross-role-emulator.json).

Ba lượt trên môi trường triển khai với Google thật, trình duyệt điện thoại và Android vẫn cần thực hiện khi thu video và bằng chứng Final. Số đo Emulator được ghi riêng trong báo cáo kiểm thử.
