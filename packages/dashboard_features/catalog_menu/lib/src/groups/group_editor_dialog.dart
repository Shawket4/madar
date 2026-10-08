/// The choice-group editor (the web's
/// `features/menu/groups/group-editor-dialog.tsx`, MENU-GRP-023..048):
/// create or edit a group, its options and what each option deducts. Opened
/// from the groups page, the add-on dialog ("New group") and the studio's
/// modifiers ("New group").
///
/// Owner after scaffolding: the `groups` unit. This file fixes the public
/// API the `items` and `studio` units code against; the body is a
/// placeholder until the groups builder lands.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the editor: [group] null = a new group. Resolves with the saved
/// group as re-read from the server (the caller selects or attaches it), or
/// null when closed without saving.
Future<GroupOut?> showGroupEditorDialog(
  BuildContext context, {
  required String orgId,
  GroupOut? group,
  int? usedOn,
  VoidCallback? onManageItems,
  bool readOnly = false,
}) => showDashDialog<GroupOut>(
  context,
  width: GroupEditorDialog.width,
  builder: (_) => GroupEditorDialog(
    orgId: orgId,
    group: group,
    usedOn: usedOn,
    onManageItems: onManageItems,
    readOnly: readOnly,
  ),
);

class GroupEditorDialog extends ConsumerStatefulWidget {
  const GroupEditorDialog({
    required this.orgId,
    this.group,
    this.usedOn,
    this.onManageItems,
    this.readOnly = false,
    super.key,
  });

  /// The web's 768 px dialog.
  static const double width = 768;

  final String orgId;

  /// Null = create a new group.
  final GroupOut? group;

  /// Items the group is attached to, when known ("Used on N items").
  final int? usedOn;

  /// "Manage…": opens the usage dialog on top.
  final VoidCallback? onManageItems;

  /// Without the capability: every control disabled, no Save.
  final bool readOnly;

  @override
  ConsumerState<GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends ConsumerState<GroupEditorDialog> {
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: widget.group == null
          ? t('menu.groups.editor.newTitle')
          : t('menu.groups.editor.editTitle'),
      description: t('menu.groups.editor.desc'),
      body: const SizedBox.shrink(),
    );
  }
}
