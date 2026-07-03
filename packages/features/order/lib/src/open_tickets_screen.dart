/// The cashier "Open tickets" settle surface — a pixel-and-behavior port
/// of the Kotlin WaiterScreen.kt (TicketsSettleBody): the live open/ready
/// ticket board (reloaded on the realtime ticket tick), the status-tinted
/// settle card, the read-only order-details overlay (voided lines strike
/// through), the void-with-reason sheet, and Settle through the ONE shared
/// [CheckoutDrawer] feeding `settleTicket` — no mirrored settle UI.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/cart_panel.dart' show OrderLinesCard;
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// The POS-side settle board, pushed over the order surface. Watches the
/// shell's realtime ticket tick — a waiter's fire/round/settle/void from
/// another device reloads the list instantly (no manual refresh).
class OpenTicketsScreen extends ConsumerStatefulWidget {
  /// Creates the open-tickets settle screen.
  const OpenTicketsScreen({super.key});

  @override
  ConsumerState<OpenTicketsScreen> createState() => _OpenTicketsScreenState();
}

class _OpenTicketsScreenState extends ConsumerState<OpenTicketsScreen> {
  OrderNotifier get _notifier => ref.read(orderProvider.notifier);

  @override
  void initState() {
    super.initState();
    // On-appear: the shift (a settle needs its id) and the open board; the
    // shared checkout drawer loads its own payment methods. Post-frame:
    // notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_notifier.reconcileShift());
      unawaited(_notifier.loadOpenTickets());
    });
  }

  // ── overlays ───────────────────────────────────────────────────────────────
  /// The read-only order-details overlay (the shared details layout with the
  /// real line items) + a Settle CTA pinned under the details.
  Future<void> _viewTicket(TicketView ticket) async {
    final settle = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: _detailsMaxWidth,
      builder: (sheetContext) => _TicketDetailsSheet(
        ticket: ticket,
        // Settle CTA: dismiss the details, then open the settle drawer.
        onSettle: () => unawaited(Navigator.of(sheetContext).maybePop(true)),
      ),
    );
    if ((settle ?? false) && mounted) await _settleTicket(ticket);
  }

  /// Settle through the ONE shared [CheckoutDrawer] — same payment/cash/tip
  /// flow as the cashier checkout. The ticket's line-item review rides in as
  /// the drawer's header, the ticket subtotal drives the total (via
  /// `startSettle`), and the terminal action settles the ticket into a paid
  /// order. Stays on the list after settling (the ticket drops out on
  /// reload).
  Future<void> _settleTicket(TicketView ticket) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (sheetContext) => _SettleDrawer(
        ticket: ticket,
        onClose: () => unawaited(Navigator.of(sheetContext).maybePop()),
        onTerminal: (result) =>
            unawaited(_settle(sheetContext, ticket, result)),
      ),
    );
    // Leaving the drawer clears a lingering settle error from the board.
    _notifier.clearError();
  }

  /// The natives' settle wiring, verbatim: tendered only for a cash tender,
  /// tip fields only when a tip was entered (its method falls back to the
  /// primary), and the drawer dismisses only on success.
  Future<void> _settle(
    BuildContext sheetContext,
    TicketView ticket,
    CheckoutResult result,
  ) async {
    final ok = await _notifier.settleTicket(
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
    if (ok) await Navigator.of(sheetContext).maybePop();
    // On failure the error stays in orderProvider and renders inside the
    // drawer's header banner.
  }

  /// Void with a reason — the shared reason-picker sheet from
  /// waiter_sheets.dart (same as the waiter cart's void).
  Future<void> _voidTicket(TicketView ticket) async {
    final result = await showMadarSheet<VoidTicketResult>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => WaiterVoidSheet(ticket: ticket),
    );
    if (result == null) return;
    await _notifier.voidTicket(ticket.id, result.reason);
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    // Realtime ticket tick — each bump reloads the open board (the natives'
    // `LaunchedEffect(model.ticketTick)`).
    ref.listen(ticketTickProvider, (_, _) {
      unawaited(_notifier.loadOpenTickets());
    });
    final openTickets = ref.watch(orderProvider.select((s) => s.openTickets));
    final error = ref.watch(orderProvider.select((s) => s.error));
    final settleable = openTickets
        .where((t) => t.status == 'open' || t.status == 'ready')
        .toList(growable: false);
    // Scaffold: every screen owns its own Material ancestor in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          MadarHeader(
            title: bridge.tr(key: 'waiter.title'),
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (error != null)
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
                                title: bridge.tr(key: 'waiter.no_tickets'),
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
                  const _TicketsToastHost(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The settle presentation over the shared [CheckoutDrawer]: starts the
/// checkout session over the ticket's FIXED subtotal (`startSettle`) and
/// rides the line-item review — plus any settle failure — in as the
/// drawer's header content.
class _SettleDrawer extends ConsumerStatefulWidget {
  const _SettleDrawer({
    required this.ticket,
    required this.onClose,
    required this.onTerminal,
  });

  final TicketView ticket;
  final VoidCallback onClose;
  final ValueChanged<CheckoutResult> onTerminal;

  @override
  ConsumerState<_SettleDrawer> createState() => _SettleDrawerState();
}

class _SettleDrawerState extends ConsumerState<_SettleDrawer> {
  @override
  void initState() {
    super.initState();
    // Post-frame: notifier writes during initState land mid-build (crash).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(checkoutProvider.notifier)
            .startSettle(
              CheckoutSummary(
                subtotalMinor: widget.ticket.subtotalMinor,
                totalMinor: widget.ticket.subtotalMinor,
              ),
            ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    final isBusy = ref.watch(orderProvider.select((s) => s.isBusy));
    // A failed settle surfaces INSIDE the drawer (the natives' model.error)
    // — rendered above the line-item review.
    final error = ref.watch(orderProvider.select((s) => s.error));
    return CheckoutDrawer(
      title: bridge.tr(key: 'waiter.settle'),
      terminalLabel: bridge.tr(key: 'waiter.settle'),
      terminalIcon: 'checkmark.circle',
      placing: isBusy,
      onClose: widget.onClose,
      headerContent: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            NoticeBanner(
              text: error,
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
            const SizedBox(height: Space.sm),
          ],
          _TicketSettleHeader(ticket: widget.ticket),
        ],
      ),
      onTerminal: widget.onTerminal,
    );
  }
}

/// Toast presenter scoped to its own watch, so a toast never rebuilds the
/// ticket list.
class _TicketsToastHost extends ConsumerWidget {
  const _TicketsToastHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(orderProvider.select((s) => s.toast));
    final notifier = ref.read(orderProvider.notifier);
    return ToastHost(
      toast,
      onAction: notifier.runToastAction,
      onDismiss: notifier.dismissToast,
    );
  }
}

/// Status pill for a ticket — label + tone from the shared map.
class _TicketStatusChip extends ConsumerWidget {
  const _TicketStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    return StatusChip(
      label: bridge.tr(key: 'ticket.status.$status'),
      tone: _ticketTone(status),
    );
  }
}

/// Settle-tab ticket card — the status-tinted card shell (status strip +
/// bold-teal total), then a body with the covering + a View / Settle action
/// pair and a danger void tile. Tapping the card body (or View) opens the
/// details sheet; Settle opens the shared checkout.
class _SettleTicketCard extends ConsumerWidget {
  const _SettleTicketCard({
    required this.ticket,
    required this.onView,
    required this.onSettle,
    required this.onVoid,
  });

  final TicketView ticket;
  final VoidCallback onView;
  final VoidCallback onSettle;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(orderProvider.select((s) => s.currency));
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
                      ticket.ticketRef ?? bridge.tr(key: 'waiter.ticket'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.h3.copyWith(
                        fontSize: _refSize,
                        fontWeight: FontWeight.w900,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  _TicketStatusChip(status: ticket.status),
                  if (ticket.queuedOffline)
                    StatusChip(
                      label: bridge.tr(key: 'waiter.queued'),
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
                      currency: currency,
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
                                '${bridge.tr(key: 'order.waiter')}: $waiter',
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
                              '${bridge.tr(key: 'waiter.items')}',
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
                          label: bridge.tr(key: 'order.view_order'),
                          icon: 'list.bullet',
                          variant: ActionVariant.outline,
                          onTap: onView,
                        ),
                      ),
                      Expanded(
                        child: ActionButton(
                          label: bridge.tr(key: 'waiter.settle'),
                          icon: 'checkmark.circle',
                          onTap: onSettle,
                        ),
                      ),
                      // Void — danger tile opening the reason sheet.
                      Semantics(
                        button: true,
                        label: bridge.tr(key: 'void.title'),
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
class _TicketDetailsSheet extends ConsumerWidget {
  const _TicketDetailsSheet({required this.ticket, required this.onSettle});

  final TicketView ticket;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final waiter = ticket.waiterName;
    final customer = ticket.customerName;
    final table = ticket.tableId;
    final covers = ticket.guestCount;
    final context_ = <(String, String)>[
      // Who took the table — the waiter who opened the ticket.
      if (waiter != null && waiter.isNotEmpty)
        ('fork.knife', '${bridge.tr(key: 'order.waiter')}: $waiter'),
      if (customer != null && customer.isNotEmpty) ('person.fill', customer),
      if (table != null && table.isNotEmpty)
        ('square.grid.2x2', '${bridge.tr(key: 'order.table')} $table'),
      if (covers != null && covers > 0)
        ('person.2.fill', '$covers ${bridge.tr(key: 'waiter.covers')}'),
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
                        ticket.ticketRef ?? bridge.tr(key: 'waiter.ticket'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.h2.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    _TicketStatusChip(status: ticket.status),
                    if (ticket.queuedOffline)
                      StatusChip(
                        label: bridge.tr(key: 'waiter.queued'),
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
                  currency: currency,
                  itemsLabel: bridge.tr(key: 'order.items'),
                  emptyLabel: bridge.tr(key: 'order.cart_empty'),
                ),
                // Totals — a ticket carries a single frozen subtotal.
                _TotalsBlock(
                  label: bridge.tr(key: 'order.total'),
                  totalMinor: ticket.subtotalMinor,
                  currency: currency,
                ),
              ],
            ),
          ),
        ),
        // Settle CTA pinned under the details.
        Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: ActionButton(
            label: bridge.tr(key: 'waiter.settle'),
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
class _TicketSettleHeader extends ConsumerWidget {
  const _TicketSettleHeader({required this.ticket});

  final TicketView ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final currency = ref.watch(orderProvider.select((s) => s.currency));
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
                  ticket.ticketRef ??
                      ref.watch(bridgeProvider).tr(key: 'waiter.ticket'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              _TicketStatusChip(status: ticket.status),
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
                  currency: currency,
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
