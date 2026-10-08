/// The offers area's shared vocabulary (the web's `features/combos/util.ts`,
/// `lib/translation.ts` and `ONE_SIZE`): weekday bits, wire times, a sale
/// window in one line, rates, money typed into a form, translated names and
/// size labels. The combos list, the combo editor and the deals read windows,
/// margins and sizes the same way through these.
library;

import 'package:dashboard_api/dashboard_api.dart' show SaleWindow;
import 'package:dashboard_core/dashboard_core.dart';

// ── Weekdays (bit 0 = Sunday … bit 6 = Saturday) ──────────────────────────

/// Every day of the week.
const int allWeekdays = 127;

/// Sunday first: the bits' order and the Egyptian week's.
const List<String> weekdayKeys = [
  'sun',
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
];

bool hasDay(int mask, int day) => mask & (1 << day) != 0;

int toggleDay(int mask, int day) => mask ^ (1 << day);

/// "Every day", or the chosen short day names in week order.
String weekdaysLabel(Translator t, int mask) {
  if (mask == allWeekdays) return t('combos.windows.everyDay');
  return [
    for (var d = 0; d < 7; d++)
      if (hasDay(mask, d)) t('combos.windows.day.${weekdayKeys[d]}'),
  ].join(t('combos.listSeparator'));
}

/// "H:MM[:SS]" → "HH:MM" (the wire form); empty or invalid → null.
String? hhmm(String? v) {
  if (v == null || v.isEmpty) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${m.group(2)}';
}

/// A window in one line: days · hours · dates · branch. Hours are the raw
/// 24-hour `HH:MM` and dates the raw `YYYY-MM-DD` ("…" for an open end), as
/// the web shows them.
String windowSummary(
  Translator t,
  SaleWindow w, {
  String? Function(String id)? branchName,
}) {
  final parts = [weekdaysLabel(t, w.weekdays ?? allWeekdays)];
  if ((w.startsAt ?? '').isNotEmpty && (w.endsAt ?? '').isNotEmpty) {
    parts.add(
      t(
        'combos.windows.hoursRange',
        args: {'from': hhmm(w.startsAt), 'to': hhmm(w.endsAt)},
      ),
    );
  }
  if (w.validFrom != null || w.validTo != null) {
    parts.add(
      t(
        'combos.windows.datesRange',
        args: {'from': w.validFrom ?? '…', 'to': w.validTo ?? '…'},
      ),
    );
  }
  final b = w.branchId;
  parts.add(
    b == null ? t('combos.windows.allBranches') : (branchName?.call(b) ?? '—'),
  );
  return parts.join(' · ');
}

// ── Rates ─────────────────────────────────────────────────────────────────

/// A wire rate ("0.5933" or a number) as a number, or null.
double? rateOf(Object? v) {
  if (v == null) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String) {
    final n = jsNumber(v);
    return n.isFinite && v.trim().isNotEmpty ? n : null;
  }
  return null;
}

/// A wire rate as a percent ("59.3%"), an em dash when unknown.
String fmtRate(DashFormat f, Object? v) {
  final r = rateOf(v);
  return r == null ? '—' : f.fmtPercent(r);
}

// ── Money typed into a form (EGP text in, piastres out) ──────────────────

/// JavaScript's `Number(text)`: surrounding spaces are fine, "" is 0, ".5"
/// is 0.5, "1e2" is 100, `0x`/`0b`/`0o` literals read; thousands separators,
/// Arabic-Indic digits and anything else are NaN.
double jsNumber(String text) {
  final s = text.trim();
  if (s.isEmpty) return 0;
  if (RegExp(r'^[+-]?Infinity$').hasMatch(s)) {
    return s.startsWith('-') ? double.negativeInfinity : double.infinity;
  }
  final radix = RegExp(r'^0([xXbBoO])([0-9a-fA-F]+)$').firstMatch(s);
  if (radix != null) {
    final base = switch (radix.group(1)!.toLowerCase()) {
      'x' => 16,
      'b' => 2,
      _ => 8,
    };
    final n = int.tryParse(radix.group(2)!, radix: base);
    return n?.toDouble() ?? double.nan;
  }
  if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(s)) {
    return double.nan;
  }
  return double.parse(s);
}

/// An EGP text box → piastres (rounded half away from zero, 19.99 → 1999);
/// blank → null; junk → NaN. Negative amounts come back negative (the form
/// refuses them).
num? moneyIn(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final n = jsNumber(text);
  if (!n.isFinite) return double.nan;
  return egpToPiastres(n);
}

/// Whether [text] is a money amount the forms accept: blank, or 0 or more.
bool moneyOk(String? text) {
  final p = moneyIn(text);
  return p == null || (p.isFinite && p >= 0);
}

/// Piastres → the EGP text a form shows ("150", "12.5"); null → "".
String moneyOut(int? piastres) =>
    piastres == null ? '' : jsNumberString(piastres / 100);

/// JavaScript's `String(n)` for an ordinary number: no trailing ".0".
String jsNumberString(num n) {
  if (n == n.truncateToDouble() && n.abs() < 1e21) {
    return n.toInt().toString();
  }
  return n.toString();
}

// ── Names and sizes ───────────────────────────────────────────────────────

/// `getTranslatedName`: the Arabic name when the language is Arabic and one
/// exists, else [name].
String translatedName(
  String name,
  Map<String, Object?>? translations,
  String lang,
) {
  final ar = translations?['ar'];
  if (lang.startsWith('ar') && ar is String) return ar;
  return name;
}

/// The Arabic name from translations (`arOf`), or null.
String? arabicOf(Map<String, Object?>? translations) {
  final ar = translations?['ar'];
  return ar is String && ar.isNotEmpty ? ar : null;
}

/// The size label a single-price item keeps its price on.
const String oneSize = 'one_size';

/// A size's display label: `one_size` reads "Standard".
String sizeLabelText(Translator t, String label) =>
    label == oneSize ? t('combos.oneSize') : label;
