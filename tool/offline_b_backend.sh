#!/usr/bin/env bash
# Offline plan B against the REAL backend, in one command.
#
#   tool/offline_b_backend.sh            # the scenarios (offline day, two devices, 1000-sale backlog)
#   tool/offline_b_backend.sh --perf     # also the large-branch performance probe
#
# What it does, and undoes:
#   1. builds the backend (`madar-rust`, the `scenario` profile: release without LTO) from $MADAR_RUST;
#   2. copies a LOCAL database with `createdb -T` ($MADAR_OB_SOURCE_DB, default
#      madar_dash_tills) — never madar_dev or madar_prodcopy, which it refuses;
#   3. starts the backend on a free port against the copy (it migrates the copy);
#   4. picks a branch that can sell (active org, a cash method, a priced item),
#      or uses $MADAR_OB_BRANCH;
#   5. runs `tests/offline_b_backend.rs` (and `offline_b_perf.rs` with --perf);
#   6. stops the backend and drops the copy — also on failure or Ctrl-C.
#
# Environment:
#   MADAR_RUST            backend checkout (default ../MadarRust next to this repo)
#   MADAR_OB_SOURCE_DB    database to copy (default madar_dash_tills)
#   MADAR_OB_PG           psql connection prefix (default: -p 5432)
#   MADAR_OB_BRANCH       branch id to use (default: picked)
#   MADAR_OB_PERF_BRANCH  branch for --perf (default: the branch with the most sales on an open till)
#   MADAR_OB_BUILD_DATABASE_URL  migrated DB for the backend build (default :5433/madar)
#   MADAR_OB_BACKEND_TARGET_DIR  the backend's cargo target dir (default $MADAR_RUST/target)
#   MADAR_OB_TESTS        space-separated test targets (default offline_b_backend;
#                         readpath_parity = the read-path parity scenarios,
#                         pricing_backend = the PRICING_TAX_AUDIT scenarios,
#                         metrics_backend = the Metrics screen: device vs endpoint)
#   MADAR_OB_FILTER       a test-name filter within the targets (default: all)
#   MADAR_OB_TEST         one test target (older name; used when MADAR_OB_TESTS is unset)
#   CARGO_TARGET_DIR      this repo's cargo target dir, as usual
# Exit status is the tests' status.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MADAR_RUST="${MADAR_RUST:-$(cd "$ROOT/../MadarRust" && pwd)}"
SOURCE_DB="${MADAR_OB_SOURCE_DB:-madar_dash_tills}"
PG_ARGS=(${MADAR_OB_PG:--p 5432})
PERF=0
[[ "${1:-}" == "--perf" ]] && PERF=1

case "$SOURCE_DB" in
  madar_dev|madar_prodcopy|madar) echo "refusing to copy $SOURCE_DB: use a throwaway source database" >&2; exit 2 ;;
esac

COPY="madar_ob_it_$$"
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
LOG="$(mktemp -t madar_ob_backend.XXXXXX)"
PID=""

cleanup() {
  local status=$?
  if [[ -n "$PID" ]]; then kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; fi
  psql "${PG_ARGS[@]}" -d postgres -qc "DROP DATABASE IF EXISTS \"$COPY\" WITH (FORCE)" >/dev/null 2>&1 || true
  if [[ $status -ne 0 ]]; then echo "backend log: $LOG" >&2; else rm -f "$LOG"; fi
  exit $status
}
trap cleanup EXIT INT TERM

echo "==> building the backend ($MADAR_RUST)"
# The backend's compile-time query checks need a migrated database (its CLAUDE.md:
# the throwaway :5433 cluster).
BACKEND_TARGET="${MADAR_OB_BACKEND_TARGET_DIR:-$MADAR_RUST/target}"
( cd "$MADAR_RUST" && CARGO_TARGET_DIR="$BACKEND_TARGET" \
    DATABASE_URL="${MADAR_OB_BUILD_DATABASE_URL:-postgres://$(whoami)@localhost:5433/madar}" \
    cargo build --profile scenario --bin madar-rust )
BIN="$BACKEND_TARGET/scenario/madar-rust"

echo "==> copying $SOURCE_DB -> $COPY"
createdb "${PG_ARGS[@]}" -T "$SOURCE_DB" "$COPY"
DB_URL="postgres://${PGUSER:-$(whoami)}@localhost:$(printf '%s' "${PG_ARGS[*]}" | sed -E 's/.*-p ?([0-9]+).*/\1/')/$COPY"

echo "==> starting the backend on :$PORT"
ASSET_URL_SECRET="$(openssl rand -hex 32)" JWT_SECRET="$(openssl rand -hex 32)" \
  MADAR_PIN_FINGERPRINT_KEY="$(openssl rand -hex 32)" MADAR_AUTHZ_SIGNING_KEY="$(openssl rand -hex 32)" \
  DATABASE_URL="$DB_URL" BIND_ADDR="127.0.0.1:$PORT" MADAR_DISABLE_AUTO_TRANSLATION=1 \
  "$BIN" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 120); do
  if curl -fs -o /dev/null "http://127.0.0.1:$PORT/health"; then break; fi
  if ! kill -0 "$PID" 2>/dev/null; then echo "backend exited" >&2; tail -20 "$LOG" >&2; exit 1; fi
  sleep 1
done
curl -fs -o /dev/null "http://127.0.0.1:$PORT/health"

q() { psql "${PG_ARGS[@]}" -d "$COPY" -Atc "$1"; }
BRANCH="${MADAR_OB_BRANCH:-$(q "
  SELECT b.id FROM branches b JOIN organizations o ON o.id = b.org_id
   WHERE b.deleted_at IS NULL AND b.is_active AND o.is_active
     AND EXISTS (SELECT 1 FROM org_payment_methods m WHERE m.org_id = o.id AND m.is_active AND m.is_cash)
     AND EXISTS (SELECT 1 FROM org_payment_methods m WHERE m.org_id = o.id AND m.is_active AND NOT m.is_cash)
     AND EXISTS (SELECT 1 FROM menu_items i WHERE i.org_id = o.id AND i.is_active AND i.deleted_at IS NULL AND i.base_price > 0)
   ORDER BY (SELECT count(*) FROM tills t WHERE t.branch_id = b.id AND t.status = 'open'), b.created_at
   LIMIT 1")}"
[[ -n "$BRANCH" ]] || { echo "no branch in $SOURCE_DB can sell (org active + cash + card + a priced item)" >&2; exit 1; }
echo "==> branch $BRANCH"

cd "$ROOT/rust-core"
export MADAR_OB_BASE="http://127.0.0.1:$PORT" MADAR_OB_DB="$DB_URL" MADAR_OB_BRANCH="$BRANCH"
for t in ${MADAR_OB_TESTS:-${MADAR_OB_TEST:-offline_b_backend}}; do
  echo "==> scenarios: $t"
  cargo test -p madar-core --test "$t" -- ${MADAR_OB_FILTER:-} --ignored --nocapture --test-threads=1
done

if [[ $PERF -eq 1 ]]; then
  PERF_TILL="$(q "SELECT t.id FROM tills t JOIN orders o ON o.till_id = t.id
                   WHERE t.status = 'open' GROUP BY t.id ORDER BY count(*) DESC LIMIT 1")"
  PERF_BRANCH="${MADAR_OB_PERF_BRANCH:-$(q "SELECT branch_id FROM tills WHERE id = '$PERF_TILL'")}"
  # Grow that open till to >= 30k sales in the COPY (its branch's sales, copied
  # with fresh ids, refs and numbers) so the probe measures a large window.
  echo "==> seeding $PERF_TILL to >= 30000 sales (copy only)"
  psql "${PG_ARGS[@]}" -d "$COPY" -v ON_ERROR_STOP=1 -q <<SQL
CREATE TEMP TABLE src AS SELECT o.* FROM orders o WHERE o.branch_id = '$PERF_BRANCH' AND o.open_ticket_id IS NULL;
CREATE TEMP TABLE m AS
  SELECT s.id AS old_id, gen_random_uuid() AS new_id, g, row_number() OVER () AS rn
    FROM src s CROSS JOIN generate_series(1, GREATEST(1, CEIL(30000.0 / GREATEST((SELECT count(*) FROM src), 1))::int)) g;
INSERT INTO orders SELECT (jsonb_populate_record(NULL::orders, to_jsonb(s) || jsonb_build_object(
    'id', m.new_id, 'till_id', '$PERF_TILL', 'idempotency_key', NULL, 'order_ref', s.order_ref || '-P' || m.g || '-' || m.rn,
    'order_number', 5000000 + m.rn, 'device_id', NULL, 'device_code', NULL,
    'created_at', now() - (random() * interval '14 days'), 'updated_at', now()))).*
  FROM m JOIN src s ON s.id = m.old_id;
INSERT INTO order_items SELECT (jsonb_populate_record(NULL::order_items, to_jsonb(i) || jsonb_build_object('id', gen_random_uuid(), 'order_id', m.new_id))).*
  FROM m JOIN order_items i ON i.order_id = m.old_id;
INSERT INTO order_payments SELECT (jsonb_populate_record(NULL::order_payments, to_jsonb(p) || jsonb_build_object('id', gen_random_uuid(), 'order_id', m.new_id))).*
  FROM m JOIN order_payments p ON p.order_id = m.old_id;
SQL
  psql "${PG_ARGS[@]}" -d "$COPY" -qc "VACUUM ANALYZE" >/dev/null
  echo "==> performance probe on $PERF_BRANCH"
  MADAR_OB_BRANCH="$PERF_BRANCH" cargo test --release -p madar-core --test offline_b_perf -- --ignored --nocapture
fi
echo "==> all passed"
