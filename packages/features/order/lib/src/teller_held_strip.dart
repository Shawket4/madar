import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart' show askManager;
import 'package:feature_order/src/held_orders_strip.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_screen.dart' show TableOrderScreen;
import 'package:feature_order/src/tables_screen.dart' show showTablePickerSheet;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Teller strip: a chip per parked draft PLUS, when the cart is non-empty,
/// the live cart's own chip (the selected one).
///
/// Drawn by `SellCart` (sell_cart.dart) on the counter: it shows what is
/// already parked and carries the live order's rename pencil.
class TellerHeldStrip extends ConsumerWidget {
  const TellerHeldStrip({this.tableId, super.key});

  /// The cart whose live chip leads the strip (null = takeaway).
  final String? tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final drafts = ref.watch(orderProvider.select((s) => s.drafts));
    final cart = ref.watch(cartProvider(tableId));
    final cartStartedAtIso = cart.startedAt;
    final cartName = cart.name;
    final cartDraftId = cart.draftId;
    final hasLines = cart.lines.isNotEmpty;
    final itemCount = cart.totals.itemCount;
    // A live cart restored FROM a draft keeps that draft's strip key, so the
    // chip is the SAME chip across hold/restore cycles — its drag position
    // and time label never jump.
    final liveKey = cartDraftId ?? '__current__';
    return HeldOrdersStrip(
      newLabel: bridge.tr(key: 'waiter.new_order'),
      tabs: [
        for (final draft in drafts)
          HeldOrderTab(
            key: draft.id,
            sortKey: draft.createdAt,
            title: _chipTitle(_customName(draft.name), draft.tableLabel),
            glyph: draft.lockedByOther ? 'lock' : null,
            author: draft.byOther ? draft.createdByName : null,
            authorLabel: draft.byOther
                ? bridge
                      .tr(key: 'drafts.started_by')
                      .replaceAll('{name}', draft.createdByName ?? '')
                : null,
            count: draft.itemCount,
            selected: false,
            onTap: () => unawaited(_openDraft(context, ref, draft)),
            // The pencil is on EVERY chip now, not only the live one. A
            // parked order could not be renamed at all before: the core had
            // no rename, so the only path was restoring it into the cart and
            // re-parking it, which displaces whatever the till is working on
            // to fix a label. It is a field on a device-local row.
            onRename: draft.lockedByOther
                ? null
                : () => unawaited(_renameDraft(context, ref, draft)),
            onClose: draft.lockedByOther
                ? null
                : () => unawaited(_confirmDiscard(context, ref, draft)),
          ),
        if (hasLines)
          HeldOrderTab(
            key: liveKey,
            // A stamp that is not there yet sorts first and shows no time —
            // `now` here re-stamped the chip, and re-sorted it, on every build.
            sortKey: cartStartedAtIso ?? '',
            title: _chipTitle(
              cartName,
              cartTableLabel(ref.watch(orderProvider), cart),
            ),
            count: itemCount,
            selected: true,
            onTap: () {},
            onRename: () => unawaited(editLiveOrderName(context, ref, tableId)),
          ),
      ],
    );
  }

  /// Resume a parked order. One parked AT THE COUNTER swaps into this cart
  /// (the cart in hand parks first, tab-style). One that belongs to a TABLE
  /// is that table's errand: it fills THAT table's cart and opens its own
  /// order screen — this cart is never touched.
  Future<void> _openDraft(
    BuildContext context,
    WidgetRef ref,
    DraftView draft,
  ) async {
    final notifier = ref.read(orderProvider.notifier);
    if (draft.tableId == null || draft.lockedByOther) {
      await notifier.resumeDraft(
        draft.id,
        fromTableId: tableId,
        parkInHand: true,
        askManager: _askManager(context, ref, 'resume', draft.id),
      );
      return;
    }
    // The strip may sit in the cart SHEET (a root surface): the page belongs
    // on the tab it was opened over, which navigatorOf finds — and the sheet
    // goes away first, or the table's page opens BEHIND it.
    final navigator = MadarPages.navigatorOf(context);
    if (ModalRoute.of(context) is MadarSheetRoute) {
      MadarSheet.close<void>(context);
    }
    final landed = await notifier.resumeDraft(
      draft.id,
      askManager: _askManager(context, ref, 'resume', draft.id),
    );
    final table = landed?.tableId;
    if (table == null) return;
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => TableOrderScreen(tableId: table)),
    );
  }

  /// The manager-PIN sheet for a queue act on someone else's held order.
  Future<ApprovalView?> Function(String reason) _askManager(
    BuildContext context,
    WidgetRef ref,
    String act,
    String id,
  ) =>
      (reason) => askManager(
        context,
        ref,
        reason: reason,
        capKey: '',
        approve: (bridge, pin) =>
            bridge.approveDraftAct(approverPin: pin, act: act, id: id),
      );

  /// Discarding a parked order loses its lines for good — it confirms,
  /// naming the order and what goes with it.
  Future<void> _confirmDiscard(
    BuildContext context,
    WidgetRef ref,
    DraftView draft,
  ) async {
    final bridge = ref.read(bridgeProvider);
    final name =
        _chipTitle(_customName(draft.name), draft.tableLabel) ??
        bridge.tr(key: 'drafts.this_order');
    final ok = await showMadarConfirm(
      context,
      title: bridge.tr(key: 'drafts.discard_title').replaceAll('{name}', name),
      body: bridge
          .tr(key: 'drafts.discard_body')
          .replaceAll('{count}', '${draft.itemCount}'),
      confirmLabel: bridge.tr(key: 'drafts.discard'),
      cancelLabel: bridge.tr(key: 'common.cancel'),
    );
    if (!ok) return;
    if (!context.mounted) return;
    await ref
        .read(orderProvider.notifier)
        .discardDraft(
          draft.id,
          askManager: _askManager(context, ref, 'discard', draft.id),
        );
  }

  /// Rename one PARKED order, or move it to a table. Neither touches the
  /// cart in hand or the claim.
  Future<void> _renameDraft(
    BuildContext context,
    WidgetRef ref,
    DraftView draft,
  ) async {
    final bridge = ref.read(bridgeProvider);
    final controller = TextEditingController(
      text: _customName(draft.name) ?? '',
    );
    final saved = await showMadarSheet<String>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            MadarSectionHeader(text: bridge.tr(key: 'drafts.rename')),
            MadarField(
              controller: controller,
              placeholder: bridge.tr(key: 'waiter.customer_optional'),
              kind: MadarFieldKind.name,
              autofocus: true,
              onSubmitted: (v) => Navigator.of(sheetContext).maybePop(v.trim()),
            ),
            if (ref.read(orderProvider).hasFloor)
              MadarButton(
                label: draft.tableLabel == null
                    ? bridge.tr(key: 'tables.assign')
                    : '${bridge.tr(key: 'order.table')} · ${draft.tableLabel}',
                icon: 'square.grid.2x2',
                variant: MadarButtonVariant.outline,
                onTap: () => unawaited(() async {
                  final pick = await showTablePickerSheet(
                    sheetContext,
                    ref,
                    currentTableId: draft.tableId,
                  );
                  if (pick == null || pick.tableId == draft.tableId) return;
                  if (sheetContext.mounted) {
                    await Navigator.of(sheetContext).maybePop();
                  }
                  await ref
                      .read(orderProvider.notifier)
                      .assignDraftTable(
                        draft.id,
                        pick.tableId,
                        announceLabel: pick.tableId == null ? null : pick.label,
                      );
                }()),
              ),
            MadarButton(
              label: bridge.tr(key: 'common.save'),
              onTap: () =>
                  Navigator.of(sheetContext).maybePop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    // After the sheet's exit: its field still builds while it slides out,
    // and a disposed controller there throws.
    unawaited(
      Future<void>.delayed(MotionSpec.gentleDuration, controller.dispose),
    );
    // An EMPTY name is an answer too: it takes the name off, and the chip
    // reads its time again.
    if (saved == null) return;
    await ref.read(orderProvider.notifier).renameDraft(draft.id, saved);
  }

  /// Legacy drafts carried an "HH:MM" auto-label as their name — show those
  /// as time (via sortKey), not as a custom title.
  static String? _customName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    if (OrderNotifier.looksLikeTimeLabel(trimmed)) return null;
    return trimmed;
  }

  /// Chip title = "name · T5" / name / table label alone — whatever exists.
  static String? _chipTitle(String? name, String? tableLabel) {
    if (tableLabel == null || tableLabel.isEmpty) return name;
    return name == null ? tableLabel : '$name · $tableLabel';
  }
}

/// The live order's edit sheet: free-text rename (persists across holds via
/// the draft's name; empty clears back to the time label) + the table pick
/// (applied when the order parks). The table row only renders when the
/// branch has a floor layout — no layout, no table anything.
Future<void> editLiveOrderName(
  BuildContext context,
  WidgetRef ref,
  String? tableId,
) async {
  final bridge = ref.read(bridgeProvider);
  final notifier = ref.read(cartProvider(tableId).notifier);
  final controller = TextEditingController(
    text: ref.read(cartProvider(tableId)).name ?? '',
  );
  final hasFloor = ref.read(orderProvider).hasFloor;
  final saved = await showMadarSheet<String>(
    context,
    size: SheetSize.hug,
    maxWidth: Responsive.sheetCompactMaxWidth,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            bridge.tr(key: 'order.rename_title'),
            style: MadarType.h3.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.lg),
          MadarField(
            controller: controller,
            placeholder: bridge.tr(key: 'order.rename_hint'),
            icon: 'pencil',
          ),
          if (hasFloor) ...[
            const SizedBox(height: Space.md),
            Consumer(
              builder: (context, sheetRef, _) {
                final label = cartTableLabel(
                  sheetRef.watch(orderProvider),
                  sheetRef.watch(cartProvider(tableId)),
                );
                return MadarButton(
                  label: label == null
                      ? bridge.tr(key: 'tables.assign')
                      : '${bridge.tr(key: 'order.table')} · $label',
                  icon: 'square.grid.2x2',
                  variant: MadarButtonVariant.outline,
                  onTap: () => unawaited(() async {
                    final pick = await showTablePickerSheet(
                      sheetContext,
                      sheetRef,
                      currentTableId: tableId,
                    );
                    if (pick == null || pick.tableId == tableId) {
                      return;
                    }
                    // Assigning PARKS the order on that table — the lines go
                    // with it. (A context switch here left them behind.)
                    // The typed name rides along; the sheet closes without
                    // re-applying it over the emptied cart.
                    await notifier.setName(controller.text);
                    if (sheetContext.mounted) {
                      await Navigator.of(sheetContext).maybePop();
                    }
                    await notifier.holdOn(pick.tableId, pick.label);
                  }()),
                );
              },
            ),
          ],
          const SizedBox(height: Space.xl),
          MadarButton(
            label: bridge.tr(key: 'common.done'),
            onTap: () => Navigator.of(sheetContext).maybePop(controller.text),
          ),
        ],
      ),
    ),
  );
  if (saved != null) {
    await ref.read(cartProvider(tableId).notifier).setName(saved);
  }
  controller.dispose();
}
