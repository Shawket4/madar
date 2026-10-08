/// The credential helpers the web keeps in `features/integrations/util.ts`
/// and `passphrase.ts`: the generated username (SET-INT-018), the file's
/// passphrase (SET-INT-020), the partner endpoint and the Basic header
/// (SET-INT-027), the shared slug.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'nfkd_slug_table.dart';
import 'secure_random.dart';

// ── slug ──────────────────────────────────────────────────────────────────

Map<int, String>? _fold;

Map<int, String> get _nfkdFold {
  final cached = _fold;
  if (cached != null) return cached;
  final map = <int, String>{};
  for (final entry in nfkdSlugFold.split(' ')) {
    if (entry.isEmpty) continue;
    final eq = entry.indexOf('=');
    final key = entry.substring(0, eq);
    final value = entry.substring(eq + 1);
    final plus = key.indexOf('+');
    if (plus < 0) {
      map[int.parse(key, radix: 16)] = value;
    } else {
      final start = int.parse(key.substring(0, plus), radix: 16);
      final count = int.parse(key.substring(plus + 1));
      final first = value.codeUnitAt(0);
      for (var i = 0; i < count; i++) {
        map[start + i] = String.fromCharCode(first + i);
      }
    }
  }
  return _fold = map;
}

final RegExp _nonSlug = RegExp('[^a-z0-9]+');
final RegExp _edgeDashes = RegExp(r'^-+|-+$');

/// `raw.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-")
/// .replace(/^-+|-+$/g, "").slice(0, 40)`: `"Rue — One Ninety"` →
/// `"rue-one-ninety"`, `"Café Rouge"` → `"cafe-rouge"`, Arabic → `""`.
///
/// Dart has no Unicode normalisation; [nfkdSlugFold] carries the NFKD of
/// every character whose decomposition keeps a letter or digit, which is
/// all the slug can see of it.
String credentialSlug(String raw) {
  final lower = raw.toLowerCase();
  final fold = _nfkdFold;
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final f = rune > 0x7f ? fold[rune] : null;
    if (f != null) {
      out.write(f);
    } else {
      out.writeCharCode(rune);
    }
  }
  final slug = out
      .toString()
      .replaceAll(_nonSlug, '-')
      .replaceAll(_edgeDashes, '');
  return slug.length > 40 ? slug.substring(0, 40) : slug;
}

// ── username ──────────────────────────────────────────────────────────────

/// Lowercase alphanumerics that are unambiguous in a username (32 symbols:
/// a byte modulo 32 is unbiased).
const String usernameSuffixAlphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

/// The random tail of a generated username: six symbols from the secure
/// source. Usernames are unique across the whole cluster; this is what makes
/// a collision vanishingly unlikely.
String randomUsernameSuffix([RandomBytes? randomBytes]) {
  final bytes = Uint8List(6);
  (randomBytes ?? IntegrationsRandom.fill)(bytes);
  return String.fromCharCodes([
    for (final b in bytes)
      usernameSuffixAlphabet.codeUnitAt(b % usernameSuffixAlphabet.length),
  ]);
}

/// `("Rue — One Ninety", "k7m2xq")` → `"rue-one-ninety-k7m2xq"`; `partner`
/// when the label has no Latin letters or digits.
String buildUsername(String label, String suffix) {
  final base = credentialSlug(label);
  return '${base.isEmpty ? 'partner' : base}-$suffix';
}

// ── passphrase ────────────────────────────────────────────────────────────

/// Read aloud down a phone line: uppercase only, no `0`/`O`, `1`/`I`/`L`.
/// 31 symbols; twenty of them ≈ 99 bits.
const String passphraseAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

const int _groups = 5;
const int _groupLength = 4;

/// The largest multiple of 31 that fits a byte (248): bytes at or above it
/// are rejected, not folded, so every symbol is equally likely.
const int _rejectAt = 256 - (256 % passphraseAlphabet.length);

/// A 20-symbol passphrase, `XXXX-XXXX-XXXX-XXXX-XXXX`.
///
/// Throws [InsecureRandomError] when the platform has no CSPRNG.
String generatePassphrase([RandomBytes? randomBytes]) {
  final fill = randomBytes ?? IntegrationsRandom.fill;
  final symbols = <int>[];
  final buf = Uint8List(32);
  const length = _groups * _groupLength;
  while (symbols.length < length) {
    fill(buf);
    for (final byte in buf) {
      if (byte >= _rejectAt) continue;
      symbols.add(
        passphraseAlphabet.codeUnitAt(byte % passphraseAlphabet.length),
      );
      if (symbols.length == length) break;
    }
  }
  return [
    for (var g = 0; g < _groups; g++)
      String.fromCharCodes(
        symbols.sublist(g * _groupLength, (g + 1) * _groupLength),
      ),
  ].join('-');
}

// ── the partner's side ────────────────────────────────────────────────────

/// The backend the app talks to (`--dart-define=MADAR_API=…`, the same
/// define and default as the app's boot), the web's `VITE_API_URL`.
const String integrationsApiBase = String.fromEnvironment(
  'MADAR_API',
  defaultValue: 'https://api.madar-pos.cloud',
);

/// The analytics endpoint a partner calls, ready to paste. There is no
/// branch parameter: the credential decides the branch.
String analyticsUrl([String base = integrationsApiBase]) {
  final trimmed = base.replaceAll(RegExp(r'/+$'), '');
  return '$trimmed/integrations/analytics/orders?from=YYYY-MM-DD&to=YYYY-MM-DD';
}

/// The literal `Authorization` header value: `Basic base64(user:secret)`,
/// UTF-8 encoded first (a password may one day be non-ASCII).
String basicAuthHeader(String username, String secret) =>
    'Basic ${base64.encode(utf8.encode('$username:$secret'))}';
