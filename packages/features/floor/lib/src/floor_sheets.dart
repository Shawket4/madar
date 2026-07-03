import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_floor/src/floor_provider.dart';
import 'package:feature_floor/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
/// Pops the picked status string (null = cancelled). Pure-DATA param: the
/// tapped [table].
class TableStatusSheet extends ConsumerWidget {
  /// Creates the status picker for [table].
  const TableStatusSheet({required this.table, super.key});

  /// The tapped table.
  final FloorTableView table;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String tr(String key) => bridge.tr(key: key);
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${table.label} · ${tr('reservations.setStatus')}',
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.md),
          for (final status in kTableStatuses) ...[
            FloorButton(
              label: tr('reservations.status_$status'),
              onTap: () => unawaited(Navigator.of(context).maybePop(status)),
            ),
            const SizedBox(height: Space.sm),
          ],
          FloorButton(
            label: tr('common.cancel'),
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
/// a successful seat. Pure-DATA params; the pick set lives on
/// [floorProvider] (the presenting screen clears it before showing).
class SeatReservationSheet extends ConsumerWidget {
  /// Creates the seat picker for [booking] over [tables].
  const SeatReservationSheet({
    required this.booking,
    required this.tables,
    super.key,
  });

  /// The booking being seated.
  final ReservationView booking;

  /// Tables of the active section, in canvas order.
  final List<FloorTableView> tables;

  Future<void> _seat(BuildContext context, WidgetRef ref) async {
    final picks = ref.read(floorProvider).seatPicks;
    final ok = await ref
        .read(floorProvider.notifier)
        .seatReservation(booking.id, picks.toList());
    if (ok && context.mounted) await Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String tr(String key) => bridge.tr(key: key);
    final picks = ref.watch(floorProvider.select((s) => s.seatPicks));
    final busy = ref.watch(floorProvider.select((s) => s.isBusy));
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            booking.customerName,
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.md),
          for (final table in tables) ...[
            _SeatTableRow(
              table: table,
              statusLabel: tr('reservations.status_${table.status}'),
              picked: picks.contains(table.id),
              onTap: () =>
                  ref.read(floorProvider.notifier).toggleSeatPick(table.id),
            ),
            const SizedBox(height: Space.sm),
          ],
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: FloorButton(
                  label: tr('common.cancel'),
                  variant: FloorButtonVariant.outline,
                  onTap: () => unawaited(Navigator.of(context).maybePop()),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: FloorButton(
                  label: tr('reservations.seat'),
                  icon: 'checkmark.circle',
                  enabled: picks.isNotEmpty,
                  loading: busy,
                  onTap: () => unawaited(_seat(context, ref)),
                ),
              ),
            ],
          ),
        ],
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
/// view-overlay). Pops `true` when the teller jumps to settle. Pure-DATA
/// params.
class TableTicketSheet extends ConsumerWidget {
  /// Creates the summary for [ticket] sitting on [tableLabel].
  const TableTicketSheet({
    required this.ticket,
    required this.tableLabel,
    super.key,
  });

  /// The table's open ticket.
  final TicketView ticket;

  /// The tapped table's label — leads the title.
  final String tableLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
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
          TicketReviewCard(ticket: ticket),
          const SizedBox(height: Space.md),
          FloorButton(
            label: bridge.tr(key: 'waiter.settle'),
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
class TicketReviewCard extends ConsumerWidget {
  /// Creates the review card for [ticket].
  const TicketReviewCard({required this.ticket, super.key});

  /// The ticket under review.
  final TicketView ticket;

  /// Ticket status → chip tone (the natives' `ticketStatusTone`).
  static ChipTone _tone(String status) => switch (status) {
    'ready' => ChipTone.success,
    'queued' => ChipTone.warning,
    'settled' => ChipTone.neutral,
    _ => ChipTone.accent,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bridge = ref.watch(bridgeProvider);
    final currency = bridge.currentSession()?.currencyCode ?? '';
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
                  ticket.ticketRef ?? bridge.tr(key: 'waiter.ticket'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: Space.sm),
              StatusChip(
                label: bridge.tr(key: 'ticket.status.${ticket.status}'),
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
/// flow as the cashier checkout), driven by the ticket subtotal via a fresh
/// `checkoutProvider` settle session, with the line-item review riding in
/// as header content; the terminal action settles the ticket into a paid
/// order. Port of the natives' TicketSettleDrawer (WaiterScreen.kt). Pops
/// `true` after settling. Pure-DATA param: the [ticket].
class TableSettleSheet extends ConsumerStatefulWidget {
  /// Creates the settle drawer for [ticket].
  const TableSettleSheet({required this.ticket, super.key});

  /// The ticket being settled.
  final TicketView ticket;

  @override
  ConsumerState<TableSettleSheet> createState() => _TableSettleSheetState();
}

class _TableSettleSheetState extends ConsumerState<TableSettleSheet> {
  @override
  void initState() {
    super.initState();
    // Fresh autoDispose checkout session over the ticket's FIXED subtotal
    // (its discount froze at fire time). First state write lands after the
    // loads (post-frame) — build-safe.
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
  }

  /// The natives' onTerminal: cash tender + tip only when present, the tip
  /// defaulting to the charge method.
  Future<void> _settle(CheckoutResult result) async {
    ref.read(checkoutProvider.notifier).setError(null);
    final tipped = result.tipMinor > 0;
    final ok = await ref
        .read(floorProvider.notifier)
        .settleTicket(
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
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).maybePop(true);
    } else {
      // Surface the failure INSIDE the drawer (the natives' model.error) —
      // the floor plan's own banner sits behind the modal scrim.
      ref
          .read(checkoutProvider.notifier)
          .setError(ref.read(floorProvider).error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    final busy = ref.watch(floorProvider.select((s) => s.isBusy));
    return CheckoutDrawer(
      title: bridge.tr(key: 'waiter.settle'),
      terminalLabel: bridge.tr(key: 'waiter.settle'),
      terminalIcon: 'checkmark.circle',
      placing: busy,
      onClose: () => unawaited(Navigator.of(context).maybePop()),
      headerContent: TicketReviewCard(ticket: widget.ticket),
      onTerminal: (result) => unawaited(_settle(result)),
    );
  }
}
