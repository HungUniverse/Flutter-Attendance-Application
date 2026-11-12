# Gợi ý kiểm tra điểm danh bằng Firebase AI Logic

## Hành vi

Nút AI trong màn điểm danh Android gửi đúng ba số nguyên `present`, `absent`, `unmarked`. Firebase AI Logic trả JSON gồm `summary` và `checks`. App xác thực schema, gắn nhãn AI, cho giảng viên chỉnh nội dung và xác nhận. Gợi ý không sửa P/A.

Remote Config cung cấp `enable_attendance_ai`, `attendance_ai_model` và `attendance_ai_prompt`. Model mặc định là `gemini-3.1-flash-lite`. `firebase/configure-ai.mjs` bổ sung cấu hình vào template hiện có bằng ETag, đồng thời cập nhật hướng dẫn xuất báo cáo cho Final.

Ba event được ghi là `ai_request`, `ai_result_accepted`, `ai_error`. Telemetry gửi tên event. Input mô hình chỉ có số đếm. Bằng chứng input/output và nội dung giảng viên xác nhận nằm trên thiết bị trong `FAP Attendance Mobile/ai-evidence`.

AI có timeout 20 giây. Tắt cấu hình, lỗi mạng, schema không hợp lệ hoặc hết hạn mức đều trả thông báo có thể tiếp tục chốt. Unit test kiểm tra cả AI tắt và AI lỗi, sau đó chốt thành công.

## Trạng thái dịch vụ thực tế

Ngày 12/11/2026, project `fap-attendance-71655` đã bật Firebase AI Logic, Gemini Developer API, Remote Config và App Check. Yêu cầu thực tế tới model trả HTTP 429 với thông báo project hết credit trả trước. Chưa có ba cặp input/output thành công để nghiệm thu AI. Chủ project cần bổ sung credit để thu các đầu ra này.

Ca native có `RUN_LIVE_AI=true` ghi lại phản hồi hoặc lỗi thực tế cho ba bộ số đếm. Bằng chứng sinh ở `build/final-previews/ai-live-evidence`. Sau khi có quota, chạy lại cùng lệnh trong [hướng dẫn chạy Final](FINAL_SETUP.md), rồi bổ sung ba đầu ra và một ca lỗi vào hồ sơ nộp bài.

Tài liệu model và App Check được đối chiếu khi triển khai. [Firebase AI Logic models](https://firebase.google.com/docs/ai-logic/models), [Firebase AI Logic App Check](https://firebase.google.com/docs/ai-logic/app-check)
