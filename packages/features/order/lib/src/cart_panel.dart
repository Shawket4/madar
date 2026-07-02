import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/held_orders_strip.dart';
import 'package:feature_order/src/order_controller.dart';
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The cart — wide column beside the grid, or the phone drawer's content.
/// Header (title · count · Clear · close), the held-orders strip, the line
/// list (with the selected ticket's fired items above the editable new
/// round in waiter mode), and the totals + hold + checkout footer.
class CartPanel extends StatelessWidget {
  const CartPanel({
    required this.model,
    required this.checkoutLabel,
    required this.checkoutIcon,
    required this.checkoutEnabled,
    required this.onCheckout,
    required this.onEditLine,
    this.checkoutTooltip,
    this.onClose,
    super.key,
  });

  final OrderController model;
  final String checkoutLabel;
  final String checkoutIcon;
  final bool checkoutEnabled;

  /// Disabled-checkout hint (the M5 tender-drawer milestone note).
  final String? checkoutTooltip;
  final VoidCallback onCheckout;
  final ValueChanged<CartLineView> onEditLine;

  /// Phone drawer close (null on the wide fixed column).
  final VoidCallback? onClose;

  Future<void> _confirmVoid(BuildContext context, TicketView ticket) async {
    final result = await showMadarSheet<VoidTicketResult>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => WaiterVoidSheet(model: model, ticket: ticket),
    );
    if (result == null) return;
    await model.voidTicket(ticket.id, result.reason);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final activeTicket = model.activeTicket;
    final hasLines = model.cartLines.isNotEmpty;

    final footer = _CartFooter(
      model: model,
      checkoutLabel: checkoutLabel,
      checkoutIcon: checkoutIcon,
      checkoutEnabled: checkoutEnabled,
      checkoutTooltip: checkoutTooltip,
      onCheckout: onCheckout,
      onHold: () => unawaited(model.holdCart()),
    );

    return ColoredBox(
      color: colors.bg,
      child: Column(
        children: [
          _CartHeader(model: model, onClose: onClose),
          Container(height: 1, color: colors.border),
          // Held-order strip — one shared component. The teller flips between
          // parked carts (switching parks the current one first); a waiter
          // gets a "New" tab + a tab per open ticket (round targets).
          if (model.isWaiter && model.openTickets.isNotEmpty)
            HeldOrdersStrip(
              tabs: _waiterTicketTabs(model),
              newLabel: model.tr('waiter.new_order'),
            )
          else if (!model.isWaiter && model.drafts.isNotEmpty)
            HeldOrdersStrip(
              tabs: _tellerHeldTabs(model),
              newLabel: model.tr('waiter.new_order'),
            ),
          if (activeTicket != null) ...[
            // A ticket is selected — its fired items (read-only) ride above
            // the editable new round; everything scrolls together.
            Expanded(
              child: ListView(
                padding: const EdgeInsetsDirectional.all(Space.lg),
                children: [
                  _TicketHeader(
                    model: model,
                    ticket: activeTicket,
                    onVoid: () =>
                        unawaited(_confirmVoid(context, activeTicket)),
                  ),
                  const SizedBox(height: Space.sm),
                  OrderLinesCard(
                    lines: activeTicket.lines,
                    currency: model.currency,
                    itemsLabel: model.tr('order.items'),
                    emptyLabel: model.tr('order.cart_empty'),
                  ),
                  const SizedBox(height: Space.sm),
                  Container(height: 1, color: colors.border),
                  const SizedBox(height: Space.sm),
                  Text(
                    model.tr('waiter.new_round'),
                    style: MadarType.title.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  if (!hasLines)
                    Text(
                      model.tr('order.cart_empty'),
                      style: MadarType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    )
                  else
                    ..._cartLineRows(),
                ],
              ),
            ),
            // "Add round" stays reachable only when the new round has lines.
            if (hasLines) footer,
          ] else if (!hasLines)
            Expanded(
              child: Center(
                child: Text(
                  model.tr('order.cart_empty'),
                  style: MadarType.body.copyWith(color: colors.textSecondary),
                ),
              ),
            )
          else ...[
            Expanded(
              child: ListView(
                padding: const EdgeInsetsDirectional.all(Space.lg),
                children: _cartLineRows(),
              ),
            ),
            footer,
          ],
        ],
      ),
    );
  }

  List<Widget> _cartLineRows() => [
    for (final line in model.cartLines)
      Padding(
        key: ValueKey('cart-${line.key}'),
        padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
        child: CartLineRow(
          model: model,
          line: line,
          // Bundles aren't re-editable in place (reconfigure by removing +
          // re-adding); only plain lines reopen the customization sheet.
          onEdit: line.bundleId == null ? () => onEditLine(line) : null,
        ),
      ),
  ];
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.model, this.onClose});

  final OrderController model;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final onClose = this.onClose;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: 14,
      ),
      child: Row(
        children: [
          Text(
            model.tr('order.cart'),
            style: MadarType.h3.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          if (model.cartTotals.itemCount > 0) ...[
            const SizedBox(width: Space.sm),
            StatusChip(
              label: '${model.cartTotals.itemCount}',
              tone: ChipTone.accent,
            ),
          ],
          const Spacer(),
          if (model.cartLines.isNotEmpty)
            GestureDetector(
              onTap: () => unawaited(model.clearCart()),
              behavior: HitTestBehavior.opaque,
              child: Text(
                model.tr('order.clear'),
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.danger,
                ),
              ),
            ),
          if (onClose != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.sm),
              child: GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: MadarIcon('xmark', tint: colors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Waiter: selected-ticket header (on-ticket count + void) ────────────────────

class _TicketHeader extends StatelessWidget {
  const _TicketHeader({
    required this.model,
    required this.ticket,
    required this.onVoid,
  });

  final OrderController model;
  final TicketView ticket;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      children: [
        Flexible(
          child: Text(
            model.tr('waiter.on_ticket'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.title.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        StatusChip(label: '${ticket.lines.length}'),
        const Spacer(),
        TactileScale(
          onTap: () {
            MadarHaptics.warning();
            onVoid();
          },
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: colors.dangerBg,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MadarIcon('trash', tint: colors.danger, size: IconSize.sm),
                const SizedBox(width: Space.xs),
                Text(
                  model.tr('void.title'),
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.danger,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Held-order tab builders ────────────────────────────────────────────────────

/// Teller strip: a chip per parked draft PLUS, when the cart is non-empty,
/// the live cart's own chip (the selected one).
List<HeldOrderTab> _tellerHeldTabs(OrderController model) => [
  for (final draft in model.drafts)
    HeldOrderTab(
      key: draft.id,
      sortKey: draft.createdAt,
      count: draft.itemCount,
      selected: false,
      onTap: () => unawaited(model.switchToHeldOrder(draft.id)),
      onClose: () => unawaited(model.discardDraft(draft.id)),
    ),
  if (model.cartLines.isNotEmpty)
    HeldOrderTab(
      key: '__current__',
      sortKey: model.cartStartedAtIso ?? nowIso(),
      count: model.cartTotals.itemCount,
      selected: true,
      onTap: () {},
    ),
];

/// Waiter strip: a chip per open ticket (creation time = openedAt) PLUS a
/// "New" tab (sortKey = now, so it sits at the newest edge). Selecting a
/// ticket only sets the round target; the cart stays the new round.
List<HeldOrderTab> _waiterTicketTabs(OrderController model) => [
  HeldOrderTab(
    key: '__new__',
    sortKey: nowIso(),
    glyph: 'plus',
    count: model.cartTotals.itemCount,
    selected: model.activeTicketId == null,
    onTap: () => model.selectTicket(null),
  ),
  for (final ticket in model.openTickets)
    HeldOrderTab(
      key: ticket.id,
      sortKey: ticket.openedAt,
      count: ticket.lines.length,
      selected: model.activeTicketId == ticket.id,
      onTap: () => model.selectTicket(ticket.id),
    ),
];

// ── Cart line row ──────────────────────────────────────────────────────────────

/// One editable cart line: swipe-to-delete (with Undo), tap-to-edit (plain
/// lines), size/addon/optional pills, notes, line total, and a qty stepper
/// whose minus becomes the remove affordance at qty 1.
class CartLineRow extends StatelessWidget {
  const CartLineRow({
    required this.model,
    required this.line,
    this.onEdit,
    super.key,
  });

  final OrderController model;
  final CartLineView line;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Dismissible(
      key: ValueKey('dismiss-${line.key}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => unawaited(model.swipeRemoveCartLine(line)),
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.xl),
        decoration: BoxDecoration(
          color: colors.danger,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: MadarIcon(
          'trash',
          tint: colors.textOnAccent,
          size: IconSize.lg,
        ),
      ),
      child: _CartLineBody(model: model, line: line, onEdit: onEdit),
    );
  }
}

class _CartLineBody extends StatelessWidget {
  const _CartLineBody({required this.model, required this.line, this.onEdit});

  final OrderController model;
  final CartLineView line;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isBundle = line.bundleId != null;
    final hasModifiers =
        line.sizeLabel != null ||
        line.addons.isNotEmpty ||
        line.optionals.isNotEmpty;
    final notes = line.notes;
    final onEdit = this.onEdit;

    Widget details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (isBundle) ...[
              const SizedBox(width: 6),
              StatusChip(
                label: model.tr('order.combos'),
                tone: ChipTone.accent,
              ),
            ],
          ],
        ),
        if (isBundle)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Space.xs),
            child: _BundleBreakdown(line: line),
          )
        else if (hasModifiers)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Space.xs),
            child: Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                if (line.sizeLabel case final size?)
                  ModifierPill(
                    text: size,
                    fg: colors.textSecondary,
                    bg: colors.surfaceAlt,
                  ),
                for (final addon in line.addons)
                  ModifierPill(
                    text: addon.qty > 1
                        ? '${addon.name} ×${addon.qty}'
                        : addon.name,
                    fg: colors.navy,
                    bg: colors.navyBg,
                  ),
                for (final optional in line.optionals)
                  ModifierPill(
                    text: optional.name,
                    fg: colors.warning,
                    bg: colors.warningBg,
                  ),
              ],
            ),
          ),
        if (notes != null && notes.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Space.xs),
            child: Text(
              '“$notes”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MadarType.labelSm.copyWith(
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: colors.textMuted,
              ),
            ),
          ),
        const SizedBox(height: Space.xs),
        MoneyText(
          line.lineTotalMinor,
          currency: model.currency,
          style: MadarType.money.copyWith(fontSize: 13),
          color: colors.textPrimary,
        ),
      ],
    );
    if (onEdit != null) {
      details = GestureDetector(
        onTap: onEdit,
        behavior: HitTestBehavior.opaque,
        child: details,
      );
    }

    return Container(
      padding: const EdgeInsetsDirectional.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(colors, dark: dark),
      ),
      child: Row(
        children: [
          Expanded(child: details),
          const SizedBox(width: Space.md),
          QtyStepper(
            qty: line.qty,
            // The minus button removes the line at qty 1.
            onDec: () => unawaited(model.setCartQty(line.key, line.qty - 1)),
            onInc: () => unawaited(model.setCartQty(line.key, line.qty + 1)),
          ),
        ],
      ),
    );
  }
}

/// A bundle line lists its components (qty × name) with each component's
/// chosen addons/optionals as sub-pills.
class _BundleBreakdown extends StatelessWidget {
  const _BundleBreakdown({required this.line});

  final CartLineView line;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final comp in line.bundleComponents)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${comp.qty}× ${comp.name}',
                  style: MadarType.labelSm.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
                if (comp.addons.isNotEmpty || comp.optionals.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 2),
                    child: Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        for (final addon in comp.addons)
                          ModifierPill(
                            text: addon.qty > 1
                                ? '${addon.name} ×${addon.qty}'
                                : addon.name,
                            fg: colors.navy,
                            bg: colors.navyBg,
                          ),
                        for (final optional in comp.optionals)
                          ModifierPill(
                            text: optional.name,
                            fg: colors.warning,
                            bg: colors.warningBg,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A compact modifier chip in the cart row (size / addon / optional).
class ModifierPill extends StatelessWidget {
  const ModifierPill({
    required this.text,
    required this.fg,
    required this.bg,
    super.key,
  });

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.xs / 2),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 7,
          vertical: 2,
        ),
        child: Text(
          text,
          style: MadarType.labelSm.copyWith(fontSize: 10, color: fg),
        ),
      ),
    );
  }
}

/// − qty + stepper (the natives' QtyStepper at [Metrics.stepper]); minus
/// shows a trash glyph at qty 1 (the remove affordance).
class QtyStepper extends StatelessWidget {
  const QtyStepper({
    required this.qty,
    required this.onDec,
    required this.onInc,
    super.key,
  });

  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StepButton(
          glyph: qty <= 1 ? 'trash' : 'minus',
          danger: qty <= 1,
          onTap: onDec,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 24 + Space.sm * 2),
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: MadarType.title.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        StepButton(glyph: 'plus', onTap: onInc),
      ],
    );
  }
}

/// A circular stepper button (natives: 30.dp, [MotionSpec.pressScaleKey]-deep
/// press).
class StepButton extends StatelessWidget {
  const StepButton({
    required this.glyph,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final String glyph;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      scale: 0.9,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        width: Metrics.stepper,
        height: Metrics.stepper,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
        ),
        child: MadarIcon(
          glyph,
          tint: danger ? colors.danger : colors.textPrimary,
          size: IconSize.sm,
        ),
      ),
    );
  }
}

// ── Footer (totals + hold + checkout) ──────────────────────────────────────────

class _CartFooter extends StatelessWidget {
  const _CartFooter({
    required this.model,
    required this.checkoutLabel,
    required this.checkoutIcon,
    required this.checkoutEnabled,
    required this.checkoutTooltip,
    required this.onCheckout,
    required this.onHold,
  });

  final OrderController model;
  final String checkoutLabel;
  final String checkoutIcon;
  final bool checkoutEnabled;
  final String? checkoutTooltip;
  final VoidCallback onCheckout;
  final VoidCallback onHold;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final totals = model.cartTotals;
    final currency = model.currency;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Column(
          children: [
            Container(height: 1, color: colors.border),
            const SizedBox(height: Space.sm),
            _TotalRow(
              label: model.tr('order.subtotal'),
              value: Money.format(totals.subtotalMinor, currency: currency),
            ),
            if (totals.discountMinor > 0) ...[
              const SizedBox(height: Space.sm),
              _TotalRow(
                label: model.tr('order.discount'),
                value:
                    '−${Money.format(totals.discountMinor, currency: currency)}',
                color: colors.success,
              ),
            ],
            const SizedBox(height: Space.sm),
            _TotalRow(
              label: model.tr('order.tax'),
              value: Money.format(totals.taxMinor, currency: currency),
            ),
            const SizedBox(height: Space.sm),
            GrandTotalBlock(
              label: model.tr('order.total'),
              totalMinor: totals.totalMinor,
              currency: currency,
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                // Park the cart (held order) — a square accent-tinted tray.
                TactileScale(
                  onTap: () {
                    MadarHaptics.impact();
                    onHold();
                  },
                  child: Container(
                    width: kActionButtonHeight,
                    height: kActionButtonHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accentBg,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: MadarIcon(
                      'tray.and.arrow.down',
                      tint: colors.accent,
                      size: IconSize.lg,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: ActionButton(
                    label: checkoutLabel,
                    icon: checkoutIcon,
                    enabled: checkoutEnabled,
                    loading: model.isBusy,
                    tooltip: checkoutTooltip,
                    onTap: onCheckout,
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

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = color ?? colors.textSecondary;
    return Row(
      children: [
        Text(
          label,
          style: MadarType.bodySm.copyWith(
            fontWeight: FontWeight.w500,
            color: fg,
          ),
        ),
        const Spacer(),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: MadarType.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: fg,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Prominent tinted-teal total block — the figure tellers look at. The
/// amount cross-fades on change (the natives' Crossfade).
class GrandTotalBlock extends StatelessWidget {
  const GrandTotalBlock({
    required this.label,
    required this.totalMinor,
    required this.currency,
    super.key,
  });

  final String label;
  final int totalMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final formatted = Money.format(totalMinor, currency: currency);
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.md),
      decoration: BoxDecoration(
        color: colors.accentBg,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: MadarType.body.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.accent,
            ),
          ),
          const Spacer(),
          AnimatedSwitcher(
            duration: MotionSpec.standardDuration,
            switchInCurve: MotionSpec.standardCurve,
            switchOutCurve: MotionSpec.standardCurve,
            child: Text(
              formatted,
              key: ValueKey(formatted),
              textDirection: TextDirection.ltr,
              style: MadarType.moneyLg.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Phone bottom cart bar ──────────────────────────────────────────────────────

/// CartBar height (natives: 56.dp).
const double _cartBarHeight = 56;

/// Sticky accent bar on narrow layouts — item count · "View cart" · total.
/// Hidden while the cart is empty.
class CartBar extends StatelessWidget {
  const CartBar({required this.model, required this.onOpen, super.key});

  final OrderController model;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final totals = model.cartTotals;
    if (totals.itemCount <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.md),
      child: TactileScale(
        scale: 0.985,
        onTap: () {
          MadarHaptics.impact();
          onOpen();
        },
        child: Container(
          height: _cartBarHeight,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(
            color: colors.accent,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              // Item count is secondary: it flexes + ellipsizes so the CTA
              // and total always stay on-screen.
              Expanded(
                child: Text(
                  '${totals.itemCount} ${model.tr('order.items')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textOnAccent.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Text(
                model.tr('order.view_cart'),
                maxLines: 1,
                style: MadarType.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textOnAccent,
                ),
              ),
              const SizedBox(width: Space.md),
              MoneyText(
                totals.totalMinor,
                currency: model.currency,
                style: MadarType.money.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
                color: colors.textOnAccent,
              ),
              const SizedBox(width: Space.md),
              MadarIcon(
                'chevron.up',
                tint: colors.textOnAccent,
                size: IconSize.sm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Read-only ticket lines (the natives' OrderLinesCard) ───────────────────────

/// Line-items card — one row per fired ticket line: qty badge + name, size +
/// modifiers under it, per-line price trailing. Voided lines strike through.
class OrderLinesCard extends StatelessWidget {
  const OrderLinesCard({
    required this.lines,
    required this.currency,
    required this.itemsLabel,
    required this.emptyLabel,
    super.key,
  });

  final List<TicketLineView> lines;
  final String currency;
  final String itemsLabel;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(colors, dark: dark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            itemsLabel.toUpperCase(),
            style: MadarType.label.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
              letterSpacing: MadarType.tracking,
            ),
          ),
          const SizedBox(height: Space.md),
          if (lines.isEmpty)
            Text(
              emptyLabel,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            )
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: Space.md),
                child: _OrderLineRow(line: line, currency: currency),
              ),
        ],
      ),
    );
  }
}

class _OrderLineRow extends StatelessWidget {
  const _OrderLineRow({required this.line, required this.currency});

  final TicketLineView line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final strike = line.voided ? TextDecoration.lineThrough : null;
    final nameColor = line.voided ? colors.textMuted : colors.textPrimary;
    final size = line.sizeLabel;
    final detail = [
      if (size != null && size.isNotEmpty) size,
      ...line.modifiers,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Qty badge — teal pill so the count reads at a glance.
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: colors.accentBg,
            borderRadius: BorderRadius.circular(Radii.xs / 2),
          ),
          child: Text(
            '${line.qty}×',
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.accent,
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.name,
                style: MadarType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: nameColor,
                  decoration: strike,
                ),
              ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 2),
                  child: Text(
                    detail.join(' · '),
                    style: MadarType.label.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                      decoration: strike,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: Space.sm),
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 2),
          child: MoneyText(
            line.lineTotalMinor,
            currency: currency,
            color: nameColor,
          ),
        ),
      ],
    );
  }
}
