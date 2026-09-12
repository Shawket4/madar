/// Queue › Bills — the bills waiting to be charged, kitchen-ready first.
///
/// One flush card of 64px rows: the state bar carries the bill's colour,
/// the title is the table ("T3") or, where there is no floor, the guest;
/// the figure is the bill's SUBTOTAL (all `TicketView` carries); Charge sits
/// on the row so the commonest act is one tap. A row tap opens the Bill —
/// the host's screen when it supplies one, else the shared details sheet.
/// Live: the screen reloads on the shell's ticket tick, so a waiter's fire
/// or round from another device shows at once.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_incoming/src/details_sheets.dart';
import 'package:feature_incoming/src/incoming_provider.dart';
import 'package:feature_incoming/src/queue_strings.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Opens the Bill for a ticket — supplied by the host shell, which owns
/// the Bill screen (feature_order). Null falls back to the details sheet.
typedef OpenBill = Future<void> Function(BuildContext context, TicketView t);

class BillsSegment extends ConsumerStatefulWidget {
  const BillsSegment({this.onOpenBill, super.key});

  final OpenBill? onOpenBill;

  @override
  ConsumerState<BillsSegment> createState() => _BillsSegmentState();
}

class _BillsSegmentState extends ConsumerState<BillsSegment> {
  @override
  void initState() {
    super.initState();
    // (Re)entering the segment refreshes the board — deferred a microtask
    // because provider writes are illegal while the tree is building.
    unawaited(
      Future<void>.microtask(() {
        if (!mounted) return;
        final n = ref.read(incomingProvider.notifier);
        unawaited(n.loadOpenTickets());
        unawaited(n.loadShift());
      }),
    );
  }

  Future<void> _open(TicketView ticket) async {
    final openBill = widget.onOpenBill;
    if (openBill != null) {
      await openBill(context, ticket);
      return;
    }
    final bridge = ref.read(bridgeProvider);
    final shiftOpen = ref.read(incomingProvider).shiftOpen ?? false;
    final charge = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: Responsive.listMaxWidth,
      builder: (sheetContext) => TicketDetailsSheet(
        ticket: ticket,
        footer: MadarMoneyBar(
          label: bridge.trOr(QueueKeys.chargeBill),
          amountMinor: ticket.subtotalMinor,
          currency: bridge.currentSession()?.currencyCode ?? '',
          enabled: shiftOpen,
          reason: bridge.trOr(QueueKeys.needShift),
          onTap: () => Navigator.of(sheetContext).maybePop(true),
        ),
      ),
    );
    if (!mounted || charge != true) return;
    await _charge(ticket);
  }

  /// Charge = the ONE tender drawer (the same one the counter and the Bill
  /// use), over this bill. Stays on the list after charging — the bill drops
  /// out on reload — and the shell learns a sale landed on the shift.
  Future<void> _charge(TicketView ticket) async {
    final labels = ref.read(incomingProvider).tableLabels;
    final tableId = ticket.tableId;
    final outcome = await showCharge(
      context,
      ChargeTarget.bill(
        ticket,
        tableLabel: tableId == null ? null : labels[tableId],
      ),
    );
    if (outcome == null || !mounted) return;
    await ref.read(incomingProvider.notifier).loadOpenTickets();
    ref.read(shellProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final bills = ref.watch(
      incomingProvider.select((s) => s.settleableTickets),
    );
    final labels = ref.watch(incomingProvider.select((s) => s.tableLabels));
    final hasFloor = ref.watch(incomingProvider.select((s) => s.hasFloor));
    final shiftOpen = ref.watch(incomingProvider.select((s) => s.shiftOpen));
    final error = ref.watch(incomingProvider.select((s) => s.error));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final layout = context.madarLayout;
    return ListView(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: layout.gutter,
        vertical: Space.lg,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Responsive.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                // Charge books onto THIS till's shift. Say so once, at the
                // top, instead of forty disabled buttons with no reason.
                if (shiftOpen == false)
                  NoticeBanner(
                    text: bridge.trOr(QueueKeys.needShift),
                    icon: 'lock',
                  ),
                if (error != null)
                  NoticeBanner(
                    text: error,
                    tone: ChipTone.danger,
                    icon: 'exclamationmark.circle',
                  ),
                if (bills.isEmpty)
                  QuietEmpty(bridge.trOr(QueueKeys.emptyBills))
                else
                  MadarCard(
                    flush: true,
                    child: Column(
                      children: [
                        for (final (i, t) in bills.indexed) ...[
                          if (i > 0) const MadarHairline.row(),
                          _BillRow(
                            key: ValueKey(t.id),
                            ticket: t,
                            tableLabel: t.tableId == null
                                ? null
                                : labels[t.tableId!],
                            hasFloor: hasFloor,
                            currency: currency,
                            chargeEnabled: shiftOpen ?? false,
                            onOpen: () => unawaited(_open(t)),
                            onCharge: () => unawaited(_charge(t)),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.xxl),
      ],
    );
  }
}

/// One bill: bar = state, title = table (or guest / ref), meta = state ·
/// covers · waiter · opened-at, figure = subtotal, then Charge.
class _BillRow extends ConsumerWidget {
  const _BillRow({
    required this.ticket,
    required this.tableLabel,
    required this.hasFloor,
    required this.currency,
    required this.chargeEnabled,
    required this.onOpen,
    required this.onCharge,
    super.key,
  });

  final TicketView ticket;
  final String? tableLabel;
  final bool hasFloor;
  final String currency;
  final bool chargeEnabled;
  final VoidCallback onOpen;
  final VoidCallback onCharge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final t = ticket;
    final tone = ticketTone(t.status);
    final guest = t.customerName;
    final waiter = t.waiterName;
    final phone = context.isPhone;
    // Title: the table where there is one; a floorless shop (or a bill fired
    // without a table) leads with the guest, then the ref.
    final title =
        tableLabel ??
        ((guest != null && guest.isNotEmpty)
            ? guest
            : (t.ticketRef ?? bridge.trOr(QueueKeys.noTable)));
    final meta = <String>[
      if (t.queuedOffline)
        bridge.tr(key: 'waiter.queued')
      else
        bridge.tr(key: 'ticket.status.${t.status}'),
      // A phone row has room for the state and the clock; covers, guest
      // and waiter wait for the Bill (or a tablet).
      if (t.guestCount case final n? when !phone && n > 0)
        '$n ${bridge.tr(key: 'waiter.covers')}',
      if (!phone && tableLabel != null && guest != null && guest.isNotEmpty)
        guest,
      if (!phone && waiter != null && waiter.isNotEmpty) waiter,
      clockLabel(bridge, t.openedAt),
    ].where((s) => s.isNotEmpty).toList(growable: false);
    return MadarRow(
      bar: tone.color(colors),
      title: title,
      subtitle: meta.join(' · '),
      onTap: onOpen,
      // The row's own Charge is the affordance; a chevron beside a button
      // is two arrows pointing at one thing.
      chevron: !phone,
      value: MoneyText(
        t.subtotalMinor,
        currency: currency,
        style: phone ? MadarType.money : MadarType.moneyMd,
        color: colors.textPrimary,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          // The word for the state rides as a tag where there is room; on
          // a phone the bar's colour and the meta line already carry it,
          // and the title needs the width more.
          if (!phone && t.queuedOffline)
            MadarTag(
              label: bridge.tr(key: 'waiter.queued'),
              tone: MadarTone.warning,
              glyph: MadarGlyph.half,
            )
          else if (!phone && t.status == 'ready')
            MadarTag(
              label: bridge.tr(key: 'ticket.status.ready'),
              tone: MadarTone.success,
              glyph: MadarGlyph.check,
            ),
          MadarButton(
            label: bridge.trOr(QueueKeys.chargeBill),
            size: MadarButtonSize.compact,
            enabled: chargeEnabled,
            tooltip: chargeEnabled ? null : bridge.trOr(QueueKeys.needShift),
            onTap: onCharge,
          ),
        ],
      ),
    );
  }
}
