# Design brief — FAP Attendance Mobile

Tài liệu mô tả phạm vi sản phẩm, bố cục màn hình, quy tắc tương tác và yêu cầu bàn giao thiết kế.

## Sản phẩm và phạm vi

FAP Attendance Mobile hỗ trợ giảng viên Trường Đại học FPT quản lý lịch lớp, điểm danh và xuất kết quả trên điện thoại Android.

Phạm vi Lab 2 gồm thiết kế UI/UX, prototype tương tác và handoff. Prototype mô phỏng các thao tác và phản hồi của hệ thống.

Người dùng và tiêu chí thành công ở [persona](../ux/persona.md); các sơ đồ ở [user flow](../ux/user-flow.md).

### Nhu cầu P01 và lựa chọn thiết kế

P01 là **proto-persona giả định**: giảng viên quản lý nhiều lớp, thao tác nhanh trên điện thoại và có thể gặp mạng yếu. Các nhu cầu liên kết với [ma trận truy vết](../ux/traceability.md).

| Nhu cầu của giảng viên | Đáp ứng trong thiết kế | Màn hình / truy vết |
| --- | --- | --- |
| Chọn đúng lớp và slot để tránh ghi nhầm | Đặt môn, lớp, ngày và khung giờ ở đầu màn; Back giữ lớp/slot nguồn | S02, S04, S08; N01 |
| Điểm danh thuận tiện trên điện thoại | Hai mode dùng chung kết quả: tạo link cho sinh viên tự điểm danh hoặc chọn Present/Absent thủ công | S04, S06; N02 |
| Tránh chốt nhầm, hiểu hậu quả trước khi xác nhận | Xác nhận nêu số Present, Absent và số chưa ghi nhận sẽ chuyển thành Absent; Hủy để tiếp tục điểm danh | S04, S06; N06 |
| Sửa sai có thể giải thích và truy vết | Lý do mới bắt buộc; tách Xem ghi chú và Sửa P/A; lưu trước/sau và cập nhật tổng liên quan | S07, S08; N05 |
| Biết kết quả đã lưu ở đâu khi mạng yếu | Local mặc định, báo cáo sao lưu Firebase Storage; tách trạng thái đã lưu trên thiết bị với đang tải/lỗi tải lên | S09, S10; N04 |

Màn hình nhỏ và thao tác nhanh là ràng buộc xuyên suốt: chữ đọc được, vùng chạm đủ lớn, tên dài xuống dòng, form cuộn khi bàn phím mở (N02).

### Trong phạm vi

- Mở workspace, import/cập nhật ODS/XLSX, cấu hình học kỳ.
- S02 có Danh sách lớp và thời khóa biểu tuần dạng ô, bấm đúng lớp/meeting.
- Roster theo slot, thống kê P/A và tỷ lệ vắng.
- Cấu hình số tuần, một/hai slot mỗi tuần, nghỉ và học bù trước khi lớp bắt đầu điểm danh.
- Điểm danh qua link: tạo và chia sẻ link để sinh viên mở trang điểm danh theo luồng cũ.
- Điểm danh thủ công: giảng viên chọn Present hoặc Absent cho từng sinh viên trong danh sách.
- Theo dõi kết quả và xác nhận chốt chung cho cả hai mode.
- Lịch sử lớp, chi tiết sinh viên, sửa có lý do và ghi chú.
- JSON dành cho extension desktop hoặc CSV trao đổi, một lớp/một slot đã chốt đủ P/A; file local-first và sao lưu Firebase Storage.
- Quản lý/xóa lớp với xác nhận.

Giảng viên dùng desktop hiển thị QR trên lớp; mobile dùng xem nhanh và điểm danh dự phòng qua link hoặc thủ công. Hai app dùng cùng tài khoản Firebase và đồng bộ dữ liệu qua backend/Firestore, có bản trên thiết bị khi mất mạng và cảnh báo xung đột. Báo cáo JSON/CSV sao lưu Firebase Storage. Bộ thiết kế gồm 10 màn hình mobile dành cho giảng viên.

### Tổ chức giao diện mobile

Chi tiết sinh viên, lịch sử lớp, xuất kết quả và Thông báo là các màn độc lập. Lịch tuần giữ nhãn khung giờ khi cuộn ngang để dễ đối chiếu.

Màn import có phần tóm tắt dữ liệu trước khi xác nhận. Các trạng thái lỗi và lưu giữ lại dữ liệu nhập cùng ngữ cảnh thao tác.

## Màn hình và điều hướng

| ID | Màn hình | Nội dung / hành động chính |
| --- | --- | --- |
| S01 | Bắt đầu workspace | Tài khoản giảng viên, chọn markbook để bắt đầu |
| S02 | Danh sách lớp / thời khóa biểu tuần | Hai chế độ; mọi lớp, ngày × khung giờ; bấm đúng lớp/meeting |
| S03 | Import markbook | File, học kỳ, ngày bắt đầu, tuần, slot/tuần; import |
| S04 | Điểm danh lớp | Ngữ cảnh lớp/buổi học, hai mode Qua link/Thủ công, danh sách sinh viên và thống kê P/A; chốt hoặc xem kết quả |
| S05 | Cấu hình lịch lớp | Số tuần, ngày học, nghỉ/học bù; lưu lịch khi được phép |
| S06 | Link điểm danh | Tạo link, sao chép/chia sẻ, trạng thái nhận điểm danh, mã xác nhận nếu bật và tiến độ |
| S07 | Chi tiết sinh viên | Lịch sử cá nhân, tỷ lệ vắng, note/audit; sửa có lý do |
| S08 | Lịch sử điểm danh lớp | Meeting theo ngày, trạng thái, tổng P/A; chọn kết quả |
| S09 | Xuất kết quả | Metadata, tổng P/A; chọn JSON/CSV, local/Firebase Storage và kết quả lưu |
| S10 | Thông báo | Quyền thông báo, lịch sử, xem đúng lớp/buổi học; làm mới và trạng thái rỗng/lỗi |

Khi có workspace, hai điểm đến cấp cao là Lịch tuần & lớp học (S02) và Thông báo (S10). Màn con có Back. Trước khi có workspace, S01/S03 chỉ có điều hướng theo tác vụ; không cho mở một dashboard chưa có dữ liệu. Thông báo chỉ mở dữ liệu đúng tài khoản và đúng buổi học có trên thiết bị.

S02 có Quản lý lớp dạng mở rộng để truy cập mọi lớp, gồm lớp không có meeting trong tuần, chỉnh lịch và xóa lớp. S08 luôn thuộc lớp đang chọn. Dialog, bottom sheet và loading/error không được tính thêm thành màn hình riêng.

S04 có hai mode trong cùng màn hình, không tính thành hai màn riêng. Ở mode Qua link, nút Tạo link/Quản lý link mở S06; Back về S04 giữ nguyên lớp, buổi học và kết quả. Mode Thủ công thao tác trực tiếp trên danh sách ở S04. Link được chia sẻ mở trang web điểm danh cho sinh viên, không phải màn hình giảng viên trong bộ S01–S10.

## Bố cục trọng tâm

### S02 — Thời khóa biểu tuần

- Danh sách lớp và lịch tuần là hai chế độ của S02. Hiển thị lớp chưa bắt đầu/đang diễn ra; truy cập được lớp ngoài tuần. Giữ tuần/bộ lọc khi chuyển chế độ và Back.
- Cột thứ Hai–Chủ Nhật, có ngày/tháng; hàng khung giờ 1–4.
- Khung giờ 1: 07:00–09:15; khung giờ 2: 09:30–11:45; khung giờ 3: 12:30–14:45; khung giờ 4: 15:00–17:15.
- Thanh đầu gồm học kỳ, khoảng ngày, tuần trước/sau, tuần này và chọn tuần.
- Ô meeting có mã môn/lớp, giờ, số thứ tự lần học trong môn, số sinh viên và trạng thái.
- Phân biệt số thứ tự buổi học (Slot) với khung giờ trong ngày; luôn kèm ngày/giờ khi cần xác nhận.
- Tô nổi ngày hiện tại bằng cam nhạt và nhãn Hôm nay; không coi cả ô là Present.
- Lấy meeting theo ngày thật, tôn trọng override, ngày nghỉ và học bù kể cả Chủ Nhật.
- Trùng lịch hiển thị tất cả meeting xếp dọc, không ghi đè. Hàng tăng chiều cao đồng bộ với cột nhãn slot.
- Bấm ô mở S04 với đúng lớp và buổi học đã chọn.
- Ô trống dùng dấu gạch. Tuần trống có thông báo và hành động chọn tuần; không nói roster trống.
- Mobile giữ nhãn slot ngoài vùng ngày cuộn ngang, thanh đổi tuần ngoài vùng cuộn. Hiển thị dấu hiệu còn ngày ở ngoài vùng nhìn.
- Giữ chữ dễ đọc; dùng cuộn ngang khi không đủ chiều rộng hiển thị các ngày.

### S04 — Điểm danh lớp

Hiển thị một buổi học tại một thời điểm. Thứ tự nội dung: môn/lớp và ngày/khung giờ, trạng thái buổi học, thống kê, bộ chọn mode, nội dung của mode và hành động Chốt danh sách.

Bộ chọn gồm đúng hai mode: **Qua link** và **Thủ công**, luôn hiển thị rõ mode đang chọn. Cả hai dùng chung danh sách, kết quả và thống kê của buổi học. Không hiển thị mã QR trên màn điểm danh của giảng viên.

Thống kê gồm Sĩ số, Present, Absent và Chưa ghi nhận. Mỗi sinh viên chỉ được tính một lần; tổng ba trạng thái phải bằng sĩ số. Có ô tìm theo họ tên/MSSV và thông báo khi không có kết quả.

#### Mode 1 — Qua link

- Hiển thị trạng thái link và nút Tạo link; khi đã có link, đổi thành Quản lý link để mở S06.
- Danh sách bên dưới hiển thị kết quả sinh viên đã gửi. Mở link đơn thuần không tự ghi nhận Present.
- Giảng viên theo dõi tiến độ, chuyển sang Thủ công khi cần bổ sung kết quả hoặc chốt danh sách.
- Tạo link cần kết nối. Khi không tạo được link, hiển thị lỗi, Thử lại và lựa chọn Điểm danh thủ công; giữ nguyên kết quả đã có.

#### Mode 2 — Thủ công

- Hiển thị danh sách sinh viên cuộn dọc. Mỗi hàng có MSSV, họ tên đầy đủ và nhóm chọn **Present (P) / Absent (A)**.
- Hai lựa chọn loại trừ nhau, dùng radio hoặc segmented control, không dùng hai checkbox độc lập. Nhãn phụ Có mặt/Vắng giúp người dùng hiểu rõ.
- Sinh viên chưa được điểm danh có trạng thái Chưa ghi nhận và chưa chọn P hoặc A; không mặc định Absent.
- Khi chọn lần đầu, lưu kết quả của sinh viên và cập nhật thống kê. Chỉ hiển thị đã lưu sau khi lưu thành công; nếu lỗi, giữ lựa chọn đang nhập và cho Thử lại.
- Đổi kết quả đã ghi thực hiện theo quy tắc sửa có lý do ở S07. Có thể mở từ lựa chọn P/A, giữ đúng sinh viên và buổi học.
- Thao tác chọn P/A không mở trang chi tiết sinh viên. Bấm tên hoặc hành động Chi tiết mới đến S07.
- Chế độ thủ công lưu trên thiết bị và sử dụng được khi mất mạng, nếu danh sách lớp đã có trên máy.

#### Chuyển mode và chốt

Chuyển mode chỉ thay cách thao tác, không tạo buổi học mới, xóa kết quả hoặc đặt lại P/A. Link đã mở vẫn nhận điểm danh cho đến khi giảng viên Dừng nhận hoặc Chốt; bộ chọn mode không phải công tắc đóng phiên link.

Kết quả thủ công của giảng viên được ưu tiên. Lượt gửi qua link chỉ bổ sung Present cho sinh viên chưa có kết quả, không ghi đè P/A đã chọn thủ công và không tăng số lượng khi gửi lặp.

Nút Chốt danh sách dùng chung cho cả hai mode. Hộp xác nhận nêu tổng Present, Absent và số Chưa ghi nhận sẽ chuyển thành Absent. Hủy giữ phiên và kết quả hiện tại. Đồng ý chốt lưu kết quả, dừng nhận qua link và khóa thao tác điểm danh trực tiếp; sửa sau chốt đi qua S07 với lý do.

### S06 — Link điểm danh

S06 thay màn hình hiển thị QR cũ. Nội dung gồm ngữ cảnh môn/lớp/buổi học, trạng thái nhận điểm danh, vùng link, nút Sao chép và Chia sẻ, tiến độ cùng hành động Dừng nhận. Không yêu cầu giảng viên đưa màn hình điện thoại cho sinh viên quét.

| Trạng thái / hành động | Phản hồi |
| --- | --- |
| Chưa có link | Hiển thị Tạo link điểm danh |
| Đang tạo | Hiện tiến trình, khóa thao tác tạo lặp |
| Đang nhận | Hiển thị link, Sao chép, Chia sẻ và tiến độ; mở lại S06 dùng link còn hiệu lực của cùng phiên |
| Sao chép / chia sẻ | Báo đã sao chép khi thực hiện thành công hoặc mở bảng chia sẻ của thiết bị. Chia sẻ không đồng nghĩa sinh viên đã điểm danh |
| Dừng nhận | Vô hiệu hóa việc gửi qua link, giữ kết quả và cho tiếp tục thủ công; không tự chốt hoặc chuyển ô trống thành Absent |
| Lỗi tạo / không thể nhận | Nêu lỗi, có Thử lại hoặc chuyển Thủ công; không hiển thị trạng thái đang nhận khi link không hoạt động |
| Buổi đã chốt | Không cho gửi thêm; hiển thị đã kết thúc, hướng giảng viên về kết quả |

Sinh viên bấm link sẽ mở trang điểm danh theo luồng cũ: kiểm tra đúng lớp/buổi học, xác nhận thông tin sinh viên, nhập mã xác nhận nếu bật rồi gửi và nhận phản hồi thành công/lỗi. Giữ kiểm tra sinh viên thuộc danh sách lớp. Link chỉ dẫn vào quy trình, không thay thế các bước xác nhận đó.

Thời hạn hoàn tất hai phút áp dụng cho từng lượt truy cập hợp lệ vào trang điểm danh, thay cho lượt quét QR cũ; không tính từ lúc giảng viên tạo link và không áp dụng như hạn chung của cả lớp. Khi phiên vẫn nhận, sinh viên có thể mở lại link để bắt đầu lượt mới.

Back khỏi S06 hoặc chuyển sang ứng dụng khác để gửi link không tự chốt hay tự thêm Absent. Hiệu lực link theo trạng thái phiên, không theo việc S06 có đang hiển thị hay không. Khi không thể duy trì nhận điểm danh, giao diện phải báo tạm ngừng và cho chuyển sang Thủ công.

### S07 — Bàn giao thao tác sửa điểm danh

Đối chiếu [handoff S07](../handoff/flutter-handoff.md#s07--chi-tiết-sinh-viên) và [ảnh sheet sửa gốc](../assets/stitch/prototype-2026-10-11/f3-03-s07-edit.png). Sheet gồm ngữ cảnh sinh viên/lớp/slot, kết quả hiện tại, lựa chọn P/A, ô lý do có label và hai hành động Hủy/Lưu. Chỉ sửa slot được phép theo nghiệp vụ, không sửa upcoming.

| Tình huống / hành động | Phản hồi và dữ liệu cần giữ |
| --- | --- |
| Mở sheet | Hiển thị đúng sinh viên, lớp, slot, ngày/khung giờ và P/A hiện tại. Lý do mới do người dùng nhập, không tự lấy lại note cũ làm lý do của lần sửa mới. |
| Lý do rỗng hoặc chỉ có khoảng trắng | Báo `Vui lòng nhập lý do chỉnh sửa.` tại ô lý do; giữ sheet mở và giữ lựa chọn P/A. |
| Hủy trước khi lưu | Đóng sheet về màn nguồn; không thay đổi P/A, tổng lớp, note hoặc audit cũ. |
| Đang lưu | Hiện trạng thái đang lưu; khóa Lưu để ngăn bấm lặp. Không báo đã lưu hoặc xóa dữ liệu nhập trước kết quả thành công. |
| Lưu thành công | Cập nhật P/A, ghi chú, lịch sử chỉnh sửa và thống kê liên quan; trở về đúng ngữ cảnh sinh viên/lớp/slot. |
| Lưu lỗi | Giải thích lỗi, giữ P/A mới cùng lý do đã nhập, có Thử lại hoặc Hủy. |
| Back / bàn phím | Sau khi đóng sheet, Back giữ lớp/slot/bộ lọc nguồn. Nội dung cuộn được, tới được Hủy/Lưu khi mở bàn phím; tên dài xuống dòng. |

Lịch sử chỉnh sửa lưu kết quả trước/sau cùng lý do để hỗ trợ đối chiếu.

| Thành phần cần bàn giao | Định hướng Flutter |
| --- | --- |
| Nút Lưu | FilledButton, có disabled/loading |
| Nút Hủy | TextButton hoặc OutlinedButton theo phong cách đã chọn |
| Ô lý do | TextField nhiều dòng, label và errorText |
| Lựa chọn P/A | Radio với nhóm lựa chọn loại trừ nhau |
| Sheet sửa | BottomSheet, xử lý keyboard inset và cuộn |
| Màu / chữ và khoảng cách | Theme dùng chung; padding/gap theo token, không dùng số riêng tùy màn |

## Quy tắc nghiệp vụ

| Nhóm | Quy tắc cần giữ |
| --- | --- |
| Workspace | Email nhập ở S01 chỉ nhận diện, không chứng minh quyền sở hữu hoặc tạo kiểm soát truy cập |
| Import | Nhận ODS/XLSX, đọc danh sách lớp và sinh viên; thông báo dữ liệu không hợp lệ trước khi xác nhận |
| Import lại | Cập nhật trong cùng học kỳ, giữ lịch sử và lịch riêng; không tự xóa lớp/sinh viên thiếu trong tệp mới. Sinh viên thêm vào buổi đã chốt được bổ sung A |
| Lịch | Cấu hình ngày học, khung giờ, tần suất, ngày nghỉ và học bù |
| Cấu hình | Số tuần 1–52, slot/tuần 1 hoặc 2. Chỉ lưu đổi lịch khi mọi meeting của lớp còn upcoming; đã active/closed thì giải thích và chặn lưu |
| Phiên điểm danh | Chỉ một buổi đang điểm danh trên workspace. Bắt đầu cho ngày hiện tại ở một trong hai mode; không mở lại buổi đã chốt |
| Hai mode | Qua link và Thủ công dùng chung buổi học, danh sách và kết quả. Chuyển mode không reset dữ liệu hoặc tự đóng link |
| Link điểm danh | Gắn với đúng lớp/buổi học; tạo cần kết nối, có thể sao chép/chia sẻ. Không hiển thị QR hoặc cơ chế đổi QR định kỳ |
| Mã xác nhận | Nếu bật cho luồng sinh viên, dùng mã sáu chữ số theo phiên link; đây là tùy chọn của mode Qua link, không phải mode thứ ba |
| Sinh viên qua link | Mở trang điểm danh theo luồng cũ; email khớp danh sách lớp, hoàn tất xác nhận mới ghi Present. Mỗi lượt hợp lệ có hai phút; được mở lại khi phiên còn nhận |
| Thủ công | Chọn riêng Present hoặc Absent cho từng sinh viên; chưa chọn là Chưa ghi nhận. Lưu trên thiết bị, không bắt buộc tạo link hoặc có mạng |
| Gửi lặp / ưu tiên kết quả | Một kết quả mỗi sinh viên/buổi học. Link không ghi đè kết quả thủ công; thay đổi kết quả đã ghi phải có lý do |
| Chốt | Xác nhận thống kê, giữ P/A đã ghi, chỉ bổ sung Absent cho Chưa ghi nhận. Sau lưu thành công, dừng link và khóa điểm danh trực tiếp ở cả hai mode |
| Dừng nhận / Back | Dừng nhận chỉ dừng link, không chốt. Back hoặc chuyển ứng dụng không tự chốt, không tự thêm Absent; hiển thị đúng tình trạng nhận của phiên |
| Qua ngày | Khi app mở/kiểm tra lịch, slot quá ngày chưa chốt được hoàn tất, ô thiếu thành A và giữ kết quả đã có; không dùng ổ khóa thay P/A |
| Sửa | Chỉ sửa buổi đang diễn ra/đã chốt; lý do không được rỗng hoặc chỉ có khoảng trắng. Lưu kết quả trước/sau |
| Lịch sử | Mỗi buổi có kết quả và lịch sử chỉnh sửa thống nhất; ghi chú vẫn xem được sau ngày học |
| Tỷ lệ vắng | Số A / tổng buổi đã lên lịch, kể cả buổi tương lai; hiển thị 0 khi chưa có buổi học |
| Xuất | Chọn JSON hoặc CSV cho một lớp/một buổi đã chốt đủ P/A. Tên và đuôi tệp thống nhất giữa xem trước, kết quả và chia sẻ. Hủy không báo thành công |
| Sao lưu báo cáo | Firebase Storage; có tiến độ, kết quả và Thử lại. Lỗi tải lên không xóa tệp trên thiết bị. Không báo đã sao lưu trước khi dịch vụ xác nhận |
| Xóa lớp | Chặn khi còn buổi đang điểm danh; yêu cầu xác nhận, lưu trữ dữ liệu trên thiết bị và giữ tệp nguồn |

Không lưu mã xác thực, mật khẩu hoặc token truy cập trong lịch sử điểm danh.

## Phong cách và nội dung

Trắng–cam là chủ đạo. Bề mặt trắng, nền phụ nhạt, chữ xám xanh đậm. Xanh lá/đỏ/xanh dương chỉ hỗ trợ trạng thái. Một hành động chính nổi bật theo trạng thái màn; thao tác phụ dùng outlined/text/menu.

Tone tiếng Việt trực tiếp, lịch sự. Hai mode dùng nhãn Qua link và Thủ công. Lựa chọn điểm danh dùng Present (P) / Absent (A), kèm Có mặt/Vắng khi cần giải thích; trạng thái chưa chọn là Chưa ghi nhận. Dùng nhất quán: Slot, Đang điểm danh, Đang nhận qua link, Link tạm ngừng, Đã chốt, Đã lưu trên máy và Chờ đồng bộ. “Đã qua” là trạng thái thời gian, không phải P/A hoặc đã chốt.

Thông báo nêu nguyên nhân và cách tiếp tục:

- `Chưa có lịch dạy trong tuần này. Chọn tuần khác.`
- `Không thể đổi lịch vì lớp đã có slot bắt đầu hoặc đã chốt.`
- `Vui lòng nhập lý do chỉnh sửa.`
- `Đã sao chép link điểm danh.`
- `Không thể tạo link. Thử lại hoặc chuyển sang điểm danh thủ công.`
- `Buổi học đã chốt. Link không còn nhận điểm danh.`
- `Đã lưu trên máy. Chưa đồng bộ được, hãy thử lại khi có mạng.`

Không hiển thị stack trace. Lỗi không xóa nội dung nhập và không báo thành công trước khi lưu.

## Design tokens

Dùng chung token màu, chữ, khoảng cách và kích thước giữa các màn hình và component.

| Token màu | Giá trị | Vai trò |
| --- | --- | --- |
| color/primary | #C93C13 | Nút chính, link trên nền trắng |
| color/on-primary | #FFFFFF | Chữ trên nút chính |
| color/brand | #F4511E | Nhận diện, điểm nhấn |
| color/primary-soft | #FFF0E8 | Ngày hiện tại/vùng chọn |
| color/background | #FFF7F3 | Nền màn hình |
| color/surface | #FFFFFF | Card, input, dialog |
| color/text | #243047 | Chữ chính |
| color/text-secondary | #667085 | Chữ phụ |
| color/border | #D9DEE7 | Phân vùng nhẹ, không là dấu hiệu duy nhất của control |
| color/control-outline | #667085 | Viền control cần nhận biết |
| color/success | #16835D | Có mặt/thành công |
| color/error | #C93A2B | Vắng/lỗi |
| color/info | #2563B8 | Thông tin hỗ trợ |

Chữ trắng trên primary có tương phản khoảng 5,07:1; trên brand khoảng 3,48:1. Không dùng chữ thường trắng trên brand.

Font Roboto hỗ trợ tiếng Việt:

| Token chữ | Size / line height | Weight |
| --- | --- | --- |
| type/heading | 24 / 32 | 700 |
| type/title | 20 / 28 | 600 |
| type/subtitle | 16 / 24 | 600 |
| type/body | 16 / 24 | 400 |
| type/supporting | 14 / 20 | 400 |
| type/button | 16 / 24 | 600 |
| type/secret | 32 / 40 | 700 |

Không cắt họ tên; tăng chiều cao thay vì giảm font. MSSV giữ một dòng khi đủ chỗ.

| Token nhóm | Giá trị | Cách dùng |
| --- | --- | --- |
| space/1–6 | 4, 8, 12, 16, 24, 32 | Padding/gap; màn và card 16, section 24 |
| radius/small | 8 | Chip |
| radius/medium | 12 | Button/input |
| radius/large | 16 | Card/dialog |
| size/touch-min | 48 | Vùng chạm tối thiểu |
| size/button-height | 52 | Nút chính |
| elevation/flat | Không shadow | Mặc định |
| elevation/card | X 0, Y 2, blur 8, spread 0, #243047 6% | Phân tầng nhẹ |
| elevation/overlay | X 0, Y 8, blur 24, spread 0, #243047 12% | Dialog |

## Component và trạng thái

Các component dùng chung token và có trạng thái nhất quán giữa các màn hình.

| Nhóm bắt buộc | Variants/states |
| --- | --- |
| Button | Default, pressed, disabled, loading; primary/secondary/text |
| Text field | Default, focused, filled, error, disabled |
| Card | Default, pressed khi bấm được |
| Navigation | Selected cho Lịch tuần và Thông báo |
| Bộ chọn mode | Qua link / Thủ công, thể hiện rõ mode đang chọn |
| Lựa chọn điểm danh | Present / Absent, chỉ chọn một; có trạng thái chưa chọn, đang lưu và lỗi lưu |
| Link điểm danh | Chưa tạo, đang tạo, đang nhận, tạm ngừng, đã kết thúc; Sao chép/Chia sẻ và Thử lại |
| App bar | Default, có action |
| Dialog | Confirmation và cancel/error |
| Loading | Ít nhất một spinner/skeleton cấp màn hình |
| Empty | Icon, thông báo và CTA |
| Error | Nguyên nhân dễ hiểu, thông báo và thử lại |

Component bổ sung: MeetingCell, StudentRow, AttendanceStatus, NoteIndicator. StudentRow ở mode Thủ công có nhóm chọn P/A; ở mode Qua link hiển thị kết quả đã nhận. Trạng thái thời gian/ngày hiện tại của MeetingCell độc lập với trạng thái chốt và P/A.

### Mẫu component dùng để trình bày

Các mẫu dưới đây minh họa component từ màn hình thiết kế.

| Mẫu quan sát được | Nguồn ảnh gốc | Phạm vi minh họa |
| --- | --- | --- |
| Nút chính Lưu thay đổi | [Sheet S07 prototype](../assets/stitch/prototype-2026-10-11/f3-03-s07-edit.png) | Nút chính của form, phân biệt với Hủy trong ảnh đầy đủ |
| Lựa chọn P/A | [Sheet S07 prototype](../assets/stitch/prototype-2026-10-11/f3-03-s07-edit.png) | Lựa chọn P và A cùng nhóm, không chỉ dựa vào màu |
| Ô lý do có nội dung | [Sheet S07 prototype](../assets/stitch/prototype-2026-10-11/f3-03-s07-edit.png) | Trường nhập nhiều dòng có label, có thể cuộn khi bàn phím mở theo handoff |
| Phản hồi lý do trống | [S07 error V2](../assets/stitch/v2-s07-edit-error.png) | Vùng thông báo lỗi tại ô lý do trong phiên bản V2 |

Mẫu minh họa bổ sung cho bảng đặc tả trạng thái, không thay thế kiểm thử tương tác.

## Accessibility và responsive

- Frame chính 360 × 800, kiểm tra thêm rộng 412; light theme bắt buộc.
- Contrast chữ thường tối thiểu 4,5:1; chữ lớn/control cần nhận biết tối thiểu 3:1.
- Vùng chạm tối thiểu 48 × 48; nội dung tối thiểu 14 sp.
- Mọi icon tương tác có nhãn; P/A/lỗi không chỉ dùng màu.
- Bộ chọn mode và nhóm Present/Absent có nhãn rõ, đọc được trạng thái chọn; thao tác P/A không trùng vùng mở chi tiết sinh viên.
- Dùng Auto Layout và Fill/Hug phù hợp; chữ dài không clip, form không bị bàn phím che.
- Lịch cuộn ngang, nhãn slot cố định ngoài vùng ngày; phần cuộn dọc gồm cả hai vùng để hàng không lệch.
- Điều khiển đổi tuần ngoài vùng cuộn ngang; navigation không che hàng cuối.
- Roster một slot, cuộn dọc. Search nếu có phải có clear và trạng thái không có kết quả.
- Từ 600 dp trở lên: mở rộng viewport để thấy nhiều ngày hơn, không phóng to font theo tỷ lệ; giới hạn chiều rộng form/vùng link và căn giữa. Mô tả trong handoff, không bắt buộc thêm frame.

## Prototype và bằng chứng

### Prototype tương tác

Thiết kế giữ 10 màn S01–S10 và ba flow mục tiêu:

- Nhập dữ liệu và cấu hình lịch lớp.
- Điểm danh qua link hoặc thủ công, theo dõi kết quả và xác nhận chốt.
- Xem lịch sử, sửa có lý do và xuất kết quả.

Mỗi flow có luồng chính, nhánh Hủy và cách phục hồi khi lỗi. Phản hồi gồm xác nhận, đang xử lý, kết quả và lỗi/thử lại. Thanh chọn Flow chỉ phục vụ demo.

[Prototype Stitch](https://stitch.withgoogle.com/preview/10059602616228007293?node-id=f4c596c319264fa182ad8c2c92ebf951) và ảnh hiện có cần cập nhật S04/S06 theo đặc tả hai mode này.

### Tài liệu đối chiếu

- [Màn hình thiết kế](screen-evidence.md) và [ma trận màn hình/trạng thái](state-coverage.md).
- [Wireframe khái quát](../assets/stitch/wireframe-generic-2026-10-26/README.md) và [ảnh prototype](prototype-review.md).
- [Prompt nguyên văn](../ai/stitch-prompts.md) và [ba vòng cải tiến](../ai/iteration-evidence.md).
- [Kịch bản demo](../presentation/output/demo-script.md).
- [Kết quả kiểm tra và quyết định thiết kế](design-decisions.md). Trạng thái xác nhận xem tại [student-confirmations](../ai/student-confirmations.md).

Dữ liệu công khai dùng thông tin giả hoặc ẩn danh, không chứa thông tin xác thực. Handoff mô tả bố cục, component, trạng thái, tương tác, điều hướng và ràng buộc cho từng màn hình.
