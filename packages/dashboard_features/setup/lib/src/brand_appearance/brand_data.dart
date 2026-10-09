/// Brand's read and what the web computes in the browser for it
/// (`features/settings/brand-pane.tsx`, `shop-address.ts`,
/// `features/loyalty/shared/brand.ts`, `public-shell/brand-color.ts`).
///
/// - [orgBrandProvider]: `GET /orgs/{id}` under the web's own key
///   `["org-brand", orgId]`; a logo, card-image or links save invalidates
///   exactly it.
/// - [publicRootDomain] / [shopAddresses]: the shop's own web addresses
///   (SET-BRD-011/012).
/// - [resolveCardBrand]: the card preview's colours (SET-BRD-019).
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' show Org;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The read's realtime key: not a path, so only `resync` (every key)
/// refreshes it besides its own invalidations.
const String orgBrandKey = 'org-brand';

/// `GET /orgs/{id}` (`getOrg`), the scoped org's brand. Watched only with
/// an org in scope (SET-BRD-002, SET-SHL-020).
final orgBrandProvider = FutureProvider.autoDispose.family<Org, String>((
  ref,
  orgId,
) {
  ref.webCache();
  ref.watch(realtimeEpochProvider(orgBrandKey));
  return ref.watch(apiProvider).orgs.getOrg(id: orgId);
});

// ── the shop's web addresses ───────────────────────────────────────────────

/// The API the app talks to (the app's `MADAR_API` define), where the web
/// reads `VITE_API_URL`.
const String brandApiBase = String.fromEnvironment(
  'MADAR_API',
  defaultValue: 'https://api.madar-pos.cloud',
);

/// The domain shops get subdomains of: the API host minus its first label
/// (`api.madar-pos.cloud` → `madar-pos.cloud`); null for fewer than three
/// labels or an IP address (local development).
String? publicRootDomain(String? apiUrl) {
  final host = Uri.tryParse(apiUrl ?? '')?.host ?? '';
  final labels = host.split('.').where((l) => l.isNotEmpty).toList();
  if (labels.length < 3) return null;
  if (labels.every((l) => RegExp(r'^\d+$').hasMatch(l))) return null;
  return labels.skip(1).join('.');
}

/// One printed address: its key (`links`, `menu`, `order`, `rewards`,
/// `book`) and the URL.
typedef ShopAddress = ({String key, String url});

/// The addresses in the web's order; empty without a slug or a root. The
/// trailing slashes on `/order/` and `/book/` are load-bearing (the nginx
/// mounts).
List<ShopAddress> shopAddresses(String? slug, String? root) {
  if (slug == null || slug.isEmpty || root == null || root.isEmpty) {
    return const [];
  }
  final origin = 'https://$slug.$root';
  return [
    (key: 'links', url: '$origin/'),
    (key: 'menu', url: '$origin/order/menu'),
    (key: 'order', url: '$origin/order/'),
    (key: 'rewards', url: '$origin/rewards'),
    (key: 'book', url: '$origin/book/'),
  ];
}

// ── the card's colours ─────────────────────────────────────────────────────

// The card wears the ORG's colours, not the app theme's: these are Madar's
// brand defaults from `brand.ts`, data like the org's own hex values.
const String madarTeal = '#0D6273';
const String madarTealLight = '#2E94A6';
const String madarPaper = '#EFF3F4';
const String madarInk = '#12222A';

/// WCAG AA for body text.
const double contrastAA = 4.5;

final RegExp _hex = RegExp(r'^#[0-9a-f]{6}$', caseSensitive: false);

bool isBrandHex(String? v) => v != null && _hex.hasMatch(v);

int _channel(String hex, int i) =>
    int.parse(hex.substring(1 + i * 2, 3 + i * 2), radix: 16);

/// WCAG relative luminance of `#rrggbb`.
double luminance(String hex) {
  double ch(int i) {
    final c = _channel(hex, i) / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch(0) + 0.7152 * ch(1) + 0.0722 * ch(2);
}

/// WCAG contrast ratio of two `#rrggbb` colours.
double contrast(String a, String b) {
  final la = luminance(a), lb = luminance(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// `#rrggbb` as a colour.
Color hexColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

/// The card's resolved look (`ResolvedBrand`, the parts the preview draws).
class CardBrand {
  const CardBrand({
    required this.orgName,
    required this.programName,
    required this.logoUrl,
    required this.cardImageUrl,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.isDark,
  });

  final String orgName;
  final String programName;
  final String? logoUrl;
  final String? cardImageUrl;

  /// `#rrggbb`.
  final String background;
  final String foreground;
  final String accent;
  final bool isDark;

  /// Quiet text: white 72 % on a dark card, black 60 % on a light one.
  Color get muted => isDark
      ? Colors.white.withValues(alpha: 0.72)
      : Colors.black.withValues(alpha: 0.60);
}

/// `resolveBrand` for the Brand preview: the org's colours where valid,
/// a foreground only if it clears AA on the background (else paper or ink,
/// whichever contrasts more), Madar's defaults otherwise.
CardBrand resolveCardBrand(Org? org, {required String programName}) {
  String safe(String? v, String fallback) => isBrandHex(v) ? v! : fallback;
  String? trimmed(String? v) {
    final s = v?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  final background = safe(org?.brandBackground, madarTeal);
  final configured = isBrandHex(org?.brandForeground)
      ? org!.brandForeground
      : null;
  final automatic =
      contrast(madarPaper, background) >= contrast(madarInk, background)
      ? madarPaper
      : madarInk;
  final foreground =
      configured != null && contrast(configured, background) >= contrastAA
      ? configured
      : automatic;
  final dark = foreground == madarPaper || luminance(foreground) > 0.5;
  return CardBrand(
    orgName: trimmed(org?.name) ?? 'Madar',
    programName: trimmed(programName) ?? 'Rewards',
    logoUrl: trimmed(org?.logoUrl),
    cardImageUrl: trimmed(org?.brandCardImage),
    background: background,
    foreground: foreground,
    accent: safe(org?.brandAccent, dark ? madarTealLight : madarTeal),
    isDark: dark,
  );
}
