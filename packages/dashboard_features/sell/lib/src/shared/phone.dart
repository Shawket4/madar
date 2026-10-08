/// The one phone rule (the web's `src/lib/phone.ts`), shared by Bookings
/// (guest phone) and Customers (phone column, form, merge picker).
///
/// Canonical = E.164 digits without the `+` (`201001234567`) — the form the
/// backend (`phone_canonical`), the POS core and the web all agree on. The
/// rule and its vectors live in madar-shared's `phone_vectors.json`; a copy
/// sits in `test/shared/` and `phone_test.dart` checks this port against it.
/// Never change the rule here alone.
library;

/// Longer than this is refused outright, before any digit is read.
const int phoneRawMax = 32;
const int _canonicalMin = 10;
const int _canonicalMax = 15;
final RegExp _egMobilePrefix = RegExp(r'^201[0125]');
const int _egMobileLength = 12;
final RegExp _nonDigits = RegExp(r'[^0-9]');
final RegExp _egMobileGroups = RegExp(r'^20(1\d{2})(\d{3})(\d{4})$');

/// Arabic-Indic (U+0660–0669) and Extended Arabic-Indic (U+06F0–06F9) → ASCII.
String _asciiDigits(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(0x30 + r - 0x06F0);
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

/// The canonical form of whatever was typed, or null when it is not a phone.
String? canonicalPhone(String? raw) {
  if (raw == null || raw.runes.length > phoneRawMax) return null;
  var digits = _asciiDigits(raw).replaceAll(_nonDigits, '');
  if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('20')) {
    // Already country-coded.
  } else if (digits.startsWith('0')) {
    digits = '20${digits.substring(1)}';
  } else if (digits.length == 10 && digits.startsWith('1')) {
    digits = '20$digits';
  }
  if (digits.length < _canonicalMin || digits.length > _canonicalMax) {
    return null;
  }
  // An Egyptian mobile is exactly 12 digits; a truncated or over-long one is
  // the commonest typo. Landlines (2013…, 202…) are untouched.
  if (_egMobilePrefix.hasMatch(digits) && digits.length != _egMobileLength) {
    return null;
  }
  return digits;
}

bool isValidPhone(String? raw) => canonicalPhone(raw) != null;

/// Whether two typed phones are the same number. Two non-phones are never
/// equal.
bool samePhone(String? a, String? b) {
  final ca = canonicalPhone(a);
  return ca != null && ca == canonicalPhone(b);
}

/// A phone for reading: `+20 100 123 4567` for an Egyptian mobile,
/// `+<digits>` otherwise; something that is not a phone comes back as it was
/// given, null as ''. Always LTR: isolate it inside Arabic text (`ltr()` from
/// dashboard_core, or a `Directionality.ltr`).
String formatPhoneDisplay(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  final c = canonicalPhone(phone);
  if (c == null) return phone;
  final m = _egMobileGroups.firstMatch(c);
  return m != null ? '+20 ${m[1]} ${m[2]} ${m[3]}' : '+$c';
}

/// A canonical phone as someone would type it: the national `01001234567`
/// for Egypt, `+<digits>` otherwise (pre-filling an input from a stored
/// value).
String formatPhoneInput(String? phone) {
  final c = canonicalPhone(phone);
  if (c == null) return phone ?? '';
  return c.startsWith('20') ? '0${c.substring(2)}' : '+$c';
}
