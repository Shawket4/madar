import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Thermal receipt width in characters — the natives' `32u` raster width.
const int kReceiptChars = 32;

/// Print lifecycle of the receipt confirmation — the natives' `PrintState`.
enum PrintState { idle, printing, printed, failed, noPrinter }

/// Sentinel for [CheckoutState.copyWith]'s nullable fields.
const Object _unset = Object();

/// The money breakdown the checkout drawer renders in its summary card +
/// hero total. The cart tender session feeds it from the live cart totals;
/// a ticket settle / delivery finalize feeds it from the ticket's subtotal.
@immutable
class CheckoutSummary {
  const CheckoutSummary({
    required this.subtotalMinor,
    required this.totalMinor,
    this.discountMinor = 0,
    this.taxMinor = 0,
  });

  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int totalMinor;
}

/// The tender the teller collected, handed to `CheckoutDrawer`'s terminal
/// action. For a normal (non-split) charge [splits] is empty and
/// [primaryMethodId] is the chosen method; for a split, [splits] carries the
/// legs and [primaryMethodId] is the largest leg (the method the checkout
/// books against).
@immutable
class CheckoutResult {
  const CheckoutResult({
    required this.primaryMethodId,
    required this.tenderedMinor,
    required this.tipMinor,
    required this.splits,
    required this.isCash,
    this.tipPaymentMethodId,
    this.customerName,
    this.notes,
  });

  final String primaryMethodId;
  final int tenderedMinor;
  final int tipMinor;
  final String? tipPaymentMethodId;
  final String? customerName;
  final String? notes;
  final List<CheckoutSplit> splits;
  final bool isCash;
}

/// One tender session's state: org config (payment methods + discounts),
/// the money summary under charge, the teller's in-progress tender picks
/// (method / cash / tip / splits), and the checkout + print lifecycle.
/// All money math and order assembly live in the core.
@immutable
class CheckoutState {
  const CheckoutState({
    this.paymentMethods = const [],
    this.discounts = const [],
    this.cartDiscountId,
    this.orgLogoPath,
    this.currency = '',
    this.branchName = '',
    this.summary = const CheckoutSummary(subtotalMinor: 0, totalMinor: 0),
    this.receipt,
    this.isPlacingOrder = false,
    this.printState = PrintState.idle,
    this.error,
    this.selectedMethodId,
    this.tenderedMinor = 0,
    this.tipMinor = 0,
    this.tipMethodId,
    this.splitMode = false,
    this.splitAmounts = const {},
  });

  // ── org config + session mirrors ──────────────────────────────────────────
  final List<PaymentMethodView> paymentMethods;
  final List<DiscountView> discounts;
  final String? cartDiscountId;

  /// Local file path of the core-cached org logo (offline-safe).
  final String? orgLogoPath;
  final String currency;
  final String branchName;

  /// What's being charged — live cart totals in a cart session, the ticket
  /// subtotal in a settle session.
  final CheckoutSummary summary;

  // ── checkout lifecycle ─────────────────────────────────────────────────────
  final ReceiptView? receipt;
  final bool isPlacingOrder;
  final PrintState printState;
  final String? error;

  // ── the teller's in-progress tender ───────────────────────────────────────
  /// Explicit method pick; null falls back to cash-first.
  final String? selectedMethodId;
  final int tenderedMinor;
  final int tipMinor;
  final String? tipMethodId;
  final bool splitMode;
  final Map<String, int> splitAmounts;

  CheckoutState copyWith({
    List<PaymentMethodView>? paymentMethods,
    List<DiscountView>? discounts,
    Object? cartDiscountId = _unset,
    Object? orgLogoPath = _unset,
    String? currency,
    String? branchName,
    CheckoutSummary? summary,
    Object? receipt = _unset,
    bool? isPlacingOrder,
    PrintState? printState,
    Object? error = _unset,
    Object? selectedMethodId = _unset,
    int? tenderedMinor,
    int? tipMinor,
    Object? tipMethodId = _unset,
    bool? splitMode,
    Map<String, int>? splitAmounts,
  }) {
    return CheckoutState(
      paymentMethods: paymentMethods ?? this.paymentMethods,
      discounts: discounts ?? this.discounts,
      cartDiscountId: cartDiscountId == _unset
          ? this.cartDiscountId
          : cartDiscountId as String?,
      orgLogoPath: orgLogoPath == _unset
          ? this.orgLogoPath
          : orgLogoPath as String?,
      currency: currency ?? this.currency,
      branchName: branchName ?? this.branchName,
      summary: summary ?? this.summary,
      receipt: receipt == _unset ? this.receipt : receipt as ReceiptView?,
      isPlacingOrder: isPlacingOrder ?? this.isPlacingOrder,
      printState: printState ?? this.printState,
      error: error == _unset ? this.error : error as String?,
      selectedMethodId: selectedMethodId == _unset
          ? this.selectedMethodId
          : selectedMethodId as String?,
      tenderedMinor: tenderedMinor ?? this.tenderedMinor,
      tipMinor: tipMinor ?? this.tipMinor,
      tipMethodId: tipMethodId == _unset
          ? this.tipMethodId
          : tipMethodId as String?,
      splitMode: splitMode ?? this.splitMode,
      splitAmounts: splitAmounts ?? this.splitAmounts,
    );
  }
}

/// The checkout state holder — one autoDispose session per presented tender
/// drawer, so every checkout / settle starts fresh. The presenting sheet
/// kicks the session in `initState`:
///
/// - the cashier tender: `ref.read(checkoutProvider.notifier).startCart()`
/// - a ticket settle:
///   `ref.read(checkoutProvider.notifier).startSettle(CheckoutSummary(...))`
///
/// Mirrors the natives' AppModel checkout slice: all money math and order
/// assembly live in the core; this only sequences bridge calls.
class CheckoutNotifier extends Notifier<CheckoutState> {
  /// Flips false on dispose — async continuations must not touch [state]
  /// (or [ref]) after the sheet closed.
  bool _live = false;

  @override
  CheckoutState build() {
    _live = true;
    ref.onDispose(() => _live = false);
    return const CheckoutState();
  }

  MadarBridge get _bridge => ref.read(bridgeProvider);

  /// Guarded state write — async continuations may land after the sheet
  /// closed (autoDispose), and a disposed notifier must not touch [state].
  void _update(CheckoutState Function(CheckoutState s) transform) {
    if (_live) state = transform(state);
  }

  /// Session snapshot fields shared by both session starters.
  CheckoutState _withSession(CheckoutState base, MadarBridge bridge) {
    return base.copyWith(
      currency: bridge.currentSession()?.currencyCode ?? '',
      branchName: bridge.deviceConfig().branchName ?? '',
    );
  }

  // ── session starters ─────────────────────────────────────────────────────

  /// The cashier tender session — mirror of the natives' on-appear load:
  /// payment methods, discounts, the applied cart discount, the org logo,
  /// and the live cart totals as the summary.
  Future<void> startCart() async {
    final bridge = _bridge;
    final methods =
        await _quiet(bridge.listPaymentMethods) ?? const <PaymentMethodView>[];
    final discounts =
        await _quiet(bridge.listDiscounts) ?? const <DiscountView>[];
    final discountId = await _quiet<String?>(bridge.cartDiscountId);
    final logo = bridge.orgLogoLocalPath();
    final totals = await _quiet(bridge.cartTotals);
    _update(
      (s) => _withSession(s, bridge).copyWith(
        paymentMethods: methods,
        discounts: discounts,
        cartDiscountId: discountId,
        orgLogoPath: logo,
        summary: totals == null ? null : _summaryOf(totals),
      ),
    );
  }

  /// A settle / finalize session over a FIXED [summary] (e.g. a ticket's
  /// subtotal) — loads the payment methods only; the discount is frozen at
  /// fire time so the cart discount slice stays untouched.
  Future<void> startSettle(CheckoutSummary summary) async {
    final bridge = _bridge;
    final methods =
        await _quiet(bridge.listPaymentMethods) ?? const <PaymentMethodView>[];
    _update(
      (s) => _withSession(s, bridge).copyWith(
        paymentMethods: methods,
        summary: summary,
      ),
    );
  }

  // ── tender picks (the drawer's collection state) ─────────────────────────

  void selectMethod(String id) =>
      _update((s) => s.copyWith(selectedMethodId: id));

  void setTendered(int minor) =>
      _update((s) => s.copyWith(tenderedMinor: minor));

  void setTip(int minor) => _update((s) => s.copyWith(tipMinor: minor));

  void setTipMethod(String id) => _update((s) => s.copyWith(tipMethodId: id));

  void toggleSplit() => _update((s) => s.copyWith(splitMode: !s.splitMode));

  void setSplitAmount(String id, int minor) {
    _update(
      (s) => s.copyWith(splitAmounts: {...s.splitAmounts, id: minor}),
    );
  }

  /// Surface (or clear) a failure inside the drawer — settle flows push
  /// their own op errors here so they present above the terminal button.
  void setError(String? message) => _update((s) => s.copyWith(error: message));

  // ── cart ops ─────────────────────────────────────────────────────────────

  /// Apply or clear the cart discount, then re-read the applied id and the
  /// totals so the summary + hero total update live (natives' setDiscount).
  Future<void> setDiscount(String? id) async {
    final bridge = _bridge;
    await _quiet(() async {
      if (id != null) {
        await bridge.cartSetDiscount(discountId: id);
      } else {
        await bridge.cartClearDiscount();
      }
      return true;
    });
    final discountId = await _quiet<String?>(bridge.cartDiscountId);
    final totals = await _quiet(bridge.cartTotals);
    if (!_live) return;
    _update(
      (s) => s.copyWith(
        cartDiscountId: discountId,
        summary: totals == null ? null : _summaryOf(totals),
      ),
    );
    ref.read(shellProvider.notifier).refresh();
  }

  /// Place the cart as an order via the core (online or queued offline). On
  /// success the core has emptied the cart; the receipt flips the sheet to
  /// the confirmation and the shell refreshes. Mirrors the natives'
  /// placeOrder split/tendered mapping: split legs zero the tendered amount,
  /// a non-cash single payment tenders 0.
  Future<void> placeOrder(CheckoutResult result) async {
    final bridge = _bridge;
    _update((s) => s.copyWith(isPlacingOrder: true, error: null));
    try {
      final input = CheckoutInput(
        paymentMethodId: result.primaryMethodId,
        amountTenderedMinor: result.splits.isEmpty && result.isCash
            ? result.tenderedMinor
            : 0,
        tipMinor: result.tipMinor,
        tipPaymentMethodId: result.tipPaymentMethodId,
        customerName: result.customerName,
        notes: result.notes,
        splits: result.splits,
      );
      final receipt = await bridge.checkout(input: input);
      if (!_live) return;
      _update((s) => s.copyWith(receipt: receipt, printState: PrintState.idle));
      MadarHaptics.success();
      ref.read(shellProvider.notifier).refresh();
      // Auto-print the receipt on checkout — the confirmation's Print button
      // is for REPRINTS. `printReceipt` no-ops with no printer configured and
      // swallows its own errors (sets PrintState.failed), so it can never
      // fail the placed order.
      await printReceipt();
    } on MadarError catch (e) {
      _raise(bridge, e);
    } finally {
      if (_live) _update((s) => s.copyWith(isPlacingOrder: false));
    }
  }

  /// Render the placed receipt in the core and stream it to the configured
  /// network printer (best-effort). Pops the till on a cash sale — only on
  /// the original auto-print; a reprint passes [kickDrawer] = false.
  Future<void> printReceipt({bool kickDrawer = true}) async {
    final bridge = _bridge;
    final r = state.receipt;
    if (r == null) return;
    // Resolve the device's transport (Bluetooth or raw-TCP) up front; null
    // means no printer is bound yet.
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      _update((s) => s.copyWith(printState: PrintState.noPrinter));
      return;
    }
    final brand = printerBrandOf(bridge.deviceConfig().printerBrand);
    _update((s) => s.copyWith(printState: PrintState.printing));
    try {
      final bytes = await bridge.renderReceipt(
        receipt: r,
        storeName: state.branchName,
        currency: state.currency,
        width: kReceiptChars,
        brand: brand,
      );
      await tx.send(bytes);
      if (kickDrawer && r.isCash) {
        // Best-effort — a drawer that fails to open must not mark the receipt
        // (already printed) as failed, whatever the transport throws.
        try {
          final kick = await bridge.cashDrawerKick(brand: brand);
          await tx.send(kick);
        } on Exception {
          // ignored: the receipt printed; the kick is a bonus.
        }
      }
      _update((s) => s.copyWith(printState: PrintState.printed));
    } on Exception {
      _update((s) => s.copyWith(printState: PrintState.failed));
    }
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  CheckoutSummary _summaryOf(CartTotals totals) {
    return CheckoutSummary(
      subtotalMinor: totals.subtotalMinor,
      discountMinor: totals.discountMinor,
      taxMinor: totals.taxMinor,
      totalMinor: totals.totalMinor,
    );
  }

  /// Surface a failed op — human message into the drawer banner, plus the
  /// shared re-auth request on a 401 with a live session.
  void _raise(MadarBridge bridge, MadarError e) {
    _update((s) => s.copyWith(error: bridge.humanMessage(e)));
    if (!_live) return;
    if (e is MadarError_Unauthenticated && bridge.currentSession() != null) {
      ref.read(reauthRequestProvider.notifier).request();
    }
  }

  /// Run a bridge call whose failure the natives swallow (cache reads,
  /// best-effort refreshes) — returns null instead of surfacing the error. A
  /// transport-class failure nudges the connectivity service (one debounced
  /// probe), so offline is noticed here instead of on a blanket timer.
  Future<T?> _quiet<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
      return null;
    }
  }
}

/// THE checkout session — autoDispose so every presented tender/settle
/// drawer starts fresh.
final NotifierProvider<CheckoutNotifier, CheckoutState> checkoutProvider =
    NotifierProvider.autoDispose(CheckoutNotifier.new);

/// Device-config brand string (`epson`/`star`) → [PrinterBrand]; anything
/// else falls back to Epson (the natives' default dialect).
PrinterBrand printerBrandOf(String? brand) =>
    brand == 'star' ? PrinterBrand.star : PrinterBrand.epson;
