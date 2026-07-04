#!/usr/bin/env bash
# Optimized release builds — every platform, every flag that matters.
#
#   tool/build-release.sh android   # per-ABI APKs (arm64 + arm32)
#   tool/build-release.sh aab       # Play Store bundle
#   tool/build-release.sh ios       # App Store archive (needs signing)
#   tool/build-release.sh macos
#   tool/build-release.sh all
#
# What the flags buy:
#   --obfuscate --split-debug-info  Dart AOT symbols stripped from the binary
#                                   (smaller, and stack traces stay decodable
#                                   via the saved symbol files under
#                                   build/symbols/<platform> — KEEP those per
#                                   release or crashes are unreadable).
#   --split-per-abi                 one lean APK per CPU instead of a fat one.
# Gradle adds R8 + resource shrinking + en/ar-only locales (build.gradle.kts);
# the Rust core builds with fat LTO + codegen-units=1 + full symbol strip, and
# the cdylib exports ONLY the FRB surface (madar-frb/build.rs) so the archived
# natives' UniFFI scaffolding is dead-stripped.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/apps/madar"
SYM="$APP/build/symbols"
cd "$APP"

android() {
  flutter build apk --release --split-per-abi \
    --target-platform android-arm64,android-arm \
    --obfuscate --split-debug-info="$SYM/android"
  ls -la build/app/outputs/flutter-apk/*release*.apk
}

aab() {
  flutter build appbundle --release \
    --obfuscate --split-debug-info="$SYM/android"
  ls -la build/app/outputs/bundle/release/*.aab
}

ios() {
  flutter build ipa --release \
    --obfuscate --split-debug-info="$SYM/ios"
}

macos() {
  flutter build macos --release \
    --obfuscate --split-debug-info="$SYM/macos"
}

case "${1:-all}" in
  android) android ;;
  aab) aab ;;
  ios) ios ;;
  macos) macos ;;
  all) android; aab; macos; ios ;;
  *) echo "usage: $0 [android|aab|ios|macos|all]" >&2; exit 1 ;;
esac
