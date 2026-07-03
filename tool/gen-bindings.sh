#!/usr/bin/env bash
# Regenerate the flutter_rust_bridge bindings from madar-frb.
# Prereq: madar-api (the OpenAPI-generated client) must exist — same
# prerequisite the native builds have. We generate it if missing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_CORE="$ROOT/rust-core"

if [ ! -f "$RUST_CORE/crates/madar-api/Cargo.toml" ]; then
  echo "madar-api missing — generating from the backend OpenAPI spec…"
  (cd "$RUST_CORE" && ./tool/generate_api.sh)
fi

WANT="2.12.0"
GOT="$(flutter_rust_bridge_codegen --version | awk '{print $2}')"
if [ "$GOT" != "$WANT" ]; then
  echo "flutter_rust_bridge_codegen $GOT != $WANT (the version pinned in madar-frb/Cargo.toml + pubspec)." >&2
  echo "Install the matching CLI: cargo install flutter_rust_bridge_codegen --version $WANT --force" >&2
  exit 1
fi

cd "$ROOT/packages/rust_bridge"
flutter_rust_bridge_codegen generate

echo "cargo check (madar-frb)…"
cargo check -p madar_frb --manifest-path "$RUST_CORE/Cargo.toml"

echo "bindings regenerated ✓"
