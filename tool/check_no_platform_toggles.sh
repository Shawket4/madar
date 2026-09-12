#!/usr/bin/env bash
# Every toggle in the product is MadarSegmented (design_system controls.dart).
# Fails when a platform toggle creeps back into packages/ or apps/.
set -euo pipefail
cd "$(dirname "$0")/.."
pattern='\b(Switch|CupertinoSwitch|SwitchListTile|CupertinoSwitch|ToggleButtons|SegmentedButton|CupertinoSegmentedControl|CupertinoSlidingSegmentedControl)(\.adaptive)?\s*(<[^>]*>)?\('
hits=$(grep -rnE "$pattern" packages apps --include='*.dart' \
  --exclude-dir=build --exclude-dir=.dart_tool \
  --exclude-dir=rust_bridge --exclude-dir=rust_bridge_dashboard --exclude-dir=rust_bridge_staff || true)
if [[ -n "$hits" ]]; then
  echo "Platform toggles found — use MadarSegmented instead:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "OK: no platform toggles"
