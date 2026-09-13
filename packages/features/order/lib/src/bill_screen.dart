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
import 'package:feature_order/src/table_history_sheet.dart';
import 'package:feature_order/src/tables_screen.dart'
    show moveParty, showTablePickerSheet;
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:feature_order/src/words.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// What a bill screen hands back to whoever pushed it when it closes itself
/// for a reason the opener acts on.
enum BillExit {
  /// "Table actions": back to the room, with this table's floor sheet open.
  tableActions,
}

/// One bill, full screen. A 640 column centred on an iPad; the width on a
/// phone.
class BillScreen extends ConsumerStatefulWidget {
  const BillScreen({
    required this.ticketId,
    this.canCharge,
    this.chargeOnOpen = false,
    super.key,
  });

  final String ticketId;

  /// Opened from a table's Charge: go straight to the tender drawer once the
  /// bill is in hand (when this shell charges at all).
  final bool chargeOnOpen;

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
        _notifier.ensureInit().then((_) => _notifier.loadOpenTickets()).then((
          _,
        ) {
          if (!mounted || !widget.chargeOnOpen) return;
          final s = ref.read(orderProvider);
          final t = _ticketOf(s);
          if (t != null && (widget.canCharge ?? !s.isWaiter) && s.shiftOpen) {
            unawaited(_charge(t, _tableLabel(s, t) ?? t.ticketRef ?? ''));
          }
        }),
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
    final table = t.tableId;
    if (table != null) {
      // The table's own cart; it finds this bill by the table.
      await MadarPages.push<void>(
        context,
        (_) => TableOrderScreen(tableId: table),
      );
      return;
    }
    // A table-less bill rides the counter cart for as long as the round is
    // being built, and lets it go again on the way back.
    final cart = _notifier.cartOf(null)..selectTicket(t.id);
    await MadarPages.push<void>(
      context,
      (_) => const TakeawaySellScreen(pushed: true),
    );
    cart.selectTicket(null);
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

  /// ⋯ — Move table, Void bill (and, on a phone, History and Unseat). Guest name and covers are not here: nothing
  /// on the bridge updates a ticket's header after its first round.
  Future<void> _more(TicketView t, {bool phone = false}) async {
    final bridge = ref.read(bridgeProvider);
    final hasFloor = ref.read(orderProvider).hasFloor;
    final label = ref
        .read(orderProvider)
        .floorLayout
        ?.tables
        .where((x) => x.id == t.tableId)
        .firstOrNull
        ?.label;
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
            if (phone && t.tableId != null && label != null)
              MadarButton(
                label: bridge.tr(key: 'tables.history'),
                glyph: MadarGlyph.clock,
                variant: MadarButtonVariant.secondary,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  unawaited(
                    showTableHistory(
                      context,
                      tableId: t.tableId!,
                      label: label,
                    ),
                  );
                },
              ),
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
            if (phone && t.tableId != null)
              MadarButton(
                label: orderWord(bridge, 'floor.unseat'),
                glyph: MadarGlyph.users,
                variant: MadarButtonVariant.ghost,
                onTap: () {
                  Navigator.of(sheetContext).maybePop();
                  unawaited(_unseat(t));
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
  /// the party; an occupied one swaps the two, after saying so. The toast
  /// offers Undo only once the core has actually moved them.
  Future<void> _move(TicketView t) async {
    final from = t.tableId;
    if (from == null) return;
    final pick = await showTablePickerSheet(
      context,
      ref,
      currentTableId: from,
      allowClear: false,
      forMove: true,
    );
    final to = pick?.tableId;
    if (to == null || !mounted) return;
    await moveParty(context, ref, from: from, to: to);
  }

  /// Unseat, from the bill. A table with a bill is not unseated around it —
  /// the party's money would vanish from the room — so this says what does
  /// free it (charge or void) and offers the void.
  Future<void> _unseat(TicketView t) async {
    final bridge = ref.read(bridgeProvider);
    final ok = await showMadarConfirm(
      context,
      title: orderWord(bridge, 'floor.unseat'),
      body: orderWord(bridge, 'bill.unseat_has_bill'),
      confirmLabel: orderWord(bridge, 'bill.void_bill'),
      cancelLabel: bridge.tr(key: 'common.cancel'),
    );
    if (ok && mounted) await _void(t);
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
        : MadarFormat.elapsed(
            DateTime.now().toUtc().difference(opened.toUtc()),
            locale: ref.watch(localeProvider).locale,
          );
    // On a phone the tag and the ⋯ leave the title no room for a ref, so
    // the ref steps down a line; the table stays the largest thing.
    final subtitle = [
      if (ticket.ticketRef != null && tableLabel != null)
        MadarFormat.ltr(ticket.ticketRef!),
      if (ticket.guestCount != null && ticket.guestCount! > 0)
        '${ticket.guestCount} ${bridge.tr(key: 'tables.guests')}',
      if (ticket.waiterName?.trim().isNotEmpty ?? false) ticket.waiterName!,
      ?seatedFor,
      if (tableLabel != null &&
          (ticket.customerName?.trim().isNotEmpty ?? false))
        ticket.customerName!,
    ].join(' · ');
    final rounds = groupBillByRound(ticket.lines);
    final ready = ticket.ready;
    final queued = ticket.queuedOffline || ticket.status == 'queued';

    final pills = <Widget>[
      if (ready)
        MadarStatusPill(
          MadarStatus(
            orderWord(bridge, 'bill.ready'),
            tone: MadarTone.success,
            glyph: MadarGlyph.checkCircle,
          ),
        ),
      if (queued)
        MadarStatusPill(
          MadarStatus(
            orderWord(bridge, 'bill.queued'),
            tone: MadarTone.warning,
            glyph: MadarGlyph.wifiOff,
          ),
        ),
    ];
    // A phone's header has room for the ⋯ alone; the doors move into it.
    final wide = layout.isTablet;
    final headerActions = <Widget>[
      if (wide) ...pills,
      // The table's own doors, from its bill: where it has been, where the
      // party goes next, unseating, and back to the table's floor sheet.
      if (wide && ticket.tableId != null && tableLabel != null)
        MadarGlyphTile(
          key: const ValueKey('bill.history'),
          glyph: MadarGlyph.clock,
          semanticLabel: bridge.tr(key: 'tables.history'),
          onTap: () => unawaited(
            showTableHistory(
              context,
              tableId: ticket.tableId!,
              label: tableLabel,
            ),
          ),
        ),
      if (wide && ticket.tableId != null && state.hasFloor)
        MadarGlyphTile(
          key: const ValueKey('bill.move'),
          glyph: MadarGlyph.move,
          semanticLabel: bridge.tr(key: 'tables.move'),
          onTap: () => unawaited(_move(ticket)),
        ),
      if (wide && ticket.tableId != null)
        MadarGlyphTile(
          key: const ValueKey('bill.unseat'),
          glyph: MadarGlyph.users,
          semanticLabel: orderWord(bridge, 'floor.unseat'),
          onTap: () => unawaited(_unseat(ticket)),
        ),
      if (wide && ticket.tableId != null && state.hasFloor)
        MadarGlyphTile(
          key: const ValueKey('bill.table_actions'),
          glyph: MadarGlyph.table,
          semanticLabel: orderWord(bridge, 'floor.table_actions'),
          onTap: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.pop(BillExit.tableActions);
          },
        ),
      MadarGlyphTile(
        glyph: MadarGlyph.more,
        semanticLabel: bridge.tr(key: 'chrome.more'),
        onTap: () => unawaited(_more(ticket, phone: !wide)),
      ),
    ];

    final roundsColumn = <Widget>[
      if (!wide && pills.isNotEmpty) ...[
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: pills),
        const SizedBox(height: Space.lg),
      ],
      if (rounds.isEmpty)
        MadarCard(
          child: Text(
            bridge.tr(key: 'tables.bill_pending'),
            style: MadarType.body.copyWith(color: colors.textMuted),
          ),
        ),
      for (final (i, round) in rounds.indexed) ...[
        if (i > 0) const SizedBox(height: Space.xl),
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
      ],
    ];
    // The bill as the SERVER prices it — the figure the drawer collects.
    final totals = _BillTotals(
      bill: ticket.bill,
      subtotalMinor: ticket.subtotalMinor,
      currency: currency,
      bridge: bridge,
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
            // What the drawer will actually take — the total, not the lines.
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

    return MadarPageScaffold(
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      width: MadarContentWidth.full,
      actions: headerActions,
      body: LayoutBuilder(
        builder: (context, box) {
          // Wide: the rounds at the start, the money and its two acts in a
          // column at the end — the total never scrolls away from Charge.
          if (layout.isTablet && box.maxWidth >= 860) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
                    children: roundsColumn,
                  ),
                ),
                const SizedBox(width: Space.xl),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.md,
                      children: [totals, ?charge, addRound],
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
                  children: [
                    ...roundsColumn,
                    const SizedBox(height: Space.xl),
                    totals,
                  ],
                ),
              ),
              const MadarHairline(),
              Padding(
                padding: EdgeInsetsDirectional.only(
                  top: Space.md,
                  bottom: Space.md + MediaQuery.paddingOf(context).bottom,
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
                        children: [charge, addRound],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The money at the foot of a bill, as summary lines in one card.
///
/// Which lines show is decided by what the server sent: a discount only when
/// something was taken off, service only when charged, tax worded by whether
/// the menu prices already contain it. The emphasised line is the TOTAL — what
/// the drawer collects — except on a bill the server has not priced yet,
/// where it is honestly a subtotal.
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
    final rate = b == null || b.taxRate <= 0
        ? ''
        : ' ${Money.ratePercent(b.taxRate)}%';
    return MadarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (b != null) ...[
            MadarSummaryLine(
              label: bridge.tr(key: 'order.subtotal'),
              minor: b.subtotalMinor,
              currency: currency,
            ),
            if (b.discountMinor > 0)
              MadarSummaryLine(
                label: bridge.tr(key: 'order.discount'),
                minor: -b.discountMinor,
                currency: currency,
              ),
            if (b.serviceChargeMinor > 0)
              MadarSummaryLine(
                label: bridge.tr(key: 'order.service_charge'),
                minor: b.serviceChargeMinor,
                currency: currency,
              ),
            // Inclusive tax is already inside the total: a note under it,
            // not a term added to it.
            if (b.taxMinor > 0 && !b.taxInclusive)
              MadarSummaryLine(
                label: '${bridge.tr(key: 'order.tax')}$rate',
                minor: b.taxMinor,
                currency: currency,
              ),
            const SizedBox(height: Space.xs),
            const MadarHairline(light: true),
          ],
          MadarSummaryLine(
            label: bridge.tr(key: b == null ? 'order.subtotal' : 'order.total'),
            minor: b?.totalMinor ?? subtotalMinor,
            currency: currency,
            emphasis: true,
          ),
          if (b != null && b.taxInclusive && b.taxMinor > 0)
            Text(
              '${bridge.tr(key: 'charge.vat_included')}$rate '
              '${Money.format(b.taxMinor, currency: currency, locale: MadarFormat.localeOf(context))}',
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// One round: a section header ("ROUND 1", its time) over a card of lines.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MadarSectionHeader(
          text: '$roundWord ${round.number}',
          trailing: time.isEmpty
              ? null
              : Text(
                  time,
                  textDirection: TextDirection.ltr,
                  style: MadarType.num.copyWith(color: colors.textMuted),
                ),
        ),
        const SizedBox(height: Space.md),
        MadarCard(
          flush: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, line) in round.lines.indexed) ...[
                if (i > 0) const MadarHairline(light: true),
                MadarRow(
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
                      ? MadarStatusPill(
                          MadarStatus(voidedWord, tone: MadarTone.danger),
                        )
                      : null,
                  chevron: false,
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
              ],
            ],
          ),
        ),
      ],
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
