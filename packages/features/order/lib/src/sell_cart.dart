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
import 'package:feature_checkout/feature_checkout.dart'
    show discountLabel, showCartDiscountPicker;
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_open_shift.dart';
import 'package:feature_order/src/teller_held_strip.dart';
import 'package:feature_order/src/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
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
    this.needsShift = false,
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

  /// Disabled only because no shift is open — the one reason with a way on
  /// from right here ("Open shift").
  final bool needsShift;
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
  var needsShift = false;
  if (s.requireTableForOrders) {
    reason = orderWord(bridge, 'sell.table_required');
  } else if (!s.shiftOpen) {
    reason = orderWord(bridge, 'sell.no_shift');
    needsShift = true;
  }
  return SellCta(
    sendsToKitchen: false,
    label: orderWord(bridge, 'sell.charge'),
    amountMinor: s.cartTotals.totalMinor,
    itemCount: count,
    enabled: count > 0 && reason == null,
    reason: reason,
    needsShift: needsShift,
  );
}

/// Emptying the whole cart — every line, including anything configured.
/// Shares its wording with the cart panel's own Clear.
Future<void> _confirmClearCart(BuildContext context, WidgetRef ref) async {
  final bridge = ref.read(bridgeProvider);
  final ok = await showMadarConfirm(
    context,
    title: bridge
        .tr(key: 'order.clear_cart_title')
        .replaceAll(
          '{count}',
          '${ref.read(orderProvider).cartTotals.itemCount}',
        ),
    body: bridge.tr(key: 'order.clear_cart_body'),
    confirmLabel: bridge.tr(key: 'order.clear_cart'),
    cancelLabel: bridge.tr(key: 'common.cancel'),
  );
  if (!ok) return;
  MadarHaptics.impact();
  await ref.read(orderProvider.notifier).clearCart();
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
    final bridge = ref.bridge;
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
            // As a COLUMN the page header above already says where this sale
            // is going ("Takeaway", "T2 · Round 3"); saying it again here was
            // the owner's "Takeaway twice". The phone's sheet has no page
            // header over it, so there the cart carries the context itself.
            title: onClose == null
                ? orderWord(bridge, 'sell.order_title')
                : _title(bridge, state, ticket, tableLabel),
            itemCount: state.cartTotals.itemCount,
            onMore: () => unawaited(_moreSheet(context, ref, state)),
            onClose: onClose,
          ),
          const MadarHairline(),
          // The parked-orders strip: what is already parked, and the pencil
          // to rename it. Without it parking reads as a dead end.
          if (isCounterFlow && (state.drafts.isNotEmpty || lines.isNotEmpty))
            const TellerHeldStrip(),
          // Who the sale is for and what comes off it — on the cart, where
          // the teller is looking, not three taps deep inside Charge.
          if (lines.isNotEmpty)
            _CartSummary(counter: isCounterFlow, lineCount: lines.length),
          Expanded(
            child: lines.isEmpty && ticket == null
                // The Lottie was already in the bundle and already supported
                // by EmptyState — the new cart just never asked for it, so
                // the asset shipped as dead weight and the screen showed a
                // flat glyph where it used to breathe.
                ? EmptyState(
                    icon: 'cart',
                    lottieAsset: 'empty_cart',
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
                            orderWord(bridge, 'sell.rounds_count').replaceAll(
                              '{count}',
                              '${groupBillByRound(ticket.lines).length}',
                            ),
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
                                roundTag: orderWord(
                                  bridge,
                                  'sell.round_tag',
                                ).replaceAll('{count}', '${round.number}'),
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
                // Confirm on the SCREEN's context, not the sheet's: the
                // sheet is closing, and a dialog raised from a context that
                // is being torn down never appears.
                unawaited(_confirmClearCart(context, ref));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CartHeader extends StatelessWidget {
  const _CartHeader({
    required this.title,
    required this.itemCount,
    required this.onMore,
    this.onClose,
  });

  final String title;

  /// Units in the cart — the count chip beside the title, which pops each
  /// time it rises (the pre-rebuild panel's bump).
  final int itemCount;
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
          // WHERE THE FLIGHT LANDS.
          //
          // playCartFlight asks CartAnchors.center() for a target and returns
          // silently when there isn't one. Both anchor keys were only ever
          // mounted inside the OLD cart panel, which nothing reaches any
          // more — so on this cart the dot had nowhere to go and every
          // add-to-cart skipped its animation without a sound. The code that
          // launches it was never the problem; it had no destination.
          //
          // Nudge is the other half: the header dips when the dot arrives,
          // so the cart acknowledges the catch instead of the item just
          // appearing in the list.
          //
          // The anchor wraps the GLYPH, not the whole row, so the dot lands
          // on the cart rather than in the middle of the title.
          CartAnchorPad(
            child: MadarIcon('cart', tint: colors.accent, size: IconSize.lg),
          ),
          Expanded(
            child: Row(
              spacing: Space.sm,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.h3.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (itemCount > 0)
                  Nudge(
                    trigger: itemCount,
                    child: StatusChip(
                      label: '$itemCount',
                      tone: ChipTone.accent,
                    ),
                  ),
              ],
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
    required this.roundTag,
    required this.line,
    required this.currency,
    required this.time,
  });

  /// "R1" / "ج1", from the core.
  final String roundTag;
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
          ConstrainedBox(
            // A floor, not a cap: "R1 07:02 PM" is wider than 56 and used to
            // clip mid-time.
            constraints: const BoxConstraints(minWidth: 56),
            child: Text(
              // The tag is a word ("R1" / "ج1") in the reading direction;
              // only the clock is an LTR island — forcing the whole string
              // LTR turned the Arabic tag round.
              '$roundTag${time.isEmpty ? '' : ' ${MadarFormat.ltr(time)}'}',
              maxLines: 1,
              style: MadarType.num.copyWith(color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              '${MadarFormat.ltr('${line.qty}×')} ${line.name}',
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
                    // The quote marks are the language's: “…” in English,
                    // «…» in Arabic — hard-coded curly quotes read backwards
                    // in RTL.
                    ref
                        .read(bridgeProvider)
                        .tr(key: 'common.quoted')
                        .replaceAll('{text}', notes),
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
          // TactileScale, not a bare GestureDetector: the old cart's line row
          // had the press-shrink and the row that replaced it did not, so a
          // tap on a line in the live bill felt like nothing happening.
          child: onEdit == null
              ? body
              : TactileScale(onTap: onEdit, child: body),
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
    final bridge = ref.bridge;
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
                // the label says so rather than calling it a total. Summed by
                // the core, keyed on both figures so it follows either.
                _FigureRow(
                  label: orderWord(bridge, 'sell.bill_so_far'),
                  minor:
                      ref
                          .watch(
                            _billSoFarProvider((
                              ticket!.subtotalMinor,
                              totals.subtotalMinor,
                            )),
                          )
                          .value ??
                      ticket!.subtotalMinor,
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
            ] else ...[
              if (cta.needsShift) SellNoShiftNotice(text: cta.reason!),
              // The discount the Charge drawer applied stays on the cart after
              // the drawer closes; say so here, not only inside Charge.
              if (totals.discountMinor > 0)
                _FigureRow(
                  label: orderWord(bridge, 'sell.discount_on_cart'),
                  minor: -totals.discountMinor,
                  currency: currency,
                  muted: true,
                ),
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
                      // The notice above says it, with its action.
                      reason: cta.needsShift ? null : cta.reason,
                      loading: isBusy,
                      onTap: onTerminal,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Bill so far" for (ticket subtotal, round subtotal) — the core adds them.
/// The round's figure is in the key only so a changed round re-asks.
final FutureProviderFamily<int, (int, int)> _billSoFarProvider = FutureProvider
    .autoDispose
    .family<int, (int, int)>(
      (ref, key) => ref
          .read(bridgeProvider)
          .cartBillSoFarMinor(ticketSubtotalMinor: key.$1),
    );

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
        AnimatedMoneyText(
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
    final bridge = ref.bridge;
    final state = ref.watch(orderProvider);
    final cta = sellCtaFor(state, bridge);
    if (cta.itemCount <= 0) return const SizedBox.shrink();
    final isBusy = state.isBusy;
    final figure = cta.sendsToKitchen
        ? state.cartTotals.subtotalMinor
        : cta.amountMinor;
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
            if (cta.needsShift)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
                child: SellNoShiftNotice(text: cta.reason!),
              )
            else if (!cta.enabled && cta.reason != null)
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
                // The phone's landing pad — same reason as the panel's.
                CartAnchorPad(
                  bar: true,
                  child: MadarIcon(
                    'cart',
                    tint: colors.accent,
                    size: IconSize.lg,
                  ),
                ),
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
                              // Pops as the count rises — the bar's bump.
                              child: Nudge(
                                trigger: cta.itemCount,
                                child: Text(
                                  '${cta.itemCount} ${bridge.tr(key: 'waiter.items')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MadarType.title.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            AnimatedMoneyText(
                              figure,
                              currency: state.currency,
                              style: MadarType.money,
                              color: colors.textSecondary,
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

/// "No shift is open" with its way on — the Open shift button — wherever the
/// cart's Charge is greyed for that reason (the column's footer, the phone's
/// bar).
class SellNoShiftNotice extends ConsumerWidget {
  const SellNoShiftNotice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return NoticeBanner(
      text: text,
      icon: 'lock',
      onTap: () => unawaited(openShiftFromSell(context, ref)),
      trailing: BannerActionPill(label: orderWord(bridge, 'sell.open_shift')),
    );
  }
}

/// The cart's chips under the parked strip: the order's note on every cart,
/// and on the counter its customer and discount. Unset, each says what it
/// adds; set, it reads the name, the discount or the note and is lit.
class _CartSummary extends ConsumerWidget {
  const _CartSummary({required this.counter, required this.lineCount});

  final bool counter;

  /// Re-asks the core for the note whenever the cart changes shape.
  final int lineCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final name = ref.watch(orderProvider.select((s) => s.cartName));
    final discountMinor = ref.watch(
      orderProvider.select((s) => s.cartTotals.discountMinor),
    );
    final discount = ref.watch(_cartDiscountLabelProvider(discountMinor)).value;
    final note = ref.watch(_cartNoteProvider(lineCount)).value;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.lg,
              0,
              Space.lg,
              Space.sm,
            ),
            child: Row(
              spacing: Space.sm,
              children: [
                if (counter) ...[
                  MadarChip(
                    label: name ?? orderWord(bridge, 'sell.customer'),
                    glyph: MadarGlyph.user,
                    selected: name != null,
                    onTap: () => unawaited(editLiveOrderName(context, ref)),
                  ),
                  MadarChip(
                    label: discount ?? orderWord(bridge, 'sell.discount'),
                    glyph: MadarGlyph.percent,
                    selected: discount != null,
                    onTap: () => unawaited(() async {
                      final changed = await showCartDiscountPicker(
                        context,
                        ref,
                      );
                      if (changed) {
                        await ref.read(orderProvider.notifier).loadCart();
                      }
                    }()),
                  ),
                ],
                MadarChip(
                  label: note ?? orderWord(bridge, 'sell.note'),
                  glyph: MadarGlyph.note,
                  selected: note != null,
                  onTap: () => unawaited(editCartNote(context, ref)),
                ),
              ],
            ),
          ),
          const MadarHairline(light: true),
        ],
      ),
    );
  }
}

/// The cart's order note, from the core.
final FutureProviderFamily<String?, int> _cartNoteProvider = FutureProvider
    .autoDispose
    .family<String?, int>((ref, _) => ref.read(bridgeProvider).cartNote());

/// Type (or clear) the note for the whole order. The core keeps it with the
/// cart and carries it on the checkout and the fired ticket.
Future<void> editCartNote(BuildContext context, WidgetRef ref) async {
  final bridge = ref.read(bridgeProvider);
  final controller = TextEditingController(text: await bridge.cartNote() ?? '');
  if (!context.mounted) return;
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
          Text(orderWord(bridge, 'sell.note_title'), style: MadarType.h2),
          MadarField(
            controller: controller,
            placeholder: orderWord(bridge, 'sell.note_hint'),
            icon: 'text.bubble',
            autofocus: true,
          ),
          MadarButton(
            label: bridge.tr(key: 'common.save'),
            onTap: () => Navigator.of(sheetContext).pop(controller.text),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (saved == null) return;
  await bridge.cartSetNote(note: saved.trim().isEmpty ? null : saved.trim());
  ref.invalidate(_cartNoteProvider);
}

/// The applied cart discount's label, or null — re-asked whenever the cart's
/// discount figure moves.
final FutureProviderFamily<String?, int> _cartDiscountLabelProvider =
    FutureProvider.autoDispose.family<String?, int>((ref, minor) async {
      if (minor <= 0) return null;
      final bridge = ref.read(bridgeProvider);
      final id = await bridge.cartDiscountId();
      if (id == null) return null;
      final all = await bridge.listDiscounts();
      final d = all.where((d) => d.id == id).firstOrNull;
      return d == null ? null : discountLabel(d);
    });
