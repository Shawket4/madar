/// The page body a one-branch page shows while All branches is selected:
/// Floor (SELL-FLR-001, Armchair, `floor.pickBranch`) and Bookings
/// (SELL-BKG-001, CalendarClock, `bookings.pickBranch`). The page makes no
/// read in that state.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The selected branch, or null while All branches is selected.
final sellBranchIdProvider = Provider<String?>(
  (ref) => ref.watch(currentScopeProvider.select((s) => s.branchId)),
);

/// "Select a branch in the top bar to see its …" as the page's empty state.
class BranchRequiredState extends StatelessWidget {
  const BranchRequiredState({
    required this.messageKey,
    required this.icon,
    super.key,
  });

  /// `floor.pickBranch` or `bookings.pickBranch`.
  final String messageKey;

  /// The page's glyph (`armchair`, `calendar-clock`).
  final String icon;

  @override
  Widget build(BuildContext context) =>
      DashEmptyState(icon: icon, title: context.t(messageKey));
}
