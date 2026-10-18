#!/usr/bin/env bash
# Ad-hoc signs an UNSIGNED iOS archive (`xcodebuild archive ... CODE_SIGNING_ALLOWED=NO`)
# so the App Store export that follows keeps the app's entitlements.
#
#   tool/ios_adhoc_sign.sh <path/to/App.xcarchive> [path/to/App.entitlements]
#
# Why the release workflows archive unsigned: signing the archive asked Apple
# for a new Apple Development certificate on every run (each runner is a fresh
# machine), until the team hit Apple's limit and every iOS release failed
# ("maximum number of certificates"). The export (`-exportArchive`,
# app-store-connect) signs everything for the App Store with Apple's
# cloud-managed distribution certificate, and takes the app's entitlements
# from the signature it finds on the archived app: a plain unsigned archive
# exports WITHOUT them (push silently gone), hence this ad-hoc signature.
#
# Inside out, as codesign requires: embedded frameworks / dylibs the build left
# unsigned first (no entitlements; the export re-signs them), then the app with
# its entitlements. An app extension would need its own entitlements, so one
# showing up fails the step instead of shipping it wrong.
#
# Guard: every entitlement the file declares must be on the signed app. With
# no entitlements file (the app declares none), the signature is verified only.
set -euo pipefail

ARCHIVE=${1:?usage: ios_adhoc_sign.sh <archive> [entitlements]}
ENTITLEMENTS=${2:-}

APP=$(ls -d "$ARCHIVE/Products/Applications/"*.app)

if compgen -G "$APP/PlugIns/*.appex" > /dev/null || compgen -G "$APP/Extensions/*.appex" > /dev/null; then
  echo "::error::$APP embeds an app extension; give it its own ad-hoc signature with its entitlements here."
  exit 1
fi

shopt -s nullglob
for nested in "$APP"/Frameworks/*.framework "$APP"/Frameworks/*.dylib; do
  codesign --verify "$nested" 2> /dev/null || codesign --force --sign - "$nested"
done
shopt -u nullglob

if [ -n "$ENTITLEMENTS" ]; then
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

if [ -n "$ENTITLEMENTS" ]; then
  SIGNED=$(codesign -d --entitlements :- "$APP" 2> /dev/null)
  for key in $(sed -n 's:.*<key>\(.*\)</key>.*:\1:p' "$ENTITLEMENTS"); do
    grep -q "<key>$key</key>" <<< "$SIGNED" \
      || { echo "::error::The archived app lost its $key entitlement."; exit 1; }
  done
  echo "Ad-hoc signed $(basename "$APP") with: $(sed -n 's:.*<key>\(.*\)</key>.*:\1:p' "$ENTITLEMENTS" | xargs)"
else
  echo "Ad-hoc signed $(basename "$APP") (it declares no entitlements)."
fi
