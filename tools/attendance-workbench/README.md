# Attendance workbench

This optional local CLI operates on files supplied by the caller. It does not
connect to the application, Firebase, or a server. It requires Node.js 22 or
newer and uses the existing offline backend utilities.

Run `node tools/attendance-workbench/cli.mjs --help` for command syntax. All
successful commands write to standard output. Choose a new output file when
redirecting so the shell does not truncate an input before the command reads it.

The `init` command accepts a UTF-8 roster CSV with `id,name,email`, a JSON
array of session IDs in chronological order, and an attendance CSV with
`studentId,sessionId,status`. Status must be `present` or `absent`. CSV errors
stop the import, and the command reports their physical line numbers.

`preview-import` reads the same three inputs but returns a review summary first.
It lists row errors across the files, checks attendance references against the
roster and session list, and reports coverage. A candidate snapshot is included
only when the import is valid; incomplete attendance remains a warning for the
reviewer. The browser offers the same preview before opening the resulting copy.

The `report` command shows coverage and missing pairs. `forecast` estimates
attendance after the supplied number of future sessions, and leaves students
with missing historical results without a forecast. `apply` accepts a JSON
array of changes with an expected previous status, preventing a stale batch
from silently overwriting a different snapshot. It produces a new snapshot only
when every expectation matches. This is an in-memory check; callers must use
their own concurrency controls when sharing files.

`report-html` produces a self-contained HTML report for a snapshot. Save its
output to a new `.html` file and open it locally. The report contains names and
attendance information, so treat the resulting file as sensitive class data.

`compare` reports differences between snapshots, including changed session
order. `export-csv` writes a spreadsheet-safe CSV. Values beginning with a
formula character receive a leading apostrophe, which is retained if that CSV
is imported again. Snapshot JSON preserves the original normalized values.

`bundle-new` creates a versioned collection for multiple classes. Use
`bundle-put` to add or replace a class by ID, `bundle-report` to review coverage
across classes, and `bundle-remove` to remove an entry. These commands also
write their result to stdout, so save each revision to a separate file before
replacing an earlier version. A bundle contains the complete student and
attendance data and should be stored accordingly.
`bundle-extract` retrieves one class snapshot for use with the other commands.
`bundle-students` aggregates recorded attendance by student ID across classes
and reports differing names or emails as identity conflicts. Confirm that shared
IDs refer to the same person before using these totals.

Use `set-roster` with a roster CSV or `set-sessions` with a JSON array to make
an updated snapshot. If an existing attendance record refers to a removed
student or session, the command reports an error. Add `--drop-records` to
explicitly discard those records. Save the output separately from the input.

`rolling` summarizes attendance over full consecutive windows, while
`absence-runs` lists consecutive absence sequences meeting a minimum length.
Missing results break a sequence and remain separate from absences.

`policy` evaluates a JSON object containing `minimumRate` (0–1) and
`maximumAbsences` (a non-negative integer). Missing results produce an
undetermined outcome when they could change the decision. The report uses only
the supplied data and rules, so it does not represent an institution's policy
unless those rules were entered by the caller.

The `scenario-new` command creates a self-contained simulation from a snapshot.
Use `scenario-set` to propose `present`, `absent`, or `missing` values and
`scenario-remove` to clear a proposal. `scenario-evaluate` reports before and
after totals and student policy changes without modifying the baseline. An
optional current snapshot checks whether a target cell changed since the
scenario was made; any conflict stops evaluation. `scenario-csv` exports the
successful impact rows. The browser interface exposes the same preview under
Phân tích → Thử kịch bản; it creates a simulated snapshot only when explicitly
downloaded.

`audit` reviews a validated snapshot for missing results, repeated names,
low-attendance patterns, long absence runs and sessions with no results. Rules
are advisory and configurable through an optional JSON options file. `audit-csv`
exports the findings without embedding the full attendance table. Invalid or
duplicate IDs and duplicate emails are rejected earlier by snapshot validation.

`schedule-generate` accepts a JSON object with `startDate`, `endDate`,
`startTime`, `durationMinutes`, `weekdays`, `resources`, `idPrefix`, and an
optional `exceptions` array. Dates and times use UTC, weekdays use Sunday=0
through Saturday=6, and exceptions are `YYYY-MM-DD` strings. The output is a
JSON schedule. `schedule-conflicts` checks that schedule for shared-resource
overlaps. `schedule-calendar` exports it as iCalendar using the supplied UID
domain and UTC generation timestamp, for example `2026-01-01T00:00:00Z`.

`schedule-plan` assigns meetings from a JSON list of candidate time and room
slots. It respects capacity, required room features, duration, group and
instructor availability, and exclusive resources. The deterministic search
returns a best partial plan when constraints prevent a complete timetable and
reports the blockers. `maxSearchNodes` bounds the search; the result states
whether that bound was reached. The browser can preview a plan and replace its
temporary schedule only after the whole plan is feasible.

## Giao diện cục bộ

Chạy `node tools/attendance-workbench/serve.mjs` từ thư mục gốc dự án và mở
địa chỉ mà lệnh in ra. Máy chủ chỉ lắng nghe trên `127.0.0.1`, không ghi tệp
và không kết nối mạng. Nó phục vụ giao diện trong `www` và các module `.mjs`
cần thiết trong `backend`. Dừng máy chủ bằng Ctrl+C.

Giao diện hỗ trợ mở bản sao JSON, bảng tổng quan, bảng điểm danh có thể sửa,
lọc và sắp xếp sinh viên, thêm và xóa buổi học, nhập CSV lớp, tạo lịch lặp,
xem xu hướng, áp dụng điều kiện điểm danh và so sánh hai bản sao. Có thể quản
lý nhiều lớp trong kho JSON ở bộ nhớ, tạo báo cáo HTML hoặc tải bản sao và CSV.
Hoàn tác và làm lại hỗ trợ tối đa 100 thay đổi. Dữ liệu chỉ được tải xuống khi
người dùng chọn nút tải xuống hoặc phím tắt Ctrl+S. Khi có thay đổi chưa tải,
trang cảnh báo trước khi đóng.

Không có thay đổi nào tự động lưu vào Firebase hoặc ứng dụng chính. Kho lớp
trong giao diện chỉ tồn tại trong bộ nhớ cho đến khi người dùng tải tệp JSON.
