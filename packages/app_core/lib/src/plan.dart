/// The organisation's plan at the till (FREEMIUM_SPEC_2026-10-11.md §5/§6).
///
/// What a plan allows is the core's answer (`entitlements()`, from
/// madar-shared's `madar-plan`); nothing here keeps a list of its own, and an
/// unknown answer is **Paid** so a paying shop never loses a screen. A screen
/// asks `ref.watch(entitlementsProvider).has(PlanFeature.floor)`.
library;

import 'package:app_core/src/generated/plans.dart';
import 'package:app_core/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The plan's features and limits and whether THIS till is switched off,
/// re-read whenever the changefeed moves (`catalog` / `sync` ticks: the plan
/// rides the branch settings row, the till's own flag its device row).
final entitlementsProvider = Provider<EntitlementsView>((ref) {
  ref
    ..watch(catalogTickProvider)
    ..watch(syncTickProvider);
  final bridge = ref.watch(bridgeProvider);
  try {
    return bridge.entitlements();
    // Never lock a paying shop out: if the core cannot answer, it is Paid.
    // ignore: avoid_catches_without_on_clauses
  } catch (_) {
    return paidEntitlements;
  }
});

/// The Paid plan, as the generated table has it: the answer when nothing
/// better is known.
final EntitlementsView paidEntitlements = EntitlementsView(
  plan: 'paid',
  features: Plans.paid.features.toList(),
  realtime: true,
  tillInactive: false,
);

extension EntitlementsX on EntitlementsView {
  /// Does the plan have [feature] (a [PlanFeature] key)? A key this build
  /// does not know is allowed: a newer server's feature never hides an old
  /// build's screen.
  bool has(String feature) {
    final known = Plans.paid.features.contains(feature);
    return !known || features.contains(feature);
  }

  bool get isFree => plan == 'free';
}

/// The web dashboard's origin, where "Sign up free" leads (`/signup`).
/// Overridable for staging with `--dart-define=MADAR_DASHBOARD_URL=…`.
const String kDashboardOrigin = String.fromEnvironment(
  'MADAR_DASHBOARD_URL',
  defaultValue: 'https://madar-pos.cloud',
);

/// The free sign-up page. No prices in the app: it only points here.
final Uri kSignupUri = Uri.parse('$kDashboardOrigin/signup');

/// Opens a web address outside the app. The app overrides it with
/// `url_launcher`; tests record, and a bare scope does nothing.
final externalLinkOpenerProvider = Provider<Future<void> Function(Uri uri)>(
  (ref) => (_) async {},
);
