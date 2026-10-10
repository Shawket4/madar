/// The wizard's own reads and the rules the web computes in the browser:
///
/// - `GET /orgs/{id}/onboarding` (dashboard_core's [onboardingStatusProvider],
///   shared with the shell's gate and the home's card) — every step's done /
///   count / required, `can_complete`, `recipe_coverage`;
/// - `GET /orgs/{id}` ([onbOrgProvider]) — the café's name, currency, logo,
///   tax (the price hint of the item editor).
///
/// The menu reads the steps and their editors share live in
/// `dialogs/menu_reads.dart`.
///
/// After a change, [onbRefreshers] ask the checklist again (the web's
/// `invalidateQueries(['/orgs/{id}/onboarding'])`).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_config.dart';

/// The checklist's request path (its web query key).
String onbStatusPath(String orgId) => '/orgs/$orgId/onboarding';

/// `GET /orgs/{id}`.
final onbOrgProvider = FutureProvider.autoDispose.family<Org, String>((
  ref,
  orgId,
) {
  ref.webCache();
  return ref.watch(apiProvider).orgs.getOrg(id: orgId);
});

/// The invalidations a write ends with, taken from [context] BEFORE the
/// write's `await`, so they run even when the step is gone by then:
/// - `checklist`: every read of `/orgs/{id}/onboarding` (closing a step's
///   editor, saving the café, a new logo; the web's key is shared with the
///   home's Keep-building card);
/// - `org`: the org changed (name, currency, logo): this page's read and the
///   shell's (the org read the scope keeps, the brand the sidebar draws).
({VoidCallback checklist, VoidCallback org}) onbRefreshers(
  BuildContext context,
  String orgId,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  final bus = container.read(realtimeBusProvider);
  return (
    checklist: () => bus.invalidate([onbStatusPath(orgId)]),
    org: () => container
      ..invalidate(onbOrgProvider(orgId))
      ..invalidate(currentOrgProvider)
      ..invalidate(publicBrandProvider),
  );
}

/// The server's steps by key.
Map<String, OnboardingStep> stepsByKey(OnboardingStatus? status) => {
  for (final s in status?.steps ?? const <OnboardingStep>[]) s.key: s,
};

/// The step the wizard opens on: the first whose server status is not done
/// (the finale when all are).
OnbStep firstIncomplete(Map<String, OnboardingStep> byKey) {
  for (final s in OnbStep.values) {
    final key = s.statusKey;
    if (key != null && !(byKey[key]?.done ?? false)) return s;
  }
  return OnbStep.goLive;
}

/// `round(required done ÷ required × 100)`, 0 with no required step.
int readyPercent(OnboardingStatus? status) {
  final steps = status?.steps ?? const <OnboardingStep>[];
  final required = steps.where((s) => s.required_).length;
  if (required == 0) return 0;
  final done = steps.where((s) => s.required_ && s.done).length;
  return (done / required * 100).round();
}

/// The cheer beside the percentage.
String cheerKey(int pct) => pct >= 100
    ? 'onboarding.cheer.done'
    : pct >= 75
    ? 'onboarding.cheer.most'
    : pct >= 50
    ? 'onboarding.cheer.half'
    : pct > 0
    ? 'onboarding.cheer.start'
    : 'onboarding.cheer.go';
