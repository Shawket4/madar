// The Bill — a screen, not a sheet over a board.
//
// Reached by tapping a table with a bill, a row in Queue › Bills, or a row in
// the waiter's Bills tab. Rounds with the time each went to the kitchen, the
// lines (struck where voided), the running subtotal, and the two things you
// do with a party who has ordered: add to it, or take their money. Both
// shells mount the same screen; only Charge is the teller's.
//
// What the ticket view does not carry is not drawn: readiness is bill-level
// (the server's `ready` status) rather than per round. A single LINE can be
// voided — tap it — which is the ordinary answer to "they sent it back",
// where voiding the whole bill and re-ringing it was the only one before.
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_screen.dart';
import 'package:feature_order/src/tables_screen.dart' show showTablePickerSheet;
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:feature_order/src/words.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// One bill, full screen. A 640 column centred on an iPad; the width on a
/// phone.
class BillScreen extends ConsumerStatefulWidget {
  const BillScreen({required this.ticketId, this.canCharge, super.key});

  final String ticketId;

  /// Whether Charge is offered. The SHELL that mounted the bill decides —
  /// the teller's says yes, the waiter's says no — so the role never has to
  /// be asked down here. Null falls back to the session's role until every
  /// shell passes it.
  final bool? canCharge;

  @override
  ConsumerState<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends ConsumerState<BillScreen>
    with RealtimeGatedPoll<BillScreen> {
  /// "42m" moves by the clock, not by an event.
  Timer? _clock;

  OrderNotifier get _notifier => ref.read(orderProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _notifier.ensureInit().then((_) => _notifier.loadOpenTickets()),
      );
    });
    _clock = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  TicketView? _ticketOf(OrderState s) =>
      s.openTickets.where((t) => t.id == widget.ticketId).firstOrNull;

  String? _tableLabel(OrderState s, TicketView t) =>
      s.floorLayout?.tables.where((x) => x.id == t.tableId).firstOrNull?.label;

  // ── acts ───────────────────────────────────────────────────────────────────

  Future<void> _addRound(TicketView t, String? tableLabel) async {
    if (t.tableId != null) {
      await _notifier.pointCartAtTable(t.tableId!, tableLabel ?? '');
    }
    _notifier.selectTicket(t.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SellScreen.forTable()),
    );
  }

  /// Charge = the ONE tender drawer, over this bill. It takes the money,
  /// prints, and its Done card asks "T5 cleared?" — so nothing is asked
  /// twice here. Once the money is taken the bill is closed and this screen
  /// goes away; the room re-reads after the card is answered either way.
  Future<void> _charge(TicketView t, String title) async {
    final tableLabel = _tableLabel(ref.read(orderProvider), t) ?? title;
    final outcome = await showCharge(
      context,
      ChargeTarget.bill(t, tableLabel: tableLabel),
      onDone: (_, _) => unawaited(_notifier.loadFloor()),
      onPrinterSettings: () => unawaited(showPrinterSheet(context)),
    );
    if (outcome == null || !mounted) return;
    await _notifier.afterBillCharged(t.id);
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// ⋯ — Move table, Void bill. Guest name and covers are not here: nothing
  /// on the bridge updates a ticket's header after its first round.
  Future<void> _more(TicketView t) async {
    final bridge = ref.read(bridgeProvider);
    final hasFloor = ref.read(orderProvider).hasFloor;
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
            if (t.tableId != null && hasFloor)
              MadarButton(
                label: bridge.tr(key: 'tables.move'),
                glyph: MadarGlyph.move,
                variant: MadarButtonVariant.secondary,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  unawaited(_move(t));
                },
              ),
            MadarButton(
              label: orderWord(bridge, 'bill.void_bill'),
              glyph: MadarGlyph.trash,
              variant: MadarButtonVariant.danger,
              onTap: () {
                Navigator.of(sheetContext).maybePop();
                unawaited(_void(t));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Move: the picker IS the room — tap the new table. A free target moves
  /// the party; an occupied one swaps the two.
  Future<void> _move(TicketView t) async {
    final pick = await showTablePickerSheet(
      context,
      ref,
      currentTableId: t.tableId,
      allowClear: false,
    );
    final to = pick?.tableId;
    if (to == null || to == t.tableId || !mounted) return;
    await _notifier.swapTables(t.tableId!, to);
  }

  /// Tap a live line: take that one plate off the bill.
  ///
  /// Only a LIVE line — a voided one is history and there is nothing left to
  /// do to it. The sheet is the bill's own void sheet with the line's words in
  /// the header, so the teller can see which plate they are about to remove.
  Future<void> _voidLine(TicketView t, TicketLineView line) async {
    if (line.voided) return;
    final result = await showMadarSheet<VoidTicketResult>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) =>
          WaiterVoidSheet(ticket: t, lineLabel: '${line.qty}× ${line.name}'),
    );
    if (result == null || !mounted) return;
    await _notifier.voidTicketLine(t.id, line.id, result.reason);
  }

  Future<void> _void(TicketView t) async {
    final result = await showMadarSheet<VoidTicketResult>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => WaiterVoidSheet(ticket: t),
    );
    if (result == null || !mounted) return;
    await _notifier.voidTicket(t.id, result.reason);
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    ref
      ..listen(ticketTickProvider, (_, _) {
        unawaited(_notifier.loadOpenTickets());
      })
      // Settled or voided on another till while this was open: say so and
      // leave, rather than showing a bill that no longer exists.
      ..listen(orderProvider.select(_ticketOf), (prev, next) {
        if (prev == null || next != null || !mounted) return;
        _notifier.showToast(
          orderWord(bridge, 'bill.gone'),
          tone: ChipTone.warning,
          icon: 'xmark.circle',
        );
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    realtimeGatedPoll(
      interval: const Duration(seconds: 15),
      onPoll: () => unawaited(_notifier.loadOpenTickets()),
    );

    final state = ref.watch(orderProvider);
    final layout = MadarLayout.of(context);
    final ticket = _ticketOf(state);
    final canCharge = widget.canCharge ?? !state.isWaiter;
    final currency = state.currency;

    if (ticket == null) {
      return MadarPageScaffold(
        title: orderWord(bridge, 'bill.title'),
        onBack: () => Navigator.of(context).maybePop(),
        body: Column(
          children: [
            Expanded(
              child: state.openTickets.isEmpty && state.isLoadingCatalog
                  ? const SkeletonList(count: 3)
                  : EmptyState(
                      icon: 'doc.text',
                      title: orderWord(bridge, 'bill.gone'),
                    ),
            ),
          ],
        ),
      );
    }

    final tableLabel = _tableLabel(state, ticket);
    final title = tableLabel ?? ticket.customerName ?? ticket.ticketRef ?? '';
    final opened = DateTime.tryParse(ticket.openedAt);
    final seatedFor = opened == null
        ? null
        : formatSeatedFor(DateTime.now().toUtc().difference(opened.toUtc()));
    // On a phone the tag and the ⋯ leave the title no room for a ref, so
    // the ref steps down a line; the table stays the largest thing.
    final refInTitle = layout.isTablet;
    final subtitle = [
      if (!refInTitle && ticket.ticketRef != null && tableLabel != null)
        ticket.ticketRef!,
      if (ticket.guestCount != null && ticket.guestCount! > 0)
        '${ticket.guestCount} ${bridge.tr(key: 'tables.guests')}',
      if (ticket.waiterName?.trim().isNotEmpty ?? false) ticket.waiterName!,
      ?seatedFor,
      if (tableLabel != null &&
          (ticket.customerName?.trim().isNotEmpty ?? false))
        ticket.customerName!,
    ].join(' · ');
    final rounds = groupBillByRound(ticket.lines);
    final ready = ticket.status == 'ready';
    final queued = ticket.queuedOffline || ticket.status == 'queued';

    final header = MadarHeader(
      // Pushed route: nothing above it pays the status-bar inset.
      safeTop: true,
      title: ticket.ticketRef == null || tableLabel == null || !refInTitle
          ? title
          : '$title · ${ticket.ticketRef}',
      subtitle: subtitle.isEmpty ? null : subtitle,
      onBack: () => Navigator.of(context).maybePop(),
      actions: [
        if (ready)
          MadarTag(
            label: orderWord(bridge, 'bill.ready'),
            tone: MadarTone.success,
            glyph: MadarGlyph.checkCircle,
          ),
        if (queued)
          MadarTag(
            label: orderWord(bridge, 'bill.queued'),
            tone: MadarTone.warning,
            glyph: MadarGlyph.half,
          ),
        MadarGlyphTile(
          glyph: MadarGlyph.more,
          semanticLabel: bridge.tr(key: 'chrome.more'),
          onTap: () => unawaited(_more(ticket)),
        ),
      ],
    );

    final body = ListView(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: layout.gutter,
        vertical: Space.md,
      ),
      children: [
        if (rounds.isEmpty)
          MadarCard(
            child: Text(
              bridge.tr(key: 'tables.bill_pending'),
              style: MadarType.body.copyWith(color: colors.textMuted),
            ),
          ),
        for (final round in rounds) ...[
          _RoundCard(
            round: round,
            currency: currency,
            roundWord: bridge.tr(key: 'tables.round'),
            voidedWord: orderWord(bridge, 'bill.voided'),
            onVoidLine: (line) => unawaited(_voidLine(ticket, line)),
            time: round.firedAt.isEmpty
                ? ''
                : bridge.formatTime(
                    rfc3339: round.firedAt,
                    style: TimeStyle.time,
                  ),
          ),
          const SizedBox(height: Space.md),
        ],
        // The bill as the SERVER prices it — the figure the drawer collects.
        // Without one (a fire that has not synced) the subtotal shows, named
        // as a subtotal, rather than passing itself off as a total.
        _BillTotals(
          bill: ticket.bill,
          subtotalMinor: ticket.subtotalMinor,
          currency: currency,
          bridge: bridge,
        ),
      ],
    );

    final addRound = MadarButton(
      label: bridge.tr(key: 'tables.add_round'),
      glyph: MadarGlyph.plus,
      variant: canCharge
          ? MadarButtonVariant.secondary
          : MadarButtonVariant.primary,
      onTap: () => unawaited(_addRound(ticket, tableLabel)),
    );
    final charge = canCharge
        ? MadarMoneyBar(
            label: orderWord(bridge, 'sell.charge'),
            // What the drawer will actually take. The button used to say the
            // subtotal while the tender screen collected the total — the same
            // discrepancy, on the same bill, one tap apart.
            amountMinor: ticket.bill?.totalMinor ?? ticket.subtotalMinor,
            currency: currency,
            enabled: state.shiftOpen && !state.isBusy,
            reason: state.shiftOpen
                ? null
                : bridge.tr(key: 'waiter.need_shift'),
            loading: state.isBusy,
            onTap: () => unawaited(_charge(ticket, title)),
          )
        : null;
    // Side by side on an iPad; stacked on a phone, where a money bar with
    // its figure and a labelled button do not share 358 points.
    final footer = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        layout.gutter,
        Space.md,
        layout.gutter,
        Space.md,
      ),
      child: layout.isTablet || charge == null
          ? Row(
              spacing: Space.md,
              children: [
                Expanded(child: addRound),
                if (charge != null) Expanded(child: charge),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [addRound, charge],
            ),
    );

    return MadarPageScaffold(
      gutter: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.billMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  layout.gutter,
                  Space.md,
                  layout.gutter,
                  0,
                ),
                child: header,
              ),
              Expanded(child: body),
              const MadarHairline(),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}

/// The money at the foot of a bill.
///
/// One card, and which lines it shows is decided by what the server sent: a
/// discount line only when something was taken off, a service line only when
/// one was charged, and the tax line worded by whether the menu prices already
/// contain it. The hero is the TOTAL — what the drawer collects — except on a
/// bill the server has not priced yet, where it is honestly a subtotal.
class _BillTotals extends StatelessWidget {
  const _BillTotals({
    required this.bill,
    required this.subtotalMinor,
    required this.currency,
    required this.bridge,
  });

  final TicketBillView? bill;
  final int subtotalMinor;
  final String currency;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final b = bill;
    Widget line(String label, int minor, {bool negative = false}) => Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: MadarType.body.copyWith(color: colors.textSecondary),
            ),
          ),
          MoneyText(
            negative ? -minor : minor,
            currency: currency,
            style: MadarType.money,
            color: colors.textSecondary,
          ),
        ],
      ),
    );
    final rate = b == null || b.taxRate <= 0
        ? ''
        : ' ${Money.ratePercent(b.taxRate)}%';
    return MadarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (b != null) ...[
            line(bridge.tr(key: 'order.subtotal'), b.subtotalMinor),
            if (b.discountMinor > 0)
              line(
                bridge.tr(key: 'order.discount'),
                b.discountMinor,
                negative: true,
              ),
            if (b.serviceChargeMinor > 0)
              line(
                bridge.tr(key: 'order.service_charge'),
                b.serviceChargeMinor,
              ),
            // Inclusive tax is already inside the total, so it reads as a
            // note under it rather than a term added to it.
            if (b.taxMinor > 0 && !b.taxInclusive)
              line('${bridge.tr(key: 'order.tax')}$rate', b.taxMinor),
            const MadarHairline(),
            const SizedBox(height: Space.xs),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  bridge.tr(key: b == null ? 'order.subtotal' : 'order.total'),
                  style: MadarType.h3.copyWith(color: colors.textPrimary),
                ),
              ),
              MoneyText(
                b?.totalMinor ?? subtotalMinor,
                currency: currency,
                style: MadarType.moneyLg,
                color: colors.textPrimary,
              ),
            ],
          ),
          if (b != null && b.taxInclusive && b.taxMinor > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: Space.xs),
              child: Text(
                '${bridge.tr(key: 'charge.vat_included')}$rate '
                '${Money.format(b.taxMinor, currency: currency)}',
                style: MadarType.bodySm.copyWith(color: colors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// One round: "ROUND 1 · 19:02" over its lines.
class _RoundCard extends StatelessWidget {
  const _RoundCard({
    required this.round,
    required this.currency,
    required this.roundWord,
    required this.voidedWord,
    required this.time,
    required this.onVoidLine,
  });

  final BillRound round;
  final String currency;
  final String roundWord;
  final String voidedWord;
  final String time;
  final void Function(TicketLineView line) onVoidLine;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return MadarCard(
      flush: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.card,
              Space.lg,
              Space.card,
              Space.xs,
            ),
            child: MadarSectionHeader(
              text: '$roundWord ${round.number}',
              trailing: time.isEmpty
                  ? null
                  : Text(
                      time,
                      textDirection: TextDirection.ltr,
                      style: MadarType.num.copyWith(color: colors.textMuted),
                    ),
            ),
          ),
          for (final line in round.lines)
            MadarRow(
              dense: true,
              // A voided line is history: nothing to tap.
              onTap: line.voided ? null : () => onVoidLine(line),
              title: '${line.qty}× ${line.name}',
              titleStyle: line.voided
                  ? MadarType.title.copyWith(
                      color: colors.textMuted,
                      decoration: TextDecoration.lineThrough,
                    )
                  : null,
              subtitle: [
                if (line.sizeLabel case final s? when s.isNotEmpty) s,
                ...line.modifiers,
              ].join(' · ').ifEmptyNull,
              trailing: line.voided
                  ? MadarTag(label: voidedWord, tone: MadarTone.danger)
                  : null,
              value: MoneyText(
                line.lineTotalMinor,
                currency: currency,
                color: line.voided ? colors.textMuted : colors.textPrimary,
                style: line.voided
                    ? MadarType.money.copyWith(
                        decoration: TextDecoration.lineThrough,
                      )
                    : null,
              ),
            ),
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
