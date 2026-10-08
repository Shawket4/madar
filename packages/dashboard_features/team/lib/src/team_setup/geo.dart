/// A branch pin from whatever the owner has to hand (`dawam/geo.ts`,
/// TEAM-SET-019/020/022): a Google Maps link (the long one a browser shows,
/// or a `?q=` / `query=` link), bare coordinates copied from Maps
/// ("30.0444, 31.2357"), or a `geo:` URI. Pure, so it is tested directly. No
/// network: a short share link (maps.app.goo.gl) only says where it
/// redirects when opened, so it is recognised and explained rather than
/// guessed at.
library;

import '../shared/team_util.dart' show latinDigits;

/// A point on the map, in degrees.
class LatLng {
  const LatLng(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is LatLng && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'LatLng($lat, $lng)';
}

/// Why a paste is not a pin.
enum PinProblem {
  /// `maps.app.goo.gl` / `goo.gl/maps`: only a browser can follow it.
  shortLink,

  /// Nothing that reads as coordinates.
  none,

  /// Numbers, but not a place on Earth.
  outOfRange,
}

/// [parsePin]'s answer: a [pin], or a [problem].
class PinParse {
  const PinParse.ok(LatLng this.pin) : problem = null;
  const PinParse.error(PinProblem this.problem) : pin = null;

  final LatLng? pin;
  final PinProblem? problem;

  bool get ok => pin != null;

  @override
  bool operator ==(Object other) =>
      other is PinParse && other.pin == pin && other.problem == problem;

  @override
  int get hashCode => Object.hash(pin, problem);

  @override
  String toString() => ok ? 'PinParse.ok($pin)' : 'PinParse.error($problem)';
}

const String _num = r'(-?\d{1,3}(?:\.\d+)?)';

bool _valid(double lat, double lng) =>
    lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

final RegExp _shortLink = RegExp(
  r'^(https?://)?(maps\.app\.goo\.gl|goo\.gl/maps)/',
  caseSensitive: false,
);

final List<RegExp> _tries = [
  // The place's own pin in a /maps/place/ link: !3d<lat>!4d<lng>.
  RegExp('!3d$_num!4d$_num'),
  // An explicit query: ?q=, &query=, ll=, destination=, center=.
  RegExp(
    '[?&](?:q|query|ll|destination|daddr|center|sll)=(?:loc:)?'
    '$_num\\s*,\\s*$_num',
  ),
  // geo:30.04,31.23
  RegExp('^geo:$_num\\s*,\\s*$_num'),
  // The map's centre in a browser link: /@30.04,31.23,17z.
  RegExp('@$_num,$_num'),
  // Bare coordinates, as Maps copies them: "30.0444, 31.2357" (or a space).
  RegExp('^$_num\\s*[,\\s]\\s*$_num\$'),
];

/// Read a pin out of pasted text.
PinParse parsePin(String raw) {
  final text = latinDigits(
    raw,
  ).replaceAll('،', ',').replaceAll('٫', '.').trim();
  if (text.isEmpty) return const PinParse.error(PinProblem.none);

  var s = text;
  try {
    s = Uri.decodeComponent(text);
  } on ArgumentError {
    // Keep it as typed (a lone "%" is not an escape).
  } on FormatException {
    // Same.
  }

  if (_shortLink.hasMatch(s)) {
    return const PinParse.error(PinProblem.shortLink);
  }

  for (final re in _tries) {
    final m = re.firstMatch(s);
    if (m == null) continue;
    final lat = double.parse(m.group(1)!);
    final lng = double.parse(m.group(2)!);
    if (!_valid(lat, lng)) return const PinParse.error(PinProblem.outOfRange);
    return PinParse.ok(LatLng(round6(lat), round6(lng)));
  }
  return const PinParse.error(PinProblem.none);
}

/// Six decimals is about 10 cm: more is noise (`Math.round(n * 1e6) / 1e6`,
/// which rounds a half up, toward +∞).
double round6(double n) => (n * 1e6 + 0.5).floorToDouble() / 1e6;

/// Roughly Egypt, to warn (never refuse) about a pin pasted from the wrong
/// place.
bool inEgypt(LatLng p) =>
    p.lat >= 21.5 && p.lat <= 32 && p.lng >= 24.5 && p.lng <= 37;

/// A link that opens the pin in Google Maps, so the owner can check it on a
/// real map: `https://www.google.com/maps?q=lat,lng` with the figures as
/// JavaScript prints them.
Uri mapsLink(LatLng p) =>
    Uri.parse('https://www.google.com/maps?q=${jsNumber(p.lat)},${jsNumber(p.lng)}');

/// `30.04440, 31.23570` for reading (always Latin digits, LTR).
String fmtLatLng(LatLng p) =>
    '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}';

/// A number as JavaScript's `String(n)` prints it: `30`, `30.5`, `0.25`
/// (Dart prints a whole double as `30.0`).
String jsNumber(num n) {
  if (n is int) return '$n';
  if (n.isFinite && n == n.truncateToDouble() && n.abs() < 1e21) {
    return n.toInt().toString();
  }
  return n.toString();
}
