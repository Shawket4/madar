# Claude Code Conventions: madar (POS / teller)

## Project Overview
The point-of-sale side of the Madar ecosystem: a **thin, high-performance Flutter UI
over a shared Rust core**. The Flutter layer renders and sequences; all business logic,
persistence, offline mirroring and sync live in `rust-core/` and are reached over
`flutter_rust_bridge` (FRB).

The guiding rule: **the UI holds no business logic.** A screen reads view models from
the core and calls bridge methods. If you find yourself computing money, resolving
conflicts, or deciding what a status means in Dart, it belongs in the core.

## The Madar ecosystem — three repos

| Repo | Path | Role |
|---|---|---|
| **MadarRust** | `/Users/magd/MadarRust` | Actix-Web API, Postgres schema, money/cost engine. **The contract.** |
| **MadarDashboard** | `/Users/magd/MadarDashboard` | React 19 management dashboard (authors configuration) |
| **madar** (this) | `/Users/magd/madar` | Flutter POS/teller + KDS over the shared Rust core |

**The dashboard AUTHORS, this app OPERATES.** The dashboard writes configuration (menu,
pricing, floor geometry); the POS writes operational state (orders, occupancy, shifts).

## Workspace layout (melos monorepo)

```
apps/
  madar/          The POS/teller Flutter app (macOS, iOS, Android)
  dashboard/      A Flutter management app (separate FRB surface)
  kds-slint/      Kitchen display, Rust + Slint (not Flutter)
packages/
  app_core/       Providers, bridge wiring, realtime ticks, shared app plumbing
  design_system/  Tokens (colors/dimens/typography/motion), sheets, toasts, icons
  rust_bridge/            Generated FRB bindings for the POS  ← do not hand-edit
  rust_bridge_dashboard/  Generated FRB bindings for apps/dashboard
  features/       auth · checkout · floor · history · incoming · kds · order · settings · shift
rust-core/
  crates/
    madar-core/   THE BRAIN: offline mirrors, outbox, money, cart, sync, i18n
    madar-api/    GENERATED typed client from the backend's OpenAPI spec
    madar-frb/            FRB surface for the POS (view models + one-line delegation)
    madar-frb-dashboard/  FRB surface for apps/dashboard
```

`packages/features/order/` is the largest feature and holds the order screen, cart,
held-orders strip, open tickets, and the **tables/floor canvas** (`tables_screen.dart`).

## Commands
- `melos run analyze` — `flutter analyze` across the workspace
- `melos run format` — `dart format --set-exit-if-changed .`
- `melos run test` — every package's tests
- `melos run bridge` — regenerate FRB bindings from `madar-frb` (`tool/gen-bindings.sh`)
- `melos run bridge_dashboard` — same for `apps/dashboard`
- `melos run gen` — `build_runner` where configured
- Core tests: `cd rust-core && cargo test -p madar-core`

Run the POS against a local backend (same Mac):

```bash
cd /Users/magd/madar/apps/madar && flutter run -d macos \
  --dart-define=MADAR_API=http://localhost:8081 \
  --dart-define=MADAR_ENV=dev
```

Prefer `localhost` over a LAN IP — a LAN address silently breaks the moment the machine
changes networks, and the app then shows an empty, "unsynced" UI with no obvious cause.

### Regenerating from the backend
```bash
cd /Users/magd/MadarRust && cargo run --bin export-openapi
cd /Users/magd/madar/rust-core && ./tool/generate_api.sh   # → crates/madar-api
cd /Users/magd/madar && melos run bridge                   # → packages/rust_bridge
```
`generate_api.sh` reads the backend from `MADAR_BACKEND_DIR` (default `../../MadarRust`).
`gen-bindings.sh` pins `flutter_rust_bridge_codegen` to an exact version and will refuse
to run on a mismatch — install the version it names.

**The dylib is built by the platform build, not by `melos run bridge`.** `bridge` only
regenerates bindings and `cargo check`s. The actual `libmadar_frb.dylib` is produced by
the CocoaPods/Gradle build phase during `flutter run`, under
`apps/madar/build/.../Pods.build/...`. Checking `rust-core/target/...` tells you nothing
about what the app is running.

## Architecture: offline-first

The POS must work with no network. `madar-core` keeps **kv mirrors** of server state and
an **outbox** of queued writes:

- Local mutations apply **optimistically** to the mirror and enqueue an outbox op.
- On drain, the server arbitrates; the next pull reconciles (server wins, except entries
  with a still-pending local op).
- Backend mutations are split live-route / `*_inner` so `/sync/replay` flushes a till's
  backlog through exactly the same code. If you add a POS-facing write, make sure the
  backend half is replay-safe.

Mirrors in `madar-core/src/held.rs`: `floor:sections`, `floor:tables`, `held:mirror`,
`transfers:mirror` (+ cursors). An **empty floor mirror is the feature gate** — no
authored layout means the POS renders no canvas at all.

Realtime is the fast path (`floor.*`, ticket ticks); a gated poll is the fallback while
the SSE stream is down. Both exist on purpose — don't remove the poll.

## Floor / tables — shared with the dashboard
`packages/features/order/lib/src/tables_screen.dart`.

- **The glyph is shared.** `_TableCell` + `seatSlots` draw the same object as the
  dashboard's `src/features/floor/table-glyph.tsx`, from the same constants in **canvas
  units** × the live scale. Change a constant in one, change it in the other.
- **Frame content, never a stored canvas size.** The dashboard's plane is unbounded;
  tables may sit at negative coordinates or far past the old nominal size. `floorBounds`
  computes the real extent (rotation envelope + chair allowance) and `kMaxFloorScale`
  stops a two-table bar from rendering each table the size of a dinner plate.
- **A floor plan is PHYSICAL space — never mirror it in RTL.** Use `Positioned`, not
  `PositionedDirectional`: `start` measures from the right in Arabic and mirrors the
  whole room, so the table by the door renders by the window and the POS contradicts the
  layout the dashboard drew. There is a test pinning this.
- **Bussing.** A checkout does not free its table. Completing a held order (or settling
  an open ticket) leaves it `dirty` — "needs clearing" — and the teller is prompted once,
  with a one-tap clear on the tables screen. Dismissing the prompt means *not yet*, never
  *cleared*: the safe default never lies about the room. Mirrored in `terminate_local`
  (core) and `bus_table` (backend).
- State never rests on colour alone: every tone has a glyph, needs-clearing is hatched.

## Bookings — the floor's future (shared with the dashboard + backend)
A booking claims tables for a window (backend `src/bookings`); the floor mirror carries
each table's `next_booking` (`held.rs` → `FloorTableStateView.booking_*`). The tables
screen derives **reserved** by the clock (`tableIsReserved`, from `booking_held_from`),
shows the guest on the pill, and offers *Seat this party* / *No-show* — both
optimistic-local + queued (`seat_booking` / `no_show_booking` replay ops). Seating
points the live order at the table under the guest's name; the ticket fired next
carries `booking_id` and the server links the two. The arrivals sheet lists today's
active bookings from `cache:bookings:arrivals` (refreshed with the floor).

Realtime: bookings ride the device's ONE SSE connection (`bookings` topic, waiters and
tellers); `booking.created` / `booking.arriving` ping through the same alert path as
tickets. Cloud-only events (delivery, bookings) are re-published on the LAN by any till
that heard them, under a deterministic id (`cloud:<branch>:<event id>`), so a LAN-only
tablet hears them once (`LanCloudRelay`, `LanRelay::publish_with_id`). A `resync` frame
from the server re-seeds every board.

## Recipe steps and their animations
An item's recipe carries an ordered list of steps (backend `src/recipes/steps.rs`). A step
is a PRESET, named by the curated library that ships with the backend and drawn with its
Lottie animation, or a line someone TYPED, which has no animation. Steps arrive inside the
menu payload `refresh_catalog` already pulls, each preset step carrying its animation's
address and a fingerprint of its bytes.

The core caches the animations in `filestore.rs` — a second `FileStore` beside the image
one, so evicting either's orphans never touches the other's files. `sync_step_animations`
runs in the same phase as the image sync: only animations THIS menu references are
downloaded, orphans are swept, failures are swallowed, and nothing fetches outside a
manual sync. `local_animation_path` is resolved onto the projected step at snapshot time,
like `local_image_path`, so the sheet plays from disk and never from the network.

On the sheet, only the step being looked at animates. A six-step recipe rendered as six
looping players is six render loops on a cheap tablet; the rest hold a still frame, and a
step with no cached file shows its number and name instead.

## Conventions
1. **No business logic in Dart.** Sequence bridge calls; compute nothing.
2. **Design system only.** `MadarType`, `Space`, `Radii`, `context.madarColors`,
   `MadarIcon`. No raw hex, no ad-hoc padding numbers.
3. **One control kit, in `design_system/controls.dart`.** `MadarButton`
   (primary / outline / ghost / danger, regular or compact), `MadarField`,
   `MadarAmountField`, `MadarCard`, `MadarSectionHeader`, `MadarHairline`, and
   `MadarHeader` above them. A feature package does NOT define its own button,
   field, card or divider.

   It used to: six near-identical buttons, six fields, four dividers, one set
   per feature. They drifted, and every fork was missing a fix made in one of
   its siblings — the checkout button never got the unbounded-width guard that
   blanks a screen, the checkout amount field never got the `EntranceFocus` fix
   for the iPad keyboard race. If a screen needs something the kit lacks, add
   it to the kit with a size or variant; a control that is genuinely one
   screen's own (a PIN pad, a payment badge, a floor table) still belongs to
   that feature.

   `apps/staff` deliberately keeps its own flatter `StaffCard` — it is a
   separate app with its own surface. Converge it on purpose or not at all.
4. **Strings go through the core's i18n** — `bridge.tr(key: '…')`, with EN **and** AR in
   `rust-core/crates/madar-core/src/i18n.rs`. Arabic is first-class.
5. **Accessibility**: touch targets 44pt iOS / 48dp Android; wrap canvas cells in
   `Semantics` with a real label; respect `MediaQuery.disableAnimations`.
6. **Tests** live beside the package (`packages/<pkg>/test/`). The floor canvas is pure
   geometry over plain data — no bridge, no providers — so test it directly.

## Gotchas
- **`melos run bridge` ≠ rebuilding the native library.** See above.
- **Text has a legibility floor; geometry does not.** Zoomed far out, an 11px label no
  longer fits a 15px table — wrap cell text in `Flexible` so it clips instead of
  throwing a layout overflow.
- **`BoxDecoration`'s `gradient` REPLACES `color`.** Setting both paints every table
  grey and silently erases the status tint. Put a sheen in its own layer.
- **`CustomPaint`: `painter` draws under the child, `foregroundPainter` over it.** A
  hatch belongs under the label.
- Rendering a widget tree to PNG in a `flutter test` is a legitimate way to *see* a
  canvas change when no simulator is available.
