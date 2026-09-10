#!/usr/bin/env bash
# Regenerates the typed Rust API client (crates/madar-api) from the MadarRust
# backend OpenAPI spec. Rust-core equivalent of the Flutter app's
# tool/generate_api.sh and the dashboard's `npm run generate:api`.
#
# Requires: cargo (backend checkout, to re-export the spec), node/npx, Java 17+.
set -euo pipefail

CORE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="${MADAR_BACKEND_DIR:-$CORE_DIR/../../MadarRust}"
PKG_DIR="$CORE_DIR/crates/madar-api"
SPEC="$BACKEND_DIR/openapi.json"

# 1/4 — (Re)export the spec from the backend unless SKIP_EXPORT=1.
if [[ "${SKIP_EXPORT:-0}" != "1" ]]; then
  echo "── 1/4 Exporting OpenAPI spec from backend…"
  ( cd "$BACKEND_DIR" && cargo run --quiet --bin export-openapi ) || {
    echo "   (export-openapi failed — falling back to existing $SPEC)"
  }
else
  echo "── 1/4 SKIP_EXPORT=1 — using existing $SPEC"
fi
[[ -f "$SPEC" ]] || { echo "!! spec not found at $SPEC"; exit 1; }

# 2/4 — Generate the Rust client (async reqwest, single-request-param structs).
echo "── 2/4 Generating Rust client (openapi-generator -g rust)…"
rm -rf "$PKG_DIR"
npx --yes @openapitools/openapi-generator-cli generate \
  -i "$SPEC" \
  -g rust \
  -o "$PKG_DIR" \
  --additional-properties=packageName=madar-api,supportAsync=true,library=reqwest,useSingleRequestParameter=true,preferUnsignedInt=true,bestFitInt=true

# 3/4 — Post-process.
#
# This step used to exist because the backend serialized BigDecimal columns as
# JSON STRINGS while the generator typed them as f64, so the plan was to make
# the CLIENT string-tolerant, "in Phase 2". Phase 2 never happened, and the
# defect was instead worked around three separate times — a local serializer for
# one field in `orders`, a `serde_json::Value` capture in `madar-core::menu`,
# and this note — while every other field kept shipping a string. The one place
# nobody had worked around was a shop's tax rate, where it read as "I set 14, it
# saved, and nothing changed".
#
# It is fixed at the source now: `MadarRust/src/decimals.rs` serializes every
# `numeric` as a number, and a guard test fails the build if a new field forgets
# the annotation. The generated client's `f64` is finally what the wire carries,
# so there is nothing to post-process.
echo "── 3/4 Post-processing (nothing to do: the wire matches the schema)…"
# Keep the generated crate out of the workspace's lint/doc noise.
cat > "$PKG_DIR/.openapi-generator-ignore" <<'EOF'
# Re-written by tool/generate_api.sh
.travis.yml
git_push.sh
EOF
# Silence clippy across the generated crate — it's machine output, not ours, and
# a workspace member now (so `cargo clippy` would otherwise flood with
# needless-return style lints). lib.rs already carries some allow attrs.
if ! grep -q 'allow(clippy::all)' "$PKG_DIR/src/lib.rs"; then
  { echo '#![allow(clippy::all)]'; cat "$PKG_DIR/src/lib.rs"; } > "$PKG_DIR/src/lib.rs.tmp" \
    && mv "$PKG_DIR/src/lib.rs.tmp" "$PKG_DIR/src/lib.rs"
fi

# Normalise the formatting.
#
# The generator writes its own style — no trailing commas, its own import
# order, long single-line signatures. Anyone who has ever run `cargo fmt` at
# the workspace root has rustfmt'd this crate, and what is committed is
# rustfmt'd. So without this step EVERY regeneration produces a five-hundred
# file diff that is pure formatting, burying the handful of lines that actually
# changed and making `cargo fmt --check` fail on machine output nobody wrote.
echo "── 3.5/4 rustfmt the generated crate…"
( cd "$PKG_DIR" && cargo fmt ) || echo "   (rustfmt unavailable — skipping)"

# 4/4 — Sanity compile the generated crate on its own.
echo "── 4/4 cargo check on generated client…"
( cd "$PKG_DIR" && cargo check --quiet ) && echo "   generated client compiles ✓" || {
  echo "!! generated client failed to compile — inspect $PKG_DIR (expected on first run; see Phase 2 notes)"
}

echo "Done. Generated Rust client lives in $PKG_DIR"
