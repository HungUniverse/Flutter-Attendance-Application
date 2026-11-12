# Web admin và không gian giảng viên

Theo xác nhận mới của người dùng, **admin là chủ hệ thống quản lý giảng viên**. Vai trò `admin` được cấp riêng qua công cụ của chủ project. Vai trò giảng viên được quản lý bằng email Google trong `teacherDirectory`; giảng viên chỉ thao tác lớp của mình. Android, Windows và web dùng cùng Firestore và cùng quy tắc cấp/thu hồi quyền.

## Đường dẫn

- Admin hệ thống: https://fap-attendance-71655.web.app/admin
- Không gian giảng viên: https://fap-attendance-71655.web.app/teacher
- Hộp thư và yêu cầu sinh viên: https://fap-attendance-71655.web.app/student
- Check-in: `/join/{sessionId}`, giữ nguyên đường dẫn của QR trên ứng dụng.

## Admin quản lý giảng viên

- Đăng nhập Google, kiểm tra `users/{uid}.role == admin`. Người dùng thường và giảng viên không thể tự cấp quyền này.
- Thêm giảng viên bằng họ tên, email Google, mã giảng viên, bộ môn và trạng thái. Không cần biết UID trước, không tạo mật khẩu và không gửi email tự động. Khi tài khoản Google đó đăng nhập, Rules đối chiếu đúng email đã xác minh.
- Sửa hồ sơ, đổi email, tạm khóa/mở lại và xóa hồ sơ. Email là khóa duy nhất. Đổi email thu hồi quyền của email cũ; dữ liệu lớp không tự chuyển sang Firebase UID mới.
- Xóa hồ sơ thu hồi quyền giảng viên; giữ dữ liệu lớp để có thể cấp lại sau. Không xóa tài khoản Google hoặc Firebase Authentication. Dữ liệu đã lưu trên thiết bị không bị xóa từ xa.
- Xem tổng số giảng viên, số hoạt động/tạm khóa, tìm theo tên/email/mã/bộ môn và lọc trạng thái.
- Mỗi thay đổi được ghi cùng transaction vào `teacherAudit`; web chỉ đọc 50 sự kiện gần nhất. Các bản ghi audit không được sửa/xóa từ client. Biểu mẫu kiểm tra timestamp để tránh ghi đè thay đổi ở tab khác.

Danh mục giảng viên không cấp quyền admin. Công cụ bootstrap tạo admin trong `users`, đồng thời chuyển quyền giảng viên cũ sang danh mục **đúng một lần**; chạy lại công cụ không tự cấp lại quyền cho giảng viên đã bị xóa.

```powershell
node firebase/provision-admin.mjs administrator@gmail.com
```

Admin cũng được sử dụng không gian giảng viên cho dữ liệu thuộc chính UID của mình. Quyền này không mở việc đọc lớp của người khác qua cổng giảng viên.

## Chức năng không gian giảng viên

- Tổng quan có ba truy vấn `count()` phía Firestore: lớp chưa lưu trữ, yêu cầu chờ duyệt, metadata báo cáo. Các thẻ tính trên tất cả học kỳ của tài khoản. Biểu đồ P/A/chưa ghi tính từ buổi đang mở và đã chốt trong học kỳ được chọn; không tính buổi sắp diễn ra.
- Tạo lớp, sinh lịch theo nhóm và slot của core, xem danh sách và từng buổi, sửa mã lớp/môn và roster, lưu trữ lớp. **Nạp Markbook** hỗ trợ ODS/XLSX trực tiếp trên web, có bản xem trước và chọn sheet. Form thủ công dùng năm cột `Class | RollNumber | Email | MemberCode | FullName`, tối đa 200 sinh viên/lớp. Xem [mẫu Markbook và quy tắc lịch](markbook-format.md).
- Sửa roster không được bỏ MSSV đã có kết quả. Khi đã có buổi chốt, không thêm MSSV mới để tránh kết quả trống trong lịch sử. Lưu trữ giữ document và lịch sử; phải chốt buổi đang hoạt động trước. Giao diện chưa có khôi phục lớp đã lưu trữ.
- Hàng chờ yêu cầu của sinh viên: đọc kết quả hiện tại, duyệt hoặc từ chối với lý do bắt buộc. Duyệt cập nhật kết quả, audit, revision workspace, trạng thái yêu cầu và thông báo trong cùng transaction. Quyết định đã xử lý không được xử lý lại.
- Soạn thông báo cho toàn bộ email trong roster hoặc hộp thư giảng viên trên Android, có thể gắn một buổi. Thông báo lớp được gửi bằng một batch; sinh viên đọc tại `/student`. Đây là hộp thư Firestore, chưa gửi push FCM từ web.
- Có trạng thái tải, rỗng, lỗi, đổi tài khoản, chọn học kỳ, tìm lớp và lọc yêu cầu. Web cần mạng để ghi; không có outbox offline như app.

## Luồng yêu cầu sửa

1. Giảng viên dùng app bắt đầu buổi, mở link/QR, rồi chốt điểm danh.
2. Sinh viên mở lại link đó, chọn liên kết hộp thư/yêu cầu ở cuối trang. Trang `/student?session={id}` điền sẵn mã phiên.
3. Sinh viên đăng nhập Google và gửi P hoặc A khác kết quả hiện tại, kèm lý do. Rules kiểm tra email token thuộc roster, buổi đã chốt và phiên trỏ đúng lớp/buổi.
4. Giảng viên xem yêu cầu trên `/teacher#requests`, đối chiếu rồi duyệt hoặc từ chối. Chỉ một yêu cầu cho mỗi sinh viên trong mỗi lớp/buổi, kể cả khi có nhiều link phiên. Bản đã bị từ chối không được gửi lại qua web; liên hệ giảng viên nếu cần xem xét thêm.
5. Sinh viên thấy quyết định và phản hồi trong hộp thư. Android/Windows nhận kết quả khi đồng bộ workspace; bản local đang sửa phải giải quyết xung đột revision trước khi ghi tiếp.

## Cấu hình và triển khai

```powershell
npm ci --prefix web
node firebase/configure-web.mjs
npm run build --prefix web
node firebase/node_modules/firebase-tools/lib/bin/firebase.js deploy --project fap-attendance-71655 --only firestore,hosting --non-interactive
```

`configure-web.mjs` thêm và đọc lại `web_admin_announcements_enabled` và `web_admin_help_text` trong Remote Config, giữ giá trị đang có. Lỗi Remote Config/Analytics không ngăn thao tác dữ liệu. Analytics chỉ nhận tên màn, quyết định, đối tượng nhận và số đếm; không gửi roster, lý do hay nội dung thông báo.

Các kiểm thử đã thực hiện và giới hạn kiểm chứng được ghi trong [báo cáo kiểm thử](test-report.md). Tài khoản Google thật và hình ảnh trên trình duyệt/Android cần kiểm chứng riêng.
