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

Use `set-roster` with a roster CSV or `set-sessions` with a JSON array to make
an updated snapshot. If an existing attendance record refers to a removed
student or session, the command reports an error. Add `--drop-records` to
explicitly discard those records. Save the output separately from the input.
