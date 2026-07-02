#!/usr/bin/env bash
# Offline→online outbox-drain reproduction. Requires the local QA backend on
# :8081 (see qa_flow_test.dart header). Runs the drain test behind a killable
# TCP proxy and flips the "network" when the test asks via marker files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKERS="$(mktemp -d)"
PROXY_PID=""

start_proxy() { python3 "$ROOT/tool/tcp_proxy.py" 8099 8081 & PROXY_PID=$!; sleep 0.5; }
stop_proxy()  { [ -n "$PROXY_PID" ] && kill "$PROXY_PID" 2>/dev/null || true; PROXY_PID=""; }
cleanup()     { stop_proxy; rm -rf "$MARKERS"; }
trap cleanup EXIT

start_proxy

# Watcher: flip the proxy when the test asks.
(
  until [ -f "$MARKERS/qa_offline.req" ]; do sleep 0.2; done
  kill "$PROXY_PID" 2>/dev/null || true
  sleep 0.5
  touch "$MARKERS/qa_offline.ack"
  echo "── proxy DOWN (offline)"
  until [ -f "$MARKERS/qa_online.req" ]; do sleep 0.2; done
  python3 "$ROOT/tool/tcp_proxy.py" 8099 8081 &
  echo $! > "$MARKERS/proxy2.pid"
  sleep 0.5
  touch "$MARKERS/qa_online.ack"
  echo "── proxy UP (online)"
) &
WATCHER_PID=$!

cd "$ROOT/packages/rust_bridge"
MADAR_QA_API=http://127.0.0.1:8099 \
MADAR_QA_EMAIL="${MADAR_QA_EMAIL:?set the seeded org email}" \
MADAR_QA_PASSWORD="${MADAR_QA_PASSWORD:?set the seeded org password}" \
MADAR_QA_MARKERS="$MARKERS" \
flutter test --tags qa-offline test/qa_offline_drain_test.dart
STATUS=$?

kill "$WATCHER_PID" 2>/dev/null || true
[ -f "$MARKERS/proxy2.pid" ] && kill "$(cat "$MARKERS/proxy2.pid")" 2>/dev/null || true
exit $STATUS
