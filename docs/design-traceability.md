# Design to Android implementation

Reference: `design/brief-lab2.md` (current brief based on Lab 2) and the
supplied `design/stitch-prototype-2026-11-03/code.html`. Original files are
preserved in the standalone Flutter repository; see `design/README.md`.
The prototype is a visual/interaction reference; its static example counts,
toast-only exports and QR screen are not used as production data or backend.

| Screen | Android implementation | Validation |
| --- | --- | --- |
| S01 workspace | WorkspaceStartPage; authenticated email | Auth guard widget test |
| S02 classes/week | DashboardPage, MobileWeekGrid; all classes accessible | 360/412 grid widget tests; existing timetable domain tests |
| S03 import | ImportPage, real picker, ODS/XLSX preview/merge | Existing importer/merge tests; invalid import ViewModel test |
| S04 attendance | AttendancePage; shared link/manual modes, search, counts | Manual priority, no reset, close tests |
| S05 schedule | SchedulePage; frequency, holidays/makeup, started lock | Existing schedule tests; layout smoke tests |
| S06 link | LinkPage + remote relay; copy/share/stop/progress | Relay authorization/TTL/idempotency tests; ViewModel close/import tests |
| S07 student | StudentPage + edit bottom sheet, fresh required reason/audit | Edit/cancel widget test and audit ViewModel tests |
| S08 history | HistoryPage, scoped filter and exact meeting route | Layout tests; domain records/tests |
| S09 export | ExportPage, JSON/CSV/local/share/Storage progress/URL | Real temp-file export + fake upload failure/retry tests |
| S10 notifications | NotificationsPage, permission, account-scoped history and correct meeting destination | Widget navigation checks; real FCM delivery still needs a configured device |

Added for Lab 3: Google authentication, account/settings page,
Remote Config controls and gated diagnostic controls. They complement the ten
business screens without a demo flow switcher.

The new S04/S06 behavior follows the design brief instead of the old prototype
QR flow. No copied demo roster or fixed sample attendance is inserted in app data.
Test fixtures are confined to `test/`.

Real-device/Firebase/ARTEMIS evidence is still pending; see test-results.md and
LAB3_ACCEPTANCE.md. Layout tests are not a complete accessibility audit.
