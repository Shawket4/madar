/// The menu pages' "no organization in scope" state (MENU-AREA-010): a
/// platform admin who has not picked an org sees an EmptyState (Store) saying
/// what to pick. Items and Groups use `menu.pickOrg`; Pricing keeps its
/// header and uses `menu.pricing.pickOrg`.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';

class MenuNoOrgState extends StatelessWidget {
  const MenuNoOrgState({this.messageKey = 'menu.pickOrg', super.key});

  /// `menu.pickOrg` (items, groups) or `menu.pricing.pickOrg` (pricing).
  final String messageKey;

  @override
  Widget build(BuildContext context) =>
      DashEmptyState(icon: 'store', title: context.t(messageKey));
}
