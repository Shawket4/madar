/// The slice of ICU's number formatting the web's `Intl.NumberFormat` calls
/// use (`numberingSystem: "latn"`, `en-GB` / `en-US` / `ar-EG`): grouping,
/// fraction digits with half-expand rounding on the shortest decimal form of
/// the double, sign display, percent, and short compact notation.
library;

/// A non-negative decimal: `digits` with the point after `intLen` of them
/// (`intLen` may be <= 0 or past the end: `0.05` is digits `5`, intLen -1).
class _Dec {
  _Dec(this.digits, this.intLen);

  /// The shortest decimal that round-trips [v] (what JavaScript prints).
  factory _Dec.of(num v) {
    final a = v.abs();
    if (a == 0) return _Dec('', 0);
    final s = a is int ? a.toString() : a.toString();
    var mant = s;
    var exp = 0;
    final e = s.indexOf('e');
    if (e >= 0) {
      mant = s.substring(0, e);
      exp = int.parse(s.substring(e + 1));
    }
    final dot = mant.indexOf('.');
    String digits;
    int intLen;
    if (dot >= 0) {
      digits = mant.substring(0, dot) + mant.substring(dot + 1);
      intLen = dot;
    } else {
      digits = mant;
      intLen = mant.length;
    }
    intLen += exp;
    // Strip leading zeros (each shifts the point left), then trailing zeros.
    var lead = 0;
    while (lead < digits.length && digits[lead] == '0') {
      lead++;
    }
    digits = digits.substring(lead);
    intLen -= lead;
    var end = digits.length;
    while (end > 0 && digits[end - 1] == '0') {
      end--;
    }
    return _Dec(digits.substring(0, end), digits.isEmpty ? 0 : intLen);
  }

  final String digits;
  final int intLen;

  bool get isZero => digits.isEmpty;

  /// floor(log10(value)); meaningless for zero.
  int get magnitude => intLen - 1;

  /// Multiplies by 10^[n].
  _Dec shift(int n) => isZero ? this : _Dec(digits, intLen + n);

  /// Rounds to [frac] fraction digits, ties away from zero (`halfExpand`).
  _Dec round(int frac) {
    if (isZero) return this;
    final keep = intLen + frac; // digits to keep
    if (keep >= digits.length) return this;
    if (keep < 0) return _Dec('', 0);
    final up = digits.codeUnitAt(keep) >= 0x35; // '5'
    var kept = digits.substring(0, keep);
    var len = intLen;
    if (up) {
      final chars = kept.split('');
      var i = chars.length - 1;
      while (i >= 0) {
        if (chars[i] == '9') {
          chars[i] = '0';
          i--;
        } else {
          chars[i] = String.fromCharCode(chars[i].codeUnitAt(0) + 1);
          break;
        }
      }
      kept = chars.join();
      if (i < 0) {
        kept = '1$kept';
        len += 1;
      }
    }
    // Normalise: strip trailing zeros (leading zeros cannot appear here).
    var end = kept.length;
    while (end > 0 && kept[end - 1] == '0') {
      end--;
    }
    kept = kept.substring(0, end);
    return _Dec(kept, kept.isEmpty ? 0 : len);
  }

  /// `1,234.5` with between [minFrac] and the digits it has after rounding.
  String render(int minFrac, {bool group = true}) {
    String intPart;
    String frac;
    if (isZero) {
      intPart = '0';
      frac = '';
    } else if (intLen <= 0) {
      intPart = '0';
      frac = '${'0' * -intLen}$digits';
    } else if (intLen >= digits.length) {
      intPart = digits + '0' * (intLen - digits.length);
      frac = '';
    } else {
      intPart = digits.substring(0, intLen);
      frac = digits.substring(intLen);
    }
    if (frac.length < minFrac) frac = frac + '0' * (minFrac - frac.length);
    if (group && intPart.length > 3) {
      final b = StringBuffer();
      final first = intPart.length % 3;
      if (first > 0) b.write(intPart.substring(0, first));
      for (var i = first; i < intPart.length; i += 3) {
        if (b.isNotEmpty) b.write(',');
        b.write(intPart.substring(i, i + 3));
      }
      intPart = b.toString();
    }
    return frac.isEmpty ? intPart : '$intPart.$frac';
  }
}

/// `Intl.NumberFormat` `signDisplay`.
enum SignDisplay { auto, always, exceptZero, never }

/// The number options the web passes (`Intl.NumberFormatOptions` subset).
class NumberOptions {
  const NumberOptions({
    this.minimumFractionDigits,
    this.maximumFractionDigits,
    this.signDisplay = SignDisplay.auto,
  });

  final int? minimumFractionDigits;
  final int? maximumFractionDigits;
  final SignDisplay signDisplay;
}

const String _lrm = '\u200e';

/// Whether [locale] is an Arabic tag.
bool _isAr(String locale) => locale.toLowerCase().startsWith('ar');

/// [minDefault]/[maxDefault]: the style's defaults (decimal 0/3, percent 0/0).
(int, int) _digits(NumberOptions o, int minDefault, int maxDefault) {
  final minF = o.minimumFractionDigits;
  final maxF = o.maximumFractionDigits;
  if (minF != null && maxF != null) return (minF, maxF < minF ? minF : maxF);
  if (minF != null) return (minF, minF > maxDefault ? minF : maxDefault);
  if (maxF != null) return (maxF < minDefault ? maxF : minDefault, maxF);
  return (minDefault, maxDefault);
}

String _sign(String locale, num v, _Dec rounded, SignDisplay d) {
  final neg = v.isNegative; // -0.0 included, as in JavaScript
  final ar = _isAr(locale);
  final minus = ar ? '$_lrm-' : '-';
  final plus = ar ? '$_lrm+' : '+';
  switch (d) {
    case SignDisplay.auto:
      return neg ? minus : '';
    case SignDisplay.always:
      return neg ? minus : plus;
    case SignDisplay.exceptZero:
      if (rounded.isZero) return '';
      return neg ? minus : plus;
    case SignDisplay.never:
      return '';
  }
}

String? _special(String locale, num v) {
  if (v.isNaN) return _isAr(locale) ? 'ليس\u00a0رقمًا' : 'NaN';
  if (v.isInfinite) return v > 0 ? '∞' : '${_isAr(locale) ? _lrm : ''}-∞';
  return null;
}

/// `new Intl.NumberFormat(locale, {numberingSystem: "latn", ...o}).format(v)`.
String icuDecimal(
  String locale,
  num v, [
  NumberOptions o = const NumberOptions(),
]) {
  final special = _special(locale, v);
  if (special != null) return special;
  final (minF, maxF) = _digits(o, 0, 3);
  final r = _Dec.of(v).round(maxF);
  return '${_sign(locale, v, r, o.signDisplay)}${r.render(minF)}';
}

/// `style: "percent"` (`maximumFractionDigits` defaults to 0).
String icuPercent(
  String locale,
  num ratio, [
  NumberOptions o = const NumberOptions(),
]) {
  final special = _special(locale, ratio);
  if (special != null) return special;
  final (minF, maxF) = _digits(o, 0, 0);
  final r = _Dec.of(ratio).shift(2).round(maxF);
  final body = r.render(minF);
  final sign = _sign(locale, ratio, r, o.signDisplay);
  return _isAr(locale) ? '$sign$body$_lrm%$_lrm' : '$sign$body%';
}

int _compactMultiplier(int magnitude) {
  if (magnitude < 3) return 0;
  if (magnitude < 6) return -3;
  if (magnitude < 9) return -6;
  if (magnitude < 12) return -9;
  return -12;
}

/// `notation: "compact"` (short), with `maximumFractionDigits` (default 0
/// here: every web call passes 1).
String icuCompact(String locale, num v, {int maximumFractionDigits = 0}) {
  final special = _special(locale, v);
  if (special != null) return special;
  final d = _Dec.of(v);
  var mult = 0;
  var r = d.round(maximumFractionDigits);
  if (!d.isZero) {
    final mag = d.magnitude;
    mult = _compactMultiplier(mag);
    r = d.shift(mult).round(maximumFractionDigits);
    // Rounding can carry into the next unit (999,999 -> 1000K -> 1M).
    if (!r.isZero) {
      final newMag = r.magnitude - mult;
      if (newMag != mag && _compactMultiplier(newMag) != mult) {
        mult = _compactMultiplier(newMag);
        r = d.shift(mult).round(maximumFractionDigits);
      }
    }
  }
  final body = r.render(0);
  final sign = _sign(locale, v, r, SignDisplay.auto);
  if (mult == 0) return '$sign$body';
  if (_isAr(locale)) {
    final String word;
    switch (mult) {
      case -3:
        // Only the one-digit thousands pattern has a `few` form (`3 آلاف`).
        final scaledMag = r.magnitude;
        final few =
            scaledMag == 0 &&
            r.intLen >= r.digits.length && // an integer
            _arFew(int.parse(body.replaceAll(',', '')));
        word = few ? 'آلاف' : 'ألف';
      case -6:
        word = 'مليون';
      case -9:
        word = 'مليار';
      default:
        word = 'ترليون';
    }
    return '$sign$body\u00a0$word';
  }
  final suffix = switch (mult) {
    -3 => 'K',
    -6 => 'M',
    -9 => 'B',
    _ => 'T',
  };
  return '$sign$body$suffix';
}

bool _arFew(int n) {
  final m = n % 100;
  return m >= 3 && m <= 10;
}
