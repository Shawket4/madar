/// The admin tables' icon-only row action (the web's
/// `features/users/row-action.tsx`, used by Organizations, Branches, Users
/// and Devices): a ghost glyph button whose label is both its accessible
/// name and its tooltip; [destructive] tints only the glyph.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

class AdminRowAction extends StatelessWidget {
  const AdminRowAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.loading = false,
    super.key,
  });

  /// A glyph name (`pencil`, `trash-2`, `shield`, `git-branch`).
  final String icon;

  /// The action's words ("Edit", "Delete"): aria-label and tooltip.
  final String label;

  /// Null disables it.
  final VoidCallback? onPressed;
  final bool destructive;
  final bool loading;

  @override
  Widget build(BuildContext context) => DashIconButton(
    icon: icon,
    semanticLabel: label,
    onPressed: onPressed,
    loading: loading,
    color: destructive ? context.madarColors.danger : null,
  );
}
