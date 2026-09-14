# old_client_api_check

Harness used by `tool/old_client_api_check.sh` (tills rework compat guard).
Not a workspace member: the script copies it beside a temp `git worktree` of an old
release (v0.5.1 = tag `v0.5.1`, v0.6.0 = commit `97c4a29`, v0.6.1 = tag `v0.6.1`), fills `Cargo.toml.in`
with that worktree's `rust-core/crates/madar-api`, pins its `Cargo.lock`, then:

- `tests/golden_parse.rs` — decodes `MadarRust/tests/fixtures/legacy_till_api/*.json`
  (per `manifest.json`) into that release's models. Passes on the pre-rename backend.
- `src/bin/gen_envelopes.rs` (`--regen-envelopes`) — rewrites
  `MadarRust/tests/fixtures/legacy_replay/<release>/`.

```
tool/old_client_api_check.sh                 # every release
tool/old_client_api_check.sh v0.6.0          # one
tool/old_client_api_check.sh --regen-envelopes
MADAR_RUST=/path/MadarRust GOLDEN_DIR=/dir tool/old_client_api_check.sh
```
After the rename: re-capture golden JSON from the NEW backend
(`MadarRust/scripts/legacy_till_golden/capture.sh`) and rerun; any failure is an old
tablet that can no longer decode a response.
