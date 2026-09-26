part of 'done_card.dart';

/// The Done card's view model, shared with Fast mode's [DonePage]: one sale's
/// live state and its actions, drawn two ways.
///
/// The state: how the print went (the auto-print answers after the sale),
/// whether the sale is still queued (a sync tick re-reads it), a table
/// clear in flight or refused. The actions: Reprint, Cleared, Add points,
/// and the auto-dismiss that steps aside once nothing is left to answer.
/// Self-contained: the Charge session is gone by the time Done is up, so it
/// prints, awards and clears with its own calls.
mixin _DoneSale<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  /// The sale being shown.
  ChargeOutcome get _outcome;

  /// Put Done away with [result].
  void _finish(DoneCardResult result);

  late PrintState _print = _outcome.printState;
  bool _clearing = false;
  String? _clearError;

  // A card kept open for a table's "cleared?" answer can outlive the
  // outbox drain — without this it would say "Queued" forever even after
  // the sale synced. Local state so a sync tick can flip it live.
  late bool _queued = _outcome.queued;
  late ReceiptView? _receipt = _outcome.receipt;

  /// The pool line the core worded when the sale was rung ("3 left today").
  /// The synced record does not carry it, so it is kept across the re-read —
  /// unless the server turned out not to support staff drinks, which the
  /// re-read says instead.
  late String? _staffNotice = _outcome.receipt?.staffNotice;
  bool _syncChecking = false;
  ProviderSubscription<int>? _syncSub;

  /// The card steps aside by itself once nothing is left to answer — the
  /// next customer is already at the counter. A touch on the card holds it.
  Timer? _autoDismiss;

  static const Duration _dismissAfter = Duration(seconds: 6);

  /// The sale's reference: the device number reads the same queued or
  /// synced (`36B-12`); the older fallbacks stay for a sale rung without one.
  String get _saleRef {
    final o = _outcome;
    final display = _receipt?.displayNumber ?? '';
    return display.isNotEmpty
        ? '#$display'
        : _queued
        ? '#${o.orderKey?.substring(0, o.orderKey!.length.clamp(0, 8)) ?? ''}'
        : o.orderNumber != null
        ? '#${o.orderNumber}'
        : (_receipt?.orderRef ?? '');
  }

  /// Add points is offered only where a programme runs — and the sale must
  /// name itself. Read off the OUTCOME: the Charge session may already be
  /// gone, and a fresh one knows nothing about the programme.
  bool get _offersPoints => _outcome.canAwardPoints && _outcome.loyaltyOffered;

  void _holdOpen() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
  }

  void _armDismiss() {
    _holdOpen();
    // A table still waiting for "cleared?", or paper that did not come out,
    // is a question for the teller: those cards wait.
    final o = _outcome;
    if (o.tableId != null) return;
    if (_print == PrintState.failed || _print == PrintState.noPrinter) return;
    _autoDismiss = Timer(_dismissAfter, () {
      if (mounted) _finish(DoneCardResult.notYet);
    });
  }

  @override
  void dispose() {
    _syncSub?.close();
    _holdOpen();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _armDismiss();
    // The auto-print is still running in the background: say "Printing…"
    // until it answers. It always answers — a timeout is a state too.
    final job = _outcome.printJob;
    if (job != null) {
      unawaited(
        job.then((result) {
          if (mounted && _print == PrintState.printing) {
            setState(() => _print = result);
            if (_autoDismiss != null) _armDismiss();
          }
        }),
      );
    }
    // The core bumps this on every sync event; a queued sale re-checks its
    // own record on each one rather than polling on a timer.
    if (_queued) {
      _syncSub = ref.listenManual(syncTickProvider, (_, _) {
        unawaited(_checkSynced());
      });
    }
  }

  /// Re-read this sale's record — a LOCAL lookup by client key or server id
  /// (`order_full_for` resolves either), so this only reaches the network in
  /// the rare case the row is not local yet. Flips the card out of "Queued"
  /// the moment the outbox has actually acked it.
  Future<void> _checkSynced() async {
    final key = _outcome.orderKey;
    if (!mounted || !_queued || _syncChecking || key == null) return;
    _syncChecking = true;
    try {
      final r = await ref.read(bridgeProvider).orderReceiptView(orderId: key);
      if (!mounted || r.queuedOffline) return;
      setState(() {
        _queued = false;
        _receipt = r;
        _staffNotice = r.staffNotice ?? _staffNotice;
      });
      _syncSub?.close();
      _syncSub = null;
      if (_autoDismiss != null) _armDismiss();
    } on Object catch (_) {
      // Best-effort, as printReceiptView: the row may not have landed
      // locally yet, or the bridge threw — the next sync tick tries again.
    } finally {
      _syncChecking = false;
    }
  }

  Future<void> _reprint() async {
    final receipt = _receipt;
    if (receipt == null || _print == PrintState.printing) return;
    setState(() => _print = PrintState.printing);
    final result = await printReceiptView(
      ref.read(bridgeProvider),
      ref.read(printerServiceProvider),
      receipt,
      kickDrawer: false,
    );
    if (mounted) setState(() => _print = result);
  }

  /// The plates are gone. Optimistic locally and queued for the server, so
  /// it works offline like everything else on the floor.
  Future<void> _clear(String tableId) async {
    if (_clearing) return;
    setState(() {
      _clearing = true;
      _clearError = null;
    });
    final bridge = ref.read(bridgeProvider);
    try {
      await bridge.clearTable(tableId: tableId);
      if (!mounted) return;
      MadarHaptics.success();
      _finish(DoneCardResult.cleared);
    } on MadarError catch (e) {
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _clearError = bridge.humanMessage(e);
      });
    }
  }

  Future<void> _addPoints() async {
    final o = _outcome;
    await showMadarSheet<bool>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => LoyaltyAwardSheet(
        orderId: o.orderId,
        // A just-rung cart sale is known by its client key — the server id
        // may not exist yet.
        orderKey: o.orderId == null ? o.orderKey : null,
        orderCreatedAt: o.createdAt,
        // If a card was scanned to pay, it is the same customer collecting —
        // no second scan.
        customerId: o.loyaltyCustomerId,
      ),
    );
  }
}
