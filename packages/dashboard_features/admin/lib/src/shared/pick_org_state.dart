/// A platform admin with no shop picked in the org picker (ADM-APP-044):
/// org-scoped admin pages show their title and an empty state instead of
/// fetching anything (Branches: ADM-BRA-002, Users: ADM-USR-004). The org in
/// scope is dashboard_core's `orgIdProvider` (null = none picked).
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';

/// The page with only its title and "Select an organization".
class PickOrgPage extends StatelessWidget {
  const PickOrgPage({
    required this.title,
    required this.message,
    this.description,
    this.icon = 'building-2',
    this.tabs,
    super.key,
  });

  /// The page's title.
  final String title;

  /// "Select an organization".
  final String message;

  /// The hint under it, where the page has one.
  final String? description;
  final String icon;

  /// The section tabs, on a page that has them.
  final Widget? tabs;

  @override
  Widget build(BuildContext context) => DashPageScaffold(
    title: title,
    tabs: tabs,
    body: DashEmptyState(icon: icon, title: message, description: description),
  );
}
