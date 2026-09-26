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
// Each line of this round carries a print tile that sends just that dish to
// the kitchen early (tap prints, long press previews). It is EXTRA paper: it
// marks nothing sent, and the round still prints in full when it fires.
//
// What it does not carry, on purpose: a discount row (that is Charge's), a tax
// row (also Charge's), a tip card, or a table picker (the Floor does that).
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart'
    show
        CartKitchenChitSheet,
        KitchenChitSheet,
        PrintState,
        buildCartKitchenChit,
        buildCartLineChit,
        cartDiscountLabel,
        discountLabel,
        printCartKitchenChit,
        sayChitPrint,
        showCartDiscountPicker;
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_open_till.dart';
import 'package:feature_order/src/staff_drink_sheet.dart';
import 'package:feature_order/src/teller_held_strip.dart';
import 'package:feature_order/src/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show FutureProviderFamily, NotifierProviderFamily;
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
    this.needsTill = false,
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

  /// Disabled only because no till is open — the one reason with a way on
  /// from right here ("Open till").
  final bool needsTill;
}

/// The cart's terminal action for [s].
///
/// A cart aimed at a table or a bill FIRES; a waiter's cart always fires (a
/// waiter has no drawer). Otherwise it is a counter sale and CHARGES — which
/// needs an open till, and is refused outright where the shop puts every sale
/// on a table, because the server refuses it too and saying so here is kinder
/// than saying so after the tender.
///
/// [tillOpen] is the shell's (`shellProvider.tillOpen`) — the one owner of
/// the till — never a copy this surface loaded for itself.
SellCta sellCtaFor(
  OrderState s,
  CartState c,
  MadarBridge bridge, {
  required bool tillOpen,
}) {
  final sendsToKitchen =
      s.isWaiter || c.tableId != null || cartTicket(s, c) != null;
  final count = c.totals.itemCount;
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
  var needsTill = false;
  if (s.requireTableForOrders) {
    reason = orderWord(bridge, 'sell.table_required');
  } else if (!tillOpen) {
    reason = orderWord(bridge, 'sell.no_shift');
    needsTill = true;
  }
  return SellCta(
    sendsToKitchen: false,
    label: orderWord(bridge, 'sell.charge'),
    amountMinor: c.totals.totalMinor,
    itemCount: count,
    enabled: count > 0 && reason == null,
    reason: reason,
    needsTill: needsTill,
  );
}

/// Emptying the whole cart — every line, including anything configured.
/// Shares its wording with the cart panel's own Clear.
Future<void> _confirmClearCart(
  BuildContext context,
  WidgetRef ref,
  String? tableId,
) async {
  final bridge = ref.read(bridgeProvider);
  final ok = await showMadarConfirm(
    context,
    title: bridge
        .tr(key: 'order.clear_cart_title')
        .replaceAll(
          '{count}',
          '${ref.read(cartProvider(tableId)).totals.itemCount}',
        ),
    body: bridge.tr(key: 'order.clear_cart_body'),
    confirmLabel: bridge.tr(key: 'order.clear_cart'),
    cancelLabel: bridge.tr(key: 'common.cancel'),
  );
  if (!ok) return;
  MadarHaptics.impact();
  await ref.read(cartProvider(tableId).notifier).clear();
}

/// The cart column / sheet.
class SellCart extends ConsumerWidget {
  const SellCart({
    required this.tableId,
    required this.onTerminal,
    required this.onEditLine,
    this.onClose,
    this.editOnSelect = false,
    super.key,
  });

  /// Fast mode: selecting a line also opens its editor, which shows beside
  /// the cart rather than over it. Elsewhere the editor is a sheet that
  /// would cover the controls the tap just showed; the line's pencil opens it.
  final bool editOnSelect;

  /// The cart this panel shows — null = takeaway, else that table's own.
  final String? tableId;

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
    final cart = ref.watch(cartProvider(tableId));
    final cta = sellCtaFor(
      state,
      cart,
      bridge,
      tillOpen: ref.watch(shellProvider.select((s) => s.tillOpen)),
    );
    final ticket = cartTicket(state, cart);
    final lines = cart.lines;
    final tableLabel = cartTableLabel(state, cart);
    // Parking is a teller's counter/takeaway move only (see CLAUDE.md's role
    // table) — never with a table or a bill already targeted, and never for
    // a waiter, whose "parking" is the open ticket.
    final isCounterFlow = !state.isWaiter && tableId == null && ticket == null;
    final canPark = isCounterFlow && lines.isNotEmpty;
    // A cart that FIRES is (or is becoming) a table's bill, and a bill never
    // carries a staff drink: a counter cart that was marked and then aimed at
    // a table or a ticket loses its marks. The core drops them and words the
    // reason; the cart toasts it.
    if (cta.sendsToKitchen && lines.any((l) => l.staffDrink != null)) {
      unawaited(
        Future.microtask(
          () =>
              ref.read(cartProvider(tableId).notifier).dropStaffMarksForBill(),
        ),
      );
    }

    final head = [
      _CartHeader(
        // As a COLUMN the page header above already says where this sale
        // is going ("Takeaway", "T2 · Round 3"); saying it again here was
        // the owner's "Takeaway twice". The phone's sheet has no page
        // header over it, so there the cart carries the context itself.
        title: onClose == null
            ? orderWord(bridge, 'sell.order_title')
            : _title(bridge, state, cart, ticket, tableLabel),
        itemCount: cart.totals.itemCount,
        onMore: () => unawaited(_moreSheet(context, ref, cart)),
        onClose: onClose,
      ),
      // Pickup or dine in, at the top where the design has it. Only on a
      // cart that charges: a round fired to a bill is dine-in already.
      // Nothing to do with the floor — it decides whether the cups and
      // lids come off stock (see `dineInProvider`).
      if (!cta.sendsToKitchen)
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.lg,
            0,
            Space.lg,
            Space.md,
          ),
          child: MadarSegmented<bool>(
            key: const ValueKey('cart-service-mode'),
            items: [
              MadarSegmentItem(
                false,
                bridge.tr(key: 'charge.pickup'),
                glyph: MadarGlyph.bag,
              ),
              MadarSegmentItem(
                true,
                bridge.tr(key: 'charge.dine_in'),
                glyph: MadarGlyph.table,
              ),
            ],
            value: ref.watch(dineInProvider(tableId)),
            onChanged: (dineIn) =>
                ref.read(dineInProvider(tableId).notifier).set(dineIn: dineIn),
          ),
        ),
      const MadarHairline(),
      // The parked-orders strip: what is already parked, and the pencil
      // to rename it. Without it parking reads as a dead end.
      if (isCounterFlow && (state.drafts.isNotEmpty || lines.isNotEmpty))
        TellerHeldStrip(tableId: tableId),
      // Who the sale is for and what comes off it — on the cart, where
      // the teller is looking, not three taps deep inside Charge.
      if (lines.isNotEmpty)
        _CartSummary(
          tableId: tableId,
          counter: isCounterFlow,
          lineCount: lines.length,
        ),
    ];
    final rows = <Widget>[
      if (ticket != null) ...[
        MadarSectionHeader(
          text: orderWord(bridge, 'sell.on_the_bill'),
          trailing: Text(
            orderWord(
              bridge,
              'sell.rounds_count',
            ).replaceAll('{count}', '${groupBillByRound(ticket.lines).length}'),
            textDirection: TextDirection.ltr,
            style: MadarType.num.copyWith(color: colors.textMuted),
          ),
        ),
        const SizedBox(height: Space.sm),
        if (ticket.lines.isEmpty)
          Text(
            bridge.tr(key: 'tables.bill_pending'),
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
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
        MadarSectionHeader(text: orderWord(bridge, 'sell.this_round')),
        const SizedBox(height: Space.sm),
        if (lines.isEmpty)
          Text(
            bridge.tr(key: 'order.cart_empty'),
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
          ),
      ],
      // The deals this cart qualifies for (the teller applies
      // one with a tap, C8), and the ones already applied.
      for (final d in cart.appliedDeals)
        _AppliedDealRow(
          key: ValueKey('deal-applied-${d.id}'),
          deal: d,
          currency: state.currency,
          onRemove: () => unawaited(
            ref.read(cartProvider(tableId).notifier).removeDeal(d.id),
          ),
        ),
      for (final d in cart.dealSuggestions)
        DealSuggestionBanner(
          key: ValueKey('deal-suggest-${d.dealId}'),
          suggestion: d,
          currency: state.currency,
          onApply: () => unawaited(
            ref.read(cartProvider(tableId).notifier).applyDeal(d.dealId),
          ),
        ),
      for (final line in lines)
        _RoundLine(
          tableId: tableId,
          key: ValueKey('round-${line.key}'),
          line: line,
          tableLabel: tableLabel,
          ticketRef: ticket?.ticketRef,
          currency: state.currency,
          counterSale: !cta.sendsToKitchen,
          editOnSelect: editOnSelect,
          onEdit: () => onEditLine(line),
        ),
    ];
    final foot = [
      if (lines.isNotEmpty)
        _CartFooter(
          tableId: tableId,
          cta: cta,
          ticket: ticket,
          onTerminal: onTerminal,
          canPark: canPark,
          onHold: () =>
              unawaited(ref.read(cartProvider(tableId).notifier).hold()),
          tableLabel: tableLabel,
          ticketRef: ticket?.ticketRef,
          lineCount: lines.length,
        ),
      // A round with nothing in it yet still needs a way to be built; the
      // empty-state above says so. Nothing else to draw.
      if (lines.isEmpty && ticket != null) const SizedBox(height: Space.lg),
    ];
    const roundPadding = EdgeInsetsDirectional.symmetric(
      horizontal: Space.md,
      vertical: Space.md,
    );

    return ColoredBox(
      color: colors.bg,
      child: LayoutBuilder(
        builder: (context, c) {
          // Short on height — the on-screen keyboard is up (an iPad in
          // landscape keeps ~300 px for the cart) or the window is small: the
          // fixed rows alone outgrew the column and overflowed (T2 B1). The
          // whole cart then scrolls as one, its footer and Charge with it.
          if (c.maxHeight < kCartScrollsBelow &&
              (lines.isNotEmpty || ticket != null)) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...head,
                  Padding(
                    padding: roundPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows,
                    ),
                  ),
                  ...foot,
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...head,
              Expanded(
                child: lines.isEmpty && ticket == null
                    // The Lottie was already in the bundle and already
                    // supported by EmptyState — the new cart just never asked
                    // for it, so the asset shipped as dead weight and the
                    // screen showed a flat glyph where it used to breathe.
                    ? EmptyState(
                        icon: 'cart',
                        lottieAsset: 'empty_cart',
                        title: bridge.tr(key: 'order.cart_empty'),
                      )
                    : ListView(padding: roundPadding, children: rows),
              ),
              ...foot,
            ],
          );
        },
      ),
    );
  }

  /// "T5 · Round 3", "Takeaway", or the guest a table-less bill was started
  /// under.
  static String _title(
    MadarBridge bridge,
    OrderState s,
    CartState cart,
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
      final name = cart.name;
      return name == null
          ? orderWord(bridge, 'bills.new_bill')
          : '${orderWord(bridge, 'bills.new_bill')} · $name';
    }
    return orderWord(bridge, 'sell.takeaway');
  }

  /// Clear — the ⋯. Park used to live here too, buried behind a menu icon
  /// that gave a teller no reason to ever open it; it's now the persistent
  /// tile on the footer beside Charge (see [_CartFooter]), so this sheet is
  /// just the one genuinely rare, no-undo action.
  Future<void> _moreSheet(
    BuildContext context,
    WidgetRef ref,
    CartState cart,
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
              enabled: cart.lines.isNotEmpty,
              onTap: () {
                // MadarSheet.close, never `Navigator.maybePop()`: maybePop is
                // async and DROPS the pop when anything is pushed before it
                // runs — the confirm below always is — which left this sheet
                // up after "Clear cart", its scrim eating the next tap on the
                // menu (T2 B3: the dead Latte tile).
                MadarSheet.close<void>(sheetContext);
                // Confirm on the SCREEN's context, not the sheet's: the
                // sheet is closing, and a dialog raised from a context that
                // is being torn down never appears.
                unawaited(_confirmClearCart(context, ref, tableId));
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
            child: MadarClippedText(
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

/// A cart column shorter than this scrolls as ONE (header, lines and footer
/// together) instead of pinning its header and footer around a scrolling
/// list: below it the pinned rows alone — the parked strip, the summary, the
/// totals and Charge, ~480 px with a combo in the cart — leave the list no
/// room, and with the keyboard up on an iPad in landscape (~300 px) they
/// overflowed (T2 B1).
const double kCartScrollsBelow = 560;

/// A cart footer narrower than this takes the dense footer: the compact
/// kitchen button with its note tile, and Park on its own row above Charge.
const double kCartFooterNarrowWidth = 320;

/// The selected line of each cart (its stepper and actions open), by the
/// cart's context. ONE at a time: a flag on each line let a second line open
/// beside the first, both highlighted.
final NotifierProviderFamily<SelectedCartLine, String?, String?>
selectedCartLineProvider = NotifierProvider.autoDispose
    .family<SelectedCartLine, String?, String?>(SelectedCartLine.new);

class SelectedCartLine extends Notifier<String?> {
  SelectedCartLine(this.arg);

  /// The cart's context (null = takeaway).
  final String? arg;

  @override
  String? build() => null;

  /// Select [key], folding the line selected before; the selected line
  /// folds itself. Whether [key] is selected now.
  bool toggle(String key) {
    state = state == key ? null : key;
    return state == key;
  }
}

/// One editable line of this round, one row: "2×", the name and what was
/// chosen, the price. A tap selects it — its stepper and actions open under
/// it, and the line selected before folds — and opens the sheet to edit it;
/// a second tap folds it. Swipe start→end removes it (the notifier offers
/// Undo).
///
/// The controls live on the selected line only (the Fast mode design's
/// cart): beside every name they left a 340 column ~30 points for it, so
/// every name ellipsised after a word.
class _RoundLine extends ConsumerStatefulWidget {
  const _RoundLine({
    required this.tableId,
    required this.line,
    required this.currency,
    this.counterSale = false,
    this.tableLabel,
    this.ticketRef,
    this.onEdit,
    this.editOnSelect = false,
    super.key,
  });

  final String? tableId;
  final CartLineView line;
  final bool editOnSelect;

  /// The cart charges a counter sale (it does not fire a round): the only
  /// flow that offers the staff-drink action.
  final bool counterSale;

  /// Where the chit says it goes, and the bill it belongs to — the same
  /// context a fired round prints with.
  final String? tableLabel;
  final String? ticketRef;
  final String currency;
  final VoidCallback? onEdit;

  @override
  ConsumerState<_RoundLine> createState() => _RoundLineState();
}

class _RoundLineState extends ConsumerState<_RoundLine> {
  String? get tableId => widget.tableId;
  CartLineView get line => widget.line;
  bool get counterSale => widget.counterSale;
  String? get tableLabel => widget.tableLabel;
  String? get ticketRef => widget.ticketRef;
  String get currency => widget.currency;

  void _tap() {
    final opened = ref
        .read(selectedCartLineProvider(tableId).notifier)
        .toggle(line.key);
    if (opened && widget.editOnSelect) widget.onEdit?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final open = ref.watch(selectedCartLineProvider(tableId)) == line.key;
    final notifier = ref.read(cartProvider(tableId).notifier);
    final isCombo = line.kind == 'combo';
    final mods = <String>[
      if (line.sizeLabel case final s? when s.isNotEmpty && !isCombo) s,
      for (final a in line.addons)
        if (a.qty > 1) '${a.name} ×${a.qty}' else a.name,
      for (final o in line.optionals) o.name,
    ];
    final notes = line.notes?.trim();
    final bridge = ref.read(bridgeProvider);

    // The name owns the row's whole width and may take two lines: the
    // stepper and the tiles sit on their own row under it. Beside the name
    // they left a 340 cart column ~30 points for it (~90 with no staff-drink
    // tile), so every name ellipsised after a word.
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        MadarClippedText(
          line.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: MadarType.title.copyWith(color: colors.textPrimary),
        ),
        // A staff drink says so, on the line. The badge is also the way back
        // to its note, and to taking the mark off.
        if (line.staffDrink != null || isCombo)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Space.xs),
            child: Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                if (line.staffDrink != null)
                  StaffDrinkBadge(line: line, tableId: tableId),
                if (isCombo)
                  MadarTag(
                    label: bridge.tr(key: 'combo.badge'),
                    tone: MadarTone.accent,
                  ),
              ],
            ),
          ),
        // A combo's items, indented under it: each with its size, what a
        // bigger size or the choice added, and its own add-ons (C12).
        if (isCombo)
          for (final p in line.parts) CartPartRow(part: p, currency: currency),
        if (mods.isNotEmpty)
          MadarClippedText(
            mods.join(' · '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
        if (notes != null && notes.isNotEmpty)
          MadarClippedText(
            // The quote marks are the language's: “…” in English,
            // «…» in Arabic — hard-coded curly quotes read backwards
            // in RTL.
            bridge.tr(key: 'common.quoted').replaceAll('{text}', notes),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(
              color: colors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        if (line.dealName case final d? when line.dealCutMinor > 0)
          MadarClippedText(
            d,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(color: colors.success),
          ),
        if (line.kitchenNote case final k? when k.trim().isNotEmpty)
          MadarClippedText(
            '${orderWord(bridge, 'sell.kitchen_note')}: ${k.trim()}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(
              color: colors.warning,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
    // One line, scaled down before it ever wraps: a figure broken over two
    // lines reads as two figures.
    // A staff drink: the normal price struck through, then what the pool
    // leaves to pay ("Free" / "Extras 25.00") — the core's figures.
    final price = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerEnd,
      child: line.staffDrink != null
          ? StaffDrinkPrice(line: line, currency: currency)
          : MoneyText(
              line.lineTotalMinor,
              currency: currency,
              color: colors.textPrimary,
            ),
    );
    // The line's own acts. Tap prints just this dish now; a long press opens
    // a sheet for its kitchen note, a preview, and print. ONE button for this
    // row's kitchen action, never confused with the cart-level "Send to
    // kitchen" in the footer, which sends every line.
    void printDish() => unawaited(
      ref
          .read(orderProvider.notifier)
          .printKitchenChit(
            line,
            tableId: tableId,
            tableLabel: tableLabel,
            ticketRef: ticketRef,
          ),
    );
    void openDishSheet() => unawaited(
      showMadarSheet<void>(
        context,
        size: SheetSize.hug,
        maxWidth: Responsive.sheetCompactMaxWidth,
        builder: (_) => _RowKitchenSheet(
          tableId: tableId,
          line: line,
          tableLabel: tableLabel,
          ticketRef: ticketRef,
        ),
      ),
    );
    // The recipe card: what goes into one and the steps, to the same printer
    // as this dish's chit. Only on an item that has either.
    void printRecipe() => unawaited(
      ref
          .read(orderProvider.notifier)
          .printRecipeChit(
            line,
            tableId: tableId,
            tableLabel: tableLabel,
            ticketRef: ticketRef,
          ),
    );
    // The branch's staff pool: only when the core says this line is on it and
    // this person may act. See `staff_drink_sheet.dart`.
    final staff = staffDrinkTileShows(
      ref,
      line,
      tableId: tableId,
      counterSale: counterSale,
    );
    final recipe = ref.read(orderProvider.notifier).lineHasRecipe(line);
    final stepper = MadarStepper(
      dense: true,
      value: line.qty,
      onChanged: (q) => unawaited(notifier.setQty(line.key, q)),
    );
    final fate = [
      if (widget.onEdit case final edit?)
        MadarGlyphTile(
          key: ValueKey('edit-${line.key}'),
          glyph: MadarGlyph.edit,
          dense: true,
          semanticLabel: orderWord(bridge, 'sell.edit_line'),
          onTap: edit,
        ),
      MadarGlyphTile(
        key: ValueKey('remove-${line.key}'),
        glyph: MadarGlyph.trash,
        dense: true,
        tint: colors.danger,
        semanticLabel: bridge.tr(key: 'order.remove_line'),
        onTap: () => unawaited(notifier.swipeRemove(line)),
      ),
    ];
    // ONE row when the stepper, the tools, edit and remove all fit (the
    // 86-wide stepper fits a food line in a 300 column, a staff drink with a
    // recipe at 340). When they do not, TWO rows on purpose: the stepper,
    // edit and remove on top, the tools as one even row of labelled buttons
    // under them. The owner: "if for some reason it needs to take a second
    // row make it look polished not like it overflowed".
    final controls = LayoutBuilder(
      builder: (context, box) {
        final toolCount = 1 + (staff ? 1 : 0) + (recipe ? 1 : 0);
        final oneRow =
            Metrics.stepperDenseWidth +
            (toolCount + fate.length) * (Metrics.glyphTileDense + Space.xs);
        if (oneRow <= box.maxWidth) {
          return Row(
            spacing: Space.xs,
            children: [
              Expanded(
                child: Row(
                  spacing: Space.xs,
                  children: [
                    stepper,
                    if (staff)
                      StaffDrinkTile(
                        line: line,
                        tableId: tableId,
                        counterSale: counterSale,
                        dense: true,
                      ),
                    // Its long press is its own (the dish's sheet, titled
                    // with the item), so its word shows on a resting mouse
                    // only.
                    MadarGlyphTile(
                      key: ValueKey('kitchen-${line.key}'),
                      glyph: MadarGlyph.printer,
                      dense: true,
                      semanticLabel: orderWord(bridge, 'sell.kitchen_row_hint'),
                      onTap: printDish,
                      onLongPress: openDishSheet,
                    ),
                    // A long press says what it does (the tile's own hold
                    // hint).
                    if (recipe)
                      MadarGlyphTile(
                        key: ValueKey('recipe-${line.key}'),
                        glyph: MadarGlyph.list,
                        dense: true,
                        semanticLabel: orderWord(bridge, 'sell.send_recipe'),
                        onTap: printRecipe,
                      ),
                  ],
                ),
              ),
              ...fate,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            Row(
              spacing: Space.xs,
              children: [stepper, const Spacer(), ...fate],
            ),
            Row(
              spacing: Space.xs,
              children: [
                if (staff)
                  Expanded(
                    child: StaffDrinkTile(
                      line: line,
                      tableId: tableId,
                      counterSale: counterSale,
                      label: orderWord(bridge, 'sell.tool_staff'),
                    ),
                  ),
                Expanded(
                  child: MadarButton(
                    key: ValueKey('kitchen-${line.key}'),
                    label: orderWord(bridge, 'sell.tool_kitchen'),
                    glyph: MadarGlyph.printer,
                    variant: MadarButtonVariant.secondary,
                    size: MadarButtonSize.dense,
                    onTap: printDish,
                    onLongPress: openDishSheet,
                  ),
                ),
                if (recipe)
                  Expanded(
                    child: MadarButton(
                      key: ValueKey('recipe-${line.key}'),
                      label: orderWord(bridge, 'sell.tool_recipe'),
                      glyph: MadarGlyph.list,
                      variant: MadarButtonVariant.secondary,
                      size: MadarButtonSize.dense,
                      onTap: printRecipe,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );

    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 26),
          child: Text(
            MadarFormat.ltr('${line.qty}×'),
            style: MadarType.numLg.copyWith(color: colors.textPrimary),
          ),
        ),
        Expanded(child: info),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 112),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              price,
              // In an applied deal: the line keeps its normal price, and
              // what the deal takes off it reads under it.
              if (line.dealCutMinor > 0)
                MadarClippedText(
                  '−${Money.format(line.dealCutMinor, currency: currency, locale: MadarFormat.localeOf(context))}',
                  key: ValueKey('deal-cut-${line.key}'),
                  maxLines: 1,
                  style: MadarType.bodySm.copyWith(color: colors.success),
                ),
            ],
          ),
        ),
      ],
    );
    final body = AnimatedContainer(
      duration: MotionSpec.gentleDuration,
      curve: MotionSpec.gentleCurve,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: open ? colors.accent.withValues(alpha: 0.08) : colors.surface,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(
          color: open ? colors.accent : colors.borderLight,
          width: open ? 2 : 1,
        ),
      ),
      child: AnimatedSize(
        duration: MotionSpec.gentleDuration,
        curve: MotionSpec.gentleCurve,
        alignment: AlignmentDirectional.topStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [head, if (open) controls],
        ),
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
          onDismissed: (_) => unawaited(notifier.swipeRemove(line)),
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
          child: TactileScale(
            key: ValueKey('line-tap-${line.key}'),
            onTap: _tap,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Build the chit in the core and show it on the print preview sheet; the
/// sheet's Print sends it. A chit the core cannot build says so. Shared by
/// the row's kitchen sheet's Preview action.
Future<void> _previewRowChit(
  BuildContext context,
  WidgetRef ref, {
  required String? tableId,
  required CartLineView line,
  String? tableLabel,
  String? ticketRef,
}) async {
  final bridge = ref.read(bridgeProvider);
  final CartLineChit chit;
  try {
    chit = await buildCartLineChit(
      bridge,
      tableId: tableId,
      lineKey: line.key,
      tableLabel: tableLabel,
      ticketRef: ticketRef,
    );
  } on Object {
    sayChitPrint(
      ref.read(appToastProvider.notifier),
      bridge,
      PrintState.failed,
    );
    return;
  }
  if (!context.mounted) return;
  await showMadarSheet<void>(
    context,
    size: SheetSize.large,
    builder: (_) =>
        KitchenChitSheet(chit: chit, tableId: tableId, lineKey: line.key),
  );
}

/// The row's long-press sheet: titled with the item's own name so it never
/// reads as the whole-cart action. Its own kitchen note, a preview of its
/// chit, and print — the row sends only THIS item, unlike the cart-level
/// "Send to kitchen" in the footer.
class _RowKitchenSheet extends ConsumerWidget {
  const _RowKitchenSheet({
    required this.tableId,
    required this.line,
    this.tableLabel,
    this.ticketRef,
  });

  final String? tableId;
  final CartLineView line;
  final String? tableLabel;
  final String? ticketRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    // The line as the cart has it NOW: its note is edited from this sheet,
    // and the chip says the saved one. Read by key, never through the row
    // that opened the sheet — that row may rebuild after this sheet does
    // (the cart lays its rows out in a LayoutBuilder).
    final line =
        ref.watch(
          cartProvider(tableId).select(
            (c) => c.lines.where((l) => l.key == this.line.key).firstOrNull,
          ),
        ) ??
        this.line;
    final note = line.kitchenNote?.trim();
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Text(line.name, style: MadarType.h2),
          MadarChip(
            label: (note != null && note.isNotEmpty)
                ? note
                : orderWord(bridge, 'sell.kitchen_row_sheet_note'),
            glyph: MadarGlyph.note,
            selected: note != null && note.isNotEmpty,
            onTap: () => unawaited(
              editLineKitchenNote(context, ref, tableId: tableId, line: line),
            ),
          ),
          MadarButton(
            label: orderWord(bridge, 'sell.kitchen_row_sheet_preview'),
            variant: MadarButtonVariant.secondary,
            onTap: () => unawaited(
              _previewRowChit(
                context,
                ref,
                tableId: tableId,
                line: line,
                tableLabel: tableLabel,
                ticketRef: ticketRef,
              ),
            ),
          ),
          if (ref.read(orderProvider.notifier).lineHasRecipe(line))
            MadarButton(
              label: orderWord(bridge, 'sell.send_recipe'),
              glyph: MadarGlyph.list,
              variant: MadarButtonVariant.secondary,
              onTap: () {
                // MadarSheet.close, never maybePop: see the Print below.
                MadarSheet.close<void>(context);
                unawaited(
                  ref
                      .read(orderProvider.notifier)
                      .printRecipeChit(
                        line,
                        tableId: tableId,
                        tableLabel: tableLabel,
                        ticketRef: ticketRef,
                      ),
                );
              },
            ),
          MadarButton(
            label: orderWord(bridge, 'sell.kitchen_row_sheet_print'),
            onTap: () {
              MadarSheet.close<void>(context);
              unawaited(
                ref
                    .read(orderProvider.notifier)
                    .printKitchenChit(
                      line,
                      tableId: tableId,
                      tableLabel: tableLabel,
                      ticketRef: ticketRef,
                    ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Round · Bill so far · Fire, or Charge · total.
class _CartFooter extends ConsumerWidget {
  const _CartFooter({
    required this.tableId,
    required this.cta,
    required this.ticket,
    required this.onTerminal,
    required this.canPark,
    required this.onHold,
    this.tableLabel,
    this.ticketRef,
    this.lineCount = 0,
  });

  final String? tableId;
  final SellCta cta;
  final TicketView? ticket;
  final VoidCallback onTerminal;

  /// Whether this cart may be parked right now (counter/takeaway, not a
  /// table or bill round).
  final bool canPark;
  final VoidCallback onHold;

  /// Where the whole-cart kitchen chit says it goes, and how many lines it
  /// carries (for the button's own label).
  final String? tableLabel;
  final String? ticketRef;
  final int lineCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final totals = ref.watch(cartProvider(tableId).select((c) => c.totals));
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final isBusy = ref.watch(cartProvider(tableId).select((c) => c.isBusy));
    final startedAt = ref.watch(
      cartProvider(tableId).select((c) => c.startedAt),
    );
    final itemsWord = bridge.tr(key: 'waiter.items');
    final kitchenNote = ref
        .watch(_cartKitchenNoteProvider((tableId, lineCount)))
        .value;
    // The footer is the case that used to eat a short screen alive: every
    // control here is worth its height, and together they left the cart
    // itself a couple of rows tall on a 10.2" iPad in landscape — with a
    // bill's rounds above them, one line and a half. The window's room
    // decides, the same way for every tablet (`MadarRoom`, not a per-screen
    // pixel guess):
    //
    //  * height DENSE (any landscape tablet, 810–834 tall): smaller padding
    //    and gaps, the compact kitchen button with its note as a 44pt tile
    //    beside it instead of a chip under it. Nothing goes away.
    //  * height TIGHT (a landscape phone): dense AND capped at a share of
    //    the screen, scrolling inside that cap rather than stealing more.
    final room = MadarRoom.of(context);
    final tight = room.height.isTight;
    final viewport = MediaQuery.sizeOf(context).height;
    final hasKitchenNote = kitchenNote != null && kitchenNote.trim().isNotEmpty;

    return LayoutBuilder(
      builder: (context, box) {
        // A narrow column (the 300 of a portrait tablet, a phone's sheet)
        // takes the dense footer too: the long labels would not fit beside
        // the figures, and Park goes above Charge instead of beside it.
        final narrow = box.maxWidth < kCartFooterNarrowWidth;
        final dense = room.height.isDense || narrow;
        return _build(
          context,
          ref,
          colors: colors,
          bridge: bridge,
          totals: totals,
          currency: currency,
          isBusy: isBusy,
          startedAt: startedAt,
          itemsWord: itemsWord,
          hasKitchenNote: hasKitchenNote,
          tight: tight,
          dense: dense,
          narrow: narrow,
          viewport: viewport,
        );
      },
    );
  }

  Widget _build(
    BuildContext context,
    WidgetRef ref, {
    required MadarColors colors,
    required MadarBridge bridge,
    required CartTotals totals,
    required String currency,
    required bool isBusy,
    required String? startedAt,
    required String itemsWord,
    required bool hasKitchenNote,
    required bool tight,
    required bool dense,
    required bool narrow,
    required double viewport,
  }) {
    // The whole-cart kitchen print, clearly separate from Charge/Fire: an
    // extra early copy for the kitchen, never instead of it. Short press
    // prints now, long press previews first — the same contract as every
    // other print button in the app.
    final kitchenButton = MadarButton(
      key: const ValueKey('print-cart-kitchen'),
      size: dense ? MadarButtonSize.compact : MadarButtonSize.regular,
      label: dense
          ? '${orderWord(bridge, 'sell.kitchen_cart_button')} ($lineCount)'
          : '${orderWord(bridge, 'sell.kitchen_cart_button')} '
                '($lineCount $itemsWord)',
      glyph: MadarGlyph.printer,
      variant: MadarButtonVariant.secondary,
      onTap: () => unawaited(
        _printWholeCartToKitchen(
          context,
          ref,
          tableId: tableId,
          tableLabel: tableLabel,
          ticketRef: ticketRef,
        ),
      ),
      onLongPress: () => unawaited(
        _previewWholeCartKitchenChit(
          context,
          ref,
          tableId: tableId,
          tableLabel: tableLabel,
          ticketRef: ticketRef,
        ),
      ),
    );

    return ColoredBox(
      color: colors.bg,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: tight ? viewport * 0.52 : double.infinity,
        ),
        child: SingleChildScrollView(
          physics: tight
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: EdgeInsetsDirectional.all(dense ? Space.md : Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: dense ? Space.xs : Space.sm,
              children: [
                const MadarHairline(light: true),
                if (dense)
                  // The note beside the button as a tile: a chip's words
                  // would not fit the row at 300 wide, and its state (set or
                  // not) is the tint. The sheet it opens shows the text.
                  Row(
                    spacing: Space.sm,
                    children: [
                      Expanded(child: kitchenButton),
                      MadarGlyphTile(
                        key: const ValueKey('cart-kitchen-note'),
                        glyph: MadarGlyph.note,
                        tint: hasKitchenNote ? colors.accent : null,
                        background: hasKitchenNote ? colors.accentBg : null,
                        semanticLabel: orderWord(
                          bridge,
                          'sell.kitchen_cart_note_field',
                        ),
                        onTap: () => unawaited(
                          editCartKitchenNote(context, ref, tableId),
                        ),
                      ),
                    ],
                  )
                else ...[
                  kitchenButton,
                  // Its own note sits right under it, never crammed into the
                  // same row — that is what overflowed at a narrow width.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: MadarChip(
                      key: const ValueKey('cart-kitchen-note'),
                      label: orderWord(bridge, 'sell.kitchen_cart_note_field'),
                      glyph: MadarGlyph.note,
                      selected: hasKitchenNote,
                      onTap: () =>
                          unawaited(editCartKitchenNote(context, ref, tableId)),
                    ),
                  ),
                ],
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
                                  tableId,
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
                  if (cta.needsTill) SellNoTillNotice(text: cta.reason!),
                  // The discount the Charge drawer applied stays on the cart after
                  // the drawer closes; say so here, not only inside Charge.
                  if (totals.discountMinor > 0)
                    _FigureRow(
                      label: orderWord(bridge, 'sell.discount_on_cart'),
                      minor: -totals.discountMinor,
                      currency: currency,
                      muted: true,
                    ),
                  if (canPark && narrow)
                    MadarButton(
                      key: const ValueKey('cart-park'),
                      label: bridge.tr(key: 'drafts.hold'),
                      glyph: MadarGlyph.bag,
                      variant: MadarButtonVariant.secondary,
                      size: MadarButtonSize.compact,
                      onTap: onHold,
                    ),
                  Row(
                    spacing: Space.sm,
                    children: [
                      // Park, right beside Charge — not a tap buried in the ⋯
                      // menu. The owner's report was that parking read as a dead
                      // end; a control nobody finds might as well not exist. In
                      // a narrow column it takes its own row above (see
                      // [narrow]), so Charge keeps room for its word AND figure.
                      if (canPark && !narrow)
                        MadarGlyphTile(
                          key: const ValueKey('cart-park'),
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
                          reason: cta.needsTill ? null : cta.reason,
                          loading: isBusy,
                          onTap: onTerminal,
                        ),
                      ),
                    ],
                  ),
                ],
                // When this order was started — the held chips show its number,
                // so the time lives here, in the branch's clock.
                if (startedAt != null && startedAt.isNotEmpty)
                  Text(
                    '${orderWord(bridge, 'sell.cart_started_at')} '
                    '${bridge.formatTime(rfc3339: startedAt, style: TimeStyle.time)}',
                    textAlign: TextAlign.center,
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Bill so far" for (ticket subtotal, round subtotal) — the core adds them.
/// The round's figure is in the key only so a changed round re-asks.
final FutureProviderFamily<int, (String?, int, int)> _billSoFarProvider =
    FutureProvider.autoDispose.family<int, (String?, int, int)>(
      (ref, key) => ref
          .read(bridgeProvider)
          .cartBillSoFarMinor(tableId: key.$1, ticketSubtotalMinor: key.$2),
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
          child: MadarClippedText(
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
  const SellBar({
    required this.tableId,
    required this.onOpen,
    required this.onTerminal,
    super.key,
  });

  /// The cart this bar is for (null = takeaway).
  final String? tableId;

  final VoidCallback onOpen;
  final VoidCallback onTerminal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final state = ref.watch(orderProvider);
    final cart = ref.watch(cartProvider(tableId));
    final cta = sellCtaFor(
      state,
      cart,
      bridge,
      tillOpen: ref.watch(shellProvider.select((s) => s.tillOpen)),
    );
    if (cta.itemCount <= 0) return const SizedBox.shrink();
    final isBusy = cart.isBusy;
    final figure = cta.sendsToKitchen
        ? cart.totals.subtotalMinor
        : cta.amountMinor;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.sm,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
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
            if (cta.needsTill)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
                child: SellNoTillNotice(text: cta.reason!),
              )
            else if (!cta.enabled && cta.reason != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.xs),
                child: MadarClippedText(
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
                                child: MadarClippedText(
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

/// "No till is open" with its way on — the Open till button — wherever the
/// cart's Charge is greyed for that reason (the column's footer, the phone's
/// bar).
class SellNoTillNotice extends ConsumerWidget {
  const SellNoTillNotice({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return NoticeBanner(
      text: text,
      icon: 'lock',
      onTap: () => unawaited(openTillFromSell(context, ref)),
      trailing: BannerActionPill(label: orderWord(bridge, 'sell.open_till')),
    );
  }
}

/// The cart's chips under the parked strip: the order's note on every cart,
/// and on the counter its customer and discount. Unset, each says what it
/// adds; set, it reads the name, the discount or the note and is lit.
class _CartSummary extends ConsumerWidget {
  const _CartSummary({
    required this.tableId,
    required this.counter,
    required this.lineCount,
  });

  final String? tableId;

  final bool counter;

  /// Re-asks the core for the note whenever the cart changes shape.
  final int lineCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final name = ref.watch(cartProvider(tableId).select((c) => c.name));
    final discountMinor = ref.watch(
      cartProvider(tableId).select((c) => c.totals.discountMinor),
    );
    final discount = ref
        .watch(_cartDiscountLabelProvider((tableId, discountMinor)))
        .value;
    final note = ref.watch(_cartNoteProvider((tableId, lineCount))).value;
    return ColoredBox(
      color: colors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            // Wraps rather than scrolling: a chip cut off at the cart's edge
            // reads as broken, and a long note must still show it is set.
            // Each chip is capped at the cart's width so a long note
            // ellipsizes inside its chip instead of running past the edge.
            child: LayoutBuilder(
              builder: (context, c) {
                final cap = BoxConstraints(maxWidth: c.maxWidth);
                return Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    if (counter) ...[
                      ConstrainedBox(
                        constraints: cap,
                        child: MadarChip(
                          label: name ?? orderWord(bridge, 'sell.customer'),
                          glyph: MadarGlyph.user,
                          selected: name != null,
                          onTap: () => unawaited(
                            editLiveOrderName(context, ref, tableId),
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: cap,
                        child: MadarChip(
                          label: discount ?? orderWord(bridge, 'sell.discount'),
                          glyph: MadarGlyph.percent,
                          selected: discount != null,
                          onTap: () => unawaited(() async {
                            final changed = await showCartDiscountPicker(
                              context,
                              ref,
                              tableId: tableId,
                            );
                            if (changed) {
                              await ref
                                  .read(cartProvider(tableId).notifier)
                                  .load();
                            }
                          }()),
                        ),
                      ),
                    ],
                    ConstrainedBox(
                      constraints: cap,
                      child: MadarChip(
                        label: note ?? orderWord(bridge, 'sell.note'),
                        glyph: MadarGlyph.note,
                        selected: note != null,
                        onTap: () =>
                            unawaited(editCartNote(context, ref, tableId)),
                      ),
                    ),
                    // The whole-cart kitchen print and its note live in the
                    // footer, beside Charge/Fire — a cart-level action, kept
                    // apart from every row's own small kitchen button.
                  ],
                );
              },
            ),
          ),
          const MadarHairline(light: true),
        ],
      ),
    );
  }
}

/// The cart's order note, from the core.
final FutureProviderFamily<String?, (String?, int)> _cartNoteProvider =
    FutureProvider.autoDispose.family<String?, (String?, int)>(
      (ref, key) => ref.read(bridgeProvider).cartNote(tableId: key.$1),
    );

/// Type (or clear) the note for the whole order. The core keeps it with the
/// cart and carries it on the checkout and the fired ticket.
Future<void> editCartNote(
  BuildContext context,
  WidgetRef ref,
  String? tableId,
) async {
  final bridge = ref.read(bridgeProvider);
  final controller = TextEditingController(
    text: await bridge.cartNote(tableId: tableId) ?? '',
  );
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
            kind: MadarFieldKind.note,
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
  await bridge.cartSetNote(
    tableId: tableId,
    note: saved.trim().isEmpty ? null : saved.trim(),
  );
  ref.invalidate(_cartNoteProvider);
}

/// Print the WHOLE cart to the kitchen right now (short press): every line's
/// chit, one after another, plus the cart-level kitchen note. An EXTRA copy
/// for the kitchen — checkout/fire printing is unchanged, nothing is marked
/// sent. On success, clears the cart-level note and every line's own note.
Future<void> _printWholeCartToKitchen(
  BuildContext context,
  WidgetRef ref, {
  required String? tableId,
  String? tableLabel,
  String? ticketRef,
}) async {
  final bridge = ref.read(bridgeProvider);
  PrintState result;
  try {
    final chit = await buildCartKitchenChit(
      bridge,
      tableId: tableId,
      tableLabel: tableLabel,
      ticketRef: ticketRef,
    );
    result = await printCartKitchenChit(ref.read(printerServiceProvider), chit);
    if (result == PrintState.printed) {
      await bridge.cartClearAllKitchenNotes(tableId: tableId);
      ref.invalidate(_cartKitchenNoteProvider);
      await ref.read(cartProvider(tableId).notifier).load();
    }
  } on Object {
    result = PrintState.failed;
  }
  if (!context.mounted) return;
  sayChitPrint(ref.read(appToastProvider.notifier), bridge, result);
}

/// Long press: build the whole-cart chit in the core and show it on the
/// print preview sheet first; the sheet's Print sends it (and clears notes
/// on success, same as the short press).
Future<void> _previewWholeCartKitchenChit(
  BuildContext context,
  WidgetRef ref, {
  required String? tableId,
  String? tableLabel,
  String? ticketRef,
}) async {
  final bridge = ref.read(bridgeProvider);
  final CartKitchenChit chit;
  try {
    chit = await buildCartKitchenChit(
      bridge,
      tableId: tableId,
      tableLabel: tableLabel,
      ticketRef: ticketRef,
    );
  } on Object {
    sayChitPrint(
      ref.read(appToastProvider.notifier),
      bridge,
      PrintState.failed,
    );
    return;
  }
  if (!context.mounted) return;
  await showMadarSheet<void>(
    context,
    size: SheetSize.large,
    builder: (_) => CartKitchenChitSheet(chit: chit, tableId: tableId),
  );
  // The preview sheet's own notifier cleared notes on print; refresh what
  // this screen shows either way.
  ref.invalidate(_cartKitchenNoteProvider);
  await ref.read(cartProvider(tableId).notifier).load();
}

/// The cart's KITCHEN-ONLY note, from the core — local, never checkout,
/// never the receipt, cleared once the whole-cart chit prints.
final FutureProviderFamily<String?, (String?, int)> _cartKitchenNoteProvider =
    FutureProvider.autoDispose.family<String?, (String?, int)>(
      (ref, key) => ref.read(bridgeProvider).cartKitchenNote(tableId: key.$1),
    );

/// Type (or clear) the CART-level kitchen note — the whole-cart print's own
/// note. Never rides the order note, never the receipt, and is cleared the
/// moment the whole-cart chit actually prints.
Future<void> editCartKitchenNote(
  BuildContext context,
  WidgetRef ref,
  String? tableId,
) async {
  final bridge = ref.read(bridgeProvider);
  final controller = TextEditingController(
    text: await bridge.cartKitchenNote(tableId: tableId) ?? '',
  );
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
          Text(
            orderWord(bridge, 'sell.cart_kitchen_note_title'),
            style: MadarType.h2,
          ),
          MadarField(
            controller: controller,
            placeholder: orderWord(bridge, 'sell.cart_kitchen_note_hint'),
            kind: MadarFieldKind.note,
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
  // NOT disposed here: `Navigator.pop` completes this future before the
  // sheet's own close animation is done, and that animation still rebuilds
  // the field for a few more frames — disposing now throws "used after
  // being disposed" mid-close. The controller is short-lived and ownerless
  // once the sheet is gone, so it is left for the GC rather than raced.
  if (saved == null) return;
  await bridge.cartSetKitchenNote(
    tableId: tableId,
    note: saved.trim().isEmpty ? null : saved.trim(),
  );
  ref.invalidate(_cartKitchenNoteProvider);
}

/// Type (or clear) ONE cart line's KITCHEN-ONLY note. Local, kitchen-chit
/// only; cleared the moment that line's chit actually prints.
Future<void> editLineKitchenNote(
  BuildContext context,
  WidgetRef ref, {
  required String? tableId,
  required CartLineView line,
}) async {
  final bridge = ref.read(bridgeProvider);
  final controller = TextEditingController(text: line.kitchenNote ?? '');
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
          Text(
            orderWord(bridge, 'sell.kitchen_note_title'),
            style: MadarType.h2,
          ),
          MadarField(
            controller: controller,
            placeholder: orderWord(bridge, 'sell.kitchen_note_hint'),
            kind: MadarFieldKind.note,
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
  // See `editCartKitchenNote`'s note: not disposed here on purpose.
  if (saved == null) return;
  await bridge.cartSetLineKitchenNote(
    tableId: tableId,
    lineKey: line.key,
    note: saved.trim().isEmpty ? null : saved.trim(),
  );
  await ref.read(cartProvider(tableId).notifier).load();
}

/// The applied cart discount's label, or null — re-asked whenever the cart's
/// discount figure moves.
final FutureProviderFamily<String?, (String?, int)> _cartDiscountLabelProvider =
    FutureProvider.autoDispose.family<String?, (String?, int)>((
      ref,
      key,
    ) async {
      if (key.$2 <= 0) return null;
      final bridge = ref.read(bridgeProvider);
      final v = await bridge.cartDiscount(tableId: key.$1);
      if (v.kind.isEmpty) return null;
      final all = await bridge.listDiscounts();
      return cartDiscountLabel(bridge, v, all, discountLabel);
    });

/// One item of a combo line, indented under it: `2× Latte · Large +10.00`,
/// then its add-ons.
class CartPartRow extends StatelessWidget {
  const CartPartRow({required this.part, required this.currency, super.key});

  final CartPartView part;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    String money(int minor) => Money.format(
      minor,
      currency: currency,
      locale: MadarFormat.localeOf(context),
    );
    final head = [
      if (part.qty > 1) '${part.qty}× ${part.itemName}' else part.itemName,
      if (part.sizeLabel case final s? when s.isNotEmpty) s,
    ].join(' · ');
    final extras = [
      for (final a in part.addons)
        if (a.qty > 1) '${a.name} ×${a.qty}' else a.name,
      for (final o in part.optionals) o.name,
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: Space.md, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MadarClippedText(
            part.surchargeMinor > 0
                ? '$head  +${money(part.surchargeMinor)}'
                : head,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
          if (extras.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.md),
              child: MadarClippedText(
                extras.map((e) => '+ $e').join('  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(color: colors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// "This order qualifies for 2 bites for 90 · Save 20.00 “Apply”" — a deal
/// the core found for this cart. Never applied until the teller taps (C8).
class DealSuggestionBanner extends ConsumerWidget {
  const DealSuggestionBanner({
    required this.suggestion,
    required this.currency,
    required this.onApply,
    super.key,
  });

  final DealSuggestion suggestion;
  final String currency;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final save = bridge
        .tr(key: 'deal.save')
        .replaceAll(
          '{amount}',
          Money.format(
            suggestion.savingMinor,
            currency: currency,
            locale: MadarFormat.localeOf(context),
          ),
        );
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: colors.successBg,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: colors.success),
        ),
        child: Row(
          spacing: Space.md,
          children: [
            MadarGlyphIcon(
              MadarGlyph.check,
              size: IconSize.sm,
              color: colors.success,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MadarClippedText(
                    bridge
                        .tr(key: 'deal.qualifies')
                        .replaceAll('{deal}', suggestion.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.title.copyWith(color: colors.textPrimary),
                  ),
                  MadarClippedText(
                    suggestion.times > 1
                        ? '$save · ${suggestion.timesLabel}'
                        : save,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(color: colors.success),
                  ),
                ],
              ),
            ),
            MadarButton(
              key: ValueKey('deal-apply-${suggestion.dealId}'),
              label: bridge.tr(key: 'deal.apply'),
              size: MadarButtonSize.compact,
              onTap: onApply,
            ),
          ],
        ),
      ),
    );
  }
}

/// An applied deal: its name, what it takes off, and the way to take it off.
class _AppliedDealRow extends ConsumerWidget {
  const _AppliedDealRow({
    required this.deal,
    required this.currency,
    required this.onRemove,
    super.key,
  });

  final AppliedDealView deal;
  final String currency;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
      child: Row(
        spacing: Space.sm,
        children: [
          MadarTag(
            label: bridge.tr(key: 'deal.badge'),
            tone: MadarTone.success,
          ),
          Expanded(
            child: MadarClippedText(
              bridge.tr(key: 'deal.applied').replaceAll('{deal}', deal.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.bodySm.copyWith(color: colors.textPrimary),
            ),
          ),
          MoneyText(
            -deal.discountMinor,
            currency: currency,
            color: colors.success,
          ),
          MadarGlyphTile(
            key: ValueKey('deal-remove-${deal.id}'),
            glyph: MadarGlyph.close,
            semanticLabel: bridge.tr(key: 'deal.remove'),
            onTap: onRemove,
          ),
        ],
      ),
    );
  }
}
