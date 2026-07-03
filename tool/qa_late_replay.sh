#!/usr/bin/env bash
# Late-replay reproduction: orders queued offline replay into a shift that
# ANOTHER till closed while this device was offline. On the offline signal the
# runner kills the proxy AND closes the branch's open shift via psql (the
# "other till"), so the drain replays into a genuinely-closed shift.
#
# Requires the local QA backend on :8081 and psql access to its DB.
#   MADAR_QA_EMAIL=... MADAR_QA_PASSWORD=... MADAR_QA_DB=madar_flutter_qa \
#     tool/qa_late_replay.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKERS="$(mktemp -d)"
DB="${MADAR_QA_DB:-madar_flutter_qa}"
PROXY_PID=""

start_proxy() { python3 "$ROOT/tool/tcp_proxy.py" 8099 8081 & PROXY_PID=$!; sleep 0.5; }
cleanup() {
  [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true
  [ -f "$MARKERS/proxy2.pid" ] && kill "$(cat "$MARKERS/proxy2.pid")" 2>/dev/null || true
  rm -rf "$MARKERS"
}
trap cleanup EXIT

start_proxy

(
  until [ -f "$MARKERS/qa_offline.req" ]; do sleep 0.2; done
  kill "$PROXY_PID" 2>/dev/null || true
  # The OTHER till closes the branch's open shift while we're offline.
  psql "$DB" -q -c \
    "UPDATE shifts SET status='closed', closed_at=now(), \
       closing_cash_declared=closing_cash_declared, \
       closing_cash_system=(SELECT opening_cash FROM shifts s2 WHERE s2.id=shifts.id) \
     WHERE status='open'" >/dev/null
  echo "── proxy DOWN + shift CLOSED by the other till"
  sleep 0.3
  touch "$MARKERS/qa_offline.ack"
  until [ -f "$MARKERS/qa_online.req" ]; do sleep 0.2; done
  python3 "$ROOT/tool/tcp_proxy.py" 8099 8081 &
  echo $! > "$MARKERS/proxy2.pid"
  sleep 0.5
  touch "$MARKERS/qa_online.ack"
  echo "── proxy UP (online) — draining into the closed shift"
) &
WATCHER_PID=$!

cd "$ROOT/packages/rust_bridge"
MADAR_QA_API=http://127.0.0.1:8099 \
MADAR_QA_EMAIL="${MADAR_QA_EMAIL:?set the seeded org email}" \
MADAR_QA_PASSWORD="${MADAR_QA_PASSWORD:?set the seeded org password}" \
MADAR_QA_MARKERS="$MARKERS" \
flutter test --tags qa-late-replay test/qa_late_replay_test.dart
STATUS=$?

kill "$WATCHER_PID" 2>/dev/null || true
exit $STATUS
