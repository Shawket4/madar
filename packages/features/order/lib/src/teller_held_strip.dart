import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart' show askManager;
import 'package:feature_order/src/held_orders_strip.dart';
import 'package:feature_order/src/order_customer_row.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_screen.dart' show TableOrderScreen;
import 'package:feature_order/src/tables_screen.dart' show showTablePickerSheet;
import 'package:feature_order/src/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Teller strip: a chip per parked draft PLUS, when the cart is non-empty,
/// the live cart's own chip (the selected one).
///
/// Drawn by `SellCart` (sell_cart.dart) on the counter, inside the cart's
/// header row: it shows what is already parked and carries the live order's
/// rename pencil.
class TellerHeldStrip extends ConsumerWidget {
  const TellerHeldStrip({
    this.tableId,
    this.style = HeldChipStyle.full,
    this.inline = false,
    this.fold = false,
    super.key,
  });

  /// The cart whose live chip leads the strip (null = takeaway).
  final String? tableId;

  /// How much each chip says (the cart column's width decides).
  final HeldChipStyle style;

  /// Laid inside a row — see [HeldOrdersStrip.inline].
  final bool inline;

  /// Fold the parked orders into ONE "N parked ▾" button that opens them as
  /// a list — a cart column under 320, where even number chips crowd the
  /// header. With nothing parked there is nothing to fold: the live order's
  /// chip (and its pencil) stays.
  final bool fold;

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
    final tabs = [
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
    ];
    if (fold && drafts.isNotEmpty) {
      return _FoldedParked(
        label: orderWord(
          bridge,
          'sell.parked_count',
        ).replaceAll('{count}', '${drafts.length}'),
        title: orderWord(bridge, 'sell.parked'),
        renameLabel: bridge.tr(key: 'drafts.rename'),
        discardLabel: bridge.tr(key: 'drafts.discard'),
        tabs: tabs,
      );
    }
    return HeldOrdersStrip(
      newLabel: bridge.tr(key: 'waiter.new_order'),
      style: style,
      inline: inline,
      tabs: tabs,
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
    // No `askManager` on a resume: a held order is shared state on the till
    // (owner decision 2026-09-19), so whoever is signed in continues it —
    // theirs, another teller's or a manager's. Only a DISCARD still asks.
    if (draft.tableId == null || draft.lockedByOther) {
      await notifier.resumeDraft(
        draft.id,
        fromTableId: tableId,
        parkInHand: true,
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
    final landed = await notifier.resumeDraft(draft.id);
    final table = landed?.tableId;
    if (table == null) return;
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => TableOrderScreen(tableId: table)),
    );
  }

  /// The manager-PIN sheet for DISCARDING someone else's held order (the only
  /// queue act still gated: resuming one never asks, rule 4).
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

/// The parked orders folded into one button ("2 parked ▾") on a narrow cart
/// column; it opens them as a list. Every row does what its chip does: a tap
/// resumes it, the pencil renames it, the ✕ discards it (and still asks).
class _FoldedParked extends StatelessWidget {
  const _FoldedParked({
    required this.label,
    required this.title,
    required this.renameLabel,
    required this.discardLabel,
    required this.tabs,
  });

  /// "2 parked".
  final String label;

  /// The list's heading ("Parked").
  final String title;
  final String renameLabel;
  final String discardLabel;
  final List<HeldOrderTab> tabs;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    Future<void> open() => showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => _ParkedList(
        title: title,
        renameLabel: renameLabel,
        discardLabel: discardLabel,
        tabs: tabs,
        // Every act leaves the list first: the resume may open a page,
        // the rename and the discard raise their own sheet or confirm.
        then: (act) {
          MadarSheet.close<void>(sheetContext);
          act();
        },
      ),
    );
    // Warm on purpose: parked orders are waiting on someone. The pause
    // glyph is parking's own (the bag is Pickup's).
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        triggerMode: TooltipTriggerMode.longPress,
        excludeFromSemantics: true,
        child: TactileScale(
          key: const ValueKey('cart-parked-fold'),
          onTap: () {
            MadarHaptics.selection();
            unawaited(open());
          },
          child: SizedBox(
            height: Metrics.buttonSmallHeight,
            child: Center(
              child: Container(
                height: Metrics.glyphTileDense,
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Space.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.warningBg,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.xs,
                  children: [
                    MadarGlyphIcon(
                      MadarGlyph.pause,
                      size: IconSize.xs,
                      color: colors.warning,
                    ),
                    Flexible(
                      child: MadarClippedText(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    MadarGlyphIcon(
                      MadarGlyph.chevronDown,
                      size: IconSize.xs,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParkedList extends StatelessWidget {
  const _ParkedList({
    required this.title,
    required this.renameLabel,
    required this.discardLabel,
    required this.tabs,
    required this.then,
  });

  final String title;
  final String renameLabel;
  final String discardLabel;
  final List<HeldOrderTab> tabs;
  final void Function(VoidCallback act) then;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final numbers = heldTabNumbers(tabs);
    final ordered = [...tabs]
      ..sort((a, b) => (numbers[a.key] ?? 0).compareTo(numbers[b.key] ?? 0));
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          MadarSectionHeader(text: title),
          for (final tab in ordered)
            Row(
              key: ValueKey('parked-row-${tab.key}'),
              spacing: Space.sm,
              children: [
                Expanded(
                  child: TactileScale(
                    onTap: () => then(tab.onTap),
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: Metrics.buttonSmallHeight,
                      ),
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: Space.md,
                        vertical: Space.sm,
                      ),
                      decoration: BoxDecoration(
                        color: tab.selected ? colors.accentBg : colors.surface,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(
                          color: tab.selected ? colors.accent : colors.border,
                        ),
                      ),
                      child: Row(
                        spacing: Space.sm,
                        children: [
                          StatusChip(
                            label: '${tab.count}',
                            tone: ChipTone.accent,
                          ),
                          Expanded(
                            child: MadarClippedText(
                              [
                                '#${numbers[tab.key] ?? 0}',
                                if (tab.title?.trim() case final t?
                                    when t.isNotEmpty)
                                  t,
                                ?tab.author,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MadarType.title.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (tab.onRename case final rename?)
                  MadarGlyphTile(
                    glyph: MadarGlyph.edit,
                    semanticLabel: renameLabel,
                    onTap: () => then(rename),
                  ),
                if (tab.onClose case final close?)
                  MadarGlyphTile(
                    glyph: MadarGlyph.close,
                    semanticLabel: discardLabel,
                    onTap: () => then(close),
                  ),
              ],
            ),
        ],
      ),
    );
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
          // A real customer, for someone who may attach one: picking fills
          // the name; a typed name stays a name and makes no customer.
          const SizedBox(height: Space.md),
          Consumer(
            builder: (context, sheetRef, _) => OrderCustomerRow(
              customerId: sheetRef.watch(
                cartProvider(tableId).select((c) => c.meta.customerId),
              ),
              onChanged: (c) {
                if (c != null) controller.text = c.name;
                unawaited(notifier.setCustomer(c));
              },
            ),
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
