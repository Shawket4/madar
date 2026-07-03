import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_incoming/src/details_sheets.dart';
import 'package:feature_incoming/src/incoming_provider.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// POS-side settle surface (cashier) — the "Open tickets" tab of the
// unified Orders surface. Live: the screen reloads on the shell's ticket
// tick so a waiter's fire/round/settle/void from another device appears
// instantly. Port of WaiterScreen.kt's TicketsSettleBody.

// Native metrics (WaiterScreen.kt) kept verbatim.

/// Ticket ref size in the tinted strip (natives: 19.sp Black).
const double _ticketRefSize = 19;

/// Strip money hero size (natives: 16.sp Black).
const double _stripMoneySize = 16;

/// The open-tickets settle board. The screen-level [ticketTickProvider]
/// listen (shell-owned SSE counter) triggers reloads.
class TicketsSettleBody extends ConsumerStatefulWidget {
  const TicketsSettleBody({super.key});

  @override
  ConsumerState<TicketsSettleBody> createState() => _TicketsSettleBodyState();
}

class _TicketsSettleBodyState extends ConsumerState<TicketsSettleBody> {
  @override
  void initState() {
    super.initState();
    // (Re)entering the tab refreshes the board — deferred a microtask
    // because provider writes are illegal while the tree is building.
    unawaited(
      Future<void>.microtask(() {
        if (!mounted) return;
        unawaited(ref.read(incomingProvider.notifier).loadOpenTickets());
      }),
    );
  }

  // ── sheet launchers ────────────────────────────────────────────────────────
  /// Order-details overlay — the SHARED details layout (real line items),
  /// with the Settle CTA pinned under the details.
  Future<void> _viewTicket(TicketView ticket) async {
    final bridge = ref.read(bridgeProvider);
    final settle = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: Responsive.listMaxWidth,
      builder: (sheetContext) => TicketDetailsSheet(
        ticket: ticket,
        footer: IncomingButton(
          label: bridge.tr(key: 'waiter.settle'),
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
      builder: (_) => _TicketSettleSheet(ticket: ticket),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    final settleable = ref
        .watch(incomingProvider.select((s) => s.openTickets))
        .where((t) => t.status == 'open' || t.status == 'ready')
        .toList(growable: false);
    final error = ref.watch(incomingProvider.select((s) => s.error));
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
                  title: bridge.tr(key: 'waiter.no_tickets'),
                )
              : ListView.separated(
                  padding: const EdgeInsetsDirectional.all(Space.lg),
                  itemCount: settleable.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (context, index) {
                    final ticket = settleable[index];
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kBoardCardMaxWidth,
                        ),
                        child: _SettleTicketCard(
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
  }
}

/// Settle-tab ticket card (cashier) — the SAME status-tinted card shell as
/// the delivery card (status strip + bold-teal total), then a body with the
/// covering + a "View order" / "Settle" action pair. Tapping the card body
/// (or View) opens the shared order-details sheet; Settle opens the shared
/// checkout. Hot path: watches only the bridge handle + the currency slice.
class _SettleTicketCard extends ConsumerWidget {
  const _SettleTicketCard({
    required this.ticket,
    required this.onView,
    required this.onSettle,
  });

  final TicketView ticket;
  final VoidCallback onView;
  final VoidCallback onSettle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
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
                      ticket.ticketRef ?? bridge.tr(key: 'waiter.ticket'),
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
                    label: bridge.tr(key: 'ticket.status.${ticket.status}'),
                    tone: ticketStatusTone(ticket.status),
                  ),
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
                      vertical: kMoneyPillVPad,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accentBg,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: MoneyText(
                      ticket.subtotalMinor,
                      currency: currency,
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
                                '${bridge.tr(key: 'order.waiter')}: '
                                '$waiterName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MadarType.labelSm.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colors.textSecondary,
                                ),
                              ),
                            Text(
                              '${ticket.lines.length} '
                              '${bridge.tr(key: 'waiter.items')}',
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
                          label: bridge.tr(key: 'order.view_order'),
                          icon: 'list.bullet',
                          variant: IncomingButtonVariant.outline,
                          onTap: onView,
                        ),
                      ),
                      Expanded(
                        child: IncomingButton(
                          label: bridge.tr(key: 'waiter.settle'),
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
/// [IncomingNotifier.settleTicket].
class _TicketSettleSheet extends ConsumerStatefulWidget {
  const _TicketSettleSheet({required this.ticket});

  final TicketView ticket;

  @override
  ConsumerState<_TicketSettleSheet> createState() => _TicketSettleSheetState();
}

class _TicketSettleSheetState extends ConsumerState<_TicketSettleSheet> {
  @override
  void initState() {
    super.initState();
    // Fresh settle session over the ticket's frozen subtotal (== total) —
    // deferred a microtask because provider writes are illegal while the
    // tree is building.
    unawaited(
      Future<void>.microtask(() {
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
      }),
    );
  }

  /// The natives' settle mapping: tendered only for a cash primary, tip
  /// only when positive (its method falling back to the primary).
  Future<void> _settle(CheckoutResult r) async {
    final checkout = ref.read(checkoutProvider.notifier)..setError(null);
    final ok = await ref
        .read(incomingProvider.notifier)
        .settleTicket(
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
      // the board's own banner sits behind the modal scrim.
      checkout.setError(ref.read(incomingProvider).error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    final placing = ref.watch(incomingProvider.select((s) => s.isBusy));
    final ticket = widget.ticket;
    final label = bridge.tr(key: 'waiter.settle');
    return CheckoutDrawer(
      title: label,
      terminalLabel: label,
      terminalIcon: 'checkmark.circle',
      placing: placing,
      onClose: () => unawaited(Navigator.of(context).maybePop()),
      headerContent: _SettleHeader(ticket: ticket),
      onTerminal: (result) => unawaited(_settle(result)),
    );
  }
}

/// Compact line-item review atop the settle drawer — the cashier sees WHAT
/// they're charging (a strike on voided lines) before tendering.
class _SettleHeader extends ConsumerWidget {
  const _SettleHeader({required this.ticket});

  final TicketView ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
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
                  ticket.ticketRef ?? bridge.tr(key: 'waiter.ticket'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              StatusChip(
                label: bridge.tr(key: 'ticket.status.${ticket.status}'),
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
                  currency: currency,
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
