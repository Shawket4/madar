// Where the cargo-built core lives, per platform.
//
// The suites used to name `libmadar_frb.dylib` outright, which is the macOS
// artifact. That was fine while CI only ran on macOS and quietly wrong
// everywhere else: the tests call `markTestSkipped()` when the library is
// missing, so on any other platform they went GREEN having loaded nothing.
//
// `cargo build -p madar_frb --release` writes:
//   macOS    libmadar_frb.dylib
//   Linux    libmadar_frb.so
//   Windows  madar_frb.dll     (no `lib` prefix)
import 'dart:io';

/// The release artifact for the host platform, relative to a package under
/// `packages/`.
File hostLibrary() {
  final name = Platform.isWindows
      ? 'madar_frb.dll'
      : Platform.isMacOS
      ? 'libmadar_frb.dylib'
      : 'libmadar_frb.so';
  return File('${Directory.current.path}/../../rust-core/target/release/$name');
}

/// What to tell someone whose run skipped, naming the file that was looked for.
String buildItFirst() =>
    'Run: cargo build -p madar_frb --release '
    '(--manifest-path rust-core/Cargo.toml)\n'
    'Looked for: ${hostLibrary().path}';
