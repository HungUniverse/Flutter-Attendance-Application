# Định dạng Markbook giảng viên

Áp dụng từ 13/11/2026, theo file Markbook người dùng cung cấp và quy tắc lịch đã xác nhận. File gốc và roster thật được giữ trên máy, không thêm vào commit mã nguồn.

## Sheet và cột

Tên sheet có dạng `11_PRN232_SE1917`: hai chữ số đầu là mã lịch, tiếp theo là mã môn và mã lớp. Mã lớp trong tên sheet phải khớp cột `Class`.

| Cột nguồn | Dữ liệu ứng dụng |
| --- | --- |
| `Class` | Mã lớp |
| `RollNumber` | MSSV, chuẩn hóa chữ hoa |
| `Email` | Email đăng nhập Google, chuẩn hóa chữ thường |
| `MemberCode` | Mã thành viên, giữ giá trị nguồn |
| `FullName` | Họ tên |

Các cột `ExamDate`, `ExamNote`, điểm thi, bài tập, project và comment không được chuyển thành điểm danh. Các dòng chỉ có điểm/công thức, không có danh tính sinh viên, được bỏ qua. Tên file như `FA26_Markbook.ods` tự gợi ý học kỳ `FA26`.

## Quy tắc lịch FA26

Mốc mặc định **07/09/2026**, không lấy `ExamDate` làm ngày bắt đầu học kỳ.

| Chữ số đầu | Cặp ngày | Buổi đầu từ mốc |
| --- | --- | --- |
| 1 | Thứ 2 + Thứ 5 | 07/09/2026 |
| 2 | Thứ 3 + Thứ 6 | 08/09/2026 |
| 3 | Thứ 4 + Thứ 7 | 09/09/2026 |

| Chữ số thứ hai | Giờ học |
| --- | --- |
| 1 | 07:30–09:15 |
| 2 | 09:30–11:45 |
| 3 | 12:30–14:45 |
| 4 | 15:00–17:15 |

Người dùng chọn số tuần và 1 hoặc 2 buổi/tuần. Với 1 buổi/tuần, dùng ngày đầu của cặp. Slot 1 đã đổi từ 07:00 sang 07:30 trong core Android/Windows và bộ sinh lịch web. ID lớp trên web được thống nhất theo `${semester}_${courseCode}_${classCode}` như importer native, tránh tạo bản trùng giữa thiết bị.

## Cách nhập

- Android: chọn Markbook ODS/XLSX, xem các lớp/số sinh viên và học kỳ tự nhận, kiểm tra ngày bắt đầu/số tuần rồi xác nhận nạp. Bản xem trước lấy lịch, môn và lớp từ tên sheet.
- Windows: chọn Markbook rồi cấu hình học kỳ. Form nhận mã học kỳ từ tên file, hiển thị các cột nguồn; mốc FA26 mặc định 07/09/2026.
- Web giảng viên: `/teacher#classes` → **Nạp Markbook** → chọn file → chọn các sheet trong bản xem trước → kiểm tra lịch và xác nhận. Mỗi lớp ghi bằng transaction riêng; lỗi giữa chừng báo số lớp đã lưu. Có thể nhập lại để cập nhật các lớp đã có, giữ lịch sử. Web giữ tối đa 200 sinh viên/lớp. `/admin` dành cho chủ hệ thống quản lý giảng viên.
- Form web thủ công dùng `Class | RollNumber | Email | MemberCode | FullName`; hỗ trợ dán năm cột từ Excel và bỏ qua cột điểm phía sau. Định dạng ba cột cũ vẫn đọc được để tương thích, nhưng không còn là mẫu nhập chính.

## Reset dữ liệu lớp trên Firebase

Đã thực hiện theo yêu cầu trên `fap-attendance-71655`: xóa **10 lớp, 200 buổi học, 1 phiên điểm danh**. Các collection yêu cầu, thông báo và metadata báo cáo khi reset không có document. Một workspace Final được đặt `layout` rỗng và tăng revision; năm workspace Lab 3 được đặt danh sách lớp rỗng và tăng revision. Hai hồ sơ người dùng, Authentication và cấu hình Firebase được giữ lại.

Đã lưu snapshot riêng ngoài repo trước khi xóa. Script `firebase/reset-classes.mjs` mặc định chỉ kiểm kê; thao tác xóa yêu cầu `--apply` cùng đường dẫn backup tuyệt đối và không ghi đè backup đang tồn tại.

Ứng dụng còn pending trước reset có thể hiển thị xung đột: chọn **Nhận bản máy chủ** để nhận danh sách rỗng. Không chọn giữ rồi nhập lại bản cũ nếu mục đích là bắt đầu từ Markbook mới. Không tự động nạp roster thật lên Firebase trong lượt sửa này; giảng viên chủ động chọn file và xác nhận.

## Kiểm chứng

Đã đọc cấu trúc XML của file gốc để đối chiếu sheet và cột. Không chạy thêm test theo yêu cầu trước đó. Kiểm tra mã tĩnh và build dùng mã nguồn mới; giao diện trên thiết bị và Google thật vẫn cần xác nhận riêng.
