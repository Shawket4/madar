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

### Before pushing or opening a PR — run CI locally first, every time

CI (`.github/workflows/ci.yml`) has failed more than once on a push whose
diff looked unrelated to the failure — the format check and the Rust test
suite run over the WHOLE tracked tree, not just the files a change touched, so
a change confined to one crate or one `.dart` file is not proof the repo is
green. Run the full sequence below before every push and before opening a PR,
not just the pieces that seem relevant to what changed:

```bash
flutter analyze .
git ls-files '*.dart' | grep -v '/cargokit/' | xargs dart format --set-exit-if-changed --output=none
cd rust-core && cargo test -p madar-core && cd ..
```

Touched anything FRB-bound (`madar-frb`, or a `madar-core` type/fn a bridge
method exposes)? Also run the host-test job CI runs on macOS:
```bash
cd rust-core && cargo build -p madar_frb --release && cd ..
cd packages/rust_bridge && flutter test && cd ../..
```
All of the above must pass locally before a push or a PR — don't rely on CI
to find a problem you could have caught here first.

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

## Offline plan B: the replicated store (OFFLINE_B_DESIGN.md)
The core keeps the branch as rows fed by `POST /sync/pull` (`sync_pull.rs`): the
money ledger in typed tables (`ledger/`: tills, orders + payment legs, cash,
refunds), every other POS type in `sync_rows`. Reads are local; a local write and
its outbox op commit in ONE transaction; acks fold the server's answer in.
- **One identity per row.** Every writer goes through `ledger::write_row`, which
  resolves the row by client key, then server id, then order_ref / ticket id and
  re-keys instead of inserting. Never write ledger tables with raw SQL.
- **A new POS-visible backend table needs a changefeed trigger** (MadarRust:
  `sync_emit` trigger + a `sync_source_tables()` entry + the migration header;
  the migration tests enforce it). Without one the POS silently never sees it.
- **Report formula changes regenerate the shared vectors.** The till report /
  drawer fold is madar-shared's (`madar_till::report`); a change to the figures
  regenerates `madar-shared/crates/madar-till/vectors/till_report_vectors.json`
  from MadarRust (`MADAR_WRITE_TILL_VECTORS=1`), ships with a madar-shared tag,
  and `ledger::report` must pass it (`madar_till::vectors::TILL_REPORT`).
- **A line's price is the server's rule, madar-shared's `madar-catalog`.** The
  size price, a swap charged over the recipe's own choice, one pick per swap
  family, the add-ons, the optional fields offered on the size: the core runs
  the crate over a view built from the mirror (`catalog_pricing.rs`, from the
  `pricing` field the server ships on every menu row and add-on row). Never add
  a swap family, a base-price or a size rule to the core; a rule change is a
  madar-shared tag, with vectors the backend regenerates.
- **The local rows are the only read path.** No screen read waits on the network:
  it returns what the device holds at once. A till not held completely is filled
  in the background (`ledger_ops::fill_till_soon`, short timeout) and a table
  change re-reads the screen; reads that are online by nature (a sale never seen
  here, search across tills, a points balance) go through `ledger_ops::within`
  (5 s) and fail offline with a clear error. Never add a blob cache or a
  server-then-cache read; add the type to the feed.
- **The network rule: reads never touch the network.** Every screen read and
  every periodic refresh (a tick, a pulse, a table change, a timer) answers from
  local rows. The network is used ONLY for:
  - `POST /sync/pull` — on a realtime `sync.changed`, a reconnect (the
    offline→online edge of `refresh_connectivity`), a till open, a manual sync,
    an ack, and the realtime-down fallback poll (5 s while pulls bring changes,
    backing off to 60 s when they don't);
  - `POST /sync/replay` (the outbox drain), the realtime SSE stream, `/health`;
  - asset bundle / file downloads; sign-in, token refresh, the offline-auth bundle;
  - server-only actions a PERSON triggers, never on a timer: search across tills,
    a loyalty lookup, a table's history, a sale or delivery never seen here, the
    delivery accepting toggle, the routing-mode write, a force close, the manual
    catalogue refresh;
  - background FILLS of what the feed cannot give yet, never on a beat: a past
    till not held here (filled once, and again only when the feed moves that
    till), the past-till history backfill (one attempt per session), a
    branch-settings field an older backend omits (once per session).
  Branch settings the till reads (routing mode, stations, delivery settings, the
  loyalty programme, the tax policy) ride `branch_settings`
  (`branch_reads.rs`; MadarRust `20260917090000_sync_feed_branch_reads.sql`).
  A new read that seems to need the network means a missing feed type: add it
  to the changefeed. `tests/network_budget.rs` (`MADAR_OB_TESTS=network_budget`)
  counts every request against the real backend, and
  `apps/madar/test/network_budget_test.dart` pins that no tick calls a
  network-capable bridge method.
- **Before adding a network call, check the local model first.** A value that
  looks missing is often already on the cached record under a different field
  (e.g. an order's `device_code`, kept independently of the `order_ref`
  backfill, reconstructs the real display number without a `GetOrder` call).
  Derive from what's already local before reaching for the network — a new
  call is the last resort, not the first fix.
- Real-backend scenarios: `tool/offline_b_backend.sh` (see its header);
  `MADAR_OB_TESTS=readpath_parity` checks every screen read against the server.

## Permissions (architecture E — PERMISSIONS_ARCHITECTURE.md)
- **Ask for a capability, never a role.** Gate a screen or action on the signed-in
  person's effective capabilities from the core (the generated `Cap` keys in
  `app_core/lib/src/generated/capabilities.dart`). `isManagerRole`-style checks are
  being removed; do not add new ones.
- **The registry is generated.** `madar-authz` is a git dependency on
  `Shawket4/madar-shared` (pinned by tag in `madar-core/Cargo.toml`, the same tag the
  backend pins), and `capabilities.dart` is generated there from its spec: in a
  madar-shared checkout, `cargo run -p authz-gen -- --pos ../madar`. Never hand-edit it.
- **Unknown means no.** While grants are not loaded, only plain selling is assumed
  (`session::SELL_WHILE_UNLOADED`); money exceptions wait for real grants. An offline
  unlock adopts the person's last-known grants from the synced teller row.
- **LAN rows are checked, never dropped.** A peer's money row whose author lacks the
  grant is kept (the money moved) and recorded in `lan_authz_flags`.

## Floor / tables — shared with the dashboard
`packages/features/order/lib/src/tables_screen.dart`.

- **The glyph is shared.** `TableGlyph` + `seatSlots` (`table_glyph.dart`, `kTable*`)
  draw the same object as the dashboard's `src/features/floor/table-glyph.tsx`
  (`TABLE_*`), from the same constants in **canvas units** × the live scale. Change a
  constant in one, change it in the other.
- **The floor screen** (`floor_screen.dart`) fits the room to both axes and docks
  `floor_inspector.dart` at the end side on iPad/desktop (under the room in portrait, a
  sheet on a phone). Every act goes through `_perform(FloorAction, table)`.
  `floor_render_test.dart` renders it (`--dart-define=MADAR_RENDER=true`).
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

## Teller and waiter — what each one does

Both work the same room. They differ in **what they may do with a bill**, not in
what they can see, and every place the code branched on the role instead of the
situation turned out to be a bug.

| | Teller (cashier) | Waiter |
|---|---|---|
| Open a till | yes — a shift is theirs | never; a waiter has no drawer |
| Seat a party / free a table | yes | yes |
| Take a round to the kitchen | yes | yes |
| See a table's bill | yes | yes |
| **Settle a bill** | **yes** | no — `if (!isWaiter)` on the sheet, `SettleOpenTicket` is Teller-only in replay |
| Void a bill | yes | yes |
| Park a cart (held order) | yes — counter and takeaway | no; a waiter's parking is the open ticket |
| Counter sale with no table | yes — the tender drawer | no; a waiter's cart always fires a ticket |
| Shift stats / Z-report | yes | no (`loadShiftStats` returns early) |

The rule for new code: **branch on the situation, not the role.** "Is there a
table in hand?" and "is a bill targeted?" decide what a button does and says;
`isWaiter` decides only whether taking money is offered. The bugs that came from
getting this backwards:

- `loadOpenTickets` was waiter-only, so a teller's floor had no bills at all —
  every seated table read "nobody has ordered", every tap opened a SECOND tab,
  and Settle was unreachable from the room. The floor is the teller's home
  screen whenever the shop puts every sale on a table.
- `activeTicket` returned null for a teller, so a teller adding a round saw a
  cart that would not show the bill so far, and printed a chit with no ticket
  reference.
- The cart's CTA said "Checkout" for a teller and "Fire" for a waiter — so the
  same button meant two different things depending on who held the till, while
  doing the same thing.

## Bookings — the floor's future (shared with the dashboard + backend)
A booking claims tables for a window (backend `src/bookings`); the floor mirror carries
each table's `next_booking` (`held.rs` → `FloorTableStateView.booking_*`). The tables
screen derives **reserved** by the clock (`tableIsReserved`, from `booking_held_from`),
shows the guest on the pill, and offers *Seat this party* / *No-show* — both
optimistic-local + queued (`seat_booking` / `no_show_booking` replay ops). Seating
points the live order at the table under the guest's name; the ticket fired next
carries `booking_id` and the server links the two. The arrivals sheet lists today's
active bookings from the synced `booking` rows, with queued seat / no-show answers applied.

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

   **Cut text is `MadarClippedText`** (`design_system/clipped_text.dart`),
   never a bare `Text(overflow: …)`: same parameters, and when it was really
   cut a long press shows the whole text (the owner's "hold shows a hint").
   A glyph standing in for a word says it the same way — give a
   `MadarGlyphTile` its `semanticLabel`, a glyph-only `MadarButton` its
   `tooltip`. A feature that owns a long press itself (a raw
   `GestureDetector(onLongPress:)`, a drag to reorder) wraps it in
   `MadarHoldHints.off` and shows the full text in what that press opens (or
   `MadarRevealHints` on what it lifts); a kit control's own `onLongPress`
   does this by itself.
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
