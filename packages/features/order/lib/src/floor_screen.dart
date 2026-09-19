// The Floor — the room, plan-first on an iPad and list-first on a phone,
// with a labelled Plan / List segment on both.
//
// Status is the server's, derived from the occupancy ledger; the till asks
// for changes and shows what it cached. ONE tap, ONE sheet, contents by
// state: a free table asks for a party size and seats; a seated table with
// no bill offers Take an order / Move / Unseat; a table with a bill opens
// the Bill screen; a table waiting to be bussed offers Cleared; a table kept
// for a booking offers Seat this party / No-show / Walk-in.
//
// Seating a party takes the table and opens NOTHING — the bill starts with
// the first round. The plan is drawn by `FloorCanvas` (shared with the table
// picker; never mirrored in RTL because a room is physical space) and the
// list by `FloorListView` (a worklist: needs clearing → ready → longest
// seated → booked → free).
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart';
import 'package:feature_order/src/bill_screen.dart';
import 'package:feature_order/src/floor_inspector.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_screen.dart';
import 'package:feature_order/src/table_clear_prompt.dart';
import 'package:feature_order/src/table_history_sheet.dart';
import 'package:feature_order/src/tables_screen.dart'
    show
        FloorCanvas,
        TableStatusWords,
        moveParty,
        showTablePickerSheet,
        tableHasBooking,
        tableIsMoveTarget,
        tableIsReserved;
import 'package:feature_order/src/waiter_sheets.dart';
import 'package:feature_order/src/words.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Plan or list.
enum FloorView { plan, list }

/// Tab id for tables that belong to no section (or an orphaned one).
const String _kNoSection = '__no_section__';

/// The Floor.
class FloorScreen extends ConsumerStatefulWidget {
  const FloorScreen({this.canCharge, super.key});

  /// Handed to the Bill a table opens — see [BillScreen.canCharge].
  final bool? canCharge;

  @override
  ConsumerState<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends ConsumerState<FloorScreen> {
  String? _sectionId;

  /// Null until the first build picks the device's default: list on a phone,
  /// plan on a tablet. A person's choice then sticks for the screen's life.
  FloorView? _view;

  /// A move in progress: the table the party is leaving.
  String? _moveFrom;

  /// The table the inspector shows (iPad and desktop); null = the worklist.
  String? _selectedId;

  /// A reserved table a walk-in is being seated at instead.
  String? _walkInId;

  /// The status summary chip that narrows the room; null = everything.
  FloorUrgency? _filter;

  /// A reserved table flips by the clock (`held_from`), and "seated 12m"
  /// ages; a once-a-minute tick keeps both honest between pulls.
  Timer? _clock;

  OrderNotifier get _notifier => ref.read(orderProvider.notifier);
  MadarBridge get _bridge => ref.read(bridgeProvider);
  String _w(String key) => orderWord(_bridge, key);
  String _tr(String key) => _bridge.tr(key: key);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_notifier.ensureInit().then((_) => _notifier.syncFloor()));
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

  TicketView? _ticketOn(List<TicketView> tickets, String tableId) =>
      tickets.where((t) => t.tableId == tableId && isLiveTicket(t)).firstOrNull;

  // ── the tap ────────────────────────────────────────────────────────────────

  /// A table was tapped. A move in progress takes it as the destination.
  /// Otherwise an iPad or desktop SELECTS it — the inspector beside the room
  /// shows it — and a phone opens the same inspector as a sheet.
  Future<void> _onTable(FloorTableStateView t, TicketView? ticket) async {
    final from = _moveFrom;
    if (from != null) {
      // Say why rather than silently doing nothing — the party's own table
      // too; stay in move mode (the banner's ✕ leaves it).
      final moved = await moveParty(context, ref, from: from, to: t.id);
      if (moved && mounted) {
        setState(() {
          _moveFrom = null;
          _selectedId = t.id;
        });
      }
      return;
    }
    // A cart parked on the table by the old flow. Nothing writes this any
    // more, but the mirror can still carry one: picking it up is the honest
    // act, and it goes through Sell like any round.
    final held = t.heldOrderId;
    if (held != null) {
      if (t.heldLockedByOther) {
        _notifier.showToast(
          _tr('tables.locked'),
          tone: ChipTone.warning,
          icon: 'lock',
        );
        return;
      }
      // Into the draft's own table cart; the Sell tab's cart is untouched.
      // No `askManager`: resuming a held order is never gated (owner decision
      // 2026-09-19 — it is shared state on the till, like the table itself).
      final landed = await _notifier.resumeDraft(held);
      if (landed?.tableId case final id?) await _toTable(id);
      return;
    }
    if (!MadarLayout.of(context).isPhone) {
      setState(() {
        _selectedId = t.id;
        _walkInId = null;
      });
      return;
    }
    await _detailSheet(t.id);
  }

  /// The phone's inspector: the same detail, live, in a sheet. Every act
  /// closes the sheet first and then happens.
  Future<void> _detailSheet(String tableId, {bool walkIn = false}) async {
    FloorAction? picked;
    int? pickedCovers;
    var pickedTakeOrder = false;
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final s = sheetRef.watch(orderProvider);
          final t = s.floorLayout?.tables
              .where((x) => x.id == tableId)
              .firstOrNull;
          if (t == null) return const SizedBox.shrink();
          return _detail(
            t,
            s,
            walkIn: walkIn,
            onAction: (a, {covers, takeOrder}) {
              picked = a;
              pickedCovers = covers;
              pickedTakeOrder = takeOrder ?? false;
              Navigator.of(sheetContext).maybePop();
            },
          );
        },
      ),
    );
    final a = picked;
    if (a == null || !mounted) return;
    final t = ref
        .read(orderProvider)
        .floorLayout
        ?.tables
        .where((x) => x.id == tableId)
        .firstOrNull;
    if (t == null) return;
    await _perform(a, t, covers: pickedCovers, takeOrder: pickedTakeOrder);
  }

  /// The detail for [t], wired to [onAction].
  Widget _detail(
    FloorTableStateView t,
    OrderState s, {
    required void Function(FloorAction, {int? covers, bool? takeOrder})
    onAction,
    bool walkIn = false,
    VoidCallback? onClose,
  }) {
    final ticket = _ticketOn(s.openTickets, t.id);
    return FloorTableDetail(
      key: ValueKey('floor.detail.${t.id}'),
      // A walk-in on a reserved table is seated like a free one.
      table: walkIn ? _asFree(t) : t,
      ticket: ticket,
      now: DateTime.now(),
      currency: s.currency,
      locale: ref.read(localeProvider).locale,
      word: _w,
      canCharge: widget.canCharge ?? !s.isWaiter,
      sectionName: s.floorLayout?.sections
          .where((x) => x.id == t.sectionId)
          .firstOrNull
          ?.name,
      pendingCovers: s.pendingCovers[t.id],
      hasArrivals: s.arrivals.isNotEmpty,
      timeOf: (iso) => _bridge.formatTime(rfc3339: iso, style: TimeStyle.time),
      onClose: onClose,
      onAction: onAction,
    );
  }

  FloorTableStateView _asFree(FloorTableStateView t) => FloorTableStateView(
    id: t.id,
    sectionId: t.sectionId,
    label: t.label,
    seats: t.seats,
    shape: t.shape,
    status: 'free',
    posX: t.posX,
    posY: t.posY,
    width: t.width,
    height: t.height,
    rotation: t.rotation,
    heldLockedByOther: false,
  );

  /// Every act on a table, from the inspector, its sheet, or a row's button.
  Future<void> _perform(
    FloorAction a,
    FloorTableStateView t, {
    int? covers,
    bool takeOrder = false,
  }) async {
    final ticket = _ticketOn(ref.read(orderProvider).openTickets, t.id);
    switch (a) {
      case FloorAction.seat:
        if (_walkInId == t.id) setState(() => _walkInId = null);
        // Takes the table on every device.
        await _notifier.seatTable(t, covers: covers ?? t.seats);
        if (!takeOrder || !mounted) return;
        await _toTable(t.id);
      case FloorAction.seatBooking:
        if (tableHasBooking(t) && tableIsReserved(t)) {
          if (t.bookingParty case final n? when n > 0) {
            _notifier.setPendingCovers(t.id, n);
          }
          await _notifier.seatBooking(t);
        } else {
          await _pickArrivalFor(t);
        }
      case FloorAction.noShow:
        final id = t.bookingId;
        if (id != null) await _notifier.noShowBooking(id);
      case FloorAction.walkIn:
        if (MadarLayout.of(context).isPhone) {
          await _detailSheet(t.id, walkIn: true);
        } else {
          setState(() => _walkInId = t.id);
        }
      case FloorAction.takeOrder:
        await _toTable(t.id);
      case FloorAction.addRound:
        // The table's cart finds the table's bill on its own.
        await _toTable(t.id);
      case FloorAction.openBill:
        await _openBillOn(t.id);
      case FloorAction.charge:
        await _chargeOn(t);
      case FloorAction.move:
        setState(() => _moveFrom = t.id);
      case FloorAction.unseat:
        await _confirmUnseat(t);
      case FloorAction.cleared:
        await _notifier.clearTable(t.id);
      case FloorAction.voidBill:
        if (ticket != null) await _voidBill(ticket);
      case FloorAction.history:
        await showTableHistory(context, tableId: t.id, label: t.label);
    }
  }

  /// Void the whole bill, with the reason the bill screen asks for.
  Future<void> _voidBill(TicketView ticket) async {
    final result = await showMadarSheet<VoidTicketResult>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => WaiterVoidSheet(ticket: ticket),
    );
    if (result == null || !mounted) return;
    await _notifier.voidTicket(ticket.id, result.reason);
  }

  Future<void> _openBill(String ticketId, {bool charge = false}) async {
    final exit = await MadarPages.push<Object?>(
      context,
      (_) => BillScreen(
        ticketId: ticketId,
        canCharge: widget.canCharge,
        chargeOnOpen: charge,
      ),
    );
    if (exit != BillExit.tableActions || !mounted) return;
    // "Table actions" from the bill: this table, wherever the party sits now.
    final s = ref.read(orderProvider);
    final tableId = s.openTickets
        .where((x) => x.id == ticketId)
        .firstOrNull
        ?.tableId;
    final t = s.floorLayout?.tables.where((x) => x.id == tableId).firstOrNull;
    if (t != null) await _onTable(t, _ticketOn(s.openTickets, t.id));
  }

  /// The bill on [tableId], re-reading the bills first when this device does
  /// not know one: a stale or offline list must never lock a party's bill
  /// away from the room. Says so when there really is none yet.
  Future<void> _openBillOn(String tableId, {bool charge = false}) async {
    var ticket = _ticketOn(ref.read(orderProvider).openTickets, tableId);
    if (ticket == null) {
      await _notifier.loadOpenTickets();
      ticket = _ticketOn(ref.read(orderProvider).openTickets, tableId);
    }
    if (!mounted) return;
    if (ticket == null) {
      _notifier.showToast(_w('floor.no_bill_yet'), icon: 'doc.text');
      return;
    }
    await _openBill(ticket.id, charge: charge);
  }

  /// Charge from the room: the Charge dialog over the floor, nothing pushed.
  /// The teller stays where they were; the table's state moves on its own.
  Future<void> _chargeOn(FloorTableStateView t) async {
    var ticket = _ticketOn(ref.read(orderProvider).openTickets, t.id);
    if (ticket == null) {
      await _notifier.loadOpenTickets();
      ticket = _ticketOn(ref.read(orderProvider).openTickets, t.id);
    }
    if (!mounted) return;
    if (ticket == null) {
      _notifier.showToast(_w('floor.no_bill_yet'), icon: 'doc.text');
      return;
    }
    final outcome = await showCharge(
      context,
      ChargeTarget.bill(ticket, tableLabel: t.label),
      onDone: (_, _) => unawaited(_notifier.loadFloor()),
      onPrinterSettings: () => unawaited(showPrinterSheet(context)),
    );
    if (outcome == null || !mounted) return;
    await _notifier.afterBillCharged(ticket.id);
  }

  /// Taking an order FOR A TABLE opens that table's own screen and cart.
  Future<void> _toTable(String tableId) async {
    if (!mounted) return;
    await MadarPages.push<void>(
      context,
      (_) => TableOrderScreen(tableId: tableId),
    );
  }

  /// Cancelling a queued table transfer — small, but irreversible here.
  Future<void> _confirmCancelTransfer(String id) async {
    if (!mounted) return;
    final ok = await showMadarConfirm(
      context,
      title: _tr('transfer.cancel_title'),
      body: _tr('transfer.cancel_body'),
      confirmLabel: _tr('tables.cancel_wish'),
      cancelLabel: _tr('common.cancel'),
    );
    if (ok) await _notifier.cancelTransfer(id);
  }

  /// Unseating erases the party from the room — it confirms first.
  Future<void> _confirmUnseat(FloorTableStateView t) async {
    if (!mounted) return;
    final ok = await showMadarConfirm(
      context,
      title: '${_w('floor.unseat')} · ${t.label}',
      body: _tr('floor.unseat_confirm'),
      confirmLabel: _w('floor.unseat'),
      cancelLabel: _tr('common.cancel'),
    );
    if (ok) unawaited(_notifier.unseatTable(t.id));
  }

  /// Today's arrivals; tapping one seats it on [at] (or on its own table).
  Future<void> _pickArrivalFor(FloorTableStateView? at) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final list = sheetRef.watch(orderProvider.select((s) => s.arrivals));
          return _StateSheet(
            title: _tr('tables.arrivals'),
            subtitle: at?.label,
            children: [
              if (list.isEmpty)
                Text(
                  _tr('tables.arrivals_empty'),
                  style: MadarType.body.copyWith(
                    color: context.madarColors.textMuted,
                  ),
                )
              else
                MadarCard(
                  flush: true,
                  child: Column(
                    children: [
                      for (final (i, b) in list.indexed) ...[
                        if (i > 0) const MadarHairline(light: true),
                        MadarRow(
                          title: b.guestName,
                          subtitle: [
                            '${b.partySize} ${_tr('tables.guests')}',
                            _bridge.formatTime(
                              rfc3339: b.startsAt,
                              style: TimeStyle.time,
                            ),
                            if (b.tableLabels.isNotEmpty) b.tableLabels.first,
                          ].join(' · '),
                          glyph: MadarGlyph.calendar,
                          trailing: MadarButton(
                            label: _tr('tables.no_show'),
                            variant: MadarButtonVariant.ghost,
                            size: MadarButtonSize.compact,
                            onTap: () =>
                                unawaited(_notifier.noShowBooking(b.id)),
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).maybePop();
                            unawaited(
                              at == null
                                  ? _notifier.seatArrival(b)
                                  : _notifier.seatArrivalAt(b, at),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Parties waiting to move: seat one where they wished, or drop the wish.
  Future<void> _openWaitlist() async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final queue = sheetRef.watch(
            orderProvider.select((s) => s.transferQueue),
          );
          return _StateSheet(
            title: _tr('tables.waitlist'),
            children: [
              if (queue.isEmpty)
                Text(
                  _tr('tables.empty_waitlist'),
                  style: MadarType.body.copyWith(
                    color: context.madarColors.textMuted,
                  ),
                )
              else
                MadarCard(
                  flush: true,
                  child: Column(
                    children: [
                      for (final (i, e) in queue.indexed) ...[
                        if (i > 0) const MadarHairline(light: true),
                        MadarRow(
                          title: e.occupantLabel ?? e.fromTableLabel ?? '',
                          subtitle:
                              e.targetTableLabel ??
                              (e.targetSectionName == null
                                  ? null
                                  : '${_tr('tables.wish_any')} ${e.targetSectionName}'),
                          glyph: MadarGlyph.clock,
                          trailing: MadarGlyphTile(
                            glyph: MadarGlyph.close,
                            semanticLabel: _tr('tables.cancel_wish'),
                            onTap: () =>
                                unawaited(_confirmCancelTransfer(e.id)),
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).maybePop();
                            unawaited(_fulfill(e));
                          },
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _fulfill(TransferQueueView e) async {
    if (e.targetTableId != null) {
      await _notifier.fulfillTransfer(e.id, e.targetTableId!);
      return;
    }
    final pick = await showTablePickerSheet(context, ref, allowClear: false);
    if (pick?.tableId == null || !mounted) return;
    await _notifier.fulfillTransfer(e.id, pick!.tableId!);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The screen's words come through [_w]/[_tr], plain bridge reads. This is
    // what re-pulls them when the language changes under a pushed route.
    ref.watch(localeGenerationProvider);
    final locale = ref.watch(localeProvider).locale;
    listenForTableClear(context, ref);
    ref
      ..listen(floorTickProvider, (_, _) => unawaited(_notifier.syncFloor()))
      ..listen(ticketTickProvider, (_, _) {
        unawaited(_notifier.loadOpenTickets());
      });

    final layout = MadarLayout.of(context);
    _view ??= layout.pick(phone: FloorView.list, tablet: FloorView.plan);
    final view = _view!;
    final state = ref.watch(orderProvider);
    final tickets = state.openTickets;
    final sections = state.floorLayout?.sections ?? const <FloorSectionInfo>[];
    final allTables =
        state.floorLayout?.tables ?? const <FloorTableStateView>[];
    final now = DateTime.now();

    // Tabs = the authored sections, plus an "unassigned" tab when tables sit
    // outside every section; the first tab that has tables is the default.
    final sectionIds = {for (final s in sections) s.id};
    final orphans = allTables
        .where((t) => t.sectionId == null || !sectionIds.contains(t.sectionId))
        .toList(growable: false);
    final tabs = <(String, String)>[
      for (final s in sections) (s.id, s.name),
      if (orphans.isNotEmpty) (_kNoSection, _tr('tables.no_section')),
    ];
    int countIn(String id) => id == _kNoSection
        ? orphans.length
        : allTables.where((t) => t.sectionId == id).length;
    final activeId = tabs.any((t) => t.$1 == _sectionId)
        ? _sectionId!
        : (tabs.where((t) => countIn(t.$1) > 0).firstOrNull?.$1 ??
              tabs.firstOrNull?.$1 ??
              _kNoSection);
    final active = sections.where((s) => s.id == activeId).firstOrNull;
    final tables = activeId == _kNoSection
        ? orphans
        : allTables
              .where((t) => t.sectionId == activeId)
              .toList(growable: false);
    String? sectionName(String? sid) =>
        sections.where((s) => s.id == sid).firstOrNull?.name;

    // The section as a worklist — the list mode's rows and the counts.
    final rows = buildFloorRows(
      tables: tables,
      ticketOn: (id) => _ticketOn(tickets, id),
      sectionName: sectionName,
      now: now,
    );
    final counts = <FloorUrgency, int>{
      for (final u in FloorUrgency.values)
        u: rows.where((r) => r.urgency == u).length,
    };
    final filter = (counts[_filter] ?? 0) > 0 ? _filter : null;
    final selected = allTables.where((t) => t.id == _selectedId).firstOrNull;

    final segment = MadarSegmented<FloorView>(
      items: [
        MadarSegmentItem(FloorView.plan, _tr('tables.view_plan')),
        MadarSegmentItem(FloorView.list, _tr('tables.view_list')),
      ],
      value: view,
      onChanged: (v) => setState(() => _view = v),
    );

    final headerActions = <Widget>[
      if (state.arrivals.isNotEmpty)
        MadarChip(
          key: const ValueKey('floor.arrivals'),
          label: _tr('tables.arrivals'),
          glyph: MadarGlyph.calendar,
          count: state.arrivals.length,
          onTap: () => unawaited(_pickArrivalFor(null)),
        ),
      if (state.transferQueue.isNotEmpty)
        MadarChip(
          key: const ValueKey('floor.waitlist'),
          label: _tr('tables.waitlist'),
          glyph: MadarGlyph.clock,
          count: state.transferQueue.length,
          onTap: () => unawaited(_openWaitlist()),
        ),
      if (layout.isTablet && allTables.isNotEmpty)
        SizedBox(width: 200, child: segment),
    ];

    // ONE row: the sections, then the room's state as filters.
    final statusChips = <Widget>[
      for (final u in const [
        FloorUrgency.needsClearing,
        FloorUrgency.foodReady,
        FloorUrgency.seated,
        FloorUrgency.reserved,
        FloorUrgency.free,
      ])
        if ((counts[u] ?? 0) > 0)
          _StatusChip(
            key: ValueKey('floor.filter.${u.name}'),
            glyph: floorGlyphOf(u),
            label: _urgencyWord(u),
            tone: floorToneOf(u),
            count: counts[u]!,
            selected: filter == u,
            onTap: () => setState(() => _filter = filter == u ? null : u),
          ),
    ];
    final chipRow = SizedBox(
      height: Metrics.chipHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (tabs.length > 1)
            for (final tab in tabs) ...[
              MadarChip(
                label: tab.$2,
                count: countIn(tab.$1) == 0 ? null : countIn(tab.$1),
                selected: tab.$1 == activeId,
                onTap: () => setState(() {
                  _sectionId = tab.$1;
                  _filter = null;
                }),
              ),
              const SizedBox(width: Space.sm),
            ],
          if (tabs.length > 1 && statusChips.isNotEmpty)
            Center(
              child: Container(
                width: 1,
                height: Space.xl,
                margin: const EdgeInsetsDirectional.only(end: Space.sm),
                color: context.madarColors.border,
              ),
            ),
          for (final c in statusChips) ...[c, const SizedBox(width: Space.sm)],
        ],
      ),
    );
    final headerBelow = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (layout.isPhone && allTables.isNotEmpty) segment,
        if (allTables.isNotEmpty) chipRow,
      ],
    );

    return MadarPageScaffold(
      safeTop: false,
      title: _w('floor.title'),
      width: MadarContentWidth.full,
      bodyInset: false,
      actions: headerActions,
      below: headerBelow,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            layout.gutter,
            Space.lg,
            layout.gutter,
            layout.gutter,
          ),
          child: allTables.isEmpty
              ? EmptyState(
                  icon: 'square.grid.2x2',
                  title: _w('floor.no_layout_title'),
                  message: _w('floor.no_layout_desc'),
                  actionLabel: _tr('chrome.sync_data'),
                  onAction: () => unawaited(_notifier.syncFloor()),
                )
              : _body(
                  context,
                  state: state,
                  view: view,
                  tables: tables,
                  rows: rows,
                  active: active,
                  activeId: activeId,
                  filter: filter,
                  selected: selected,
                  now: now,
                  locale: locale,
                ),
        ),
      ),
    );
  }

  String _urgencyWord(FloorUrgency u) => switch (u) {
    FloorUrgency.needsClearing => _tr('tables.needs_clearing'),
    FloorUrgency.foodReady => _w('bill.ready'),
    FloorUrgency.seated => _tr('tables.seated'),
    FloorUrgency.reserved => _tr('tables.reserved'),
    FloorUrgency.free => _tr('tables.free'),
  };

  /// The room and its inspector. iPad landscape and desktop: the room with
  /// the inspector docked at the END side (it swaps in Arabic; the room
  /// never mirrors). iPad portrait: the inspector under the room. Phone: the
  /// room alone — the inspector is a sheet.
  Widget _body(
    BuildContext context, {
    required OrderState state,
    required FloorView view,
    required List<FloorTableStateView> tables,
    required List<FloorRow> rows,
    required FloorSectionInfo? active,
    required String activeId,
    required FloorUrgency? filter,
    required FloorTableStateView? selected,
    required DateTime now,
    required String locale,
  }) {
    final layout = MadarLayout.of(context);
    final tickets = state.openTickets;
    final colors = context.madarColors;
    void tap(FloorTableStateView t) =>
        unawaited(_onTable(t, _ticketOn(tickets, t.id)));
    final moveFrom = _moveFrom;

    Widget room;
    if (tables.isEmpty) {
      room = EmptyState(
        icon: 'square.grid.2x2',
        title: _w('floor.empty_section'),
        message: _w('floor.empty_section_desc'),
      );
    } else if (view == FloorView.list) {
      room = FloorListView(
        rows: filter == null
            ? rows
            : rows.where((r) => r.urgency == filter).toList(growable: false),
        now: now,
        currency: state.currency,
        locale: locale,
        words: FloorListWords.of(_bridge),
        canCharge: widget.canCharge ?? !state.isWaiter,
        armedId: moveFrom,
        selectedId: layout.isPhone ? null : selected?.id,
        onTap: tap,
        onLongPress: tap,
        onAction: (a, t) => unawaited(_perform(a, t)),
      );
    } else {
      room = AnimatedSwitcher(
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : MotionSpec.gentleDuration,
        child: FloorCanvas(
          key: ValueKey(activeId),
          section: active,
          tables: tables,
          tickets: tickets,
          seatsWord: _tr('tables.seats'),
          words: TableStatusWords.of(_bridge),
          zoomable: true,
          fitLabel: _w('floor.fit_room'),
          swapArmedId: moveFrom,
          selectedId: layout.isPhone ? null : selected?.id,
          // While moving, the tables a party cannot go to read as such; a
          // status filter quiets the rest of the room the same way.
          enabledOf: moveFrom != null
              ? (x) =>
                    x.id == moveFrom ||
                    tableIsMoveTarget(x, from: moveFrom, tickets: tickets)
              : filter == null
              ? null
              : (x) => urgencyOf(x, _ticketOn(tickets, x.id)) == filter,
          onDisabledTap: tap,
          onTap: tap,
        ),
      );
    }

    if (moveFrom != null) {
      final label = state.floorLayout?.tables
          .where((t) => t.id == moveFrom)
          .firstOrNull
          ?.label;
      room = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          NoticeBanner(
            text: label == null
                ? _tr('tables.swap_pick')
                : '$label · ${_tr('tables.swap_pick')}',
            tone: ChipTone.accent,
            icon: 'arrow.triangle.2.circlepath',
            onTap: () => setState(() => _moveFrom = null),
            trailing: MadarGlyphIcon(
              MadarGlyph.close,
              size: IconSize.md,
              color: colors.textSecondary,
            ),
          ),
          Expanded(child: room),
        ],
      );
    }

    if (layout.isPhone) return room;

    final inspector = DecoratedBox(
      key: const ValueKey('floor.inspector'),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: colors.borderLight),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: AnimatedSwitcher(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : MotionSpec.standardDuration,
          layoutBuilder: (current, previous) =>
              Stack(children: [...previous, ?current]),
          child: selected == null
              ? FloorWorklist(
                  key: const ValueKey('floor.worklist'),
                  rows: needsAttention(rows, now: now),
                  now: now,
                  currency: state.currency,
                  locale: locale,
                  word: _w,
                  canCharge: widget.canCharge ?? !state.isWaiter,
                  onSelect: (t) => setState(() => _selectedId = t.id),
                  onAction: (a, t) => unawaited(_perform(a, t)),
                )
              : _detail(
                  selected,
                  state,
                  walkIn: _walkInId == selected.id,
                  onClose: () => setState(() {
                    _selectedId = null;
                    _walkInId = null;
                  }),
                  onAction: (a, {covers, takeOrder}) => unawaited(
                    _perform(
                      a,
                      selected,
                      covers: covers,
                      takeOrder: takeOrder ?? false,
                    ),
                  ),
                ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final portrait = box.maxHeight > box.maxWidth;
        if (portrait) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: room),
              const SizedBox(height: Space.lg),
              SizedBox(height: box.maxHeight * 0.42, child: inspector),
            ],
          );
        }
        final side = (box.maxWidth * 0.35).clamp(340.0, 440.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: room),
            const SizedBox(width: Space.lg),
            SizedBox(width: side, child: inspector),
          ],
        );
      },
    );
  }
}

/// A status summary chip: the state's glyph in its tone, the word, the count.
/// Tapping it narrows the room to that state; tapping it again widens it.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.glyph,
    required this.tone,
    required this.count,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final MadarGlyph glyph;
  final MadarTone tone;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final ink = tone == MadarTone.neutral
        ? colors.textSecondary
        : tone.color(colors);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: TactileScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : MotionSpec.standardDuration,
          height: Metrics.chipHeight,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            color: selected ? tone.tint(colors) : colors.surface,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(
              color: selected ? ink : colors.borderLight,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.sm,
              children: [
                MadarGlyphIcon(glyph, size: IconSize.xs, color: ink),
                Text(
                  label,
                  style: MadarType.bodySm.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$count',
                  textDirection: TextDirection.ltr,
                  style: MadarType.numMd.copyWith(color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A sheet's body: a title, one muted line, then the sheet's rows.
class _StateSheet extends StatelessWidget {
  const _StateSheet({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: MadarType.h2.copyWith(color: colors.textPrimary)),
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: Space.xs),
              child: Text(
                subtitle!,
                style: MadarType.body.copyWith(color: colors.textSecondary),
              ),
            ),
          const SizedBox(height: Space.lg),
          ...children,
        ],
      ),
    );
  }
}
