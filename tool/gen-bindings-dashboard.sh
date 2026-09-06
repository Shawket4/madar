#!/usr/bin/env bash
# Regenerate the flutter_rust_bridge bindings for the DASHBOARD bridge
# (madar-frb-dashboard → packages/rust_bridge_dashboard). Parallel to
# tool/gen-bindings.sh (the teller/POS bridge) — a SEPARATE bindings binary.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_CORE="$ROOT/rust-core"

if [ ! -f "$RUST_CORE/crates/madar-api/Cargo.toml" ]; then
  echo "madar-api missing — generating from the backend OpenAPI spec…"
  (cd "$RUST_CORE" && ./tool/generate_api.sh)
fi

WANT="2.13.0"
GOT="$(flutter_rust_bridge_codegen --version | awk '{print $2}')"
if [ "$GOT" != "$WANT" ]; then
  echo "flutter_rust_bridge_codegen $GOT != $WANT (pinned in madar-frb-dashboard/Cargo.toml + pubspec)." >&2
  echo "Install the matching CLI: cargo install flutter_rust_bridge_codegen --version $WANT --force" >&2
  exit 1
fi

cd "$ROOT/packages/rust_bridge_dashboard"
flutter_rust_bridge_codegen generate

echo "cargo check (madar-frb-dashboard)…"
cargo check -p madar_frb_dashboard --manifest-path "$RUST_CORE/Cargo.toml"

echo "dashboard bindings regenerated ✓"
