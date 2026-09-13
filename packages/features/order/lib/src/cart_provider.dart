part of 'order_providers.dart';

// One cart PER CONTEXT: the counter's takeaway cart (`tableId == null`) and
// one for every table. There is no cart "in hand" and nothing to switch —
// the Sell tab reads `cartProvider(null)`, a table's order screen reads
// `cartProvider(tableId)`, and every core call names the context it acts on.
// A screen can therefore never show, fire or park another screen's cart.

const CartMeta _emptyMeta = CartMeta(name: '');

/// [m] with the given fields replaced (pass `null` to clear a field).
CartMeta cartMetaWith(
  CartMeta m, {
  String? name,
  Object? draftId = _unset,
  Object? bookingId = _unset,
  Object? tableLabel = _unset,
  Object? guestName = _unset,
  Object? startedAt = _unset,
  Object? covers = _unset,
}) => CartMeta(
  name: name ?? m.name,
  draftId: identical(draftId, _unset) ? m.draftId : draftId as String?,
  bookingId: identical(bookingId, _unset) ? m.bookingId : bookingId as String?,
  tableLabel: identical(tableLabel, _unset)
      ? m.tableLabel
      : tableLabel as String?,
  guestName: identical(guestName, _unset) ? m.guestName : guestName as String?,
  startedAt: identical(startedAt, _unset) ? m.startedAt : startedAt as String?,
  covers: identical(covers, _unset) ? m.covers : covers as int?,
);

/// One context's cart: its lines, totals, identity (the core's persisted
/// [CartMeta]) and the round it is building.
@immutable
class CartState {
  const CartState({
    required this.tableId,
    this.lines = const [],
    this.totals = _emptyTotals,
    this.meta = _emptyMeta,
    this.activeTicketId,
    this.firedSeq = 0,
    this.isBusy = false,
    this.loaded = false,
  });

  /// The context: null = takeaway, else the floor table this cart is for.
  final String? tableId;
  final List<CartLineView> lines;
  final CartTotals totals;

  /// Name, parked-order id, booking, label, guest, started-at, covers — kept
  /// by the core with the lines, so it survives a restart.
  final CartMeta meta;

  /// An explicitly picked bill for this cart's next round (a table-less
  /// bill). A table's cart finds its bill by the table — see [cartTicket].
  final String? activeTicketId;

  /// Bumped every time THIS cart fires or adds a round — a signal the pushed
  /// order screen watches to take itself away.
  final int firedSeq;

  /// A fire/round of this cart is on its way.
  final bool isBusy;

  /// The first read from the core has landed.
  final bool loaded;

  bool get isTakeaway => tableId == null;

  /// The live order's free-text name; null when unnamed (or a legacy
  /// "HH:MM" auto-label).
  String? get name {
    final n = meta.name.trim();
    if (n.isEmpty || OrderNotifier.looksLikeTimeLabel(n)) return null;
    return n;
  }

  String? get draftId => meta.draftId;
  String? get bookingId => meta.bookingId;
  String? get startedAt => meta.startedAt;

  /// Total quantity of an item in this cart, across its config variants.
  int qtyForItem(String itemId) =>
      lines.where((l) => l.itemId == itemId).fold(0, (sum, l) => sum + l.qty);

  CartState copyWith({
    List<CartLineView>? lines,
    CartTotals? totals,
    CartMeta? meta,
    Object? activeTicketId = _unset,
    int? firedSeq,
    bool? isBusy,
    bool? loaded,
  }) => CartState(
    tableId: tableId,
    lines: lines ?? this.lines,
    totals: totals ?? this.totals,
    meta: meta ?? this.meta,
    activeTicketId: identical(activeTicketId, _unset)
        ? this.activeTicketId
        : activeTicketId as String?,
    firedSeq: firedSeq ?? this.firedSeq,
    isBusy: isBusy ?? this.isBusy,
    loaded: loaded ?? this.loaded,
  );
}

/// The bill [c]'s next round goes on: the one explicitly picked, else — for
/// a table's cart — the open bill on that table. Keyed on the situation, not
/// the role: a teller adding to a table's bill sees the bill so far too.
TicketView? cartTicket(OrderState s, CartState c) {
  final picked = c.activeTicketId;
  if (picked != null) {
    final t = s.openTickets.where((t) => t.id == picked).firstOrNull;
    if (t != null) return t;
  }
  final table = c.tableId;
  if (table == null) return null;
  return s.openTickets.where((t) => t.tableId == table).firstOrNull;
}

/// The floor's label for [c]'s table (else the one remembered with the
/// cart); null for takeaway.
String? cartTableLabel(OrderState s, CartState c) {
  final id = c.tableId;
  if (id == null) return null;
  return s.floorLayout?.tables.where((t) => t.id == id).firstOrNull?.label ??
      c.meta.tableLabel;
}

/// The party size known for [c]'s table: the bill's own count, else the core's
/// covers on the table, else what was picked at seating. Null for takeaway or
/// when nobody said.
int? cartGuests(OrderState s, CartState c) {
  final ticket = cartTicket(s, c);
  final table = c.tableId;
  final n =
      ticket?.guestCount ??
      (table == null
          ? null
          : s.floorLayout?.tables
                    .where((t) => t.id == table)
                    .firstOrNull
                    ?.covers ??
                s.pendingCovers[table] ??
                c.meta.covers);
  return n == null || n <= 0 ? null : n;
}

/// One context's cart notifier. Every bridge call passes [arg].
class CartNotifier extends Notifier<CartState> {
  CartNotifier(this.arg);

  /// The context (null = takeaway).
  final String? arg;

  MadarBridge get _bridge => ref.read(bridgeProvider);
  OrderNotifier get _order => ref.read(orderProvider.notifier);
  String _tr(String key) => _bridge.tr(key: key);

  @override
  CartState build() {
    // A closed till emptied every cart in the core: start over from it.
    ref.watch(cartsClearedTickProvider);
    // The core has this context's cart already (it persists); read it as
    // soon as anyone looks.
    unawaited(Future.microtask(load));
    return CartState(tableId: arg);
  }

  /// Bumped by every local write; a read that started before one does not
  /// land over it (the first read races the first tap on a fresh cart).
  int _writes = 0;

  /// Re-read lines, totals and meta from the core.
  Future<void> load() async {
    final seen = _writes;
    // Captured up front: the provider may be disposed across the awaits.
    final order = _order;
    final bridge = _bridge;
    final lines = await order._quiet(() => bridge.cartLines(tableId: arg));
    if (!ref.mounted) return;
    final totals = await order._quiet(() => bridge.cartTotals(tableId: arg));
    if (!ref.mounted) return;
    final meta = await order._quiet(() => bridge.cartMeta(tableId: arg));
    if (!ref.mounted) return;
    if (seen != _writes) return;
    state = state.copyWith(
      lines: lines ?? state.lines,
      totals: totals ?? state.totals,
      meta: meta ?? state.meta,
      loaded: true,
    );
  }

  /// Replace this cart's meta — here and in the core.
  Future<void> updateMeta(CartMeta Function(CartMeta) change) async {
    _writes += 1;
    final next = change(state.meta);
    state = state.copyWith(meta: next);
    await _order._quiet(() => _bridge.cartSetMeta(tableId: arg, meta: next));
  }

  /// Run a mutation that returns the new lines, then re-read the totals. The
  /// order's identity is stamped on its first line and forgotten once the
  /// cart empties (the booking, guest and covers stay with the table).
  Future<void> _apply(Future<List<CartLineView>> Function() op) async {
    _writes += 1;
    try {
      final lines = await op();
      final totals =
          await _order._quiet(() => _bridge.cartTotals(tableId: arg)) ??
          _emptyTotals;
      if (!ref.mounted) return;
      final meta = state.meta;
      state = state.copyWith(lines: lines, totals: totals);
      if (lines.isEmpty &&
          (meta.name.isNotEmpty ||
              meta.draftId != null ||
              meta.startedAt != null)) {
        await updateMeta(
          (m) => cartMetaWith(m, name: '', draftId: null, startedAt: null),
        );
      } else if (lines.isNotEmpty && meta.startedAt == null) {
        await updateMeta((m) => cartMetaWith(m, startedAt: nowIso()));
      }
    } on MadarError catch (e) {
      _order._fail(e);
    }
  }

  /// Add one unit of [item] — the core merges into the matching line.
  Future<void> add(MenuItemView item) => _apply(
    () => _bridge.cartAdd(
      tableId: arg,
      itemId: item.id,
      name: item.name,
      unitPriceMinor: item.basePriceMinor,
    ),
  );

  /// Add (or, in edit mode, replace) a configured line — one core call, so a
  /// refused edit keeps the original. Returns whether the cart took it.
  Future<bool> addConfigured({
    required String itemId,
    required List<AddonSelection> addons,
    required List<String> optionalIds,
    required int qty,
    String? sizeLabel,
    String? notes,
    String? replaceLineKey,
  }) async {
    var ok = true;
    try {
      if (replaceLineKey != null) {
        await _bridge.cartReplaceConfigured(
          tableId: arg,
          lineKey: replaceLineKey,
          itemId: itemId,
          sizeLabel: sizeLabel,
          addons: addons,
          optionalFieldIds: optionalIds,
          qty: qty,
          notes: notes,
        );
      } else {
        await _bridge.cartAddConfigured(
          tableId: arg,
          itemId: itemId,
          sizeLabel: sizeLabel,
          addons: addons,
          optionalFieldIds: optionalIds,
          qty: qty,
          notes: notes,
        );
      }
    } on MadarError catch (e) {
      ok = false;
      _order._fail(e);
      _order.showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
    }
    await _apply(() => _bridge.cartLines(tableId: arg));
    return ok;
  }

  /// Add a configured bundle at its fixed price.
  Future<void> addBundle(
    String bundleId,
    List<BundleComponentSelection> components,
  ) => _apply(
    () => _bridge.cartAddBundle(
      tableId: arg,
      bundleId: bundleId,
      components: components,
      qty: 1,
    ),
  );

  Future<void> setQty(String lineKey, int qty) =>
      _apply(() => _bridge.cartSetQty(tableId: arg, itemId: lineKey, qty: qty));

  /// Swipe-to-delete: the row leaves the state SYNCHRONOUSLY (a rebuild in
  /// the await window with the dismissed Dismissible still in the tree
  /// throws), then the core reconciles and an Undo toast is offered.
  Future<void> swipeRemove(CartLineView line) async {
    _writes += 1;
    state = state.copyWith(
      lines: state.lines.where((l) => l.key != line.key).toList(),
    );
    await _apply(() => _bridge.cartRemove(tableId: arg, itemId: line.key));
    _order.showToast(
      '${_tr('order.removed')} ${line.name}',
      actionLabel: _tr('order.undo'),
      action: () => unawaited(undoRemove()),
      seconds: 4,
      icon: 'trash',
    );
  }

  Future<void> undoRemove() =>
      _apply(() => _bridge.cartRestoreRemoved(tableId: arg));

  /// Empty this cart (its meta goes with it, in the core).
  Future<void> clear() async {
    await _order._quiet(() async {
      await _bridge.cartClear(tableId: arg);
      return true;
    });
    await load();
  }

  /// Rename the live order (empty clears back to the time label).
  Future<void> setName(String? name) =>
      updateMeta((m) => cartMetaWith(m, name: name?.trim() ?? ''));

  /// Pick (or clear) the bill this cart's next round goes on.
  void selectTicket(String? id) => state = state.copyWith(activeTicketId: id);

  // ── park ─────────────────────────────────────────────────────────────────

  /// Park this cart as a held order (on its own table, if it has one).
  Future<void> hold() => _order._heldOnce(() async {
    await _hold(onto: arg);
  });

  /// Park this cart ON [onto] (null = the counter) — the strip's "Assign
  /// table". Says where it landed.
  Future<void> holdOn(String? onto, String? label) =>
      _order._heldOnce(() async {
        if (state.lines.isEmpty) return;
        final ok = await _hold(onto: onto);
        if (ok && onto != null) {
          _order.showToast(
            _tr('drafts.on_table').replaceAll('{table}', label ?? ''),
            tone: ChipTone.success,
            icon: 'checkmark.circle',
          );
        }
      });

  /// Whether the order parked where it was asked to (false on a lost table
  /// race or a refusal — both already told the teller).
  Future<bool> _hold({required String? onto}) async {
    if (state.lines.isEmpty) return false;
    final bool conflict;
    try {
      conflict = await _bridge.holdCartOnTable(
        tableId: arg,
        // The draft keeps the ORDER's identity: its name, the id it was
        // restored from, and its first-item stamp.
        name: state.meta.name,
        draftId: state.meta.draftId,
        startedAt: state.meta.startedAt,
        ontoTableId: onto,
      );
    } on MadarError catch (e) {
      _order.showToast(
        _bridge.humanMessage(e),
        tone: ChipTone.danger,
        icon: 'xmark.circle',
      );
      return false;
    }
    if (conflict) {
      _order.showToast(
        _tr('tables.taken'),
        tone: ChipTone.warning,
        icon: 'table',
      );
    }
    await load();
    await Future.wait([_order.loadDrafts(), _order.loadFloor()]);
    return !conflict;
  }

  // ── fire / round ─────────────────────────────────────────────────────────

  /// Fire this cart as a NEW ticket, or add it as a ROUND to its bill. The
  /// kitchen's copy prints on its own.
  Future<bool> fireOrAddRound({String? notes, int? guestCount}) async {
    // A second tap while the first fire is on its way is not a second round.
    if (state.isBusy || state.lines.isEmpty) return false;
    final order = ref.read(orderProvider);
    final ticket = cartTicket(order, state);
    final label = cartTableLabel(order, state);
    // Captured BEFORE the fire: a successful one clears the cart.
    final round = List<CartLineView>.unmodifiable(state.lines);
    state = state.copyWith(isBusy: true);
    _order.clearError();
    var ok = false;
    try {
      if (ticket != null) {
        await _bridge.addTicketRound(tableId: arg, ticketId: ticket.id);
        _order.showToast(
          _tr('waiter.fired'),
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      } else {
        final fired = await _bridge.fireTicket(
          tableId: arg,
          // A table-less bill carries the name it was started under.
          customerName: state.name ?? state.meta.guestName,
          notes: notes,
          // The covers picked at seating, if nobody said otherwise since.
          guestCount: guestCount ?? _order.coversOn(arg) ?? state.meta.covers,
          // The booking this order seats, if "Seat this party" was tapped.
          bookingId: state.meta.bookingId,
        );
        _order._dropPendingCovers(arg);
        _order.showToast(
          fired.queuedOffline
              ? '${_tr('waiter.fired')} · ${_tr('waiter.queued')}'
              : _tr('waiter.fired'),
          tone: ChipTone.success,
          icon: 'checkmark.circle',
        );
      }
      ok = true;
    } on MadarError catch (e) {
      _order._fail(e);
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
    if (!ok || !ref.mounted) return false;
    await Future.wait([load(), _order.loadOpenTickets()]);
    unawaited(
      _order.printRound(round, tableLabel: label, ticketRef: ticket?.ticketRef),
    );
    state = state.copyWith(activeTicketId: null, firedSeq: state.firedSeq + 1);
    _order._refreshShell();
    return true;
  }

  /// This cart just CHECKED OUT through Charge — close the loop: the held
  /// order it was resumed from completes, and a table sale leaves its table
  /// needing a bus (and asks once).
  Future<void> onOrderSettled(String? draftId) async {
    final table = arg;
    final label = cartTableLabel(ref.read(orderProvider), state);
    if (draftId != null) {
      await _order._quiet(() async {
        await _bridge.completeDraft(id: draftId);
        return true;
      });
    }
    if (table != null) {
      await _order._busTableLocally(table);
      _order._askToClear(table, label);
    }
    await Future.wait([
      load(),
      _order.loadTillStats(),
      _order.loadDrafts(),
      _order.loadFloor(),
    ]);
  }
}

/// THE carts, one per context: `cartProvider(null)` is takeaway,
/// `cartProvider(tableId)` that table's own.
final NotifierProviderFamily<CartNotifier, CartState, String?> cartProvider =
    NotifierProvider.family<CartNotifier, CartState, String?>(CartNotifier.new);
