/// The Record waste dialog (INV-WST-014…023, INV-WST-031), opened from the
/// Waste log, from Today's "Log waste" (INV-TOD-030, no preset) and from the
/// ingredient drawer's "Record waste" (INV-ING-043/046, ingredient preset).
/// Owned by the waste unit; Today and Ingredients call
/// [showRecordWasteDialog] and nothing else.
///
/// Scaffold placeholder: the waste builder fills the body.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the dialog for [branchId] (with [presetIngredientId] picked); true
/// once the waste was recorded (inventory invalidated, toast shown).
Future<bool?> showRecordWasteDialog(
  BuildContext context, {
  required String branchId,
  String? presetIngredientId,
}) => showDashDialog<bool>(
  context,
  builder: (_) => RecordWasteDialog(
    branchId: branchId,
    presetIngredientId: presetIngredientId,
  ),
);

class RecordWasteDialog extends ConsumerWidget {
  const RecordWasteDialog({
    required this.branchId,
    this.presetIngredientId,
    super.key,
  });

  final String branchId;
  final String? presetIngredientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: t('inventory.waste.recordTitle'),
      description: t('inventory.waste.title'),
      body: Text(t('shell.pendingBody')),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
