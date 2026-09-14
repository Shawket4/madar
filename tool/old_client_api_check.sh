#!/usr/bin/env bash
# Old-client API compatibility check (tills rework guard).
#
# POS v0.5.0, v0.5.1, v0.6.0 and v0.6.1 are in the field and must keep working against the new
# backend. This checks out the madar-api crate (generated models) of each old
# release into a temp git worktree, builds a tiny harness against it, and:
#   1. (always) deserializes every golden backend response in
#      MadarRust/tests/fixtures/legacy_till_api/ into that release's models
#      (tests/golden_parse.rs, driven by manifest.json's `clients` list);
#   2. (--regen-envelopes) regenerates the /sync/replay envelopes that release's
#      core produces into MadarRust/tests/fixtures/legacy_replay/<release>/.
#
# Usage:
#   tool/old_client_api_check.sh                      # check every release
#   tool/old_client_api_check.sh v0.6.0               # one release
#   tool/old_client_api_check.sh --regen-envelopes    # also rewrite envelope fixtures
#   MADAR_RUST=/path/to/MadarRust GOLDEN_DIR=/other/dir tool/old_client_api_check.sh
#
# Today (pre-rename) it passes; after the rename, re-capture the golden JSON from
# the NEW backend's legacy /shifts adapters and rerun — a failure means an old
# tablet would fail to decode a response.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MADAR_RUST="${MADAR_RUST:-$(cd "$ROOT/../MadarRust" && pwd)}"
GOLDEN_DIR="${GOLDEN_DIR:-$MADAR_RUST/tests/fixtures/legacy_till_api}"
TARGET="${CARGO_TARGET_DIR:-${TMPDIR:-/tmp}/old_client_api_check_target}"

# release label -> git ref : cargo feature
# v0.5.0 is checked against the goldens listed for v0.5.1 (a patch release on
# the same endpoints), with its own feature for where its models differ.
declare -a RELEASES=("v0.5.0:v0.5.0:v050" "v0.5.1:v0.5.1:v051" "v0.6.0:97c4a29:v060" "v0.6.1:v0.6.1:v061")

REGEN=0
ONLY=""
for a in "$@"; do
  case "$a" in
    --regen-envelopes) REGEN=1 ;;
    v0.5.0|v0.5.1|v0.6.0|v0.6.1) ONLY="$a" ;;
    -h|--help) sed -n 2,21p "$0"; exit 0 ;;
    *) echo "unknown arg $a" >&2; exit 2 ;;
  esac
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/old_client_api_check.XXXXXX")"
cleanup() {
  for d in "$TMP"/wt-*; do
    [ -d "$d" ] && git -C "$ROOT" worktree remove --force "$d" >/dev/null 2>&1 || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

status=0
for spec in "${RELEASES[@]}"; do
  IFS=: read -r label ref feat <<<"$spec"
  [ -n "$ONLY" ] && [ "$ONLY" != "$label" ] && continue
  echo "==> $label ($ref)"
  wt="$TMP/wt-$label"
  git -C "$ROOT" worktree add --detach "$wt" "$ref" >/dev/null
  h="$TMP/harness-$label"
  cp -R "$ROOT/tool/old_client_api_check" "$h"
  sed "s#@MADAR_API@#$wt/rust-core/crates/madar-api#" "$h/Cargo.toml.in" >"$h/Cargo.toml"
  # Pin dependency versions to what that release actually shipped with.
  cp "$wt/rust-core/Cargo.lock" "$h/Cargo.lock"
  if [ "$REGEN" = 1 ]; then
    out="$MADAR_RUST/tests/fixtures/legacy_replay/$label"
    rm -rf "$out"
    (cd "$h" && CARGO_TARGET_DIR="$TARGET" cargo run -q --features "$feat" --bin gen_envelopes -- "$out")
  fi
  if ! (cd "$h" && GOLDEN_DIR="$GOLDEN_DIR" CARGO_TARGET_DIR="$TARGET" \
        cargo test -q --features "$feat" --test golden_parse -- --nocapture); then
    echo "FAIL: $label cannot decode the golden responses" >&2
    status=1
  fi
done
exit $status
