# Analytics plan - FAP Attendance Android

Written before adding Lab 3 tracking, 03/11/2026. Events are emitted by the
ViewModel through TelemetryService. Firebase UID is the user ID. No names,
email, roll numbers, free text, filenames, URLs or attendance reasons are sent.

| Event | Trigger | Parameters (type) | Product question | Flow |
| --- | --- | --- | --- | --- |
| login | Google sign-in completes | method (string: google) | Can teachers enter? | Entry |
| logout | Sign-out completes | none | Are sessions ended? | Entry |
| markbook_import | Roster saved locally | class_count (int) | Is setup completed? | 1 |
| attendance_mode_selected | Teacher changes mode | mode (string: link/manual) | Which mode is used? | 2 |
| attendance_link_created | Backend confirms active link | none | Can links be created? | 2 |
| attendance_marked | Record persisted locally | mode (string), status (string: P/A) | Is attendance saved? | 2 |
| attendance_closed | Final result persisted | present_count, absent_count (int) | Are meetings finalized? | 2 |
| student_detail_viewed | Teacher opens student detail | none | Is individual history used? | 3 |
| attendance_exported | JSON/CSV written successfully | format (string: json/csv) | Are reports produced? | 3 |
| report_uploaded | Storage upload finishes | format (string) | Does backup succeed? | 3 |

Do not emit from build(). Tracking failure must not roll back attendance or
block navigation. Test through a fake telemetry service, then verify all events
and parameter types on a real configured Android device with Analytics
DebugView. Enable with `adb shell setprop debug.firebase.analytics.app
vn.edu.fpt.fap_attendance`; disable with `.none.`. Console evidence has not been
collected yet. Record device, build, event and screenshot in test-results.md.
