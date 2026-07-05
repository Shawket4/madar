# Madar KDS (Slint)

The standalone kitchen-display app — the first Slint surface of the
Rust-migration pilot. Links `madar-core` as a **plain Cargo dependency**
(no UniFFI, no flutter_rust_bridge): the UI calls the core as ordinary
Rust. A pixel/behavior port of the Flutter `feature_kds` (which is itself
a port of the Kotlin `KitchenDisplayScreen.kt`).

## Run

```sh
cargo run                              # dev, against prod API
MADAR_API=http://192.168.1.10:8080 \
MADAR_ENV=dev cargo run                # against a local backend
MADAR_LOCALE=ar cargo run              # Arabic (RTL applies from core)
MADAR_THEME=dark cargo run             # dark palette
MADAR_PREVIEW=login|station|board cargo run   # dev-only screen previews
```

Data (SQLite store, core-owned session) lives under the platform data dir
in `madar-kds/madar.db`.

## What's mirrored from the Flutter app

- **Flow**: boot → cached-session restore → `app_route()`: manager
  email+password device setup → branch bind → teller PIN login (6-digit
  pad, auto-submit, failure shake) → station picker → board.
- **Board**: adaptive ≥260px grid with top-aligned rows, fixed 54px
  age-tinted card headers (accent → amber @5m → red @10m, green + heavy
  border when ready), bumpable line rows with the 700ms sweep-check
  acknowledgment, per-line station labels, warning-tinted notes,
  reconnecting banner, success-tinted all-clear state.
- **Realtime**: `core.start_realtime` — `kitchen.*` events reload; a 30s
  tick re-escalates ages and doubles as the safety poll while offline.
- **Design system**: exact color roles (light+dark), 4-pt spacing, radii,
  Cairo type scale, card/raised/glow shadows, StatusChip / NoticeBanner /
  press-scale metrics. Arabic shaping + bidi verified via the Skia
  renderer (do not switch renderers without re-verifying Arabic).

## Known divergences (documented, deliberate)

1. **Settings gear toggles the theme** — the Flutter app pushes the full
   SettingsScreen, which is out of the pilot's scope.
2. **No ping sound / OS notifications yet** — `RealtimePlayer` sinks are
   no-ops; the core still decides when to alert.
3. **Line-height approximation** — Slint (this version) has no Text
   line-height; the brand headline pre-splits lines into 50px rows. Other
   multi-line text uses Cairo's default (looser) leading.
4. **Strikethrough** — Slint Text has no strikethrough; bumped lines draw
   a hairline overlay across the first text line.
5. **Press spring** — Flutter uses a physical spring (620/.72); here it's
   a 160ms ease-out-back approximation.

## Slint gotchas learned (keep for the wider migration)

- `states` blocks with `in`/`out` transition animations silently broke
  rendering of the whole subtree (Slint 1.x, Skia). Inline ternaries with
  `animate` work. Investigate upstream before using states.
- Component roots wrapped around layouts collapse to 0 preferred size —
  pin `preferred-height`/`min-height` explicitly (see `CTA`).
- `transform-rotation`/`transform-scale-*` don't apply on component root
  elements, and not at all on the software renderer.
- lucide-static via unpkg needs `curl -L` (redirects) and comment
  stripping before Slint's SVG parser accepts the files.

## ⚠️ Licensing gate — decide BEFORE shipping

Slint is triple-licensed: **GPLv3**, **Royalty-Free**, or **Commercial**.
The royalty-free grant excludes *embedded* deployments, and a dedicated
kitchen terminal plausibly crosses that line. Building and evaluating
internally is fine; before any production rollout, either confirm the
royalty-free terms cover tablet-POS use or price the commercial license
(per-seat) into the hardware economics. GPLv3 is an option only if
open-sourcing this app is acceptable.
