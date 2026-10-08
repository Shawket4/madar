/// Where the integrations unit gets its randomness: the platform's CSPRNG,
/// never a seeded or time-based fallback (`passphrase.ts` `hasSecureRandom`,
/// `secureRandomBytes`).
///
/// One seam, so a test can stand in for a device without a secure source
/// (SET-INT-011) or pin the bytes.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Fills a buffer with random bytes.
typedef RandomBytes = void Function(Uint8List out);

/// Thrown rather than ever silently falling back to a non-secure source.
class InsecureRandomError implements Exception {
  const InsecureRandomError();

  @override
  String toString() =>
      'Secure random number generation is unavailable on this device.';
}

/// The secure random source: `Random.secure()`, or null when the platform
/// has none (it throws `UnsupportedError` there).
abstract final class IntegrationsRandom {
  static Random? _platform() {
    try {
      return Random.secure();
    } on UnsupportedError {
      return null;
    }
  }

  /// The source in use. Tests replace it (null = no CSPRNG) and put it back
  /// with [reset].
  @visibleForTesting
  static Random? Function() source = _platform;

  @visibleForTesting
  static void reset() => source = _platform;

  /// Whether a secure source exists (`hasSecureRandom()`).
  static bool get available => source() != null;

  /// Fills [out] from the secure source; [InsecureRandomError] without one.
  static void fill(Uint8List out) {
    final r = source();
    if (r == null) throw const InsecureRandomError();
    for (var i = 0; i < out.length; i++) {
      out[i] = r.nextInt(256);
    }
  }
}
