/// Deterministic ids and a deterministic random source for the mock data.
library;

const int _fnvOffset = 0xcbf29ce484222325;
const int _fnvPrime = 0x100000001b3;

int _fnv(String s, int seed) {
  var h = _fnvOffset ^ seed;
  for (final c in s.codeUnits) {
    h ^= c;
    h *= _fnvPrime;
  }
  return h;
}

String _hex64(int v) =>
    (v >>> 32).toRadixString(16).padLeft(8, '0') +
    (v & 0xffffffff).toRadixString(16).padLeft(8, '0');

/// A stable UUID (version-4 shaped) for [key], e.g. `mockUuid('branch:maadi')`.
/// The same key always gives the same id, on every run.
String mockUuid(String key) {
  final a = _hex64(_fnv(key, 0));
  final b = _hex64(_fnv(key, 0x9e3779b97f4a7c15));
  final variant = '89ab'[int.parse(b[0], radix: 16) & 3];
  return '${a.substring(0, 8)}-${a.substring(8, 12)}-4${a.substring(13, 16)}-'
      '$variant${b.substring(1, 4)}-${b.substring(4, 16)}';
}

/// A small, fast, seedable PRNG (xorshift64*), so the seed never depends on
/// `dart:math`'s implementation.
class MockRandom {
  MockRandom(String seed) : _s = _fnv(seed, 0x2545f4914f6cdd1d) | 1;

  int _s;

  int _next() {
    var x = _s;
    x ^= x >>> 12;
    x ^= x << 25;
    x ^= x >>> 27;
    _s = x;
    return (x * 0x2545f4914f6cdd1d) >>> 11; // 53 bits
  }

  /// In [0, 1).
  double nextDouble() => _next() / 9007199254740992.0;

  /// In [0, max).
  int nextInt(int max) => (nextDouble() * max).floor();

  /// In [min, max] inclusive.
  int range(int min, int max) => min + nextInt(max - min + 1);

  bool chance(double p) => nextDouble() < p;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  /// Picks by weight (weights need not sum to 1).
  T weighted<T>(List<T> items, List<num> weights) {
    var total = 0.0;
    for (final w in weights) {
      total += w;
    }
    var r = nextDouble() * total;
    for (var i = 0; i < items.length; i++) {
      r -= weights[i];
      if (r < 0) return items[i];
    }
    return items.last;
  }
}
