import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_incoming/src/details_sheets.dart';
import 'package:feature_incoming/src/incoming_controller.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

// POS-side settle surface (cashier) — the "Open tickets" tab of the
// unified Orders surface. Live: reloads on the shell's ticket tick so a
// waiter's fire/round/settle/void from another device appears instantly.
// Port of WaiterScreen.kt's TicketsSettleBody.

// Native metrics (WaiterScreen.kt) kept verbatim.

/// Ticket ref size in the tinted strip (natives: 19.sp Black).
const double _ticketRefSize = 19;

/// Strip money hero size (natives: 16.sp Black).
const double _stripMoneySize = 16;

/// The open-tickets settle board. The unified [tick] Listenable
/// (shell-owned SSE counter) triggers reloads.
class TicketsSettleBody extends StatefulWidget {
  const TicketsSettleBody({required this.model, this.tick, super.key});

  final IncomingController model;

  /// Bumped by the shell on `ticket.*` realtime events.
  final Listenable? tick;

  @override
  State<TicketsSettleBody> createState() => _TicketsSettleBodyState();
}

class _TicketsSettleBodyState extends State<TicketsSettleBody> {
  IncomingController get _model => widget.model;

  @override
  void initState() {
    super.initState();
    unawaited(_model.loadOpenTickets());
    widget.tick?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.tick?.removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_model.loadOpenTickets());

  // ── sheet launchers ────────────────────────────────────────────────────────
  /// Order-details overlay — the SHARED details layout (real line items),
  /// with the Settle CTA pinned under the details.
  Future<void> _viewTicket(TicketView ticket) async {
    final settle = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: Responsive.listMaxWidth,
      builder: (sheetContext) => TicketDetailsSheet(
        ticket: ticket,
        currency: _model.currency,
        tr: _model.tr,
        footer: IncomingButton(
          label: _model.tr('waiter.settle'),
          icon: 'checkmark.circle',
          onTap: () => unawaited(Navigator.of(sheetContext).maybePop(true)),
        ),
      ),
    );
    if (!mounted || settle != true) return;
    await _settle(ticket);
  }

  /// Settle overlay — the ONE real CheckoutDrawer (same as the cashier
  /// checkout), driven by the ticket total; terminal action = settle.
  /// Stays on the list after settling (the ticket drops out on reload).
  Future<void> _settle(TicketView ticket) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => _TicketSettleSheet(model: _model, ticket: ticket),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (context, _) {
        final model = _model;
        final settleable = model.settleableTickets;
        final error = model.error;
        return Column(
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
                      title: model.tr('waiter.no_tickets'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsetsDirectional.all(Space.lg),
                      itemCount: settleable.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.sm),
                      itemBuilder: (context, index) {
                        final ticket = settleable[index];
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: kBoardCardMaxWidth,
                            ),
                            child: _SettleTicketCard(
                              model: model,
                              ticket: ticket,
                              onView: () => unawaited(_viewTicket(ticket)),
                              onSettle: () => unawaited(_settle(ticket)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Settle-tab ticket card (cashier) — the SAME status-tinted card shell as
/// the delivery card (status strip + bold-teal total), then a body with the
/// covering + a "View order" / "Settle" action pair. Tapping the card body
/// (or View) opens the shared order-details sheet; Settle opens the shared
/// checkout.
class _SettleTicketCard extends StatelessWidget {
  const _SettleTicketCard({
    required this.model,
    required this.ticket,
    required this.onView,
    required this.onSettle,
  });

  final IncomingController model;
  final TicketView ticket;
  final VoidCallback onView;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final (statusFg, statusBg) = _ticketStatusTint(ticket.status, colors);
    final customerName = ticket.customerName;
    final waiterName = ticket.waiterName;
    return TactileScale(
      onTap: onView,
      child: IncomingCard(
        clip: true,
        padding: EdgeInsetsDirectional.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status-tinted strip — dot + ref + state lead, money the hero.
            Container(
              height: kTicketStripHeight,
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
                    child: const SizedBox.square(dimension: kStatusDot),
                  ),
                  Flexible(
                    child: Text(
                      ticket.ticketRef ?? model.tr('waiter.ticket'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.h3.copyWith(
                        fontSize: _ticketRefSize,
                        fontWeight: FontWeight.w900,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  StatusChip(
                    label: model.tr('ticket.status.${ticket.status}'),
                    tone: ticketStatusTone(ticket.status),
                  ),
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
                      vertical: kMoneyPillVPad,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accentBg,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: MoneyText(
                      ticket.subtotalMinor,
                      currency: model.currency,
                      style: MadarType.money.copyWith(
                        fontSize: _stripMoneySize,
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
                  // Covering + item count — leading person tile (mirrors
                  // the delivery card).
                  Row(
                    spacing: Space.sm,
                    children: [
                      Container(
                        width: kPersonTileSm,
                        height: kPersonTileSm,
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
                          spacing: Space.xs / 2,
                          children: [
                            if (customerName != null && customerName.isNotEmpty)
                              Text(
                                customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MadarType.title.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            // The waiter who opened the ticket — so the
                            // teller sees who took it.
                            if (waiterName != null && waiterName.isNotEmpty)
                              Text(
                                '${model.tr('order.waiter')}: $waiterName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MadarType.labelSm.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colors.textSecondary,
                                ),
                              ),
                            Text(
                              '${ticket.lines.length} '
                              '${model.tr('waiter.items')}',
                              style: MadarType.labelSm.copyWith(
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
                        child: IncomingButton(
                          label: model.tr('order.view_order'),
                          icon: 'list.bullet',
                          variant: IncomingButtonVariant.outline,
                          onTap: onView,
                        ),
                      ),
                      Expanded(
                        child: IncomingButton(
                          label: model.tr('waiter.settle'),
                          icon: 'checkmark.circle',
                          onTap: onSettle,
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

/// Settle a ticket through the SHARED [CheckoutDrawer] — same payment/cash/
/// tip flow as the cashier checkout. The ticket's line-item review rides in
/// as the drawer's header, the ticket subtotal drives the total, and the
/// terminal action settles the ticket into a paid order via
/// [IncomingController.settleTicket].
class _TicketSettleSheet extends StatefulWidget {
  const _TicketSettleSheet({required this.model, required this.ticket});

  final IncomingController model;
  final TicketView ticket;

  @override
  State<_TicketSettleSheet> createState() => _TicketSettleSheetState();
}

class _TicketSettleSheetState extends State<_TicketSettleSheet> {
  late final CheckoutController _checkout;

  @override
  void initState() {
    super.initState();
    _checkout = CheckoutController(
      core: widget.model.core,
      onStateChanged: widget.model.onStateChanged,
    );
    unawaited(_checkout.init());
  }

  @override
  void dispose() {
    _checkout.dispose();
    super.dispose();
  }

  /// The natives' settle mapping: tendered only for a cash primary, tip
  /// only when positive (its method falling back to the primary).
  Future<void> _settle(CheckoutResult r) async {
    _checkout.error = null;
    final ok = await widget.model.settleTicket(
      ticketId: widget.ticket.id,
      paymentMethodId: r.primaryMethodId,
      amountTenderedMinor: r.isCash && r.tenderedMinor > 0
          ? r.tenderedMinor
          : null,
      tipMinor: r.tipMinor > 0 ? r.tipMinor : null,
      tipPaymentMethodId: r.tipMinor > 0
          ? (r.tipPaymentMethodId ?? r.primaryMethodId)
          : null,
    );
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).maybePop();
    } else {
      // Surface the failure INSIDE the drawer (the natives' model.error) —
      // the board's own banner sits behind the modal scrim. The model's
      // pending notify rebuilds the ListenableBuilder above.
      _checkout.error = widget.model.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final ticket = widget.ticket;
    final label = model.tr('waiter.settle');
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => CheckoutDrawer(
        controller: _checkout,
        // A ticket carries a single frozen subtotal (== total).
        summary: CheckoutSummary(
          subtotalMinor: ticket.subtotalMinor,
          totalMinor: ticket.subtotalMinor,
        ),
        title: label,
        terminalLabel: label,
        terminalIcon: 'checkmark.circle',
        placing: model.isBusy,
        onClose: () => unawaited(Navigator.of(context).maybePop()),
        headerContent: _SettleHeader(model: model, ticket: ticket),
        onTerminal: (result) => unawaited(_settle(result)),
      ),
    );
  }
}

/// Compact line-item review atop the settle drawer — the cashier sees WHAT
/// they're charging (a strike on voided lines) before tendering.
class _SettleHeader extends StatelessWidget {
  const _SettleHeader({required this.model, required this.ticket});

  final IncomingController model;
  final TicketView ticket;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return IncomingCard(
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
              StatusChip(
                label: model.tr('ticket.status.${ticket.status}'),
                tone: ticketStatusTone(ticket.status),
              ),
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
                    fontSize: 13,
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

/// Ticket status → (foreground, tinted-background) pair for the card's
/// header strip. Mirrors the Delivery/Kitchen tint pattern.
(Color, Color) _ticketStatusTint(String status, MadarColors colors) =>
    switch (status) {
      'ready' => (colors.success, colors.successBg),
      'queued' => (colors.warning, colors.warningBg),
      'settled' => (colors.textSecondary, colors.surfaceAlt),
      _ => (colors.accent, colors.accentBg),
    };
