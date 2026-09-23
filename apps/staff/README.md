# Dawam by Madar — staff app

The employee and manager app for every workflow in the Dawam Target Spec,
Arabic first, built the way the POS is:

| Piece | Where | Like the POS's |
|---|---|---|
| App shell: boot, theme, tabs, inbox, settings | `apps/staff` | `apps/madar` |
| Spine: core handle, locale / theme / toast providers, `tr`, shared Dawam widgets | `packages/staff_core` | `packages/app_core` |
| Sign-in | `packages/features/dawam_auth` | `feature_auth` |
| Home (clock-in) + Timesheet | `packages/features/dawam_clock` | |
| Shifts + Schedule on a calendar (kalender) | `packages/features/dawam_schedule` | |
| Requests + Approvals | `packages/features/dawam_requests` | |
| Team, flags, punch for someone | `packages/features/dawam_team` | |
| Pay, payslips, advances, payroll run | `packages/features/dawam_pay` | |

- **Words** come from madar-core like every Madar app:
  `rust-core/crates/madar-core/src/i18n.rs` (`staff.*`, plus the shared
  `settings.*` / `common.*`), read through this app's own bindings,
  `rust_bridge_staff`. `{placeholders}` are filled by `tr()` in staff_core.
- **Look** is `design_system` only: the shell scaffold, rows, stat cards,
  summary lines, sheets, the shared `MadarBrandPanel`, `MadarThemePicker`,
  `MadarLanguagePicker`, and the `series` palette for people's colours.
- **Theme** is the POS's `ThemeChoice` (light · dark · system), persisted under
  the POS's keys (`madar.theme`, `madar.locale`).
- **Workflows** run through madar-core: every screen reads one snapshot and
  sends one action (`dawam_do`), offline-first through the core's outbox.
  Screens reach it only via `dawamProvider`.

    flutter run                      # builds the Rust core via Cargokit
    flutter test                     # workflows + every screen, AR/EN, phone/tablet
    flutter test test/screens_test.dart --dart-define=MADAR_RENDER=true   # PNGs → build/shots
    cd ../../packages/staff_core && flutter test                         # the money path

## Firebase (push, APP-6)

The generated config is **not in git** — these repos are public, and it
carries the project's API key and app ids. Nothing else is needed to run the
app's tests; a device build wants the files back:

    cd apps/staff
    flutterfire configure --project=dawam-by-madar \
      --platforms=android,ios \
      --ios-bundle-id=com.madar.madarStaff --android-package-name=com.madar.madar_staff

That writes `lib/firebase_options.dart`, `android/app/google-services.json`,
`ios/Runner/GoogleService-Info.plist` and `firebase.json`, all git-ignored. The
APNs key (`.p8`) is uploaded once in the Firebase console, and the server's
service-account JSON lives outside every repo (`FCM_SERVICE_ACCOUNT_FILE` in
MadarRust's `.env`). CI injects the four files from its own secrets.

Demo: pick a demo account on sign-in (code 123456). Profile → Demo controls
moves the clock, the geofence, "Always" location, battery and connection, and
simulates what the 15-minute pings would catch.
