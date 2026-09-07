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
    this.cartLines = const [],
    this.loyaltyMember,
    this.loyaltyRewards = const [],
    this.redemptions = const {},
    this.loyaltyBusy = false,
    this.loyaltyError,
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

  // ── Loyalty rewards on this basket ────────────────────────────────────────
  // Redeeming happens HERE, before payment, because a reward changes what is
  // owed. Earning is the opposite — a separate button after the sale, open for
  // 24 hours. Pay less now, collect after.

  /// The cart's lines, in the order the server will index them. Loaded for a
  /// cart session only; a ticket settle has no cart to cover.
  final List<CartLineView> cartLines;

  /// The member whose balance is being spent, once scanned.
  final LoyaltyMemberView? loyaltyMember;

  /// What that balance can actually afford here — the server filters by both
  /// the branch's catalogue and the member's balance, so anything in this list
  /// is genuinely claimable.
  final List<LoyaltyRewardView> loyaltyRewards;

  /// Cart line index → units covered by a reward.
  final Map<int, int> redemptions;

  final bool loyaltyBusy;

  /// Why the last scan failed. Never blocks the sale — a card that will not
  /// scan must not stop a customer from paying.
  final String? loyaltyError;

  /// The reward priced for a cart line, when that line has one it can afford.
  LoyaltyRewardView? rewardForLine(int index) {
    if (index < 0 || index >= cartLines.length) return null;
    final itemId = cartLines[index].itemId;
    for (final r in loyaltyRewards) {
      if (r.menuItemId == itemId) return r;
    }
    return null;
  }

  /// What the ticked rewards cost in total, in the member's currency.
  int get redemptionCost {
    var total = 0;
    redemptions.forEach((index, units) {
      final r = rewardForLine(index);
      if (r != null) total += r.costAmount * units;
    });
    return total;
  }

  /// The balance left after the ticked rewards.
  int get balanceAfterRedemptions =>
      (loyaltyMember?.balance ?? 0) - redemptionCost;

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
    List<CartLineView>? cartLines,
    Object? loyaltyMember = _unset,
    List<LoyaltyRewardView>? loyaltyRewards,
    Map<int, int>? redemptions,
    bool? loyaltyBusy,
    Object? loyaltyError = _unset,
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
      cartLines: cartLines ?? this.cartLines,
      loyaltyMember: loyaltyMember == _unset
          ? this.loyaltyMember
          : loyaltyMember as LoyaltyMemberView?,
      loyaltyRewards: loyaltyRewards ?? this.loyaltyRewards,
      redemptions: redemptions ?? this.redemptions,
      loyaltyBusy: loyaltyBusy ?? this.loyaltyBusy,
      loyaltyError: loyaltyError == _unset
          ? this.loyaltyError
          : loyaltyError as String?,
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
    // The lines in the order the server indexes them — a reward names a line by
    // its position, so this list and the wire order must be the same list.
    final lines = await _quiet(bridge.cartLines) ?? const <CartLineView>[];
    _update(
      (s) => _withSession(s, bridge).copyWith(
        paymentMethods: methods,
        discounts: discounts,
        cartDiscountId: discountId,
        orgLogoPath: logo,
        cartLines: lines,
        summary: totals == null ? null : _summaryOf(totals),
      ),
    );
  }

  // ── Loyalty ───────────────────────────────────────────────────────────────

  /// Identify the member whose balance is about to be spent.
  ///
  /// Online only, and the core enforces it. Redeeming gives away goods: two
  /// disconnected tills could each honour the last reward and neither could be
  /// undone, because the coffee is gone. Earning has no such problem and works
  /// offline, which is why only this half insists.
  Future<bool> scanLoyalty({String? token, String? phone}) async {
    final bridge = _bridge;
    _update((s) => s.copyWith(loyaltyBusy: true, loyaltyError: null));
    try {
      final scan = await bridge.loyaltyLookup(token: token, phone: phone);
      if (!_live) return false;
      _update(
        (s) => s.copyWith(
          loyaltyMember: scan.member,
          loyaltyRewards: scan.rewards,
          loyaltyError: null,
        ),
      );
      MadarHaptics.success();
      return true;
    } on MadarError catch (e) {
      if (!_live) return false;
      _update((s) => s.copyWith(loyaltyError: bridge.humanMessage(e)));
      return false;
    } finally {
      if (_live) _update((s) => s.copyWith(loyaltyBusy: false));
    }
  }

  /// Cover one more unit of a cart line with a reward, or take the cover off.
  ///
  /// Refuses to tick past the balance — the server would reject the whole sale,
  /// and finding that out at the moment of payment is the worst time.
  void toggleReward(int lineIndex) {
    final s = state;
    final reward = s.rewardForLine(lineIndex);
    if (reward == null) return;
    final next = Map<int, int>.from(s.redemptions);
    final current = next[lineIndex] ?? 0;
    final qty = s.cartLines[lineIndex].qty;
    if (current >= qty) {
      next.remove(lineIndex);
    } else {
      final wouldCost = reward.costAmount;
      if (s.balanceAfterRedemptions < wouldCost) return;
      next[lineIndex] = current + 1;
    }
    _update((st) => st.copyWith(redemptions: next));
  }

  /// Drop the member and every reward with them.
  void clearLoyalty() => _update(
    (s) => s.copyWith(
      loyaltyMember: null,
      loyaltyRewards: const [],
      redemptions: const {},
      loyaltyError: null,
    ),
  );

  /// A settle / finalize session over a FIXED [summary] (e.g. a ticket's
  /// subtotal) — loads the payment methods only; the discount is frozen at
  /// fire time so the cart discount slice stays untouched.
  Future<void> startSettle(CheckoutSummary summary) async {
    final bridge = _bridge;
    final methods =
        await _quiet(bridge.listPaymentMethods) ?? const <PaymentMethodView>[];
    _update(
      (s) => _withSession(
        s,
        bridge,
      ).copyWith(paymentMethods: methods, summary: summary),
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
    _update((s) => s.copyWith(splitAmounts: {...s.splitAmounts, id: minor}));
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
        // WHICH lines, never a price. The server looks each reward up in the
        // branch's catalogue, checks the balance against the whole basket, and
        // refuses the sale outright if it does not cover it.
        loyaltyCustomerId: state.redemptions.isEmpty
            ? null
            : state.loyaltyMember?.id,
        loyaltyRedemptions: state.redemptions.entries
            .map((e) => CheckoutRedemption(itemIndex: e.key, units: e.value))
            .toList(growable: false),
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
