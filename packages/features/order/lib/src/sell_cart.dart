// The cart beside the catalog — a column on an iPad, a sheet behind the
// bottom bar on a phone. One widget for both, because a round is the same
// round whichever device it was built on.
//
// Two shapes of content, one layout:
//   * at the counter: the lines, then Charge · total;
//   * on a bill: what is ALREADY on the bill (read-only, by round, with the
//     time each round went to the kitchen), then THIS ROUND (editable), then
//     Round · Bill so far, then Fire.
//
// What it does not carry, on purpose: a per-line kitchen printer button (a
// round prints once when it fires), a discount row (that is Charge's), a tax
// row (also Charge's), a tip card, or a table picker (the Floor does that).
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/cart_panel.dart' show TellerHeldStrip;
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// What the cart's one terminal button does right now, and whether it may.
///
/// Computed once from state and shared by the tablet column's footer and the
/// phone's bottom bar, so the two can never disagree about whether a sale is
/// allowed — the reason a bar is disabled is the same reason on both.
@immutable
class SellCta {
  const SellCta({
    required this.sendsToKitchen,
    required this.label,
    required this.amountMinor,
    required this.itemCount,
    required this.enabled,
    this.reason,
  });

  /// True when the cart fires a round; false when it charges a counter sale.
  final bool sendsToKitchen;

  /// The verb, already localised: "Charge" or "Fire".
  final String label;

  /// What a counter sale takes; 0 for a round (a round has no money bar).
  final int amountMinor;
  final int itemCount;
  final bool enabled;

  /// Why [enabled] is false, already localised — shown in the bar's figure
  /// slot, because a disabled control that does not say why is a broken one.
  final String? reason;
}

/// The cart's terminal action for [s].
///
/// A cart aimed at a table or a bill FIRES; a waiter's cart always fires (a
/// waiter has no drawer). Otherwise it is a counter sale and CHARGES — which
/// needs an open shift, and is refused outright where the shop puts every sale
/// on a table, because the server refuses it too and saying so here is kinder
/// than saying so after the tender.
SellCta sellCtaFor(OrderState s, MadarBridge bridge) {
  final sendsToKitchen =
      s.isWaiter || s.cartTableId != null || s.activeTicketId != null;
  final count = s.cartTotals.itemCount;
  if (sendsToKitchen) {
    return SellCta(
      sendsToKitchen: true,
      label: orderWord(bridge, 'sell.fire'),
      amountMinor: 0,
      itemCount: count,
      enabled: count > 0,
    );
  }
  String? reason;
  if (s.requireTableForOrders) {
    reason = orderWord(bridge, 'sell.table_required');
  } else if (!s.shiftOpen) {
    reason = bridge.tr(key: 'waiter.need_shift');
  }
  return SellCta(
    sendsToKitchen: false,
    label: orderWord(bridge, 'sell.charge'),
    amountMinor: s.cartTotals.totalMinor,
    itemCount: count,
    enabled: count > 0 && reason == null,
    reason: reason,
  );
}

/// The cart column / sheet.
class SellCart extends ConsumerWidget {
  const SellCart({
    required this.onTerminal,
    required this.onEditLine,
    this.onClose,
    super.key,
  });

  /// Charge or Fire — the screen decides which drawer that opens.
  final VoidCallback onTerminal;
  final ValueChanged<CartLineView> onEditLine;

  /// Set when the cart is a sheet (phone); the header then shows a close tile.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final state = ref.watch(orderProvider);
    final cta = sellCtaFor(state, bridge);
    final ticket = state.activeTicket;
    final lines = state.cartLines;
    final tableLabel = _tableLabel(state, ticket);
    // Parking is a teller's counter/takeaway move only (see CLAUDE.md's role
    // table) — never with a table or a bill already targeted, and never for
    // a waiter, whose "parking" is the open ticket.
    final isCounterFlow =
        !state.isWaiter && state.cartTableId == null && ticket == null;
    final canPark = isCounterFlow && lines.isNotEmpty;

    return ColoredBox(
      color: colors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CartHeader(
            title: _title(bridge, state, ticket, tableLabel),
            onMore: () => unawaited(_moreSheet(context, ref, state)),
            onClose: onClose,
          ),
          const MadarHairline(),
          // The parked-orders strip — dropped when this screen replaced the
          // older CartPanel and never rebuilt, which is most of why parking
          // read as a dead end: nothing showed what was already parked, and
          // nothing offered to rename it. `TellerHeldStrip` is the SAME
          // widget `CartPanel` still uses; wiring it in here just restores
          // parity between the two cart columns.
          if (isCounterFlow && (state.drafts.isNotEmpty || lines.isNotEmpty))
            const TellerHeldStrip(),
          Expanded(
            child: lines.isEmpty && ticket == null
                ? EmptyState(
                    icon: 'cart',
                    title: bridge.tr(key: 'order.cart_empty'),
                  )
                : ListView(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: Space.lg,
                      vertical: Space.md,
                    ),
                    children: [
                      if (ticket != null) ...[
                        MadarSectionHeader(
                          text: orderWord(bridge, 'sell.on_the_bill'),
                          trailing: Text(
                            '${groupBillByRound(ticket.lines).length} r',
                            textDirection: TextDirection.ltr,
                            style: MadarType.num.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        if (ticket.lines.isEmpty)
                          Text(
                            bridge.tr(key: 'tables.bill_pending'),
                            style: MadarType.bodySm.copyWith(
                              color: colors.textMuted,
                            ),
                          )
                        else
                          for (final round in groupBillByRound(ticket.lines))
                            for (final line in round.lines)
                              _OnBillLine(
                                round: round,
                                line: line,
                                currency: state.currency,
                                time: round.firedAt.isEmpty
                                    ? ''
                                    : bridge.formatTime(
                                        rfc3339: round.firedAt,
                                        style: TimeStyle.time,
                                      ),
                              ),
                        const SizedBox(height: Space.md),
                        const MadarHairline(light: true),
                        const SizedBox(height: Space.md),
                        MadarSectionHeader(
                          text: orderWord(bridge, 'sell.this_round'),
                        ),
                        const SizedBox(height: Space.sm),
                        if (lines.isEmpty)
                          Text(
                            bridge.tr(key: 'order.cart_empty'),
                            style: MadarType.bodySm.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                      ],
                      for (final line in lines)
                        _RoundLine(
                          key: ValueKey('round-${line.key}'),
                          line: line,
                          currency: state.currency,
                          onEdit: line.bundleId == null
                              ? () => onEditLine(line)
                              : null,
                        ),
                    ],
                  ),
          ),
          if (lines.isNotEmpty)
            _CartFooter(
              cta: cta,
              ticket: ticket,
              onTerminal: onTerminal,
              canPark: canPark,
              onHold: () =>
                  unawaited(ref.read(orderProvider.notifier).holdCart()),
            ),
          // A round with nothing in it yet still needs a way to be built; the
          // empty-state above says so. Nothing else to draw.
          if (lines.isEmpty && ticket != null) const SizedBox(height: Space.lg),
        ],
      ),
    );
  }

  /// "T5 · Round 3", "Takeaway", or the guest a table-less bill was started
  /// under.
  static String _title(
    MadarBridge bridge,
    OrderState s,
    TicketView? ticket,
    String? tableLabel,
  ) {
    if (ticket != null) {
      final next = groupBillByRound(ticket.lines).length + 1;
      final who = tableLabel ?? ticket.customerName ?? ticket.ticketRef ?? '';
      return '$who · ${bridge.tr(key: 'tables.round')} $next';
    }
    if (tableLabel != null) {
      return '$tableLabel · ${bridge.tr(key: 'tables.round')} 1';
    }
    if (s.isWaiter) {
      final name = s.cartName;
      return name == null
          ? orderWord(bridge, 'bills.new_bill')
          : '${orderWord(bridge, 'bills.new_bill')} · $name';
    }
    return orderWord(bridge, 'sell.takeaway');
  }

  static String? _tableLabel(OrderState s, TicketView? ticket) {
    final id = ticket?.tableId ?? s.cartTableId;
    if (id == null) return s.cartTableLabel;
    return s.floorLayout?.tables.where((t) => t.id == id).firstOrNull?.label ??
        s.cartTableLabel;
  }

  /// Clear — the ⋯. Park used to live here too, buried behind a menu icon
  /// that gave a teller no reason to ever open it; it's now the persistent
  /// tile on the footer beside Charge (see [_CartFooter]), so this sheet is
  /// just the one genuinely rare, no-undo action.
  Future<void> _moreSheet(
    BuildContext context,
    WidgetRef ref,
    OrderState s,
  ) async {
    final bridge = ref.read(bridgeProvider);
    final notifier = ref.read(orderProvider.notifier);
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            MadarButton(
              label: bridge.tr(key: 'order.clear'),
              glyph: MadarGlyph.trash,
              variant: MadarButtonVariant.danger,
              enabled: s.cartLines.isNotEmpty,
              onTap: () {
                Navigator.of(sheetContext).maybePop();
                unawaited(notifier.clearCart());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.title, required this.onMore, this.onClose});

  final String title;
  final VoidCallback onMore;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.md,
        Space.md,
        Space.md,
      ),
      child: Row(
        spacing: Space.sm,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.h3.copyWith(color: colors.textPrimary),
            ),
          ),
          MadarGlyphTile(glyph: MadarGlyph.more, onTap: onMore),
          if (onClose != null)
            MadarGlyphTile(glyph: MadarGlyph.close, onTap: onClose!),
        ],
      ),
    );
  }
}

/// One line already on the bill: "R1 19:02  2× Latte  90.00", read-only,
/// struck when voided.
class _OnBillLine extends StatelessWidget {
  const _OnBillLine({
    required this.round,
    required this.line,
    required this.currency,
    required this.time,
  });

  final BillRound round;
  final TicketLineView line;
  final String currency;
  final String time;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final strike = line.voided ? TextDecoration.lineThrough : null;
    final ink = line.voided ? colors.textMuted : colors.textSecondary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.xs),
      child: Row(
        spacing: Space.sm,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              'R${round.number}${time.isEmpty ? '' : ' $time'}',
              maxLines: 1,
              textDirection: TextDirection.ltr,
              style: MadarType.num.copyWith(color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              '${line.qty}× ${line.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.bodySm.copyWith(color: ink, decoration: strike),
            ),
          ),
          MoneyText(
            line.lineTotalMinor,
            currency: currency,
            style: MadarType.num.copyWith(decoration: strike),
            color: ink,
          ),
        ],
      ),
    );
  }
}

/// One editable line of this round: swipe start→end removes it (the notifier
/// offers Undo), tap opens the sheet to edit it, the stepper changes its
/// count and removes it at zero.
class _RoundLine extends ConsumerWidget {
  const _RoundLine({
    required this.line,
    required this.currency,
    this.onEdit,
    super.key,
  });

  final CartLineView line;
  final String currency;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final notifier = ref.read(orderProvider.notifier);
    final mods = <String>[
      if (line.sizeLabel case final s? when s.isNotEmpty) s,
      for (final a in line.addons)
        if (a.qty > 1) '${a.name} ×${a.qty}' else a.name,
      for (final o in line.optionals) o.name,
      for (final c in line.bundleComponents) '${c.qty}× ${c.name}',
    ];
    final notes = line.notes?.trim();

    final body = Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: colors.borderLight),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
                if (mods.isNotEmpty)
                  Text(
                    mods.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                if (notes != null && notes.isNotEmpty)
                  Text(
                    '“$notes”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(
                      color: colors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                const SizedBox(height: Space.xs),
                MoneyText(
                  line.lineTotalMinor,
                  currency: currency,
                  color: colors.textPrimary,
                ),
              ],
            ),
          ),
          MadarStepper(
            value: line.qty,
            onChanged: (q) => unawaited(notifier.setCartQty(line.key, q)),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
      // ClipRect: a Dismissible slides its child sideways without clipping,
      // and the column beside a catalog would otherwise watch the row sail
      // out over the tiles.
      child: ClipRect(
        child: Dismissible(
          key: ValueKey('dismiss-${line.key}'),
          direction: DismissDirection.endToStart,
          // Removing a line is destructive — the shared confirm, not a swipe
          // that fires on a mis-drag. `confirmDismiss` holds the tile mid-
          // swipe until the answer comes back; `false` springs it home.
          confirmDismiss: (_) => showMadarConfirm(
            context,
            title:
                '${ref.read(bridgeProvider).tr(key: 'order.remove_line')} · '
                '${line.name}',
            confirmLabel: ref.read(bridgeProvider).tr(key: 'order.remove_line'),
            cancelLabel: ref.read(bridgeProvider).tr(key: 'common.cancel'),
          ),
          onDismissed: (_) => unawaited(notifier.swipeRemoveCartLine(line)),
          background: Container(
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.xl,
            ),
            decoration: BoxDecoration(
              color: colors.danger,
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: MadarGlyphIcon(MadarGlyph.trash, color: colors.textOnAccent),
          ),
          child: onEdit == null
              ? body
              : GestureDetector(
                  onTap: onEdit,
                  behavior: HitTestBehavior.opaque,
                  child: body,
                ),
        ),
      ),
    );
  }
}

/// Round · Bill so far · Fire, or Charge · total.
class _CartFooter extends ConsumerWidget {
  const _CartFooter({
    required this.cta,
    required this.ticket,
    required this.onTerminal,
    required this.canPark,
    required this.onHold,
  });

  final SellCta cta;
  final TicketView? ticket;
  final VoidCallback onTerminal;

  /// Whether this cart may be parked right now (counter/takeaway, not a
  /// table or bill round).
  final bool canPark;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final totals = ref.watch(orderProvider.select((s) => s.cartTotals));
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final isBusy = ref.watch(orderProvider.select((s) => s.isBusy));
    final itemsWord = bridge.tr(key: 'waiter.items');
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            const MadarHairline(light: true),
            if (cta.sendsToKitchen) ...[
              _FigureRow(
                label: orderWord(bridge, 'sell.round_total'),
                minor: totals.subtotalMinor,
                currency: currency,
              ),
              if (ticket != null)
                // A SUBTOTAL: the ticket view carries no tax or service, and
                // the label says so rather than calling it a total.
                _FigureRow(
                  label: orderWord(bridge, 'sell.bill_so_far'),
                  minor: ticket!.subtotalMinor + totals.subtotalMinor,
                  currency: currency,
                  muted: true,
                ),
              MadarButton(
                label: '${cta.label} · ${cta.itemCount} $itemsWord',
                glyph: MadarGlyph.flame,
                loading: isBusy,
                enabled: cta.enabled,
                onTap: onTerminal,
              ),
            ] else
              Row(
                spacing: Space.sm,
                children: [
                  // Park, right beside Charge — not a tap buried in the ⋯
                  // menu. The owner's report was that parking read as a dead
                  // end; a control nobody finds might as well not exist.
                  if (canPark)
                    MadarGlyphTile(
                      glyph: MadarGlyph.bag,
                      tint: colors.accent,
                      background: colors.accentBg,
                      semanticLabel: bridge.tr(key: 'drafts.hold'),
                      onTap: onHold,
                    ),
                  Expanded(
                    child: MadarMoneyBar(
                      label: cta.label,
                      amountMinor: cta.amountMinor,
                      currency: currency,
                      enabled: cta.enabled,
                      reason: cta.reason,
                      loading: isBusy,
                      onTap: onTerminal,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({
    required this.label,
    required this.minor,
    required this.currency,
    this.muted = false,
  });

  final String label;
  final int minor;
  final String currency;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final ink = muted ? colors.textSecondary : colors.textPrimary;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (muted ? MadarType.bodySm : MadarType.title).copyWith(
              color: ink,
            ),
          ),
        ),
        MoneyText(
          minor,
          currency: currency,
          style: muted ? MadarType.money : MadarType.moneyMd,
          color: ink,
        ),
      ],
    );
  }
}

/// The phone's bottom bar: "3 items ▲" opens the cart sheet at the start,
/// the terminal verb sits at the end. Hidden while the cart is empty — the
/// next tile tap is the next sale.
class SellBar extends ConsumerWidget {
  const SellBar({required this.onOpen, required this.onTerminal, super.key});

  final VoidCallback onOpen;
  final VoidCallback onTerminal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final state = ref.watch(orderProvider);
    final cta = sellCtaFor(state, bridge);
    if (cta.itemCount <= 0) return const SizedBox.shrink();
    final isBusy = state.isBusy;
    final figure = cta.sendsToKitchen
        ? Money.format(state.cartTotals.subtotalMinor, currency: state.currency)
        : Money.format(cta.amountMinor, currency: state.currency);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Why the verb is greyed, in words, above it — the bar is too
            // narrow to carry the sentence in the button itself.
            if (!cta.enabled && cta.reason != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.xs),
                child: Text(
                  cta.reason!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(color: colors.warning),
                ),
              ),
            Row(
              spacing: Space.md,
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        MadarHaptics.selection();
                        onOpen();
                      },
                      child: SizedBox(
                        height: Metrics.buttonHeight,
                        child: Row(
                          spacing: Space.sm,
                          children: [
                            MadarGlyphIcon(
                              MadarGlyph.chevronUp,
                              color: colors.textSecondary,
                            ),
                            Flexible(
                              child: Text(
                                '${cta.itemCount} ${bridge.tr(key: 'waiter.items')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MadarType.title.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              figure,
                              textDirection: TextDirection.ltr,
                              style: MadarType.money.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                MadarButton(
                  label: cta.label,
                  glyph: cta.sendsToKitchen
                      ? MadarGlyph.flame
                      : MadarGlyph.wallet,
                  loading: isBusy,
                  enabled: cta.enabled,
                  tooltip: cta.reason,
                  onTap: onTerminal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
