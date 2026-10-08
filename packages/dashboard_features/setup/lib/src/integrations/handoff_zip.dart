/// The AES-256 encrypted handoff archive (`handoff-zip.ts`, SET-INT-020).
///
/// WinZip AES (method 99, strength 3 = AES-256, PBKDF2-HMAC-SHA1 keys, an
/// HMAC-SHA1 tag per entry) — never the legacy ZipCrypto cipher. 7-Zip,
/// WinRAR and Keka open it; the Windows and macOS built-in extractors and
/// Info-ZIP `unzip` cannot, which is why the dialog names the tools.
///
/// Built on the UI isolate, as the web builds it on the main thread: the
/// archive is two small text files.
library;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'handoff_content.dart';

/// The archive's bytes for [files], encrypted with [passphrase].
List<int> encryptedHandoffZip(List<HandoffFile> files, String passphrase) {
  final archive = Archive();
  for (final f in files) {
    archive.addFile(ArchiveFile.string(f.name, f.text));
  }
  return ZipEncoder(password: passphrase).encodeBytes(archive);
}

/// Builds the archive (asynchronously, so the "Preparing…" frame shows
/// first). Tests replace [build] to hold or fail it.
abstract final class HandoffZipBuilder {
  static Future<List<int>> _default(
    List<HandoffFile> files,
    String passphrase,
  ) => Future(() => encryptedHandoffZip(files, passphrase));

  @visibleForTesting
  static Future<List<int>> Function(List<HandoffFile> files, String passphrase)
  build = _default;

  @visibleForTesting
  static void reset() => build = _default;
}

/// The archive's MIME type.
const String zipMimeType = 'application/zip';
