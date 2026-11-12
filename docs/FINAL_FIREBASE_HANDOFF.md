# FAP Attendance — Bàn giao chuyển sang Firebase cho PRM393 Final

Tài liệu này mô tả các thay đổi cần thực hiện trên repo Lab 3 `HungUniverse/Flutter-Attendance-Application`. Các mục bên dưới là kế hoạch triển khai và tiêu chí nghiệm thu. Đối chiếu đề **PRM393 — Final Assignment: One Complete System on Firebase**, mục 3–10 và checklist trang 8.

## 1. Phạm vi và người dùng

| Người dùng | Nơi thao tác | Nghiệp vụ |
| --- | --- | --- |
| **Giảng viên** | App Flutter Android | Nạp danh sách, cấu hình lịch, mở phiên qua link, ghi Có mặt/Vắng thủ công, chốt, xem lịch sử, sửa kết quả có lý do và xuất báo cáo. |
| **Sinh viên** | Trang check-in trên trình duyệt, mở qua QR hoặc link | Đăng nhập và xác nhận lượt điểm danh của chính mình. Sinh viên không sử dụng app Flutter giảng viên. |

Giữ hai nhóm người dùng trên. Phạm vi hiện tại chưa có Staff, giáo vụ hay quản trị viên nghiệp vụ. Desktop Windows là bản Lab 3 dành cho giảng viên để chiếu QR. Kiểm tra riêng với giảng viên hướng dẫn nếu cần đưa desktop vào bản Final. Nếu đưa vào demo Final, QR trên desktop phải trỏ đến phiên Firebase mới.

## 2. Hiện trạng và kiến trúc cần chuyển tới

- **Hiện trạng** — Android đồng bộ học kỳ và kết quả qua Node.js trên Render. Backend đọc/ghi Firestore bằng Admin SDK. Phiên link/QR và lượt gửi sinh viên do backend xử lý. Android có tùy chọn sao lưu báo cáo lên Cloud Storage.
- **Bản Final** — Android và các trang web dùng Firebase Authentication và cùng một Firestore. Ứng dụng đọc/ghi qua Firebase SDK. Security Rules kiểm tra danh tính, quyền và trạng thái. Firebase Hosting phục vụ trang check-in và web quản lý khi phạm vi web được chốt.
- **Phần tái sử dụng** — Google Sign-In trên Android, màn hình, ViewModel, bộ nạp ODS/XLSX, quy tắc lịch và điểm danh, xuất tệp, Analytics, Remote Config và Crashlytics. Đối chiếu màn S01–S10 trong [bảng thiết kế Lab 3](design-traceability.md).
- **Phụ thuộc cần gỡ khỏi bản Final** — API Node.js/Render, URL tunnel và tùy chọn upload Cloud Storage. Node.js vẫn có thể dùng để chạy Firebase CLI và kiểm thử Rules. Giữ dự án Lab 3 làm mốc đối chiếu trong thời gian chuyển đổi.

## 3. Những chỗ cần sửa trong repo

| Khu vực hiện tại | Thay đổi cần thực hiện |
| --- | --- |
| [mobile_bootstrap.dart](../lib/lab3/mobile_bootstrap.dart), [shared_workspace_sync.dart](../lib/data/shared_workspace_sync.dart), [contracts.dart](../lib/lab3/services/contracts.dart) | Tạo lớp đọc/ghi Firestore cho Final và truyền vào ViewModel. Thay `SharedApi` và cấu hình `ATTENDANCE_API_URL` trong luồng Android Final. Giữ xử lý trạng thái tải, rỗng, lỗi và báo rõ khi ghi chưa đồng bộ. |
| [models.dart](../lib/domain/models.dart), [attendance_service.dart](../lib/domain/attendance_service.dart) | Tái sử dụng model và nghiệp vụ phù hợp. Đưa phần dùng chung cho Android và web vào `packages/core/`. Giữ ràng buộc lịch, ưu tiên điểm danh thủ công, quy tắc chốt và lý do khi sửa. |
| [attendance_link_service.dart](../lib/lab3/services/attendance_link_service.dart), [relay.mjs](../backend/relay.mjs), [student.html](../backend/student.html) | Thay lớp gọi HTTP bằng lớp quản lý phiên trên Firestore. Chuyển trang sinh viên sang Hosting và thay các request `/api/join/...` bằng Firebase SDK. Dùng backend cũ để đối chiếu các ca hết hạn, gửi trùng và dừng nhận. |
| [firestore.rules](../firebase/firestore.rules) | Rules Lab 3 đang từ chối mọi truy cập trực tiếp từ app. Viết Rules mới cho các collection của Final và chạy kiểm thử Emulator trước khi publish. |
| [firebase_services.dart](../lib/lab3/services/firebase_services.dart), [attendance_screens.dart](../lib/lab3/ui/attendance_screens.dart) | Gỡ lựa chọn sao lưu Storage khỏi Android Final. Thêm xuất, lưu và chia sẻ **PDF trên thiết bị**. Ghi metadata báo cáo lên Firestore. Duy trì JSON/CSV nếu các luồng Lab 3 còn dùng các định dạng đó. |
| Màn Thông báo, cấu hình và theo dõi lỗi | Nối hộp thư với Firestore. Duy trì Remote Config và Analytics trên Android, tích hợp vào web quản lý theo yêu cầu đề. Giữ Crashlytics trên Android. |

## 4. Mô hình dữ liệu và kiểm soát quyền

Các đường dẫn dưới đây là **đề xuất để nhóm chốt trong `docs/data-model.md`**. Tài liệu phải ghi trường, kiểu, quyền CRUD, màn sử dụng và các chuyển trạng thái hợp lệ.

| Dữ liệu | Đường dẫn đề xuất | Quyền chính |
| --- | --- | --- |
| Hồ sơ và vai trò | `users/{uid}` | Kiểm tra vai trò từ Firestore. Người dùng thường không tự gán quyền giảng viên hoặc sửa vai trò của chính mình. Thống nhất cơ chế khởi tạo tài khoản đặc quyền theo mục 6 của đề. |
| Lớp, danh sách, buổi học | `classes/{classId}`, `members/{memberId}` và `meetings/{meetingId}` dưới lớp | Giảng viên chỉ truy cập lớp được giao. Sinh viên chỉ có quyền check-in theo thông tin thành viên đã xác minh. |
| Phiên và lượt check-in | `attendanceSessions/{sessionId}/checkIns/{studentUid}` | Giảng viên mở và đóng phiên của lớp mình. Sinh viên chỉ được tạo lượt của chính mình trong phiên còn mở và còn hạn. |
| Kết quả và chỉnh sửa | Bản ghi theo buổi và sinh viên, kèm nhật ký sửa | Giảng viên có quyền ghi trong lớp phụ trách. Khi chỉnh buổi đã chốt, lưu lý do và lịch sử. Lượt check-in không ghi đè lựa chọn thủ công. |
| Hộp thư và báo cáo | `announcements/{id}`, `reportMetadata/{id}` | Hộp thư chỉ hiển thị thông báo đúng đối tượng. Metadata báo cáo thuộc giảng viên/lớp tương ứng. |

Kiểm tra quyền ở Rules, kể cả khi app đã ẩn nút hoặc chặn màn hình. Rules mặc định từ chối, kiểm tra kiểu và trường dữ liệu, quyền sở hữu, trạng thái buổi và thời hạn bằng thời gian máy chủ. Sinh viên không được đọc toàn bộ roster hoặc kết quả của người khác. Liên kết tài khoản Google đã xác minh với roster, không dựa vào MSSV hoặc email tự nhập để cấp quyền. Bật App Check cho Firestore và AI Logic khi triển khai Final.

## 5. Luồng check-in và các ca cần giữ

1. Giảng viên mở phiên cho buổi đang học. App tạo mã phiên và URL Hosting dạng `/join/<sessionId>`. Có thể biểu diễn cùng URL bằng QR.
2. Sinh viên mở URL, đăng nhập Google và xác nhận. Rules chỉ cho tài khoản đúng lớp tạo một bản ghi có ID là UID của chính mình. Trang check-in hiển thị rõ thành công, đã gửi, không thuộc lớp hoặc phiên đã đóng/hết hạn.
3. App giảng viên theo dõi lượt gửi theo thời gian thực. Khi chốt, bảo toàn Có mặt/Vắng đã ghi thủ công và chuyển các bản ghi còn Chưa ghi thành Vắng theo nghiệp vụ hiện có. Kiểm thử lượt check-in đến sát thời điểm đóng để số đếm và kết quả đã chốt khớp nhau.
4. Kiểm thử cả **Tạo link → check-in → dừng nhận** và **Thủ công → chốt → sửa có lý do → xuất tệp**. Đối chiếu mã xác nhận xoay vòng và thời hạn xác nhận của QR desktop Lab 3 nếu desktop/QR nâng cao được yêu cầu trong Final.

## 6. Các mục cần chốt với giảng viên hướng dẫn

- **Web quản lý** — Đề có hạng mục web admin riêng gồm đăng nhập Google, quản lý một loại dữ liệu, hàng chờ duyệt, dashboard và form thông báo. Nếu Lab 2 chỉ có một vai trò, đề yêu cầu thống nhất vai trò web với giảng viên. Đề xuất web quản lý cho **chính Giảng viên**, trang check-in riêng cho **Sinh viên**. Chốt bằng văn bản cách áp dụng hàng chờ duyệt, form thông báo và cơ chế quyền Admin trong phạm vi sản phẩm này.
- **Luồng liên vai trò** — Đề xuất trình diễn **Sinh viên check-in trên web → Giảng viên thấy lượt gửi trên Android → Giảng viên chốt buổi**. Xác nhận giảng viên chấp nhận luồng này và cách chứng minh phần duyệt trên web. Ghi từng bước, dữ liệu ghi, Rules tương ứng và thời gian cập nhật đo được trong `docs/cross-role-flow.md`.
- **Phạm vi triển khai song song** — Có thể làm Firestore, Android và trang check-in ngay. Khi phương án web được duyệt, triển khai màn quản lý với loading/empty/error, dashboard có ít nhất ba số liệu truy vấn tổng hợp và một biểu đồ, rồi đưa web lên Hosting.

## 7. AI, kiểm thử và hồ sơ Final

- **AI đề xuất** — Trước khi chốt, dùng Firebase AI Logic để tạo gợi ý kiểm tra dạng JSON từ số lượng Có mặt/Vắng/Chưa ghi. Gắn nhãn kết quả AI, cho giảng viên sửa và xác nhận. Dùng Remote Config cho model, prompt và công tắc. Luồng vẫn chốt được khi AI tắt, mất mạng hoặc hết hạn mức. Chỉ gửi số liệu tổng hợp, giữ danh tính sinh viên ngoài đầu vào. Ghi `ai_request`, `ai_result_accepted`, `ai_error` và lưu ba cặp đầu vào/đầu ra thật cùng một ca lỗi trong `docs/ai-feature.md`.
- **Rules và tích hợp** — Chạy Emulator có ít nhất một ca cho phép và một ca từ chối cho mỗi vai trò trên từng collection. Chạy ba lượt luồng liên vai trò trên hệ thống đã triển khai, ghi kết quả thực tế và thời gian cập nhật. Kiểm tra app và web chạy khi Node.js/Render không tham gia.
- **ARTEMIS và web** — Chạy ba lượt mỗi ca cho mọi luồng Lab 2, các bước mobile trong luồng liên vai trò và luồng AI. Ghi pass rate và ảnh/log. Chụp thao tác chính của từng màn web, từ chối sai vai trò, trạng thái rỗng và lỗi. Chạy AI code review trên phần mã Final, ghi ít nhất ba nhận xét và quyết định trong `docs/test-report.md`.
- **Nộp bài** — Tiếp tục repo Lab 3 theo tên `PRM393_Final_<ID>` và cấu trúc đề yêu cầu. Bổ sung `mobile/`, `web/`, `packages/core/`, `firebase/`, `e2e_test/` và `evidence/`. README có URL web, vai trò, cách chạy, phiên bản, tài khoản demo theo vai trò, công cụ AI và link video. Chuẩn bị báo cáo PDF 10–15 trang, slide PDF 12–15 trang và video demo 8–12 phút. Kiểm tra các link nộp bằng cửa sổ ẩn danh.

## 8. Thứ tự thực hiện

1. Lập `docs/gap-review.md`, chốt mô hình dữ liệu và tài khoản demo. Dùng Emulator và dữ liệu mẫu để chuyển đổi. Sao lưu dữ liệu Lab 3 trước nếu cần nhập sang bản Final.
2. Làm mốc đầu tiên **Giảng viên đăng nhập → nạp một lớp → ghi điểm danh thủ công → mở lại thấy kết quả**. Kiểm chứng tài khoản ngoài lớp bị từ chối.
3. Thay luồng link/QR bằng Firebase Hosting và Firestore. Chạy các ca gửi hợp lệ, gửi trùng, ngoài lớp, hết hạn và phiên đã đóng.
4. Làm web quản lý theo phạm vi đã thống nhất. Nối hộp thư, luồng liên vai trò, PDF và AI. Sau khi kiểm thử mới chuyển bản demo sang cấu hình Final.
5. Chia PR theo phần việc của từng thành viên. Mỗi PR ghi tính năng, kết quả kiểm thử và link minh chứng do người thực hiện tạo.
