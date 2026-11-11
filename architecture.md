# FAP Attendance - Android architecture

## Boundaries

`lib/main.dart` selects the Android teacher app. Windows keeps its existing entry
and controller. `lib/main_student.dart` preserves the optional legacy student
app; students can use the browser instead.

```text
Android View (lib/lab3/ui)
  -> TeacherViewModel (ChangeNotifier, provided through Provider)
    -> AuthService / TelemetryService / ConfigService / NotificationService
       UploadService / AttendanceLinkService / DeviceService
    -> MobileWorkspaceRepository
    -> existing domain services (attendance, schedule, merge, roster import)
      -> Firebase SDKs, Google Sign-In, HTTPS relay, local files
```

Views contain layout, route navigation, form validation and picker interactions.
No View imports a Firebase SDK. Bootstrap constructs concrete adapters and
injects them; tests replace service contracts with fakes. Shared components and
tokens are in `components.dart` and `mobile_theme.dart`.

## State and persistence

- Initial loading: `loadingWorkspace`; operation loading: `busy`.
- Data: account-scoped `workspace`; empty: no workspace/no classes/no matching
  students/no history; error: `error`, `workspaceLoadFailed`, `linkError`.
- Only one mutation runs at a time. Local changes are published after repository
  save succeeds. Auxiliary Analytics/diagnostic failures cannot cancel a saved
  attendance result. Failed forms keep their inputs.
- Files live below `FAP Attendance Mobile/teachers/{uid}/{semester}/` in Android
  app documents. Signing out clears in-memory data and protected routes, not the
  account's saved files. Android automatic backup is disabled. This is app-private
  storage, not a claim of independent file encryption.
- Domain rules enforce one active meeting, P/A exclusivity, unmarked initial
  state, no link override of existing results, required edit reason and audit,
  schedule lock after start, and missing-to-A finalization.
- JSON export uses the existing versioned single-session schema accepted by the
  Chrome extension. CSV uses the existing exporter. Files can be shared using the
  Android share sheet.

## Link mode and lifecycle

The phone does not launch a desktop executable/tunnel. `backend/` is a separate
Node HTTPS relay, configured with `ATTENDANCE_API_URL`. Shared workspaces use
Firestore via server-side Admin SDK; sessions use JSON on a persistent volume.
Firebase Admin verifies
teacher/student tokens; teacher accounts must be on the server allowlist.

A link belongs to one teacher/class/meeting. The relay keeps receiving while the
phone is backgrounded. Each browser visit obtains its own two-minute challenge.
Verified student email must match the roster. Submissions are idempotent and carry
the server acceptance timestamp. The phone polls on resume and every ten seconds
while active; repeated poll results cannot overwrite manual decisions.

Before closing, the ViewModel stops reception, retrieves final submissions, saves
them, then fills unmarked A. If reception cannot be stopped or final results
cannot be read, close fails visibly and can be retried; it does not falsely claim
that the remote link is closed. Date rollover imports accepted submissions before
finalizing. After a server restart the student starts a new challenge; saved
submissions survive. Link tokens and credentials are not analytics parameters.

The relay is **single-process/single-writer**. Production availability, persistent
volume, HTTPS proxy, allowlist and credentials must be configured before using
real students. It has not been deployed by this change.

## Firebase

- Auth: native Google Sign-In + Firebase identity, guarded teacher routes.
- Storage: reports under `reports/{uid}/{semester}/{course}/{class}/{date}_Slot-{number}/`,
  with an immutable destination captured at export, upload progress and download URL;
  owner-only rules in `firebase/storage.rules`; local file survives upload errors.
- FCM: permission, foreground ingestion, background entry point, initial/tap
  handling and account-scoped inbox. Target data includes `uid`, `classId`,
  `meetingId`; unknown targets stay in the inbox. No confidential data in push
  titles/bodies. OS notification display cannot be promised after force-stop.
- Analytics: planned events emitted on actions/success, never widget rebuild.
- Crashlytics: scrubbed non-fatal errors + UID/operation key; intentional native
  crash is gated by `LAB3_DEMO_TOOLS=true` and a confirmation.
- Remote Config: defaults/cache plus explicit refresh of
  `enable_link_attendance` and `export_help_message`; does not erase active work.
- Report backup uses Firebase Storage only. Google Sign-In requests identity
  permissions; it does not request access to files. Workspace JSON is cached locally
  and synchronized through the authenticated backend when its HTTPS URL is configured.
- Legacy workspace JSON can contain a retired syncState key. Loading ignores that
  metadata and preserves the class roster, attendance and audit records.

## Validation boundaries

Shared desktop/mobile setup, optimistic revisions, durable outbox, QR handoff,
legacy import and deployment limits: `docs/DESKTOP_MOBILE_SYNC.md`.
Firestore client rules deny access; backend Admin SDK enforces owner and teacher
allowlist on every workspace request. Desktop browser login uses a one-time ticket
with a separate polling secret and an in-memory 8-hour session, revoked on logout.
No administrator credential is included in either client. Whole-workspace conflicts
require explicit recovery; the pending version is backed up before replacement.

Automated domain, ViewModel, repository, widget and relay tests are local evidence.
Widget tests use fake identities/services. They do not prove Google OAuth,
Storage rules, notifications, Analytics DebugView or Crashlytics Console delivery.
Those require the owner's Firebase configuration and a real Android device.
ARTEMIS runs, exploratory testing and PR review are tracked separately; no runs
or review findings are invented.
