/// Queue › Bills — the bills waiting to be charged, kitchen-ready first.
///
/// One flush card of 64px rows: the state bar carries the bill's colour,
/// the title is the table ("T3") or, where there is no floor, the guest;
/// the figure is the bill's TOTAL as the server priced it — the same figure
/// Charge will take — or its subtotal while it is still unpriced; Charge sits
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
      }),
    );
  }

  /// A bill or a Charge on its way. A second tap while the first is opening
  /// stacked two drawers over one bill.
  bool _busy = false;

  Future<void> _guarded(Future<void> Function() op) async {
    if (_busy) return;
    _busy = true;
    try {
      await op();
    } finally {
      if (mounted) _busy = false;
    }
  }

  Future<void> _open(TicketView ticket) async {
    ref.read(incomingProvider.notifier).clearError();
    final openBill = widget.onOpenBill;
    if (openBill != null) {
      await openBill(context, ticket);
      return;
    }
    final bridge = ref.read(bridgeProvider);
    final tillOpen = ref.read(shellProvider).tillOpen;
    final charge = await showMadarSheet<bool>(
      context,
      size: SheetSize.large,
      maxWidth: Responsive.listMaxWidth,
      builder: (sheetContext) => TicketDetailsSheet(
        ticket: ticket,
        footer: MadarMoneyBar(
          label: bridge.trOr(QueueKeys.chargeBill),
          amountMinor: ticket.bill?.totalMinor ?? ticket.subtotalMinor,
          currency: bridge.currentSession()?.currencyCode ?? '',
          enabled: tillOpen && !ticket.queuedOffline,
          reason: ticket.queuedOffline
              ? bridge.tr(key: 'queue.bill_not_synced')
              : bridge.trOr(QueueKeys.needTill),
          onTap: () => Navigator.of(sheetContext).maybePop(true),
        ),
      ),
    );
    if (!mounted || charge != true) return;
    await _charge(ticket);
  }

  /// Charge = the ONE tender drawer (the same one the counter and the Bill
  /// use), over this bill. Stays on the list after charging — the bill drops
  /// out on reload — and the shell learns a sale landed on the till.
  Future<void> _charge(TicketView ticket) async {
    // A bill still in the outbox has no server id to settle against.
    if (ticket.queuedOffline) return;
    ref.read(incomingProvider.notifier).clearError();
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

  /// The bill shown in the pane beside the list (wide layouts only).
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final bills = ref.watch(
      incomingProvider.select((s) => s.settleableTickets),
    );
    final loaded = ref.watch(incomingProvider.select((s) => s.ticketsLoaded));
    final labels = ref.watch(incomingProvider.select((s) => s.tableLabels));
    final hasFloor = ref.watch(incomingProvider.select((s) => s.hasFloor));
    // Charge books onto THE till — the shell's, the one owner.
    final tillOpen = ref.watch(shellProvider.select((s) => s.tillOpen));
    final error = ref.watch(incomingProvider.select((s) => s.error));
    final currency = ref.watch(
      shellProvider.select((s) => s.session?.currencyCode ?? ''),
    );
    final layout = context.madarLayout;
    String t(String key) => bridge.tr(key: key);

    String titleOf(TicketView b) {
      final label = b.tableId == null ? null : labels[b.tableId!];
      final guest = b.customerName;
      return label ??
          ((guest != null && guest.isNotEmpty)
              ? guest
              : (b.ticketRef ?? bridge.trOr(QueueKeys.noTable)));
    }

    MadarStatus statusOf(TicketView b) {
      if (b.queuedOffline) {
        return MadarStatus(
          t('waiter.queued'),
          tone: MadarTone.warning,
          glyph: MadarGlyph.wifiOff,
        );
      }
      return MadarStatus(
        t('ticket.status.${b.status}'),
        tone: ticketTone(b.status),
      );
    }

    final chargeReady = tillOpen;
    Widget chargeFor(TicketView b) => MadarButton(
      label: bridge.trOr(QueueKeys.chargeBill),
      size: MadarButtonSize.compact,
      // A bill still queued offline cannot be settled yet: the button used
      // to look ready and end in an error. Its status says why.
      enabled: chargeReady && !b.queuedOffline,
      tooltip: b.queuedOffline
          ? t('queue.bill_not_synced')
          : chargeReady
          ? null
          : bridge.trOr(QueueKeys.needTill),
      onTap: () => unawaited(_guarded(() => _charge(b))),
    );

    final MadarTableState<TicketView> tableState;
    if (!loaded) {
      tableState = const MadarTableState.loading(rows: 4);
    } else if (error != null && bills.isEmpty) {
      tableState = MadarTableState.error(
        message: error.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: () =>
            unawaited(ref.read(incomingProvider.notifier).loadOpenTickets()),
      );
    } else {
      tableState = MadarTableState.data(bills);
    }

    // Wide enough for the list AND a readable bill beside it: the bill opens
    // in place and the row keeps its one Charge. Narrower, a row opens the
    // Bill as before.
    final screen = MediaQuery.sizeOf(context).width;
    final content =
        screen - 2 * layout.gutter - (layout.isPhone ? 0 : Metrics.railWidth);
    final split = !layout.isPhone && content >= kQueueSplitMinWidth;
    final selected = split
        ? bills.where((b) => b.id == _selectedId).firstOrNull ??
              bills.firstOrNull
        : null;

    final table = MadarDataTable<TicketView>(
      state: tableState,
      // A short or empty list still pulls to refresh.
      physics: MadarRefresh.physics,
      rowKey: (b) => b.id,
      empty: MadarEmptyContent(
        title: bridge.trOr(QueueKeys.emptyBills),
        message: t('queue.empty_bills_hint'),
      ),
      columns: [
        MadarColumn(
          id: 'table',
          label: hasFloor ? t('order.table') : t('order.customer'),
          text: titleOf,
          emphasis: true,
          flex: 2,
          phone: MadarPhoneRole.title,
        ),
        MadarColumn.status(
          id: 'status',
          label: t('queue.col_status'),
          status: statusOf,
          width: 150,
        ),
        MadarColumn(
          id: 'waiter',
          label: t('order.waiter'),
          // A name is its own direction: isolated, a Latin name in an Arabic
          // meta line no longer drags the figures beside it out of order.
          text: (b) =>
              b.waiterName == null ? '' : '\u2068${b.waiterName}\u2069',
          flex: 2,
          priority: 2,
        ),
        MadarColumn(
          id: 'opened',
          label: t('queue.col_open_for'),
          text: (b) => bridge.formatElapsedSince(rfc3339: b.openedAt),
          mono: true,
          muted: true,
          width: 96,
          priority: 1,
        ),
        MadarColumn.money(
          id: 'total',
          label: t('order.total'),
          // The server's priced total — what Charge will take — when it has
          // one; only an unsynced fire shows its subtotal.
          minor: (b) => b.bill?.totalMinor ?? b.subtotalMinor,
          currency: currency,
          width: 132,
        ),
        // The row's ONE action, in its own column so every row's Charge
        // lines up and a row without a status never knocks the figures over.
        MadarColumn(
          id: 'charge',
          label: '',
          cell: (context, b) => chargeFor(b),
          width: 116,
          align: MadarColumnAlign.end,
          phone: MadarPhoneRole.hidden,
        ),
      ],
      rail: (b) => b.queuedOffline ? MadarTone.warning : ticketTone(b.status),
      selected: split ? (b) => b.id == selected?.id : null,
      onTap: (b) => split
          ? setState(() => _selectedId = b.id)
          : unawaited(_guarded(() => _open(b))),
      chevron: false,
      // The phone's collapsed rows carry Charge in the trailing slot; the
      // wide table has its column.
      trailing: layout.isPhone ? (context, b) => chargeFor(b) : null,
    );

    final banners = <Widget>[
      // Charge books onto THIS till's till. Say so once, at the top, instead
      // of every row's button greyed with no reason.
      if (!tillOpen)
        NoticeBanner(text: bridge.trOr(QueueKeys.needTill), icon: 'lock'),
      if (error != null && bills.isNotEmpty)
        NoticeBanner(
          text: error.of(bridge),
          tone: ChipTone.danger,
          icon: 'exclamationmark.circle',
        ),
    ];

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        ...banners,
        Flexible(child: table),
      ],
    );

    final Widget body;
    if (split) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.lg,
        children: [
          Expanded(child: list),
          SizedBox(
            width: queuePaneWidth(content),
            child: selected == null
                ? const SizedBox.shrink()
                : MadarCard(
                    flush: true,
                    child: TicketDetailsSheet(
                      key: ValueKey('pane-${selected.id}'),
                      ticket: selected,
                      tableLabel: selected.tableId == null
                          ? null
                          : labels[selected.tableId!],
                      footer: _PaneFooter(
                        ticket: selected,
                        currency: currency,
                        chargeReady: chargeReady,
                        onCharge: () =>
                            unawaited(_guarded(() => _charge(selected))),
                        onOpenBill: widget.onOpenBill == null
                            ? null
                            : () => unawaited(
                                _guarded(
                                  () => widget.onOpenBill!(context, selected),
                                ),
                              ),
                      ),
                    ),
                  ),
          ),
        ],
      );
    } else {
      body = list;
    }

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        layout.gutter,
        Space.lg,
        layout.gutter,
        Space.lg,
      ),
      child: body,
    );
  }
}

/// Under the bill in the pane: Charge with the figure it takes, and the way
/// into the full Bill (rounds, voids, moves).
class _PaneFooter extends ConsumerWidget {
  const _PaneFooter({
    required this.ticket,
    required this.currency,
    required this.chargeReady,
    required this.onCharge,
    required this.onOpenBill,
  });

  final TicketView ticket;
  final String currency;
  final bool chargeReady;
  final VoidCallback onCharge;
  final VoidCallback? onOpenBill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        MadarMoneyBar(
          label: bridge.trOr(QueueKeys.chargeBill),
          amountMinor: ticket.bill?.totalMinor ?? ticket.subtotalMinor,
          currency: currency,
          enabled: chargeReady && !ticket.queuedOffline,
          reason: ticket.queuedOffline
              ? bridge.tr(key: 'queue.bill_not_synced')
              : chargeReady
              ? null
              : bridge.trOr(QueueKeys.needTill),
          onTap: onCharge,
        ),
        if (onOpenBill != null)
          MadarButton(
            label: bridge.tr(key: 'queue.open_bill'),
            glyph: MadarGlyph.receipt,
            variant: MadarButtonVariant.secondary,
            onTap: onOpenBill!,
          ),
      ],
    );
  }
}
