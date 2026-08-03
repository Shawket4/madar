import 'package:flutter/painting.dart';

/// Payment-method + chart series colors, ported from the web dashboard's
/// `--payment-*` / `--chart-*` design tokens. (design_system has no payment
/// palette; these are dashboard-only.)
const Map<String, Color> _paymentColors = {
  'cash': Color(0xFF3ABA6A),
  'card': Color(0xFF2D6FCD),
  'digital_wallet': Color(0xFF735CC7),
  'wallet': Color(0xFF735CC7),
  'mixed': Color(0xFFDE9C31),
  'talabat_online': Color(0xFFE26B1B),
  'talabat_cash': Color(0xFF944D24),
};

/// Series palette for categories / multi-slice charts (web `--chart-*`).
const List<Color> kSeriesColors = [
  Color(0xFF2E94A6),
  Color(0xFF2A624B),
  Color(0xFF32669A),
  Color(0xFFE19B1B),
  Color(0xFF8160B5),
  Color(0xFF00A4AC),
];

/// Brand teal fallback for unknown payment methods.
const Color _fallback = Color(0xFF2E94A6);

Color paymentColor(String method) =>
    _paymentColors[method.toLowerCase()] ?? _fallback;

/// Humanize a payment-method key, e.g. `talabat_online` → `Talabat online`.
String paymentLabel(String method) {
  if (method.isEmpty) return method;
  final words = method.replaceAll('_', ' ').replaceAll('-', ' ').trim();
  return words.isEmpty ? method : words[0].toUpperCase() + words.substring(1);
}
