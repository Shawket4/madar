# Settings feature port — integrator notes

Port of `packages/features/settings` (settings_screen.dart 1178 +
settings_provider.dart 323 + sync_screen.dart 414 + sync_provider.dart 92)
to `ui/feature_settings.slint` + `src/feature_settings.rs`. Compile-verified
(scratch import + `cargo build`, then reverted — no shared files edited).

## Wiring (app.slint)

```slint
import { SettingsState, SyncState, SettingsScreen, SyncScreen,
         SettingsTillData, SettingsStationData, SettingsDiagData,
         SyncOutboxData } from "feature_settings.slint";
export { SettingsState, SyncState, SettingsTillData, SettingsStationData,
         SettingsDiagData, SyncOutboxData }
```

- Add `settings` (and optionally `sync`) to the `Screen` enum and render:
  ```slint
  if root.screen == Screen.settings: SettingsScreen {
      width: parent.width; height: parent.height;
  }
  if root.screen == Screen.sync: SyncScreen {
      width: parent.width; height: parent.height;
  }
  ```
  Both are full-screen overlays in Flutter (pushed routes over the order
  screen / KDS board); rendering them as screens (or trailing overlay
  children over the board, like the current settings modal) both work — the
  screens own their `T.bg` fill.
- The KDS gear (`KdsBoard.open-settings`) should now route here instead of
  the interim modal card in app.slint (that modal was a stopgap slice of
  this screen; replacing it is the integrator's call — this port does not
  touch app.slint).

## Wiring (main.rs)

```rust
mod feature_settings;
// at boot, after the other on_* hookups:
feature_settings::wire_settings(&app_window, &app);
```

- **Opening**: when routing to the screen, call
  `feature_settings::open_settings(&app)` (seeds the three text fields from
  the device config — the Flutter `initState` controllers — resets
  error/print status, then primes shift/tills/stations/pending/diagnostics
  like `SettingsNotifier.load`). For the sync center:
  `feature_settings::open_sync(&app)`.
- **Back**: `SettingsState.back()` / `SyncState.back()` are fired by the
  header back tile AND invoked from Rust after a successful
  reconfigure/sign-out (pop first, then `route_refresh` — the Dart
  `Navigator.maybePop(); shell.refresh()` order). The integrator hooks
  them to whatever pops the screen:
  ```rust
  ui.global::<SettingsState>().on_back(move || /* pop to previous screen */);
  ui.global::<SyncState>().on_back(move || /* pop */);
  ```
- **Locale flips**: `feature_settings::apply_settings_strings(&ui, &core)`
  must run wherever `apply_strings` runs (the settings language card calls
  both itself via its own `set-locale` handler; if the app.slint modal's
  `set-locale` stays wired too, add the call there).

## Core APIs used (verified against rust-core/crates/madar-core/src/lib.rs)

`device_config`, `device_code`, `set_device_code`, `set_device_printer`,
`set_device_lan_hub`, `set_device_till`, `set_device_station`,
`start_reconfigure`, `current_shift`, `current_session`, `list_tills`
(async), `kds_list_stations` (async), `pending_outbox_count`, `recent_logs`,
`clear_logs`, `lan_active`, `lan_peer_count`, `lan_stop`,
`is_realtime_subscribed`, `unsubscribe_realtime`, `logout(false)`,
`base_url`, `core_version()` (free fn), `tr`, `locale`, `set_locale`,
`render_receipt` (sync), `send_to_printer` (async), `list_outbox`,
`retry_outbox` (async), `sync_now` (async), `refresh_connectivity` (async),
`discard_outbox_item`.

## Parity compromises

1. **Orientation rows** — `OrientationController` is a mobile platform
   service (SystemChrome locks). Desktop has no rotation lock, so the glue
   sets `can-flip: false` (the flip row hides — the Dart phone behavior)
   and mirrors the threshold stepper in-memory only (default 7.0", the
   controller's `defaultTabletThresholdInches`; steps 0.5 clamped 5–10 are
   ported verbatim in the .slint). No persistence — nothing to apply it to.
2. **Dark mode / theme persistence** — `darkModeProvider`'s host vault
   doesn't exist in this app (theme comes from `MADAR_THEME`); `set-dark`
   flips `T.dark` for the session only.
3. **Connectivity nudge** — the Dart `_quiet` reports transport errors to
   `connectivityRefreshProvider`; this app has no connectivity service, so
   failures are swallowed silently (same rendering behavior: settings render
   offline with whatever's cached).
4. **Shell refresh after sync actions** — Dart's retry/syncNow/discard call
   `shell.refresh()` so the order screen's sync chip re-reads. There is no
   sync chrome in this app yet; the glue reloads only the outbox model.
   `bind-station` DOES call `route_refresh` (the station rides the route),
   which flips the screen to the re-bound board — matching the Dart shell
   re-read, but it exits settings; the integrator may prefer to defer the
   refresh to `back()`.
5. **Error 2-line cap (sync rows)** — Slint Text has no `maxLines`; the
   error text is word-wrapped inside a clipping box capped at 40px
   (≈ 2 lines @ 12px Cairo) with no ellipsis on the second line.
6. **Haptics** — `MadarHaptics.impact()` on the CTA has no desktop
   equivalent; omitted (Press tactile scale kept).
7. **Row order in RTL** — like the rest of this app (auth/kds precedent),
   horizontal layouts are not order-mirrored; directional bits ARE handled
   (chevron rotation, InfoRow end-alignment, sync-row start/end insets swap,
   text shaping via Skia).
8. **Print-failure detail** — Dart swallows the exception and shows only the
   localized "print failed" status; ditto here (`human_message` resolved and
   discarded to keep the pathway greppable).
9. **`sync.discard`** — the Kotlin natives have a labeled discard action;
   the Flutter source renders an icon-only trash button, so the key is
   unused here too (parity with the Flutter source of truth).

## Kit gaps flagged for promotion

- `SettingsTextField` — kit `Field` + a per-keystroke `edited(string)`
  callback and a two-way `text` mirror (the Flutter `_SettingsTextField`
  with `onChanged`). Defined locally; promote by adding `edited` to
  `Field`.
- `SettingsCta` — the natives' `MadarButton` outline + danger variants
  (kit `CTA` only does primary/ghost). 54px, 1.5px accent outline / danger
  fill, 20px spinner.
- `SettingsCard`, `SettingsChip`, `StepChip`, `PickerRow`, `InfoRow`,
  `Hairline` — settings-specific; promote if the checkout/floor ports need
  them.
