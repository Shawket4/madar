/// The cashier "Open tickets" settle surface — a pixel-and-behavior port
/// of the Kotlin WaiterScreen.kt (TicketsSettleBody): the live open/ready
/// ticket board (reloaded on the realtime ticket tick), the status-tinted
/// settle card, the read-only order-details overlay (voided lines strike
/// through), the void-with-reason sheet, and Settle through the ONE shared
/// [CheckoutDrawer] feeding `settleTicket` — no mirrored settle UI.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/cart_panel.dart' show OrderLinesCard;
import 'package:feature_order/src/order_controller.dart';
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (WaiterScreen.kt / OrderDetailsSheet.kt) that fall between
// the 4-pt Space steps — kept verbatim so the Flutter chrome measures
// identically.

/// Ticket card width cap in the settle list (natives: widthIn(max = 620.dp)).
const double _cardMaxWidth = 620;

/// Order-details overlay width cap (natives: maxWidth = 560.dp).
const double _detailsMaxWidth = 560;

/// Card header strip height (natives: 56.dp).
const double _headerStripHeight = 56;

/// Status dot inside the header strip (natives: 8.dp).
const double _statusDot = 8;

/// Ticket ref in the header strip (natives: 19.sp Black).
const double _refSize = 19;

/// Header-strip money (natives: 16.sp Black) and pill v-inset (7.dp).
const double _cardMoneySize = 16;
const double _moneyPillVPad = 7;

/// Leading person tile (natives: 34.dp square, Radii.sm).
const double _personTile = 34;

/// Waiter/items meta line (natives: 11.sp).
const double _metaSize = 11;

/// Settle-header per-line money (natives: 13.sp SemiBold).
const double _headerLineMoneySize = 13;

/// Context-chip vertical inset (natives: 6.dp) and label size (12.sp).
const double _chipVPad = 6;
const double _chipLabelSize = 12;

/// Totals-block grand total (natives: 20.sp Black).
const double _totalSize = 20;

/// Ticket status → [ChipTone] (ready → success, queued → warning,
/// settled → neutral, else accent) — the natives' ticketStatusTone.
ChipTone _ticketTone(String status) => switch (status) {
  'ready' => ChipTone.success,
  'queued' => ChipTone.warning,
  'settled' => ChipTone.neutral,
  _ => ChipTone.accent,
};

/// Ticket status → (foreground, tinted background) for the card's header
/// strip — the natives' ticketStatusTint (Delivery/Kitchen tint pattern).
(Color, Color) _ticketTint(String status, MadarColors colors) =>
    switch (status) {
      'ready' => (colors.success, colors.successBg),
      'queued' => (colors.warning, colors.warningBg),
      'settled' => (colors.textSecondary, colors.surfaceAlt),
      _ => (colors.accent, colors.accentBg),
    };

/// The POS-side settle board. Takes the shared screen contract ([core] +
/// [onStateChanged]); [tickToListen] is the shell's realtime ticket tick —
/// a waiter's fire/round/settle/void from another device reloads the list
/// instantly (no manual refresh).
class OpenTicketsScreen extends StatefulWidget {
  /// Creates the open-tickets settle screen.
  const OpenTicketsScreen({
    required this.core,
    required this.onStateChanged,
    this.tickToListen,
    super.key,
  });

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// Invoked after any call that can move `app_route()` / the session
  /// (a settle books into the shift).
  final void Function() onStateChanged;

  /// Optional realtime tick — each notification reloads the open board
  /// (the natives' `LaunchedEffect(model.ticketTick)`).
  final Listenable? tickToListen;

  @override
  State<OpenTicketsScreen> createState() => _OpenTicketsScreenState();
}

class _OpenTicketsScreenState extends State<OpenTicketsScreen> {
  late final OrderController _model;
  late final CheckoutController _checkout;

  @override
  void initState() {
    super.initState();
    _model = OrderController(
      core: widget.core,
      onStateChanged: widget.onStateChanged,
    );
    _checkout = CheckoutController(
      core: widget.core,
      onStateChanged: widget.onStateChanged,
    );
    // On-appear: the shift (a settle needs its id), the open board, and the
    // payment methods for the shared drawer.
    unawaited(_model.reconcileShift());
    unawaited(_model.loadOpenTickets());
    unawaited(_checkout.init());
    widget.tickToListen?.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.tickToListen?.removeListener(_onTick);
    _model.dispose();
    _checkout.dispose();
    super.dispose();
  }

  void _onTick() => unawaited(_model.loadOpenTickets());

  // ── overlays ───────────────────────────────────────────────────────────────
  /// The read-only order-details overlay (the shared details layout with the
  /// real line items) + a Settle CTA pinned under the details.
  Future<void> _viewTicket(TicketView ticket) async {
    final settle = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: _detailsMaxWidth,
      builder: (sheetContext) => _TicketDetailsSheet(
        model: _model,
        ticket: ticket,
        // Settle CTA: dismiss the details, then open the settle drawer.
        onSettle: () => unawaited(Navigator.of(sheetContext).maybePop(true)),
      ),
    );
    if ((settle ?? false) && mounted) await _settleTicket(ticket);
  }

  /// Settle through the ONE shared [CheckoutDrawer] — same payment/cash/tip
  /// flow as the cashier checkout. The ticket's line-item review rides in as
  /// the drawer's header, the ticket subtotal drives the total, and the
  /// terminal action settles the ticket into a paid order. Stays on the list
  /// after settling (the ticket drops out on reload).
  Future<void> _settleTicket(TicketView ticket) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (sheetContext) => ListenableBuilder(
        listenable: _model,
        builder: (context, _) => CheckoutDrawer(
          controller: _checkout,
          summary: CheckoutSummary(
            subtotalMinor: ticket.subtotalMinor,
            totalMinor: ticket.subtotalMinor,
          ),
          title: _model.tr('waiter.settle'),
          terminalLabel: _model.tr('waiter.settle'),
          terminalIcon: 'checkmark.circle',
          placing: _model.isBusy,
          onClose: () => unawaited(Navigator.of(sheetContext).maybePop()),
          headerContent: _TicketSettleHeader(model: _model, ticket: ticket),
          onTerminal: (result) =>
              unawaited(_settle(sheetContext, ticket, result)),
        ),
      ),
    );
  }

  /// The natives' settle wiring, verbatim: tendered only for a cash tender,
  /// tip fields only when a tip was entered (its method falls back to the
  /// primary), and the drawer dismisses only on success.
  Future<void> _settle(
    BuildContext sheetContext,
    TicketView ticket,
    CheckoutResult result,
  ) async {
    _checkout.error = null;
    final ok = await _model.settleTicket(
      ticket.id,
      result.primaryMethodId,
      amountTenderedMinor: result.isCash && result.tenderedMinor > 0
          ? result.tenderedMinor
          : null,
      tipMinor: result.tipMinor > 0 ? result.tipMinor : null,
      tipPaymentMethodId: result.tipMinor > 0
          ? (result.tipPaymentMethodId ?? result.primaryMethodId)
          : null,
    );
    if (!sheetContext.mounted) return;
    if (ok) {
      await Navigator.of(sheetContext).maybePop();
    } else {
      // Surface the failure INSIDE the drawer (the natives' model.error) —
      // the ListenableBuilder above rebuilds on the model's notify.
      _checkout.error = _model.error;
    }
  }

  /// Void with a reason — the shared reason-picker sheet from
  /// waiter_sheets.dart (same as the waiter cart's void).
  Future<void> _voidTicket(TicketView ticket) async {
    final result = await showMadarSheet<VoidTicketResult>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => WaiterVoidSheet(model: _model, ticket: ticket),
    );
    if (result == null) return;
    await _model.voidTicket(ticket.id, result.reason);
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final colors = context.madarColors;
        final settleable = _model.openTickets
            .where((t) => t.status == 'open' || t.status == 'ready')
            .toList(growable: false);
        // Scaffold: every screen owns its own Material ancestor in this app.
        return Scaffold(
          backgroundColor: colors.bg,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    if (_model.error case final error?)
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: Space.lg,
                          vertical: Space.sm,
                        ),
                        child: NoticeBanner(
                          text: error,
                          icon: 'exclamationmark.circle',
                        ),
                      ),
                    Expanded(
                      child: settleable.isEmpty
                          ? EmptyState(
                              icon: 'tray',
                              title: _model.tr('waiter.no_tickets'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsetsDirectional.all(
                                Space.lg,
                              ),
                              itemCount: settleable.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: Space.sm),
                              itemBuilder: (context, index) {
                                final ticket = settleable[index];
                                return Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: _cardMaxWidth,
                                    ),
                                    child: _SettleTicketCard(
                                      model: _model,
                                      ticket: ticket,
                                      onView: () =>
                                          unawaited(_viewTicket(ticket)),
                                      onSettle: () =>
                                          unawaited(_settleTicket(ticket)),
                                      onVoid: () =>
                                          unawaited(_voidTicket(ticket)),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                // Toasts float above everything on this screen.
                ToastHost(
                  _model.toast,
                  onAction: _model.runToastAction,
                  onDismiss: _model.dismissToast,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Status pill for a ticket — label + tone from the shared map.
class _TicketStatusChip extends StatelessWidget {
  const _TicketStatusChip({required this.model, required this.status});

  final OrderController model;
  final String status;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: model.tr('ticket.status.$status'),
      tone: _ticketTone(status),
    );
  }
}

/// Settle-tab ticket card — the status-tinted card shell (status strip +
/// bold-teal total), then a body with the covering + a View / Settle action
/// pair and a danger void tile. Tapping the card body (or View) opens the
/// details sheet; Settle opens the shared checkout.
class _SettleTicketCard extends StatelessWidget {
  const _SettleTicketCard({
    required this.model,
    required this.ticket,
    required this.onView,
    required this.onSettle,
    required this.onVoid,
  });

  final OrderController model;
  final TicketView ticket;
  final VoidCallback onView;
  final VoidCallback onSettle;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (statusFg, statusBg) = _ticketTint(ticket.status, colors);
    final customer = ticket.customerName;
    final waiter = ticket.waiterName;
    return TactileScale(
      onTap: onView,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.borderLight),
          boxShadow: MadarElevation.card.shadows(colors, dark: dark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status-tinted header strip — dot + ref + state lead, money is
            // the hero.
            Container(
              height: _headerStripHeight,
              color: statusBg,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.md,
              ),
              child: Row(
                spacing: Space.sm,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: statusFg,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: _statusDot),
                  ),
                  Flexible(
                    child: Text(
                      ticket.ticketRef ?? model.tr('waiter.ticket'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.h3.copyWith(
                        fontSize: _refSize,
                        fontWeight: FontWeight.w900,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  _TicketStatusChip(model: model, status: ticket.status),
                  if (ticket.queuedOffline)
                    StatusChip(
                      label: model.tr('waiter.queued'),
                      tone: ChipTone.warning,
                      icon: 'tray.and.arrow.up',
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: Space.md,
                      vertical: _moneyPillVPad,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accentBg,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: MoneyText(
                      ticket.subtotalMinor,
                      currency: model.currency,
                      style: MadarType.money.copyWith(
                        fontSize: _cardMoneySize,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  // Covering + item count — leading person tile (mirrors the
                  // delivery card).
                  Row(
                    spacing: Space.sm,
                    children: [
                      Container(
                        width: _personTile,
                        height: _personTile,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.accentBg,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: MadarIcon('person.fill', tint: colors.accent),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            if (customer != null && customer.isNotEmpty)
                              Text(
                                customer,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MadarType.title.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            // The waiter who opened the ticket — so the
                            // teller sees who took it.
                            if (waiter != null && waiter.isNotEmpty)
                              Text(
                                '${model.tr('order.waiter')}: $waiter',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MadarType.labelSm.copyWith(
                                  fontSize: _metaSize,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textSecondary,
                                ),
                              ),
                            Text(
                              '${ticket.lines.length} '
                              '${model.tr('waiter.items')}',
                              style: MadarType.labelSm.copyWith(
                                fontSize: _metaSize,
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    spacing: Space.sm,
                    children: [
                      Expanded(
                        child: ActionButton(
                          label: model.tr('order.view_order'),
                          icon: 'list.bullet',
                          variant: ActionVariant.outline,
                          onTap: onView,
                        ),
                      ),
                      Expanded(
                        child: ActionButton(
                          label: model.tr('waiter.settle'),
                          icon: 'checkmark.circle',
                          onTap: onSettle,
                        ),
                      ),
                      // Void — danger tile opening the reason sheet.
                      Semantics(
                        button: true,
                        label: model.tr('void.title'),
                        child: TactileScale(
                          onTap: onVoid,
                          child: Container(
                            width: kActionButtonHeight,
                            height: kActionButtonHeight,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.dangerBg,
                              borderRadius: BorderRadius.circular(Radii.sm),
                            ),
                            child: MadarIcon('trash', tint: colors.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ticket details — the covering + table/guests context chips, the real
/// line items (voided lines strike through), the frozen total, and the
/// Settle CTA pinned under the scrolling details. Port of the natives'
/// TicketDetailsSheet (OrderDetailsSheet.kt) + WaiterScreen's pinned CTA.
class _TicketDetailsSheet extends StatelessWidget {
  const _TicketDetailsSheet({
    required this.model,
    required this.ticket,
    required this.onSettle,
  });

  final OrderController model;
  final TicketView ticket;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final waiter = ticket.waiterName;
    final customer = ticket.customerName;
    final table = ticket.tableId;
    final covers = ticket.guestCount;
    final context_ = <(String, String)>[
      // Who took the table — the waiter who opened the ticket.
      if (waiter != null && waiter.isNotEmpty)
        ('fork.knife', '${model.tr('order.waiter')}: $waiter'),
      if (customer != null && customer.isNotEmpty) ('person.fill', customer),
      if (table != null && table.isNotEmpty)
        ('square.grid.2x2', '${model.tr('order.table')} $table'),
      if (covers != null && covers > 0)
        ('person.2.fill', '$covers ${model.tr('waiter.covers')}'),
    ];
    return Column(
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                // Title row — ticket ref + live status chip.
                Row(
                  spacing: Space.sm,
                  children: [
                    MadarIcon(
                      'doc.text',
                      tint: colors.accent,
                      size: IconSize.lg,
                    ),
                    Flexible(
                      child: Text(
                        ticket.ticketRef ?? model.tr('waiter.ticket'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.h2.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    _TicketStatusChip(model: model, status: ticket.status),
                    if (ticket.queuedOffline)
                      StatusChip(
                        label: model.tr('waiter.queued'),
                        tone: ChipTone.warning,
                        icon: 'tray.and.arrow.up',
                      ),
                  ],
                ),
                // Context chips — waiter / customer / table / covers.
                if (context_.isNotEmpty)
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final (icon, label) in context_)
                        _ContextChip(icon: icon, label: label),
                    ],
                  ),
                // Line items — the real ticket lines, voided struck through.
                OrderLinesCard(
                  lines: ticket.lines,
                  currency: model.currency,
                  itemsLabel: model.tr('order.items'),
                  emptyLabel: model.tr('order.cart_empty'),
                ),
                // Totals — a ticket carries a single frozen subtotal.
                _TotalsBlock(
                  label: model.tr('order.total'),
                  totalMinor: ticket.subtotalMinor,
                  currency: model.currency,
                ),
              ],
            ),
          ),
        ),
        // Settle CTA pinned under the details.
        Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: ActionButton(
            label: model.tr('waiter.settle'),
            icon: 'checkmark.circle',
            onTap: onSettle,
          ),
        ),
      ],
    );
  }
}

/// A pill of context (waiter / customer / table / covers) with an icon.
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.icon, required this.label});

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: _chipVPad,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          MadarIcon(icon, tint: colors.textSecondary, size: IconSize.sm),
          Text(
            label,
            style: MadarType.label.copyWith(
              fontSize: _chipLabelSize,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Totals block — the tinted-teal grand total (the hero figure), matching
/// the CheckoutDrawer / CartFooter total block.
class _TotalsBlock extends StatelessWidget {
  const _TotalsBlock({
    required this.label,
    required this.totalMinor,
    required this.currency,
  });

  final String label;
  final int totalMinor;
  final String currency;

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
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: colors.accentBg,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: MadarType.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.accent,
                ),
              ),
            ),
            MoneyText(
              totalMinor,
              currency: currency,
              style: MadarType.money.copyWith(
                fontSize: _totalSize,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact line-item review at the top of the settle drawer — the cashier
/// sees WHAT they're charging (a strike on voided lines) before tendering.
class _TicketSettleHeader extends StatelessWidget {
  const _TicketSettleHeader({required this.model, required this.ticket});

  final OrderController model;
  final TicketView ticket;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              Flexible(
                child: Text(
                  ticket.ticketRef ?? model.tr('waiter.ticket'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              _TicketStatusChip(model: model, status: ticket.status),
            ],
          ),
          for (final line in ticket.lines)
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: Text(
                    '${line.qty}× ${line.name}',
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                      decoration: line.voided
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                MoneyText(
                  line.lineTotalMinor,
                  currency: model.currency,
                  style: MadarType.money.copyWith(
                    fontSize: _headerLineMoneySize,
                    fontWeight: FontWeight.w600,
                  ),
                  color: colors.textPrimary,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
