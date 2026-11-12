# Cấu trúc báo cáo trên Firebase Storage

Báo cáo mới được xếp theo tài khoản → học kỳ → môn → lớp → ngày và số buổi:

```text
reports/
  <UID giảng viên>/
    FA26/
      PRM393/
        SE1913/
          2026-11-04_Slot-01/
            FA26_PRM393_SE1913_M01_2026-11-04.json
```

UID là mã tài khoản Firebase Authentication, được giữ làm ranh giới phân quyền
và đáp ứng cấu trúc `reports/{uid}/…` trong hướng dẫn Lab 3. Có thể đối chiếu UID
tại Firebase Console → Authentication → Users. Không dùng email làm tên thư mục.

Thư mục được lấy từ dữ liệu của báo cáo khi xuất. Chuyển lớp/học kỳ sau đó hoặc
thử tải lại không làm đổi nơi lưu của tệp đã xuất. PDF, JSON và CSV cùng dùng cấu trúc
này. Tệp được tải lại với cùng tên và cùng buổi sẽ cập nhật đúng object đó.

Màn xuất file hiển thị thư mục đích và trạng thái sao lưu. Có thể chia sẻ bản
trên thiết bị bằng nút Chia sẻ tệp.
Metadata trên object gồm UID chủ sở hữu, học kỳ, mã môn, mã lớp, ngày và số buổi.

## Áp dụng trên project Firebase

1. Vào Firebase Console → Storage → Rules.
2. Thay nội dung bằng toàn bộ file `firebase/storage.rules`, rồi chọn **Publish**.
3. Cài bản app mới. Chọn một buổi đã chốt, xuất file và chọn sao lưu Firebase Storage.
4. Mở Storage → Files → reports → UID → học kỳ → môn → lớp → ngày/buổi.
5. Mở tệp, kiểm tra tên, nội dung tải xuống và metadata. Thử tải lại sau lỗi mạng.
6. Kiểm tra tài khoản khác không đọc/ghi được đường dẫn của chủ sở hữu.

Source đã cập nhật rules nhưng không tự xuất bản lên Firebase. Cần Publish trước
khi tải tệp theo cấu trúc mới. Rules cho phép chủ sở hữu đọc cả báo cáo cũ nằm
trực tiếp trong `reports/{uid}/`, và ghi báo cáo mới vào cấu trúc phía trên.

## Báo cáo đã có trên Storage

Bản cập nhật không di chuyển hoặc xóa các object cũ. Xuất và sao lưu lại buổi học
sẽ tạo bản ở thư mục mới; bản cũ vẫn còn. Sau khi tự kiểm tra bản mới, có thể dọn
bản cũ trong Console nếu không còn cần dùng.
