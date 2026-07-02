# Package version research (verified against pub.dev, 2026-07-02)

Toolchain on this machine: Flutter 3.41.4 stable / Dart 3.11.1 / Rust 1.90.

| Package | Latest stable | Notes |
|---|---|---|
| riverpod / flutter_riverpod | 3.3.2 | 3.x is the stable line; pairs with annotation/generator 4.x |
| riverpod_annotation | 4.0.3 | |
| riverpod_generator | 4.0.4 | |
| go_router | 17.3.0 | |
| freezed | 3.2.5 | 3.x current (4.0 still dev prerelease — skip) |
| flutter_rust_bridge | 2.12.0 | 2.13 is still beta. Cargo crate + pub package + codegen CLI must be the SAME version (FRB requirement) — install all three at latest stable and upgrade together |
| melos | 8.0.0 | Built on Dart pub workspaces: root `workspace:` key + `resolution: workspace` per member; config lives in root pubspec `melos:` section |
| very_good_analysis | 10.3.0 | |
| skeletonizer | 2.1.3 | Not used — the natives' skeleton is a simple 900 ms alpha pulse we implement directly in design_system |

Policy (user-confirmed): latest stable of everything, caret constraints, nothing pinned —
`flutter pub add` resolves at scaffold time. The FRB three-way version match is the only
lockstep requirement, and it's FRB's own, not a pin to an old version.
