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
import 'package:feature_order/src/bill_screen.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/sell_screen.dart';
import 'package:feature_order/src/table_clear_prompt.dart';
import 'package:feature_order/src/table_history_sheet.dart';
import 'package:feature_order/src/tables_screen.dart'
    show
        FloorCanvas,
        TableStatusWords,
        showTablePickerSheet,
        tableBookingSeated,
        tableHasBooking,
        tableIsReserved,
        tableNeedsClearing;
import 'package:feature_order/src/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Plan or list.
enum FloorView { plan, list }

/// Tab id for tables that belong to no section (or an orphaned one).
const String _kNoSection = '__no_section__';

/// The largest party the chip row offers before the number is typed.
const int _kMaxPartyChip = 8;

/// The Floor.
class FloorScreen extends ConsumerStatefulWidget {
  const FloorScreen({this.canCharge, super.key});

  /// Handed to the Bill a table opens — see [BillScreen.canCharge].
  final bool? canCharge;

  @override
  ConsumerState<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends ConsumerState<FloorScreen>
    with RealtimeGatedPoll<FloorScreen> {
  String? _sectionId;

  /// Null until the first build picks the device's default: list on a phone,
  /// plan on a tablet. A person's choice then sticks for the screen's life.
  FloorView? _view;

  /// A move in progress: the table the party is leaving.
  String? _moveFrom;

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

  Future<void> _onTable(FloorTableStateView t, TicketView? ticket) async {
    final from = _moveFrom;
    if (from != null) {
      setState(() => _moveFrom = null);
      if (from != t.id) await _notifier.swapTables(from, t.id);
      return;
    }
    if (ticket != null) {
      await _openBill(ticket.id);
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
      await _notifier.switchToHeldOrder(held);
      await _toSell();
      return;
    }
    if (tableNeedsClearing(t)) {
      await _dirtySheet(t);
      return;
    }
    if (t.status == 'seated' || tableBookingSeated(t)) {
      await _seatedSheet(t);
      return;
    }
    if (tableHasBooking(t) && tableIsReserved(t)) {
      await _bookedSheet(t);
      return;
    }
    await _freeSheet(t);
  }

  Future<void> _openBill(String ticketId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BillScreen(ticketId: ticketId, canCharge: widget.canCharge),
      ),
    );
  }

  /// Taking an order FOR A TABLE opens its own screen, not the Sell tab.
  /// The tab is the counter; this errand has a table in hand and a back
  /// button to the room it came from.
  Future<void> _toSell() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SellScreen.forTable()),
    );
  }

  // ── the sheets ─────────────────────────────────────────────────────────────

  /// FREE: party size as chips, the table's capacity preselected; Seat.
  Future<void> _freeSheet(FloorTableStateView t) async {
    final section = ref
        .read(orderProvider)
        .floorLayout
        ?.sections
        .where((s) => s.id == t.sectionId)
        .firstOrNull
        ?.name;
    final hasArrivals = ref.read(orderProvider).arrivals.isNotEmpty;
    var covers = t.seats.clamp(1, _kMaxPartyChip);
    final seat = await showMadarSheet<int>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => _StateSheet(
          title: t.label,
          subtitle: ['${t.seats} ${_tr('tables.seats')}', ?section].join(' · '),
          children: [
            MadarSectionHeader(text: _w('floor.party_size')),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (var n = 1; n <= _kMaxPartyChip; n++)
                  MadarChip.tile(
                    label: '$n',
                    selected: covers == n,
                    onTap: () => setSheet(() => covers = n),
                  ),
              ],
            ),
            const SizedBox(height: Space.lg),
            MadarButton(
              label: _w('floor.seat'),
              glyph: MadarGlyph.users,
              onTap: () => Navigator.of(sheetContext).maybePop(covers),
            ),
            if (hasArrivals)
              MadarButton(
                label: _w('floor.seat_booking_here'),
                variant: MadarButtonVariant.ghost,
                onTap: () => Navigator.of(sheetContext).maybePop(-1),
              ),
          ],
        ),
      ),
    );
    if (seat == null || !mounted) return;
    if (seat == -1) {
      await _pickArrivalFor(t);
      return;
    }
    // Takes the table on every device. Opens nothing.
    await _notifier.seatTable(t, covers: seat, bindCart: false);
  }

  /// SEATED, no bill yet: take the first order, move, or unseat.
  Future<void> _seatedSheet(FloorTableStateView t) async {
    final since = t.heldSince ?? t.bookingStartsAt;
    final opened = since == null ? null : DateTime.tryParse(since);
    final ago = opened == null
        ? null
        : formatSeatedFor(DateTime.now().toUtc().difference(opened.toUtc()));
    final covers = ref.read(orderProvider).pendingCovers[t.id];
    final guest = t.bookingGuest?.trim();
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => _StateSheet(
        title: t.label,
        historyFor: t.id,
        historyLabel: _tr('tables.history'),
        subtitle: [
          _tr('tables.seated'),
          ?ago,
          if (covers != null) '$covers ${_tr('tables.guests')}',
          if (guest != null && guest.isNotEmpty) guest,
        ].join(' · '),
        children: [
          MadarButton(
            label: _w('floor.take_order'),
            glyph: MadarGlyph.receipt,
            onTap: () {
              Navigator.of(sheetContext).maybePop();
              unawaited(() async {
                await _notifier.pointCartAtTable(t.id, t.label);
                await _toSell();
              }());
            },
          ),
          MadarButton(
            label: _tr('tables.move'),
            glyph: MadarGlyph.move,
            variant: MadarButtonVariant.ghost,
            onTap: () {
              Navigator.of(sheetContext).maybePop();
              setState(() => _moveFrom = t.id);
            },
          ),
          MadarButton(
            label: _w('floor.unseat'),
            variant: MadarButtonVariant.ghost,
            onTap: () {
              Navigator.of(sheetContext).maybePop();
              unawaited(_confirmUnseat(t));
            },
          ),
        ],
      ),
    );
  }

  /// Unseating says nobody is there any more — the one act on this sheet a
  /// mis-tap cannot walk back from other than seating the party again from
  /// scratch (any bill, any covers on record, gone from the room). Destructive,
  /// so it confirms first like every other floor action that erases rather
  /// than merely tidies.
  /// Cancelling a queued table transfer — the table keeps its bill where it
  /// is and nothing moves. Small, but irreversible from the teller's side.
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

  /// NEEDS CLEARING: the one honest act. "Reprint last receipt" is not here
  /// because nothing links a dirty table to its last sale.
  Future<void> _dirtySheet(FloorTableStateView t) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => _StateSheet(
        title: t.label,
        historyFor: t.id,
        historyLabel: _tr('tables.history'),
        subtitle: _tr('tables.needs_clearing'),
        children: [
          MadarButton(
            label: _w('floor.cleared'),
            glyph: MadarGlyph.check,
            onTap: () {
              Navigator.of(sheetContext).maybePop();
              unawaited(_notifier.clearTable(t.id));
            },
          ),
        ],
      ),
    );
  }

  /// BOOKED, hold window open: seat the party, no-show them, or seat a
  /// walk-in instead.
  Future<void> _bookedSheet(FloorTableStateView t) async {
    final when = t.bookingStartsAt == null
        ? null
        : _bridge.formatTime(
            rfc3339: t.bookingStartsAt!,
            style: TimeStyle.time,
          );
    final walkIn = await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => _StateSheet(
        title: t.label,
        historyFor: t.id,
        historyLabel: _tr('tables.history'),
        subtitle: [
          if (t.bookingGuest?.trim().isNotEmpty ?? false) t.bookingGuest!,
          if (t.bookingParty != null)
            '${t.bookingParty} ${_tr('tables.guests')}',
          ?when,
        ].join(' · '),
        children: [
          MadarButton(
            label: _tr('tables.seat_booking'),
            glyph: MadarGlyph.users,
            onTap: () {
              Navigator.of(sheetContext).maybePop(false);
              if (t.bookingParty case final n? when n > 0) {
                _notifier.setPendingCovers(t.id, n);
              }
              unawaited(_notifier.seatBooking(t));
            },
          ),
          MadarButton(
            label: _tr('tables.no_show'),
            variant: MadarButtonVariant.ghost,
            onTap: () {
              Navigator.of(sheetContext).maybePop(false);
              final id = t.bookingId;
              if (id != null) unawaited(_notifier.noShowBooking(id));
            },
          ),
          MadarButton(
            label: _w('floor.walk_in_here'),
            variant: MadarButtonVariant.ghost,
            onTap: () => Navigator.of(sheetContext).maybePop(true),
          ),
        ],
      ),
    );
    if ((walkIn ?? false) && mounted) await _freeSheet(t);
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
    final colors = context.madarColors;
    listenForTableClear(context, ref);
    ref
      ..listen(floorTickProvider, (_, _) => unawaited(_notifier.syncFloor()))
      ..listen(ticketTickProvider, (_, _) {
        unawaited(_notifier.loadOpenTickets());
      });
    realtimeGatedPoll(
      interval: const Duration(seconds: 20),
      onPoll: () => unawaited(_notifier.syncFloor()),
    );

    final layout = MadarLayout.of(context);
    _view ??= layout.pick(phone: FloorView.list, tablet: FloorView.plan);
    final view = _view!;
    final state = ref.watch(orderProvider);
    final tickets = state.openTickets;
    final sections = state.floorLayout?.sections ?? const <FloorSectionInfo>[];
    final allTables =
        state.floorLayout?.tables ?? const <FloorTableStateView>[];

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

    // The room at a glance.
    var seated = 0;
    var free = 0;
    var dirty = 0;
    var booked = 0;
    for (final t in allTables) {
      final occupied =
          _ticketOn(tickets, t.id) != null ||
          t.heldOrderId != null ||
          t.status == 'seated' ||
          tableBookingSeated(t);
      if (occupied) {
        seated++;
      } else if (tableNeedsClearing(t)) {
        dirty++;
      } else if (tableIsReserved(t)) {
        booked++;
      } else {
        free++;
      }
    }

    final segment = MadarSegmented<FloorView>(
      items: [
        MadarSegmentItem(FloorView.plan, _tr('tables.view_plan')),
        MadarSegmentItem(FloorView.list, _tr('tables.view_list')),
      ],
      value: view,
      onChanged: (v) => setState(() => _view = v),
    );

    final summary = Wrap(
      spacing: Space.lg,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Count(tone: colors.accent, word: _tr('tables.seated'), n: seated),
        _Count(tone: colors.success, word: _tr('tables.free'), n: free),
        if (dirty > 0)
          _Count(
            tone: colors.danger,
            word: _tr('tables.needs_clearing'),
            n: dirty,
          ),
        if (booked > 0)
          _Count(tone: colors.warning, word: _tr('tables.reserved'), n: booked),
        MadarButton(
          label: state.arrivals.isEmpty
              ? _tr('tables.arrivals')
              : '${_tr('tables.arrivals')} ${state.arrivals.length}',
          glyph: MadarGlyph.calendar,
          variant: MadarButtonVariant.ghost,
          size: MadarButtonSize.compact,
          onTap: () => unawaited(_pickArrivalFor(null)),
        ),
        MadarButton(
          label: state.transferQueue.isEmpty
              ? _tr('tables.waitlist')
              : '${_tr('tables.waitlist')} ${state.transferQueue.length}',
          glyph: MadarGlyph.clock,
          variant: MadarButtonVariant.ghost,
          size: MadarButtonSize.compact,
          onTap: () => unawaited(_openWaitlist()),
        ),
      ],
    );

    final header = MadarHeader(
      title: _w('floor.title'),
      onBack: Navigator.of(context).canPop()
          ? () => Navigator.of(context).maybePop()
          : null,
      actions: [if (layout.isTablet) SizedBox(width: 200, child: segment)],
      below: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          if (layout.isPhone) segment,
          if (tabs.length > 1)
            SizedBox(
              height: Metrics.chipHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (i, tab) in tabs.indexed) ...[
                    if (i > 0) const SizedBox(width: Space.sm),
                    MadarChip(
                      label: tab.$2,
                      count: countIn(tab.$1) == 0 ? null : countIn(tab.$1),
                      selected: tab.$1 == activeId,
                      onTap: () => setState(() => _sectionId = tab.$1),
                    ),
                  ],
                ],
              ),
            ),
          if (allTables.isNotEmpty) summary,
        ],
      ),
    );

    Widget room;
    if (allTables.isEmpty) {
      room = EmptyState(
        icon: 'square.grid.2x2',
        title: _tr('tables.empty_title'),
        message: _tr('tables.empty_desc'),
        actionLabel: _tr('chrome.sync_data'),
        onAction: () => unawaited(_notifier.syncFloor()),
      );
    } else if (view == FloorView.list) {
      room = FloorListView(
        rows: buildFloorRows(
          tables: tables,
          ticketOn: (id) => _ticketOn(tickets, id),
          sectionName: (sid) =>
              sections.where((s) => s.id == sid).firstOrNull?.name,
          now: DateTime.now(),
        ),
        now: DateTime.now(),
        currency: state.currency,
        words: FloorListWords.of(_bridge),
        armedId: _moveFrom,
        onTap: (t) => unawaited(_onTable(t, _ticketOn(tickets, t.id))),
        onLongPress: (t) => unawaited(_onTable(t, _ticketOn(tickets, t.id))),
      );
    } else {
      // No outer scroller any more: the canvas gets the `Expanded` region
      // below as a BOUNDED window, which is what lets `FloorCanvas` pan and
      // pinch-zoom the room in both axes instead of only growing taller. Keyed
      // by section so switching sections (terrace → inside → bar) cross-fades
      // into the new room instead of snapping — "moving between them cleanly".
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
          swapArmedId: _moveFrom,
          onTap: (t) => unawaited(_onTable(t, _ticketOn(tickets, t.id))),
        ),
      );
    }

    // A tab body, never pushed (chrome.dart mounts it for _Tab.floor), so
    // the shell's top bar has already paid the status-bar inset.
    return MadarPageScaffold(
      safeTop: false,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                layout.gutter,
                Space.md,
                layout.gutter,
                Space.md,
              ),
              child: header,
            ),
            if (_moveFrom != null)
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  layout.gutter,
                  0,
                  layout.gutter,
                  Space.md,
                ),
                child: NoticeBanner(
                  text: _tr('tables.swap_pick'),
                  tone: ChipTone.accent,
                  icon: 'arrow.triangle.2.circlepath',
                  onTap: () => setState(() => _moveFrom = null),
                  trailing: MadarGlyphIcon(
                    MadarGlyph.close,
                    size: IconSize.md,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: layout.gutter,
                ),
                child: room,
              ),
            ),
            if (view == FloorView.plan && allTables.isNotEmpty)
              Padding(
                padding: EdgeInsetsDirectional.all(layout.gutter),
                child: Wrap(
                  spacing: Space.lg,
                  runSpacing: Space.xs,
                  children: [
                    _Legend(tone: colors.accent, word: _tr('tables.seated')),
                    _Legend(tone: colors.success, word: _tr('tables.free')),
                    _Legend(
                      tone: colors.danger,
                      word: _tr('tables.needs_clearing'),
                    ),
                    _Legend(tone: colors.warning, word: _tr('tables.reserved')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A sheet's body: title, one muted line, then whatever the state offers.
class _StateSheet extends StatelessWidget {
  const _StateSheet({
    required this.title,
    required this.children,
    this.subtitle,
    this.historyFor,
    this.historyLabel,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// The table to open a history for, appended as the quietest action on
  /// every state sheet. Every table has a past, whatever it is doing now, so
  /// the door belongs on all of them rather than on one.
  final String? historyFor;

  /// Already-localised label for that action.
  final String? historyLabel;

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
          for (final (i, child) in children.indexed) ...[
            if (i > 0 && child is MadarButton) const SizedBox(height: Space.sm),
            child,
          ],
          if (historyFor != null) ...[
            const SizedBox(height: Space.sm),
            MadarButton(
              label: historyLabel ?? '',
              glyph: MadarGlyph.clock,
              variant: MadarButtonVariant.ghost,
              onTap: () {
                Navigator.of(context).maybePop();
                unawaited(
                  showTableHistory(context, tableId: historyFor!, label: title),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// "● 6 seated" — a dot in the state's colour, a mono count, the word.
class _Count extends StatelessWidget {
  const _Count({required this.tone, required this.word, required this.n});

  final Color tone;
  final String word;
  final int n;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        MadarGlyphIcon(MadarGlyph.full, size: IconSize.xs, color: tone),
        Text(
          '$n',
          textDirection: TextDirection.ltr,
          style: MadarType.numMd.copyWith(color: colors.textPrimary),
        ),
        Text(
          word,
          style: MadarType.bodySm.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.tone, required this.word});

  final Color tone;
  final String word;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        MadarGlyphIcon(MadarGlyph.full, size: IconSize.xs, color: tone),
        Text(word, style: MadarType.bodySm.copyWith(color: colors.textMuted)),
      ],
    );
  }
}
