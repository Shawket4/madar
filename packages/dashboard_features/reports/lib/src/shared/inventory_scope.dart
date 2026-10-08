/// The "This branch" / "Whole organization" toggle the inventory-backed
/// report tabs share: Financial's Valuation, Supplier spend and Material cost
/// trend (REP-FIN-005) and the Inventory reports page (REP-INV-005).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which endpoint family an inventory report reads: the branch's
/// (`/reports/branches/{branchId}/…`) or the org's (`/reports/orgs/{orgId}/…`).
enum InventoryScope { branch, org }

/// The toggle's starting value, set ONCE when the page opens: This branch
/// when a branch is selected, else Whole organization. It does not follow
/// later scope-bar changes (`fin:76-78`, `inv:29-32`).
InventoryScope initialInventoryScope(Scope scope) =>
    scope.isAllBranches ? InventoryScope.org : InventoryScope.branch;

/// Whether a branch-scoped read can run: "This branch" while All branches is
/// selected has no branch to ask about (Financial then shows its empty
/// state; Inventory reports shows "Select a branch to manage its stock").
bool inventoryBranchMissing(InventoryScope value, Scope scope) =>
    value == InventoryScope.branch && scope.isAllBranches;

/// The segmented control: `inventory.reports.branch` "This branch" /
/// `inventory.reports.org` "Whole organization".
class InventoryScopeToggle extends ConsumerWidget {
  const InventoryScopeToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final InventoryScope value;
  final ValueChanged<InventoryScope> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashSegmentedControl<InventoryScope>(
      value: value,
      onChanged: onChanged,
      options: [
        DashOption(
          value: InventoryScope.branch,
          label: t('inventory.reports.branch'),
        ),
        DashOption(
          value: InventoryScope.org,
          label: t('inventory.reports.org'),
        ),
      ],
    );
  }
}
