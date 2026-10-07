#!/usr/bin/env bash
# Every check in every Madar repo, with one summary at the end.
#
#   tool/check_everything.sh            # repos beside this one (../MadarRust …)
#   MADAR_ROOT=~/Desktop/Madar tool/check_everything.sh
#
# A step passes only when it exits 0 AND printed no warning, no failure and no
# ignored or skipped test. Each step's full output is kept under $LOGS.
#
# Needs: the throwaway Postgres test cluster on :5433 (MadarRust CLAUDE.md,
# ../tool/test_pg_ram.sh), cargo-nextest, sqlx-cli, flutter, node.
#
# Suites that need a live backend are not part of this run, on purpose:
# madar-core's `backend-tests` feature (tool/offline_b_backend.sh) and the
# rust_bridge QA suites in qa_test/ (tool/qa_*.sh).
# Written for macOS's bash 3.2: no associative arrays, no `mapfile`.
set -u

ROOT="${MADAR_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
LOGS="${LOGS:-/tmp/madar-checks}"
rm -rf "$LOGS" && mkdir -p "$LOGS"
NAMES=()
RESULTS=()

# step <name> <warning regex|-> <skip regex|-> -- <command…>
step() {
  local name="$1" warn="$2" skip="$3"
  shift 4
  local log="$LOGS/$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_').log"
  printf '%-36s ' "$name"
  "$@" >"$log" 2>&1
  local rc=$? why=""
  [ $rc -ne 0 ] && why="exit $rc"
  if [ "$warn" != "-" ]; then
    local n
    n=$(grep -cE "$warn" "$log")
    [ "$n" -gt 0 ] && why="${why:+$why, }$n warning line(s)"
  fi
  if [ "$skip" != "-" ]; then
    local n
    n=$(grep -cE "$skip" "$log")
    [ "$n" -gt 0 ] && why="${why:+$why, }ignored/skipped tests"
  fi
  if [ -z "$why" ]; then
    echo "✓"
    RESULTS+=("✓ $name")
  else
    echo "✗ ($why) — $log"
    RESULTS+=("✗ $name — $why — $log")
  fi
  NAMES+=("$name")
}

RUST_WARN='^(warning|error)(\[|:)'
RUST_SKIP='test result: .* [1-9][0-9]* ignored'
FLUTTER_WARN='^Warning: |would not hit test|MISSING KEY|Unable to find a font|^ERROR: (ERROR: )?[^ ]'
FLUTTER_SKIP=' ~[0-9]+: |All tests skipped'

# ── madar-shared ──────────────────────────────────────────────
cd "$ROOT/madar-shared" || exit 1
step "shared · fmt" - - -- cargo fmt --all --check
step "shared · clippy" "$RUST_WARN" - -- cargo clippy --workspace --all-targets --locked -- -D warnings
step "shared · tests" "$RUST_WARN" "$RUST_SKIP" -- cargo test --workspace --locked
step "shared · authz-gen check" - - -- cargo run -q --locked -p authz-gen -- --check

# ── MadarRust ─────────────────────────────────────────────────
cd "$ROOT/MadarRust" || exit 1
export DATABASE_URL="${DATABASE_URL:-postgres://$USER@localhost:5433/madar}"
step "backend · migrate test cluster" - - -- sh -c '
  DATABASE_URL="${DATABASE_URL%/*}/madar" sqlx migrate run &&
  DATABASE_URL="${DATABASE_URL%/*}/template1" sqlx migrate run'
step "backend · fmt" - - -- cargo fmt --all --check
step "backend · clippy" "$RUST_WARN" - -- cargo clippy --all-targets --all-features -- -D warnings
step "backend · all suites" "$RUST_WARN" ' [1-9][0-9]* skipped' -- scripts/run_tests.sh

# ── MadarDashboard ────────────────────────────────────────────
cd "$ROOT/MadarDashboard" || exit 1
step "dashboard · install" - - -- npm ci --no-audit --no-fund
step "dashboard · lint" - - -- npm run lint
step "dashboard · tests" '^stderr \||Warning: |not wrapped in act' ' [1-9][0-9]* skipped' -- npx vitest run
step "dashboard · build" '\(!\)|warning' - -- npm run build

# ── madar (POS) ───────────────────────────────────────────────
cd "$ROOT/madar" || exit 1
step "pos · pub get" - - -- flutter pub get
step "pos · analyze" - - -- flutter analyze .
step "pos · format" - - -- sh -c "git ls-files '*.dart' | grep -v '/cargokit/' | xargs dart format --set-exit-if-changed --output=none"
step "pos · rust workspace" "$RUST_WARN" - -- sh -c 'cd rust-core && cargo check --workspace --all-targets --locked'
step "pos · core tests" "$RUST_WARN" "$RUST_SKIP" -- sh -c 'cd rust-core && cargo test -p madar-core --locked'
step "pos · bridge library" "$RUST_WARN" - -- sh -c 'cd rust-core && cargo build -p madar_frb --release --locked'
step "pos · kds" "$RUST_WARN" "$RUST_SKIP" -- sh -c 'cd apps/kds-slint && cargo test --locked'
for pkg in $(git ls-files '*/pubspec.yaml' | grep -v '/cargokit/' | xargs -n1 dirname | sort); do
  [ -d "$pkg/test" ] || continue
  step "pos · flutter $(basename "$pkg")" "$FLUTTER_WARN" "$FLUTTER_SKIP" -- sh -c "cd '$pkg' && flutter test --no-pub"
done

echo
echo "══════════ SUMMARY ══════════"
fails=0
for r in "${RESULTS[@]}"; do
  echo "$r"
  case "$r" in ✗*) fails=$((fails + 1)) ;; esac
done
echo
if [ $fails -eq 0 ]; then
  echo "ALL GREEN — ${#NAMES[@]} steps, no warnings, nothing skipped."
else
  echo "$fails of ${#NAMES[@]} steps need a look (logs in $LOGS)."
fi
exit $fails
