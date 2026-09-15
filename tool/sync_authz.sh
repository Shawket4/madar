#!/usr/bin/env bash
# Regenerate the permission registry into this repo from the backend's spec.
#
# The spec (MadarRust/authz/spec/capabilities.toml) is the single source of
# truth. This writes:
#   rust-core/crates/madar-authz/                      (vendored crate, byte-identical)
#   packages/app_core/lib/src/generated/capabilities.dart
# `--check` fails when either is stale. Never edit those files by hand: the
# crate's `crate_hash_matches_its_files` test fails on a hand edit.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MADAR_RUST="${MADAR_RUST:-$(cd "$ROOT/../MadarRust" && pwd)}"
cargo run --quiet --manifest-path "$MADAR_RUST/authz/gen/Cargo.toml" -- --pos "$ROOT" "$@"
