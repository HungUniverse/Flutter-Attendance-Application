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

`map-suggest` inspects only CSV headers and suggests the roster or attendance
field mapping. It recognizes common English and Vietnamese column names and
flags ambiguous or approximate matches for review. `map-preview` accepts comma,
semicolon, tab or pipe separated files, localized attendance statuses, manual
header mappings, custom status aliases, and explicit duplicate-row policies.
Its options JSON can contain `rosterOptions` and `attendanceOptions`, each with
`delimiter`, `mapping` and `duplicatePolicy`; attendance options can also set
`statusAliases`. By default duplicates are errors. `first` and `last` policies
must be chosen explicitly and are recorded as warnings. Missing statuses become
unrecorded cells. No partial snapshot is returned while errors remain.
`map-issues-csv` exports row diagnostics without copying source-cell values.
CSV input is limited to 20 MB, 500,000 rows and 256 columns.

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

`policy-grid` expands explicit arrays of `minimumRates` and `maximumAbsences`
into at most 40 named candidate rules. `policy-lab` applies those rules (or a
caller-authored policy list) to a snapshot and compares four clearly labeled
missing-data assumptions: keep unknown results bounded, assume they are
present, assume they are absent, or exclude them from the rate. These are
hypothetical calculations only; none fills or changes an attendance record.
Each candidate has pass, fail and undetermined totals, optional cohort
summaries, and outcome-change counts against a selected baseline rule. A cohort
definition lists student IDs supplied in the options JSON. Cohorts smaller
than `minimumCohortSize` (default 5) have their aggregate counts suppressed;
use at least 2 as the threshold. Students not assigned to a cohort are grouped
as `unassigned`.

For example, save this as `policy-options.json` and run
`node tools/attendance-workbench/cli.mjs policy-lab snapshot.json policy-options.json`:

```json
{
  "policies": [
    { "id": "baseline", "name": "Current proposal", "minimumRate": 0.75, "maximumAbsences": 2 },
    { "id": "alternative", "name": "Alternative proposal", "minimumRate": 0.8, "maximumAbsences": 3 }
  ],
  "missingModes": ["bounded", "assume-present", "assume-absent", "exclude-missing"],
  "baselinePolicyId": "baseline",
  "minimumCohortSize": 5,
  "cohorts": [
    { "id": "section-a", "label": "Section A", "studentIds": ["S001", "S002"] }
  ]
}
```

The default JSON contains aggregate results only. Student rows require the
explicit `includeStudentRows: true` option, are limited to 10,000, and can be
exported using the `students` CSV section. `policy-lab-csv` also supports the
`summary`, `cohorts`, and `comparisons` sections. The comparison section shows
outcome changes per cohort and suppresses counts for cohorts below the same
minimum size. CSV cells are escaped for spreadsheet use.
The lab is an offline analysis aid; review the actual records and approved
institutional rules before making any decision. This optional CLI module is
only loaded by `tools/attendance-workbench/cli.mjs` and is not imported by the
Flutter/web application.

## Additional offline analysis commands

These commands are available only through the explicit workbench CLI. The
query engine accepts a bounded JSON filter tree (`all`, `any`, `not`) instead
of executable expressions, supports sorting and pagination, and keeps names and
emails out of result rows unless they are listed in `columns`. Group summaries
can suppress groups below a caller-selected minimum size. Use:

```text
node tools/attendance-workbench/cli.mjs snapshot-query snapshot.json query.json
node tools/attendance-workbench/cli.mjs snapshot-query-csv snapshot.json query.json rows
node tools/attendance-workbench/cli.mjs snapshot-query-diff before.json after.json [query.json]
```

`cohort-explore` builds weighted cohort and time-window summaries with
coverage, rate distributions, paired-window comparisons and small-group
suppression. `schedule-insights` reports resource overlaps, turnarounds,
utilization, capacity warnings and daily workload from an explicitly supplied
schedule JSON file. Both accept options JSON and have CSV variants.

`source-reconcile` accepts a JSON array of source descriptions. Each entry
contains `id`, optional `label` and `priority`, and either an embedded
`snapshot` or a `snapshotFile` path relative to the source-list file. Optional
mapping, target, conflict and provenance choices go in an options JSON file.
The command produces a review plan; it never changes its source files.

`correction-new`, `correction-update`, `correction-audit` and
`correction-apply` manage an append-only correction review ledger. Applying
approved corrections returns a separate snapshot in stdout only after the
baseline and expected cell values match. It does not overwrite the supplied
snapshot. Reviewer notes are excluded from CSV unless
`correction-csv ... --include-notes` is explicitly requested.

`retention-plan` evaluates a caller-supplied metadata inventory against explicit
retention rules and a chosen `asOf` date. It accounts for legal holds, temporary
approved overrides, conflicting rules, policy gaps and review windows. The
`entries`, `kinds` and `summary` CSV sections contain inventory metadata only;
this command never opens, deletes, redacts or rewrites the files described by
the inventory.

`export-plan` checks an explicitly scoped snapshot export against a supplied
least-privilege policy. It blocks disallowed recipients, purposes, fields,
validity periods and oversized results; aggregate requests suppress groups
below the configured minimum size. External record-level exports and
policy-required exports return no payload until `export-approve` records a
named reviewer and reason. `governed-export-csv` exports only an approved plan.
These commands prepare a local preview and never send or save data.

`exemption-new` and `exemption-update` keep reviewed absence excuses, campus
closures, make-up credits and duplicate corrections in a separate versioned
ledger. `exemption-report` evaluates approved entries over the current snapshot
as an analytics overlay; stale results or a closure that overlaps a student
exception block the adjusted report. It leaves the original attendance values
alone and reports the adjusted denominator, coverage and rate separately.

`patterns` reviews absence and missing-result runs, overlapping or fixed-size
session windows, coverage, rate distributions and simple up/down trend signals.
Student-level rows are omitted unless `includeStudentRows` is enabled; small
cohort summaries are suppressed by `minimumGroupSize`. These are descriptive
signals from recorded results and do not infer causes.

`forecast-evaluate` performs a chronological holdout backtest for mean,
last-result, recency-weighted and linear-trend estimators. It compares errors,
threshold confusion counts and calibration bins while preserving missing
results. Detail predictions are opt-in and small calibration groups are
suppressed. This is a model check on past data, not a live student prediction.

`migration-plan` previews student/session ID changes, target dimensions,
record collisions and explicit removals. Many-to-one student merges need an
authoritative target roster when identity fields differ; conflicting attendance
cells need a per-conflict choice or an explicit present/absent priority. The
target snapshot is included only with `includeSnapshot: true`, and source data
is never overwritten.

`contract-check` validates a snapshot against a caller-authored versioned JSON
contract. Checks cover dimensions, record counts, coverage, missing-result
limits, required IDs, exact session order, selected cells, absence rates and
placeholder identities. Error-level failures reject the snapshot; warning
checks remain visible without failing acceptance.

`release-plan` converts an accepted contract check into a local approval plan.
`release-decide` records a named approval or rejection; failed warning checks
must be acknowledged explicitly before approval. `release-verify` rechecks the
receipt against the supplied snapshot and contract, and `release-csv` exports
compact evidence. `release-compare` checks two receipts for snapshot, contract,
warning-acknowledgement and approval changes. The receipt digest detects accidental edits but is not a
digital signature; these commands do not publish or replace the snapshot.

`recovery-plan` combines a target attendance rate and absence limit with an
explicit number of future sessions. Choose how historical missing results are
handled (`optimistic`, `pessimistic` or `exclude`) in the options JSON. The
default output contains only totals and caller-defined cohort summaries, with
small cohorts suppressed. Student rows require `includeStudentRows: true`.
This is a hypothetical plan and does not fill or edit attendance records.

`attendance-impact-diff` compares two snapshots by roster member and shared
session, reports added or removed dimensions and changed cells, and can compare
outcomes against a caller-provided attendance policy. Cohort totals are
suppressed below the selected minimum size. Student rows and names are opt-in;
both source snapshots remain unchanged.

All of these commands read caller-named files and write results to stdout.
Their modules are imported by `tools/attendance-workbench/cli.mjs`; the Flutter
and web app entry points do not import or invoke the workbench.

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

`anomaly-scan` analyzes a validated snapshot for statistical and behavioral
attendance anomalies, including zero-attendance sessions, sudden session-to-session
attendance drops (`sessionDropThreshold`, default 0.35), late-semester student
drift (`lateDriftThreshold`, default 0.4), and alternating present/absent
oscillations (`minAlternatingLength`, default 6). `anomaly-scan-csv` exports the
anomaly list with spreadsheet-safe CSV escaping.

`archive-new` starts a versioned snapshot history. `archive-add` appends a
revision with its parent, author and note; revisions can branch from older
points through the library API. `archive-compare` shows semantic changes,
`archive-restore` appends an earlier snapshot as a new revision, and
`archive-csv` exports a compact index without attendance rows. The archive is
written only when the caller saves command output to a file.

`demo-generate` builds a repeatable synthetic snapshot; `demo-manifest` reports
the generator settings, dimensions, attendance mix and cohort summaries without
including student names. Set `seed` to an integer or string to recreate the
same dataset. Options include student/session counts, profile weights, group
count, absence and missing rates, missing-data pattern, and ID prefixes. The
generator uses only `Demo Student` names and `example.invalid` email addresses,
and refuses datasets larger than 250,000 student-session cells. `demo-profiles`
describes the available attendance patterns, and `demo-summary` reports the
shape and coverage of any validated snapshot. None of these commands sends
data to a service or writes files on its own. The browser workbench has a
separate generator form for the same synthetic data; its output is an in-memory
copy until explicitly downloaded.

`anonymize-snapshot`, `anonymize-bundle`, and `anonymize-archive` create new
documents with HMAC-SHA-256 pseudonyms. Student names and emails are replaced;
session labels, class names, archive notes, authors, custom revision IDs and
real timestamps are also removed by default. Attendance states and references
remain consistent. Supply a private options JSON file such as
`{"secret":"use-a-private-random-secret-of-at-least-16-bytes"}`. The secret
is not copied to output. Reusing the same secret intentionally makes a person
match across separately anonymized files; use different secrets when that link
is not wanted. `keepSessionIds: true` retains the original session labels.
`anonymize-report` checks that snapshot dimensions and attendance were
preserved and reports whether identity fields remain. The output still contains
attendance patterns, so use synthetic data when sharing a reproducible example
and review any output before sending it elsewhere.

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

`review-plan` builds an explainable queue from caller-configured attendance
signals, and `review-allocate` can distribute that queue across reviewers with
declared capacities. Both are suggestions for a human to inspect; neither
updates a snapshot or contacts anyone. `casebook-new`, `casebook-update`, and
`casebook-reconcile` maintain an append-only local review history while keeping
status transitions and expected revisions explicit. `casebook-summary` and
`casebook-csv` show the current state; notes stay out of the CSV unless
`--include-notes` is supplied.

`casebook-sla` reports time spent in each review status, with a paused clock
while a case is waiting for data. Priority thresholds can be tuned in an
options JSON file, and the report groups totals by priority and assignee.
Student identifiers and names are omitted unless
`includeStudentDetails: true` is selected. The report only reads the local
casebook; it does not notify assignees or change case status.

`casebook-workload` compares current open assignments with reviewer case and
weighted-point capacities supplied in a separate JSON roster. It identifies
unassigned, orphaned, inactive and over-capacity work, and reports load
utilization by reviewer. Case rows and reviewer names are opt-in. The report
does not change assignments or reviewer profiles.

`casebook-batch` applies a list of independent case updates only when the
casebook revision and every selected case revision still match. It validates
the full batch before returning a new casebook, so stale or invalid operations
produce no partial output. The batch is supplied as JSON with
`expectedBookRevision`, `operations`, and optional `actor` and `at` fields.

`casebook-activity` summarizes event counts, daily volume, status transitions,
reopenings and resolution time over an explicit UTC time window. Event rows and
actor breakdowns require separate opt-ins. Notes and student identities never
appear in this report.

`casebook-service-level` checks first-response and resolution targets by
priority. Waiting-for-data intervals pause the clock by default. Set `from`,
`to`, `asOf`, thresholds and paused statuses in the options JSON; detailed case
rows are opt-in. It reports historical and still-open deadline results without
notifying reviewers or changing the casebook.

`review-allocate-constrained` adds optional skill, conflict, case-limit and
weighted-capacity checks to local allocation planning. It sorts urgent and
less-flexible cases first, spreads load by projected utilization, and reports
why a case could not be assigned. Pass an options JSON file to tune priority
weights, cohort and repeat-student balancing, and whether reviewer names may
appear in the report. `review-allocate-csv` exports assignments, reviewer
loads, or unassigned cases. These commands only produce a plan in stdout; they
do not create work items or modify application data.

`review-board` combines the open assignments in a casebook with a new review
plan and reviewer capacity roster. It ignores cases already present in the
casebook, reserves existing reviewer load, and proposes only the remaining
assignments. It flags unknown assignees and reviewers already over capacity;
student IDs and reviewer names remain opt-in. The board does not update the
casebook.

`casebook-events` filters the history by event types, actor, case ID or time
range, with a bounded result count. Student identity and note text are omitted
unless `includeStudentDetails: true` or `includeNotes: true` is set in its
options JSON. `casebook-events-csv` exports the same filtered rows with
spreadsheet-safe cells. `casebook-history-audit` checks status and assignment
event chains against each case's current state; it reports aggregate findings
by default and includes case IDs only with `includeCaseIds: true`. Its `-csv`
variant exports the bounded findings list.

`report-studio` creates a filtered report object and `report-html-studio`
renders a self-contained HTML copy. The `report-csv-studio` sections are
`summary`, `students`, `sessions`, `matrix`, `audit`, and `policy`. Options can
limit rows and matrix cells, redact student/session labels, or include a
caller-supplied policy review. Reports may contain identifying attendance
information unless those fields are explicitly hidden.

`closeout-pack` builds a checksummed JSON package in memory. It includes
reports and CSV summaries; a complete snapshot is excluded by default and only
included with `includeSnapshot: true`. The manifest states whether the package
contains student names, student IDs, session IDs, or the full snapshot.
`closeout-inspect` verifies all checksums and shows privacy flags and file
metadata without exposing file contents. `closeout-compare` verifies two
packages and reports added, removed, changed, and unchanged files plus
dimension and privacy changes. `closeout-extract PACKAGE.json FILE_NAME` writes
one named package member to stdout after verifying the whole package. The
`*-csv` variants export safe file inventories to stdout. All CLI commands
require explicit input paths and write results only to stdout, so save outputs
to new files of your choice.

To create a report bundle without student or session identifiers, save these
options to a JSON file:

```json
{
  "includeSnapshot": false,
  "reportOptions": {
    "includeStudentNames": false,
    "includeStudentIds": false,
    "includeSessionIds": false
  }
}
```

Run `node tools/attendance-workbench/cli.mjs closeout-pack snapshot.json
closeout-options.json` and redirect stdout to a new package file. Verify its
manifest with `closeout-inspect`, or compare it to an earlier package with
`closeout-compare`.

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

## Ví dụ quy trình rà soát offline

Các lệnh dưới đây chỉ chạy khi gọi trực tiếp `node tools/attendance-workbench/cli.mjs`.
Hãy lưu mỗi kết quả vào một tệp mới để giữ lại bản đầu vào và lịch sử có thể
đối chiếu. Các lệnh không tự ghi tệp; chuyển hướng stdout là thao tác lưu của
người gọi.

### Phân công hồ sơ và ghi nhận quyết định

Tạo hàng đợi từ một snapshot đã nhập hoặc đã tạo bằng `demo-generate`:

```powershell
node tools/attendance-workbench/cli.mjs review-plan snapshot.json review-options.json > review-plan.json
node tools/attendance-workbench/cli.mjs casebook-new review-plan.json > casebook-v1.json
```

Danh sách người rà soát là dữ liệu đầu vào riêng. Trọng số năng lực tính theo
điểm; số hồ sơ tối đa được kiểm tra độc lập với tổng điểm:

```json
[
  {
    "id": "team-a",
    "name": "Attendance Review Team A",
    "active": true,
    "skills": ["attendance", "language-vi"],
    "capacityCases": 35,
    "capacityPoints": 120,
    "currentLoadPoints": 8,
    "conflictStudentIds": [],
    "blockedCaseIds": []
  }
]
```

Lưu danh sách trên thành `reviewers.json`, rồi lập đề xuất phân công tính cả
tải hiện có trong sổ:

```powershell
node tools/attendance-workbench/cli.mjs review-board casebook-v1.json review-plan.json reviewers.json > review-board.json
node tools/attendance-workbench/cli.mjs review-board-csv casebook-v1.json review-plan.json reviewers.json reviewers
```

Board bỏ qua hồ sơ đã có trong sổ, hiển thị hồ sơ không có người nhận hợp lệ
và không áp dụng phân công. Nếu người rà soát chấp thuận một số thay đổi, tạo
tệp `batch.json` từ các ID và revision hiện tại:

```json
{
  "expectedBookRevision": 1,
  "actor": "review-lead",
  "at": "2026-11-13T09:00:00Z",
  "operations": [
    {
      "caseId": "review-case-id",
      "expectedRevision": 1,
      "action": {
        "status": "in_review",
        "assigneeId": "team-a",
        "note": "Check the source attendance register."
      }
    }
  ]
}
```

Chạy `casebook-batch` để kiểm tra tất cả revision và nhận một bản sổ mới:

```powershell
node tools/attendance-workbench/cli.mjs casebook-batch casebook-v1.json batch.json > casebook-v2.json
node tools/attendance-workbench/cli.mjs casebook-sla casebook-v2.json sla-options.json
node tools/attendance-workbench/cli.mjs casebook-activity casebook-v2.json activity-options.json
node tools/attendance-workbench/cli.mjs casebook-service-level casebook-v2.json service-options.json
```

Nếu bất kỳ case revision, trạng thái hoặc action nào sai, lệnh batch dừng và
không xuất một casebook một phần. `casebook-workload` nhận roster reviewer có
capacity để đối chiếu các phân công đang mở. Tên và ID học sinh trong báo cáo
chi tiết luôn cần được bật bằng tùy chọn riêng.

### Kiểm tra và duyệt snapshot

Hợp đồng là JSON khai báo; đặt check severity thành `warning` nếu muốn người
duyệt có thể chấp nhận nhưng phải xác nhận cảnh báo:

```json
{
  "format": "attendance-snapshot-contract",
  "version": 1,
  "id": "semester-intake",
  "title": "Semester attendance import",
  "revision": 1,
  "checks": [
    { "id": "minimum-roster", "type": "min_students", "value": 2 },
    { "id": "coverage", "type": "minimum_coverage", "value": 0.9, "severity": "warning" },
    { "id": "sessions", "type": "min_sessions", "value": 1 }
  ]
}
```

Lập plan, xem các check, rồi ghi quyết định rõ ràng. Khi có check cảnh báo
không đạt, approval phải liệt kê tất cả ID đó trong `acknowledgedWarnings`:

```powershell
node tools/attendance-workbench/cli.mjs contract-check snapshot.json contract.json
node tools/attendance-workbench/cli.mjs release-plan snapshot.json contract.json > release-plan.json
node tools/attendance-workbench/cli.mjs release-decide release-plan.json approval.json > release-receipt.json
node tools/attendance-workbench/cli.mjs release-verify release-receipt.json snapshot.json contract.json
node tools/attendance-workbench/cli.mjs release-csv release-receipt.json
```

Receipt chỉ ghi fingerprint, kích thước snapshot, revision hợp đồng và thông
tin duyệt; nó không chứa bảng điểm danh. Verification kiểm tra lại snapshot
và contract được truyền vào. SHA-256 trong receipt giúp phát hiện chỉnh sửa
vô ý, nhưng không thay thế chữ ký số hay quy trình lưu trữ được phê duyệt.

### So sánh bản trước và sau

Tạo snapshot sửa riêng bằng `apply`, `correction-apply` hoặc thao tác có kiểm
tra revision. So sánh kết quả và tính kế hoạch phục hồi mà không thay đổi hai
bản đầu vào:

```json
{
  "policy": { "minimumRate": 0.75, "maximumAbsences": 2 },
  "minimumCohortSize": 5,
  "includeStudentRows": false,
  "cohorts": [
    { "id": "section-a", "label": "Section A", "studentIds": ["S001", "S002", "S003", "S004", "S005"] }
  ]
}
```

```powershell
node tools/attendance-workbench/cli.mjs attendance-impact-diff before.json after.json impact-options.json
node tools/attendance-workbench/cli.mjs attendance-impact-diff-csv before.json after.json summary impact-options.json
node tools/attendance-workbench/cli.mjs recovery-plan after.json policy.json recovery-options.json
node tools/attendance-workbench/cli.mjs release-compare old-receipt.json new-receipt.json
```

`attendance-impact-diff` phân loại thay đổi policy, coverage và ô điểm danh;
`recovery-plan` yêu cầu số buổi tương lai và cách xử lý kết quả thiếu rõ ràng.
Mặc định báo cáo chỉ có tổng hợp. Bật dòng chi tiết khi cần kiểm tra từng hồ sơ
và giới hạn số dòng trước khi xuất CSV.

Các ví dụ này dùng dữ liệu minh họa. Với dữ liệu thật, chọn thư mục lưu trữ
phù hợp và xem lại các file đầu ra trước khi chia sẻ. `flutter run` không gọi
những lệnh trong tài liệu này.

## Ranh giới với ứng dụng đang chạy

Mã workbench nằm dưới `tools/attendance-workbench`; ứng dụng Flutter/web không
import các module ở đây. Chạy `flutter run` vẫn khởi động mã ứng dụng theo entry
point hiện có và không khởi chạy CLI hay máy chủ workbench. Máy chủ cục bộ chỉ
chạy khi người dùng gọi `serve.mjs`, chỉ bind `127.0.0.1` và chỉ phục vụ giao
diện workbench cùng module đọc cần thiết. CLI đọc các đường dẫn mà người dùng
truyền vào, xử lý dữ liệu trong tiến trình rồi ghi kết quả ra stdout; nó không
tự lưu hoặc gửi dữ liệu. Các chức năng mới trong CLI như rà soát lịch sử, so
sánh chính sách và kiểm tra gói kết sổ cũng chỉ được thực thi khi gọi đúng
lệnh `node tools/attendance-workbench/cli.mjs ...`.
