# Madar POS — Flutter

The Madar Point-of-Sale app: a **thin, high-performance Flutter UI** over the shared
**Rust core** (`../madar-pos/rust-core/crates/madar-core`). This app replaces the two
native UIs (Compose + SwiftUI) with one Flutter UI on the same core.

## The one rule

All real logic lives in the Rust core — routing, cart/checkout/settle math, offline
outbox/sync, ESC/POS printing, LAN relay, i18n, waiter tickets, delivery, KDS. Flutter
renders DTOs, fires commands, and holds only ephemeral UI state. If a piece of logic
could ever differ between platforms, it belongs in Rust.

## Layout (Dart pub workspace + melos 8)

```
madar/
├── apps/madar/            # app shell: DI, go_router (core-driven), chrome, wiring
├── packages/
│   ├── rust_bridge/       # flutter_rust_bridge bindings + domain repositories (M1)
│   ├── design_system/     # ink/teal tokens, Cairo type, MadarIcon, shared widgets (M2)
│   └── features/          # auth, shift, order, checkout, incoming, kds, history,
│                          # settings, floor — one package per feature
├── docs/reference/        # exploration reports: core API, screen specs, tokens, assets
└── tool/gen-bindings.sh   # FRB codegen (M1)
```

The FFI wrapper crate lives with the core: `../madar-pos/rust-core/crates/madar-frb`.

## Commands

```bash
dart pub get                     # bootstrap the workspace
dart run melos run analyze       # static analysis (very_good_analysis)
dart run melos run format        # formatting check
dart run melos run test          # all package tests
dart run melos run gen           # build_runner codegen
dart run melos run bridge        # regenerate FRB bindings from madar-frb
```

- App ids: Android `com.madar.pos` (`.dev` suffix in debug so it installs beside the
  native app), iOS/macOS `com.madar.pos`.
- Orientation is locked to a single landscape, matching the natives.
- Launcher icons are copied from the native apps' sources (pixel parity), not generated.
- Behavioral spec per screen = the Kotlin **and** Swift implementations
  (`madar-pos/kotlin-app/.../app/madar/*.kt`, `madar-pos/swift-app/Sources/MadarUI/*.swift`)
  — read both before building a screen. Design tokens: `docs/reference/kotlinTokens.md`.
