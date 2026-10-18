/// The plan gate (FREEMIUM_SPEC_2026-10-11.md §6): which pages the
/// organisation's plan has at all. The web does the same from its generated
/// `plans.ts` (`feature` on `config/nav.ts` and `settings-nav.ts`); here the
/// plan's answer is the core's (`entitlements()`, madar-shared's `madar-plan`)
/// and this file only says which feature a path belongs to.
///
/// Unknown means allowed: until the plan is known, and for a feature key this
/// build does not list, nothing is hidden, so a paying shop never loses a page.
/// The server refuses a Free request regardless (`plan_feature`, 403).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The features the plan has, or null while unknown (everything shown). Keys
/// are `madar_plan::Feature` words (`inventory`, `loyalty`, `online`,
/// `bookings`, `floor`, `kitchen`, `dawam`, `branding`, `basira`).
class PlanFeaturesNotifier extends Notifier<Set<String>?> {
  @override
  Set<String>? build() => null;

  // A notifier's verb, like every other notifier's `set`; not a setter.
  // ignore: use_setters_to_change_properties
  void set(Set<String>? features) => state = features;
}

final planFeaturesProvider =
    NotifierProvider<PlanFeaturesNotifier, Set<String>?>(
      PlanFeaturesNotifier.new,
    );

/// Path prefix -> the plan feature the page belongs to. Pages behind no entry
/// are on every plan (selling, menu, payment methods, discounts, tills,
/// customers, basic sales reports). Hand-kept beside the generated nav until
/// the web's `feature` field is generated with it.
const List<(String, String)> featureRoutes = <(String, String)>[
  ('/inventory', 'inventory'),
  ('/reports/inventory', 'inventory'),
  ('/menu/bases', 'inventory'),
  ('/menu/packaging', 'inventory'),
  ('/settings/loyalty', 'loyalty'),
  ('/reports/loyalty', 'loyalty'),
  ('/delivery', 'online'),
  ('/settings/delivery', 'online'),
  ('/settings/delivery-zones', 'online'),
  // NOT '/settings/links': every plan opens it, for its "Menu (no prices)"
  // section; the links page's own sections lock themselves on Free
  // (`PaidFeatureLock`, `branding`).
  ('/settings/qr', 'online'),
  ('/qr', 'online'),
  ('/bookings', 'bookings'),
  ('/settings/bookings', 'bookings'),
  ('/floor', 'floor'),
  ('/kitchen', 'kitchen'),
  ('/settings/kitchen-stations', 'kitchen'),
  ('/settings/kitchen-routing', 'kitchen'),
  ('/staff', 'dawam'),
  ('/reports/staff', 'dawam'),
  ('/settings/brand', 'branding'),
  ('/basira', 'basira'),
];

/// The feature a path belongs to: the longest listed prefix on a segment
/// boundary (`moduleOfPath`'s rule). Null = on every plan.
String? featureOfPath(String pathname) {
  var path = pathname;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  (String, String)? best;
  for (final r in featureRoutes) {
    if (path == r.$1 || path.startsWith('${r.$1}/')) {
      if (best == null || r.$1.length > best.$1.length) best = r;
    }
  }
  return best?.$2;
}

/// Does the plan have the page at [path]? [features] null = unknown = yes.
bool planHasPath(Set<String>? features, String path) {
  if (features == null) return true;
  final needs = featureOfPath(path);
  return needs == null || features.contains(needs);
}
