import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_floor/src/floor_controller.dart';
import 'package:feature_floor/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The four live table states, in the natives' pick order
/// (FloorPlanScreen.kt `STATUSES`).
const List<String> kTableStatuses = ['free', 'held', 'seated', 'dirty'];

/// Status → tone color, the natives' `tableColor` mapped onto tokens
/// (green/amber/blue/gray → success/warning/navy/textMuted).
Color tableColor(MadarColors colors, String status) => switch (status) {
  'free' => colors.success,
  'held' => colors.warning,
  'seated' => colors.navy,
  _ => colors.textMuted,
};

/// Set-status sheet — the natives' set-status AlertDialog: a
/// "label · Set status" title, one full-width button per state, Cancel.
/// Pops the picked status string (null = cancelled).
class TableStatusSheet extends StatelessWidget {
  /// Creates the status picker for [table].
  const TableStatusSheet({
    required this.model,
    required this.table,
    super.key,
  });

  /// The floor state holder (strings only).
  final FloorController model;

  /// The tapped table.
  final FloorTableView table;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${table.label} · ${model.tr('reservations.setStatus')}',
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.md),
          for (final status in kTableStatuses) ...[
            FloorButton(
              label: model.tr('reservations.status_$status'),
              onTap: () => unawaited(Navigator.of(context).maybePop(status)),
            ),
            const SizedBox(height: Space.sm),
          ],
          FloorButton(
            label: model.tr('common.cancel'),
            variant: FloorButtonVariant.outline,
            onTap: () => unawaited(Navigator.of(context).maybePop()),
          ),
        ],
      ),
    );
  }
}

/// Seat sheet — the natives' seat AlertDialog: the booking's name, one
/// toggle row per table in the active section ("✓ label · seats · status",
/// multiple picks ⇒ merged tables), then Seat / Cancel. Pops `true` after
/// a successful seat.
class SeatReservationSheet extends StatefulWidget {
  /// Creates the seat picker for [booking] over [tables].
  const SeatReservationSheet({
    required this.model,
    required this.booking,
    required this.tables,
    super.key,
  });

  /// The floor state holder — runs the seat call.
  final FloorController model;

  /// The booking being seated.
  final ReservationView booking;

  /// Tables of the active section, in canvas order.
  final List<FloorTableView> tables;

  @override
  State<SeatReservationSheet> createState() => _SeatReservationSheetState();
}

class _SeatReservationSheetState extends State<SeatReservationSheet> {
  final Set<String> _picked = {};

  Future<void> _seat() async {
    final ok = await widget.model.seatReservation(
      widget.booking.id,
      _picked.toList(),
    );
    if (ok && mounted) await Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final model = widget.model;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.booking.customerName,
              style: MadarType.h2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: Space.md),
            for (final table in widget.tables) ...[
              _SeatTableRow(
                table: table,
                statusLabel: model.tr('reservations.status_${table.status}'),
                picked: _picked.contains(table.id),
                onTap: () => setState(() {
                  if (!_picked.remove(table.id)) _picked.add(table.id);
                }),
              ),
              const SizedBox(height: Space.sm),
            ],
            const SizedBox(height: Space.xs),
            Row(
              children: [
                Expanded(
                  child: FloorButton(
                    label: model.tr('common.cancel'),
                    variant: FloorButtonVariant.outline,
                    onTap: () => unawaited(Navigator.of(context).maybePop()),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: FloorButton(
                    label: model.tr('reservations.seat'),
                    icon: 'checkmark.circle',
                    enabled: _picked.isNotEmpty,
                    loading: model.isBusy,
                    onTap: () => unawaited(_seat()),
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

/// One toggle row in the seat sheet — check glyph + "label · seats ·
/// status", accent-tinted when picked.
class _SeatTableRow extends StatelessWidget {
  const _SeatTableRow({
    required this.table,
    required this.statusLabel,
    required this.picked,
    required this.onTap,
  });

  final FloorTableView table;
  final String statusLabel;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      scale: 0.99,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.all(Space.md),
        decoration: BoxDecoration(
          color: picked ? colors.accentBg : colors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: picked
                ? colors.accent.withValues(alpha: Opacities.disabled)
                : colors.border,
          ),
        ),
        child: Row(
          children: [
            MadarIcon(
              picked ? 'checkmark.circle' : 'circle',
              tint: picked ? colors.accent : colors.textMuted,
              size: IconSize.lg,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                '${table.label} · ${table.seats} · $statusLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.body.copyWith(
                  fontWeight: picked ? FontWeight.w700 : FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Occupied-table summary — the ticket's line-item review (the natives'
/// TicketSettleHeader card: ref + status chip, a strike on voided lines,
/// the subtotal) with a Settle CTA pinned under it (WaiterScreen.kt's
/// view-overlay). Pops `true` when the teller jumps to settle.
class TableTicketSheet extends StatelessWidget {
  /// Creates the summary for [ticket] sitting on [tableLabel].
  const TableTicketSheet({
    required this.model,
    required this.ticket,
    required this.tableLabel,
    super.key,
  });

  /// The floor state holder (strings only).
  final FloorController model;

  /// The table's open ticket.
  final TicketView ticket;

  /// The tapped table's label — leads the title.
  final String tableLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tableLabel,
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.md),
          TicketReviewCard(
            model: model,
            ticket: ticket,
            currency: model.currency,
          ),
          const SizedBox(height: Space.md),
          FloorButton(
            label: model.tr('waiter.settle'),
            icon: 'checkmark.circle',
            onTap: () => unawaited(Navigator.of(context).maybePop(true)),
          ),
        ],
      ),
    );
  }
}

/// Compact line-item review card — port of the natives'
/// TicketSettleHeader (WaiterScreen.kt): ref + status chip header, one row
/// per line (strikethrough when voided), money per line.
class TicketReviewCard extends StatelessWidget {
  /// Creates the review card for [ticket].
  const TicketReviewCard({
    required this.model,
    required this.ticket,
    required this.currency,
    super.key,
  });

  /// Strings source.
  final FloorController model;

  /// The ticket under review.
  final TicketView ticket;

  /// Currency code for the line money.
  final String currency;

  /// Ticket status → chip tone (the natives' `ticketStatusTone`).
  static ChipTone _tone(String status) => switch (status) {
    'ready' => ChipTone.success,
    'queued' => ChipTone.warning,
    'settled' => ChipTone.neutral,
    _ => ChipTone.accent,
  };

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
          Row(
            children: [
              Flexible(
                child: Text(
                  ticket.ticketRef ?? model.tr('waiter.ticket'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: Space.sm),
              StatusChip(
                label: model.tr('ticket.status.${ticket.status}'),
                tone: _tone(ticket.status),
              ),
            ],
          ),
          for (final line in ticket.lines) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${line.qty}× ${line.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.bodySm.copyWith(
                      color: colors.textSecondary,
                      decoration: line.voided
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                MoneyText(
                  line.lineTotalMinor,
                  currency: currency,
                  style: MadarType.money,
                  color: colors.textPrimary,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Settle sheet — the ONE shared [CheckoutDrawer] (same payment/cash/tip
/// flow as the cashier checkout), driven by the ticket subtotal, with the
/// line-item review riding in as header content; the terminal action
/// settles the ticket into a paid order. Port of the natives'
/// TicketSettleDrawer (WaiterScreen.kt). Pops `true` after settling.
class TableSettleSheet extends StatefulWidget {
  /// Creates the settle drawer for [ticket].
  const TableSettleSheet({
    required this.model,
    required this.ticket,
    super.key,
  });

  /// The floor state holder — runs the settle call.
  final FloorController model;

  /// The ticket being settled.
  final TicketView ticket;

  @override
  State<TableSettleSheet> createState() => _TableSettleSheetState();
}

class _TableSettleSheetState extends State<TableSettleSheet> {
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

  /// The natives' onTerminal: cash tender + tip only when present, the tip
  /// defaulting to the charge method.
  Future<void> _settle(CheckoutResult result) async {
    final tipped = result.tipMinor > 0;
    final ok = await widget.model.settleTicket(
      ticketId: widget.ticket.id,
      paymentMethodId: result.primaryMethodId,
      amountTenderedMinor: result.isCash && result.tenderedMinor > 0
          ? result.tenderedMinor
          : null,
      tipMinor: tipped ? result.tipMinor : null,
      tipPaymentMethodId: tipped
          ? (result.tipPaymentMethodId ?? result.primaryMethodId)
          : null,
    );
    if (ok && mounted) await Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final ticket = widget.ticket;
    return ListenableBuilder(
      listenable: Listenable.merge([model, _checkout]),
      builder: (context, _) => CheckoutDrawer(
        controller: _checkout,
        summary: CheckoutSummary(
          subtotalMinor: ticket.subtotalMinor,
          totalMinor: ticket.subtotalMinor,
        ),
        title: model.tr('waiter.settle'),
        terminalLabel: model.tr('waiter.settle'),
        terminalIcon: 'checkmark.circle',
        placing: model.isBusy,
        onClose: () => unawaited(Navigator.of(context).maybePop()),
        headerContent: TicketReviewCard(
          model: model,
          ticket: ticket,
          currency: model.currency,
        ),
        onTerminal: (result) => unawaited(_settle(result)),
      ),
    );
  }
}
