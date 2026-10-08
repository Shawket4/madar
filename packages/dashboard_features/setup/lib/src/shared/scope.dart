/// The scope rules several setup panes share.
///
/// - Org and branch come from the header: `orgIdProvider` (a platform
///   admin's picked org; null = none picked) and
///   `scopeProvider.select((s) => s.branchId)` (null = "All branches").
///   Switching the header branch reloads a branch-scoped pane (SET-SHL-015).
/// - A branch-scoped settings row (Loyalty, Staff drinks) is INHERITED when a
///   branch is in scope and the server answered with another row (the
///   organisation's): saving creates the branch's own, "Follow the
///   organisation" deletes it.
/// - The in-page refusal (Combos, Staff drinks, Integrations, WhatsApp):
///   [SetupRefusalPane].
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';

/// Whether the settings row the server returned for [scopeBranchId] is the
/// organisation's, not the branch's own (`inherited` in `use-program.ts`,
/// `use-staff-pool.ts`).
bool isInheritedScope({
  required String? scopeBranchId,
  required String? rowBranchId,
}) => scopeBranchId != null && rowBranchId != scopeBranchId;

/// A pane that refuses in place: its own header, then an empty state
/// saying why (the web's `<Restricted>` inside the pane, or WhatsApp's own
/// "Only super admins…"). Nothing is requested behind it.
class SetupRefusalPane extends StatelessWidget {
  const SetupRefusalPane({
    required this.title,
    required this.stateTitle,
    this.message,
    this.icon = 'lock',
    super.key,
  });

  /// The pane's title ("Combos and deals").
  final String title;

  /// The empty state's sentence ("Not available on this account").
  final String stateTitle;
  final String? message;
  final String icon;

  @override
  Widget build(BuildContext context) => DashPageScaffold(
    title: title,
    width: DashPageWidth.reading,
    body: DashEmptyState(icon: icon, title: stateTitle, description: message),
  );
}
