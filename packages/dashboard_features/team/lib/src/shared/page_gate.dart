/// The in-page `<Restricted>` of the seven guarded team pages (TEAM-ALL-007):
/// Set-up, Team, Approvals, Schedule, Payroll, Reports and Rules. The web's
/// routes carry no guard; each page checks once the person's permissions are
/// known (`authz.ready && !can…`) and then shows the page's OWN title and
/// `who` words, requesting nothing. Until then the page renders (its reads
/// stay off without the right). Employees, Attendance, Work shifts and
/// Requests have no in-page guard at all: their reads 403 into each list's
/// error state.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TeamPageGate extends ConsumerWidget {
  const TeamPageGate({
    required this.allowed,
    required this.titleKey,
    required this.whoKey,
    required this.child,
    super.key,
  });

  /// Whether this person may use the page (e.g. `(a) => a.can(Cap.…)`).
  final bool Function(Authz authz) allowed;

  /// The page's own title (`dawam.team`), not the nav label.
  final String titleKey;

  /// Who the page is for (`dawam.teamNoAccess`).
  final String whoKey;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authz = ref.watch(authzProvider);
    if (authz.ready && !allowed(authz)) {
      final t = ref.watch(tProvider);
      return Restricted(title: t(titleKey), who: t(whoKey));
    }
    return child;
  }
}
