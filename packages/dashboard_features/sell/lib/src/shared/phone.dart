/// The one phone rule, shared by Bookings (guest phone) and Customers (phone
/// column, form, merge picker).
///
/// Canonical = E.164 digits without the `+` (`201001234567`): madar-ids
/// `phone::canonical`, run through the bridge (`rules.phoneCanonical`), the
/// copy the backend and the POS core run. Only the display forms below are
/// Dart, and they read the canonical form from the rule.
library;

import 'package:rust_bridge_dashboard/rules.dart' as rules;

final RegExp _egMobileGroups = RegExp(r'^20(1\d{2})(\d{3})(\d{4})$');

/// The canonical form of whatever was typed, or null when it is not a phone.
String? canonicalPhone(String? raw) =>
    raw == null ? null : rules.phoneCanonical(raw: raw);

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
