/// The waiting transfer queue (FIFO) with its Fulfill and Cancel actions —
/// the web's `transfer-queue.tsx` (SELL-FLR-074 – 078, -091).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/invalidate.dart';
import 'floor_util.dart';
import '../shared/error_text.dart';

class TransferQueue extends ConsumerWidget {
  const TransferQueue({
    required this.transfers,
    required this.tables,
    required this.sections,
    super.key,
  });

  final List<TransferView> transfers;

  /// Every table of the branch (labels; Fulfill's candidates).
  final List<FloorTable> tables;
  final List<FloorSection> sections;

  String? _tableLabel(String? id) =>
      id == null ? null : tables.where((t) => t.id == id).firstOrNull?.label;

  String? _sectionName(String? id) =>
      id == null ? null : sections.where((s) => s.id == id).firstOrNull?.name;

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    TransferView tr,
  ) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('floor.cancelTransferTitle'),
      description: t(
        'floor.cancelTransferDescription',
        args: {'name': tr.occupantLabel ?? t('floor.aParty')},
      ),
      destructive: true,
      confirmLabel: t('floor.cancelTransfer'),
      cancelLabel: t('floor.keepWaiting'),
    );
    if (!ok || !context.mounted) return;
    final bus = ref.read(realtimeBusProvider);
    try {
      await ref.read(apiProvider).floorTransfers.cancelTransfer(id: tr.id);
      bus.invalidate(SellInvalidate.transfers);
      if (context.mounted) {
        DashToast.success(context, t('floor.transferCancelled'));
      }
    } on Object catch (e) {
      if (context.mounted) DashToast.error(context, sellErrorText(e, t));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final waiting = transfers.where((tr) => tr.status == 'waiting').toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final quiet = DashType.meta.copyWith(color: c.textSecondary);

    return Semantics(
      container: true,
      label: t('floor.transferQueue'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t('floor.transferQueue'),
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
              ),
              if (waiting.isNotEmpty) DashBadge(fmt.fmtNumber(waiting.length)),
            ],
          ),
          if (waiting.isEmpty)
            Row(
              spacing: Space.sm,
              children: [
                DashIcon('list-x', color: c.textSecondary),
                Expanded(
                  child: Text(
                    t('floor.noTransfers'),
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            )
          else
            for (final tr in waiting)
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: c.hairline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.sm,
                  children: [
                    Expanded(child: _transferBody(context, t, fmt, tr, quiet)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: Space.xs,
                      children: [
                        DashButton(
                          label: t('floor.fulfill'),
                          size: DashButtonSize.compact,
                          onPressed: () => showDashDialog<void>(
                            context,
                            builder: (_) => FulfillDialog(
                              transfer: tr,
                              tables: tables,
                              sections: sections,
                            ),
                          ),
                        ),
                        _DangerGhostButton(
                          label: t('common.cancel'),
                          onPressed: () => _cancel(context, ref, tr),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _transferBody(
    BuildContext context,
    Translator t,
    DashFormat fmt,
    TransferView tr,
    TextStyle quiet,
  ) {
    final c = context.madarColors;
    final ticket = tr.occupantKind == 'open_ticket';
    final from = _tableLabel(tr.fromTableId);
    final wishTable = _tableLabel(tr.targetTableId);
    final wish =
        wishTable ??
        _sectionName(tr.targetSectionId) ??
        t('floor.anyFreeTable');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.xs,
      children: [
        Row(
          spacing: Space.xs + 2,
          children: [
            Semantics(
              container: true,
              label: t(ticket ? 'floor.openTicket' : 'floor.heldOrder'),
              child: DashIcon(
                ticket ? 'receipt-text' : 'circle-pause',
                color: c.textSecondary,
              ),
            ),
            Expanded(
              child: MadarClippedText(
                tr.occupantLabel ?? t('floor.unnamedParty'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: Space.sm,
          runSpacing: DashMetrics.hair,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(from ?? t('floor.noTable'), style: quiet),
            DashIcon(
              DashIcon.arrowForward(context),
              size: IconSize.xs,
              color: c.textSecondary,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                DashIcon(
                  wishTable != null ? 'armchair' : 'layout-grid',
                  size: IconSize.xs,
                  color: c.textPrimary,
                ),
                Text(
                  wish,
                  style: DashType.smallMedium.copyWith(color: c.textPrimary),
                ),
              ],
            ),
            Tooltip(
              message: t('floor.waitingFor'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  DashIcon('timer', size: IconSize.xs, color: c.textSecondary),
                  Text(fmt.fmtDuration(tr.createdAt), style: quiet),
                ],
              ),
            ),
          ],
        ),
        if (tr.note case final note? when note.isNotEmpty)
          Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: quiet,
          ),
      ],
    );
  }
}

/// Cancel, in the destructive ink on a ghost face (`variant="ghost"
/// className="text-destructive"`); the kit's button has no such tone.
class _DangerGhostButton extends StatelessWidget {
  const _DangerGhostButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onPressed,
      semanticLabel: label,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s.highlighted ? c.dangerBg : null,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        foregroundDecoration: dashFocusRing(
          context,
          s,
          BorderRadius.circular(Radii.sm),
        ),
        child: Text(
          label,
          style: DashType.bodyMedium.copyWith(color: c.danger),
        ),
      ),
    );
  }
}

/// Pick the free table the party actually moves to (`FulfillDialog`).
class FulfillDialog extends ConsumerStatefulWidget {
  const FulfillDialog({
    required this.transfer,
    required this.tables,
    required this.sections,
    super.key,
  });

  final TransferView transfer;
  final List<FloorTable> tables;
  final List<FloorSection> sections;

  @override
  ConsumerState<FulfillDialog> createState() => _FulfillDialogState();
}

class _FulfillDialogState extends ConsumerState<FulfillDialog> {
  String? _picked;
  bool _busy = false;

  Future<void> _submit() async {
    final picked = _picked;
    if (picked == null || _busy) return;
    final t = ref.read(tProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .floorTransfers
          .fulfillTransfer(
            id: widget.transfer.id,
            body: FulfillTransferRequest(tableId: picked),
          );
      bus.invalidate(SellInvalidate.transfers);
      if (!mounted) return;
      DashToast.success(context, t('floor.transferFulfilled'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, sellErrorText(e, t));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final candidates = transferCandidates(widget.transfer, widget.tables);
    String? section(String? id) => id == null
        ? null
        : widget.sections.where((s) => s.id == id).firstOrNull?.name;
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm ? 3 : 2;

    return DashSurface(
      title: t(
        'floor.moveParty',
        args: {'name': widget.transfer.occupantLabel ?? t('floor.aParty')},
      ),
      description: t('floor.moveDescription'),
      body: candidates.isEmpty
          ? Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: c.border),
              ),
              child: Text(
                t('floor.noMatchingTables'),
                textAlign: TextAlign.center,
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            )
          : LayoutBuilder(
              builder: (context, box) {
                final w = (box.maxWidth - Space.sm * (cols - 1)) / cols;
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _gridMax),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        for (final tb in candidates)
                          SizedBox(
                            width: w,
                            child: _Candidate(
                              table: tb,
                              area: section(tb.sectionId),
                              picked: _picked == tb.id,
                              onTap: () => setState(
                                () => _picked = _picked == tb.id ? null : tb.id,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DashButton(
          label: t('floor.confirmMove'),
          loading: _busy,
          onPressed: _picked == null ? null : _submit,
        ),
      ],
    );
  }
}

/// The candidate grid scrolls past this (`max-h-72`).
const double _gridMax = Space.xxl * 9;

class _Candidate extends StatelessWidget {
  const _Candidate({
    required this.table,
    required this.area,
    required this.picked,
    required this.onTap,
  });

  final FloorTable table;
  final String? area;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.translator;
    final sub =
        '${table.seats} ${t('floor.seatsShort')}'
        '${area == null ? '' : ' · $area'}';
    return Semantics(
      toggled: picked,
      child: DashPressable(
        onTap: onTap,
        selected: picked,
        semanticLabel: '${table.label}, $sub',
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => Container(
          padding: const EdgeInsets.all(Space.sm),
          decoration: BoxDecoration(
            color: picked || s.highlighted ? c.hover : c.card,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(
              color: picked ? c.accent : c.border,
              width: picked ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MadarClippedText(
                table.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              MadarClippedText(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.meta.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
