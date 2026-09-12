import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/charge_target.dart';
import 'package:feature_checkout/src/receipt_printing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

export 'package:feature_checkout/src/receipt_printing.dart'
    show PrintState, kReceiptChars, printerBrandOf;

/// Sentinel for [CheckoutState.copyWith]'s nullable fields.
const Object _unset = Object();

/// The money breakdown the drawer renders in its hero + summary line. The
/// cart session feeds it from the live cart totals; a bill from the ticket's
/// subtotal; an online order from its frozen totals.
@immutable
class CheckoutSummary {
  const CheckoutSummary({
    required this.subtotalMinor,
    required this.totalMinor,
    this.discountMinor = 0,
    this.taxMinor = 0,
    this.serviceChargeMinor = 0,
    this.deliveryFeeMinor = 0,
  });

  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int serviceChargeMinor;
  final int deliveryFeeMinor;
  final int totalMinor;
}

/// The tender the teller collected, handed to the legacy `CheckoutDrawer`'s
/// terminal action. The new Charge sheet reads the same picks straight off
/// [CheckoutState] and calls [CheckoutNotifier.charge].
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

/// A line a reward could cover, from either kind of session.
///
/// The cart names its lines by POSITION (the server indexes the items it is
/// sent, in order). A ticket names them by ID, because the server flattens the
/// ticket's rounds in its own order at settle time and a guessed position takes
/// the wrong item off the bill. One type carries both so the rewards UI is one
/// thing rather than two that drift.
@immutable
class RedeemableLine {
  const RedeemableLine({
    required this.itemId,
    required this.name,
    required this.qty,
    this.cartIndex,
    this.ticketLineId,
  });

  /// The menu item, for matching against the reward catalogue.
  final String itemId;
  final String name;
  final int qty;

  /// Position in the cart. Null for a ticket line.
  final int? cartIndex;

  /// `open_ticket_items.id`. Null for a cart line.
  final String? ticketLineId;
}

/// Why the Charge bar is dimmed, if it is. The sheet turns it into words.
enum ChargeBlock {
  /// Ready — the bar is lit.
  none,

  /// No open shift on this till. The bar says so instead of the figure.
  noShift,

  /// Cash needs an amount, a card needs a tap, a split needs to reach zero.
  needTender,

  /// The call is in flight.
  charging,
}

/// One tender session's state: org config (payment methods + discounts),
/// the money summary under charge, the teller's in-progress tender picks
/// (method / cash / tip / splits / discount / member), and the charge +
/// print lifecycle. All money math and order assembly live in the core.
@immutable
class CheckoutState {
  const CheckoutState({
    this.target,
    this.paymentMethods = const [],
    this.discounts = const [],
    this.cartDiscountId,
    this.billDiscount,
    this.orgLogoPath,
    this.currency = '',
    this.branchName = '',
    this.summary = const CheckoutSummary(subtotalMinor: 0, totalMinor: 0),
    this.taxInclusive = true,
    this.serviceChargeRate = 0,
    this.taxRate = 0,
    this.shiftId,
    this.shiftKnown = false,
    this.receipt,
    this.outcome,
    this.isPlacingOrder = false,
    this.printState = PrintState.idle,
    this.error,
    this.selectedMethodId,
    this.tenderedMinor = 0,
    this.tipOpen = false,
    this.tipMinor = 0,
    this.tipMethodId,
    this.splitMode = false,
    this.splitAmounts = const {},
    this.redeemableLines = const [],
    this.loyaltyAnyItem = false,
    this.loyaltyAnyItemCost = 0,
    this.loyaltyMember,
    this.loyaltyRewards = const [],
    this.redemptions = const {},
    this.loyaltyBusy = false,
    this.loyaltyError,
    this.loyaltyProgramme,
  });

  // ── what is being charged ─────────────────────────────────────────────────
  /// Null until a session starts (the legacy drawer's `startSettle` path
  /// leaves it null too and behaves as a bill without a ticket).
  final ChargeTarget? target;

  // ── org config + session mirrors ──────────────────────────────────────────
  final List<PaymentMethodView> paymentMethods;
  final List<DiscountView> discounts;

  /// The discount the CART carries (the core prices it live).
  final String? cartDiscountId;

  /// The discount picked for a BILL. The server applies it at settle; the
  /// till has no preview, which is why it is a pick and not a priced total.
  final DiscountView? billDiscount;

  /// Local file path of the core-cached org logo (offline-safe).
  final String? orgLogoPath;
  final String currency;
  final String branchName;

  /// What's being charged — live cart totals in a cart session, the ticket
  /// subtotal for a bill, the frozen totals for an online order.
  final CheckoutSummary summary;

  /// The session's tax policy, for the wording under the hero.
  final bool taxInclusive;
  final double serviceChargeRate;
  final double taxRate;

  /// The open shift's id, or null when there is none. [shiftKnown] flips
  /// once the lookup has answered, so the bar does not flash "no shift"
  /// during the first frame.
  final String? shiftId;
  final bool shiftKnown;

  // ── charge lifecycle ──────────────────────────────────────────────────────
  final ReceiptView? receipt;

  /// Set the moment money is taken. The sheet resolves with it.
  final ChargeOutcome? outcome;
  final bool isPlacingOrder;
  final PrintState printState;
  final String? error;

  // ── the teller's in-progress tender ───────────────────────────────────────
  /// Explicit method pick; null falls back to cash-first for a cart or a
  /// bill. An online order has no cash section, so there nothing is picked
  /// until the teller taps.
  final String? selectedMethodId;
  final int tenderedMinor;

  /// "Add tip" was tapped — the amount row is showing.
  final bool tipOpen;
  final int tipMinor;
  final String? tipMethodId;
  final bool splitMode;
  final Map<String, int> splitAmounts;

  // ── Loyalty rewards on this basket ────────────────────────────────────────
  // Redeeming happens HERE, before payment, because a reward changes what is
  // owed. Earning is the opposite — a separate button after the sale, open for
  // 24 hours. Pay less now, collect after.

  /// What this session's rewards could cover: the cart's lines in a cart
  /// session, the ticket's lines in a bill. Empty for an online order.
  final List<RedeemableLine> redeemableLines;

  /// The member whose balance is being spent, once scanned.
  final LoyaltyMemberView? loyaltyMember;

  /// The branch's programme — whether one runs at all, and what it is called.
  /// Null until the read lands; [loyaltyOffered] treats that as "not yet".
  final LoyaltyProgrammeView? loyaltyProgramme;

  /// May the till offer to attach a member? Only where a programme actually
  /// runs. A shop with none used to get a *Member ›* row that answered every
  /// scan with a lookup failure, which reads as a broken till rather than as
  /// a feature nobody bought.
  bool get loyaltyOffered => loyaltyProgramme?.enabled ?? false;

  /// What that balance can actually afford here — the server filters by both
  /// the branch's catalogue and the member's balance, so anything in this list
  /// is genuinely claimable.
  final List<LoyaltyRewardView> loyaltyRewards;

  /// The whole menu is claimable, not just [loyaltyRewards].
  ///
  /// A shop whose programme is "collect five, get anything" cannot express that
  /// as a catalogue without listing its entire menu and keeping that list in
  /// step forever. With this on the catalogue stops being the list of what MAY
  /// be claimed and every line is offered at [loyaltyAnyItemCost].
  final bool loyaltyAnyItem;

  /// What one line costs in that mode. Meaningless unless [loyaltyAnyItem].
  final int loyaltyAnyItemCost;

  /// Redeemable-line index → units covered by a reward.
  final Map<int, int> redemptions;

  final bool loyaltyBusy;

  /// Why the last scan failed. Never blocks the sale — a card that will not
  /// scan must not stop a customer from paying.
  final String? loyaltyError;

  // ── derived: which caller ─────────────────────────────────────────────────

  bool get isCart => target is CartChargeTarget;
  bool get isBill => target is BillChargeTarget;
  bool get isOnline => target is OnlineChargeTarget;

  /// Cash tendered, tip, discount and member exist only where the bridge
  /// call can carry them; an online finalize takes a method and nothing
  /// else.
  bool get takesTender => !isOnline;

  /// A table splits too, now that `settleTicket` carries its legs. Four people
  /// settling one bill across a card and two notes used to be recorded under
  /// whichever method the cashier tapped, and the drawer then reconciled
  /// against a card line that never moved.
  ///
  /// Still not an online order: a finalize takes one method and nothing else.
  bool get canSplit => !isOnline && paymentMethods.length >= 2;

  bool get shiftOpen => shiftId != null;

  // ── derived: the money ────────────────────────────────────────────────────

  /// The figure in the hero. A bill's is its SUBTOTAL — `TicketView` carries
  /// nothing else — and is labelled so.
  int get dueMinor => summary.totalMinor;
  bool get heroIsSubtotal => isBill;

  /// A bill's change is only honest when nothing is added on top of the
  /// subtotal the till can see: no service charge, and tax already inside
  /// the prices.
  bool get showsChange => !isBill || (serviceChargeRate == 0 && taxInclusive);

  /// The method that would charge if the teller tapped the bar now.
  String? get effectiveMethodId {
    final picked = selectedMethodId;
    if (picked != null && paymentMethods.any((m) => m.id == picked)) {
      return picked;
    }
    if (isOnline) {
      // Nothing to type, so the tap IS the pick — unless there is only one
      // method, where the bar simply names it.
      return paymentMethods.length == 1 ? paymentMethods.first.id : null;
    }
    final cash = paymentMethods.where((m) => m.isCash).firstOrNull;
    return (cash ?? paymentMethods.firstOrNull)?.id;
  }

  PaymentMethodView? get effectiveMethod =>
      paymentMethods.where((m) => m.id == effectiveMethodId).firstOrNull;

  bool get isCash => effectiveMethod?.isCash ?? false;

  /// A tip paid by cash comes out of the same drawer, so it is due with the
  /// bill. The tip can ride a DIFFERENT method than the order (card order +
  /// cash tip), so this gates on the TIP method's isCash.
  int get tipCashMinor {
    if (tipMinor <= 0) return 0;
    final tipMethod = paymentMethods
        .where((m) => m.id == (tipMethodId ?? effectiveMethodId))
        .firstOrNull;
    return (tipMethod?.isCash ?? isCash) ? tipMinor : 0;
  }

  /// What the cash in hand must reach.
  int get dueCashMinor => dueMinor + tipCashMinor;
  int get changeMinor => math.max(tenderedMinor - dueCashMinor, 0);
  int get shortMinor => math.max(dueCashMinor - tenderedMinor, 0);

  int get splitAllocated => splitAmounts.values.fold(0, (a, b) => a + b);
  int get splitRemaining => dueMinor - splitAllocated;

  List<CheckoutSplit> get splitLegs => [
    for (final e in splitAmounts.entries)
      if (e.value > 0)
        CheckoutSplit(paymentMethodId: e.key, amountMinor: e.value),
  ];

  /// The largest leg — the method the sale is booked against.
  String? get splitPrimary {
    String? id;
    var largest = 0;
    for (final e in splitAmounts.entries) {
      if (e.value > largest) {
        largest = e.value;
        id = e.key;
      }
    }
    return id;
  }

  /// Whether the bar is lit, and if not, why. The bar stays dimmed until a
  /// tender is picked or typed: cash needs an amount that covers the due,
  /// a card needs an explicit tap (or to be the only method), a split needs
  /// its legs to reach the due.
  ChargeBlock get block {
    if (isPlacingOrder) return ChargeBlock.charging;
    if (shiftKnown && !shiftOpen) return ChargeBlock.noShift;
    if (splitMode) {
      return splitRemaining == 0 && splitLegs.isNotEmpty
          ? ChargeBlock.none
          : ChargeBlock.needTender;
    }
    final method = effectiveMethod;
    if (method == null) return ChargeBlock.needTender;
    if (isOnline) return ChargeBlock.none;
    if (method.isCash) {
      return tenderedMinor >= dueCashMinor && dueCashMinor >= 0
          ? ChargeBlock.none
          : ChargeBlock.needTender;
    }
    // A non-cash method counts as picked only when the teller tapped it —
    // or there is nothing else it could be.
    final picked = selectedMethodId == method.id || paymentMethods.length == 1;
    return picked ? ChargeBlock.none : ChargeBlock.needTender;
  }

  bool get canCharge => block == ChargeBlock.none;

  /// Exact cash is the lit primary: it needs only a shift and cash to be
  /// the method.
  bool get canChargeExact =>
      !isPlacingOrder &&
      !(shiftKnown && !shiftOpen) &&
      !splitMode &&
      takesTender &&
      isCash;

  // ── derived: rewards ──────────────────────────────────────────────────────

  /// The reward priced for a line, when that line has one the balance affords.
  LoyaltyRewardView? rewardForLine(int index) {
    if (index < 0 || index >= redeemableLines.length) return null;
    final line = redeemableLines[index];
    for (final r in loyaltyRewards) {
      if (r.menuItemId == line.itemId) return r;
    }
    // "Collect five, get anything." A line the catalogue does not list is still
    // claimable, at the flat price. The server prices it the same way, so this
    // offers nothing it would then refuse.
    if (loyaltyAnyItem && (loyaltyMember?.balance ?? 0) >= loyaltyAnyItemCost) {
      return LoyaltyRewardView(
        menuItemId: line.itemId,
        name: line.name,
        priceMinor: 0,
        costCurrency: loyaltyMember?.mode ?? 'points',
        costAmount: loyaltyAnyItemCost,
        costLabel: '$loyaltyAnyItemCost ${loyaltyMember?.balanceLabel ?? ''}'
            .trim(),
      );
    }
    return null;
  }

  /// Indexes of the lines this balance could pay for. A basket of four
  /// coffees and a steak offers the coffees.
  List<int> get claimableLines => [
    for (var i = 0; i < redeemableLines.length; i++)
      if (rewardForLine(i) != null) i,
  ];

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

  /// The ticked rewards, in the shape the core takes.
  ///
  /// A cart line goes by position and a ticket line by id — the two paths index
  /// differently and only the server can resolve a ticket's.
  List<CheckoutRedemption> get redemptionInputs => [
    for (final e in redemptions.entries)
      if (e.key >= 0 && e.key < redeemableLines.length)
        CheckoutRedemption(
          itemIndex: redeemableLines[e.key].cartIndex ?? 0,
          ticketLineId: redeemableLines[e.key].ticketLineId,
          units: e.value,
        ),
  ];

  CheckoutState copyWith({
    Object? target = _unset,
    List<PaymentMethodView>? paymentMethods,
    List<DiscountView>? discounts,
    Object? cartDiscountId = _unset,
    Object? billDiscount = _unset,
    Object? orgLogoPath = _unset,
    String? currency,
    String? branchName,
    CheckoutSummary? summary,
    bool? taxInclusive,
    double? serviceChargeRate,
    double? taxRate,
    Object? shiftId = _unset,
    bool? shiftKnown,
    Object? receipt = _unset,
    Object? outcome = _unset,
    bool? isPlacingOrder,
    PrintState? printState,
    Object? error = _unset,
    Object? selectedMethodId = _unset,
    int? tenderedMinor,
    bool? tipOpen,
    int? tipMinor,
    Object? tipMethodId = _unset,
    bool? splitMode,
    Map<String, int>? splitAmounts,
    List<RedeemableLine>? redeemableLines,
    bool? loyaltyAnyItem,
    int? loyaltyAnyItemCost,
    Object? loyaltyMember = _unset,
    List<LoyaltyRewardView>? loyaltyRewards,
    Map<int, int>? redemptions,
    bool? loyaltyBusy,
    Object? loyaltyError = _unset,
    LoyaltyProgrammeView? loyaltyProgramme,
  }) {
    return CheckoutState(
      target: target == _unset ? this.target : target as ChargeTarget?,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      discounts: discounts ?? this.discounts,
      loyaltyProgramme: loyaltyProgramme ?? this.loyaltyProgramme,
      cartDiscountId: cartDiscountId == _unset
          ? this.cartDiscountId
          : cartDiscountId as String?,
      billDiscount: billDiscount == _unset
          ? this.billDiscount
          : billDiscount as DiscountView?,
      orgLogoPath: orgLogoPath == _unset
          ? this.orgLogoPath
          : orgLogoPath as String?,
      currency: currency ?? this.currency,
      branchName: branchName ?? this.branchName,
      summary: summary ?? this.summary,
      taxInclusive: taxInclusive ?? this.taxInclusive,
      serviceChargeRate: serviceChargeRate ?? this.serviceChargeRate,
      taxRate: taxRate ?? this.taxRate,
      shiftId: shiftId == _unset ? this.shiftId : shiftId as String?,
      shiftKnown: shiftKnown ?? this.shiftKnown,
      receipt: receipt == _unset ? this.receipt : receipt as ReceiptView?,
      outcome: outcome == _unset ? this.outcome : outcome as ChargeOutcome?,
      isPlacingOrder: isPlacingOrder ?? this.isPlacingOrder,
      printState: printState ?? this.printState,
      error: error == _unset ? this.error : error as String?,
      selectedMethodId: selectedMethodId == _unset
          ? this.selectedMethodId
          : selectedMethodId as String?,
      tenderedMinor: tenderedMinor ?? this.tenderedMinor,
      tipOpen: tipOpen ?? this.tipOpen,
      tipMinor: tipMinor ?? this.tipMinor,
      tipMethodId: tipMethodId == _unset
          ? this.tipMethodId
          : tipMethodId as String?,
      splitMode: splitMode ?? this.splitMode,
      splitAmounts: splitAmounts ?? this.splitAmounts,
      redeemableLines: redeemableLines ?? this.redeemableLines,
      loyaltyAnyItem: loyaltyAnyItem ?? this.loyaltyAnyItem,
      loyaltyAnyItemCost: loyaltyAnyItemCost ?? this.loyaltyAnyItemCost,
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

/// The Charge session — one autoDispose session per presented drawer, so
/// every charge starts fresh. The sheet kicks it in `initState` with
/// [start]; the legacy drawer's `startCart` / `startSettle` still work.
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

  /// Session snapshot fields shared by every session starter: currency,
  /// branch, the tax policy that decides the wording under the hero.
  CheckoutState _withSession(CheckoutState base, MadarBridge bridge) {
    final session = bridge.currentSession();
    return base.copyWith(
      currency: session?.currencyCode ?? '',
      branchName: bridge.deviceConfig().branchName ?? '',
      taxInclusive: session?.taxInclusive ?? true,
      serviceChargeRate: session?.serviceChargeRate ?? 0,
      taxRate: session?.taxRate ?? 0,
    );
  }

  /// The one honest gate on Charge: is there an open shift on this till.
  /// Answered after the first frame so the bar never flashes "no shift"
  /// while the lookup is in flight.
  Future<void> _loadShift() async {
    final shift = await _quiet(_bridge.currentShift);
    _update(
      (s) => s.copyWith(
        shiftId: (shift?.isOpen ?? false) ? shift!.id : null,
        shiftKnown: true,
      ),
    );
  }

  // ── session starters ─────────────────────────────────────────────────────

  /// Start the session for [target]. The one entry point the Charge sheet
  /// uses; the three below are what it dispatches to.
  Future<void> start(ChargeTarget target) => switch (target) {
    CartChargeTarget() => startCart(target: target),
    BillChargeTarget(:final ticket) => startBill(ticket, target: target),
    OnlineChargeTarget(:final order) => startOnline(order, target: target),
  };

  /// The cart session — payment methods, discounts, the applied cart
  /// discount, the org logo, the live cart totals as the summary, and the
  /// lines in the order the server indexes them (a reward names a line by
  /// its position, so this list and the wire order must be the same list).
  Future<void> startCart({
    ChargeTarget target = const CartChargeTarget(),
  }) async {
    final bridge = _bridge;
    _update((s) => s.copyWith(target: target));
    final methods =
        await _quiet(bridge.listPaymentMethods) ?? const <PaymentMethodView>[];
    final discounts =
        await _quiet(bridge.listDiscounts) ?? const <DiscountView>[];
    final discountId = await _quiet<String?>(bridge.cartDiscountId);
    final programme = await _quiet(bridge.loyaltySettings);
    final logo = bridge.orgLogoLocalPath();
    final totals = await _quiet(bridge.cartTotals);
    final lines = await _quiet(bridge.cartLines) ?? const <CartLineView>[];
    final redeemable = [
      for (var i = 0; i < lines.length; i++)
        RedeemableLine(
          itemId: lines[i].itemId,
          name: lines[i].name,
          qty: lines[i].qty,
          cartIndex: i,
        ),
    ];
    _update(
      (s) => _withSession(s, bridge).copyWith(
        paymentMethods: methods,
        discounts: discounts,
        loyaltyProgramme: programme,
        cartDiscountId: discountId,
        orgLogoPath: logo,
        redeemableLines: redeemable,
        summary: totals == null ? null : _summaryOf(totals),
      ),
    );
    await _loadShift();
  }

  /// A bill, priced by the SERVER.
  ///
  /// `totalMinor` used to be the ticket's subtotal, because `TicketView` had
  /// nothing else on it — so the drawer collected the lines while the settle
  /// booked lines + service charge + tax. Every branch sits at rate 0, so no
  /// till has yet been short; a new organisation defaults to 14% exclusive,
  /// and from that moment every dine-in bill would have been undercollected by
  /// exactly the tax.
  ///
  /// `ticket.bill` is absent only for a fire still in the outbox, which the
  /// server has never priced. Falling back to the subtotal there is honest —
  /// it is all that is known — and such a ticket cannot be charged anyway.
  Future<void> startBill(TicketView ticket, {ChargeTarget? target}) async {
    _update((s) => s.copyWith(target: target ?? BillChargeTarget(ticket)));
    final bill = ticket.bill;
    await startSettle(
      bill == null
          ? CheckoutSummary(
              subtotalMinor: ticket.subtotalMinor,
              totalMinor: ticket.subtotalMinor,
            )
          : CheckoutSummary(
              subtotalMinor: bill.subtotalMinor,
              discountMinor: bill.discountMinor,
              serviceChargeMinor: bill.serviceChargeMinor,
              taxMinor: bill.taxMinor,
              totalMinor: bill.totalMinor,
            ),
      ticketLines: ticket.lines,
      loadDiscounts: true,
    );
  }

  /// An online order: the frozen totals, and the methods. Nothing else —
  /// `deliveryFinalize` takes a method id and no more.
  Future<void> startOnline(
    DeliveryOrderView order, {
    ChargeTarget? target,
  }) async {
    _update((s) => s.copyWith(target: target ?? OnlineChargeTarget(order)));
    await startSettle(
      CheckoutSummary(
        subtotalMinor: order.subtotalMinor,
        discountMinor: order.discountMinor,
        deliveryFeeMinor: order.deliveryFeeMinor,
        totalMinor: order.totalMinor,
      ),
    );
  }

  /// A settle session over a FIXED [summary] — loads the payment methods
  /// (and, for a bill, the discounts) and leaves the cart's discount slice
  /// untouched. The legacy drawer's entry point; [startBill] and
  /// [startOnline] go through it.
  Future<void> startSettle(
    CheckoutSummary summary, {

    /// The ticket's live lines, so its bill can carry rewards too. Dine-in is
    /// an open ticket now, so without these a table order could never redeem —
    /// which would be most of them.
    List<TicketLineView> ticketLines = const [],
    bool loadDiscounts = false,
  }) async {
    final bridge = _bridge;
    final methods =
        await _quiet(bridge.listPaymentMethods) ?? const <PaymentMethodView>[];
    final discounts = loadDiscounts
        ? await _quiet(bridge.listDiscounts) ?? const <DiscountView>[]
        : const <DiscountView>[];
    final programme = await _quiet(bridge.loyaltySettings);
    final redeemable = [
      for (final l in ticketLines)
        // A voided line is not on the bill, and one that has not synced has no
        // id for the server to resolve — neither can be covered.
        if (!l.voided && l.id.isNotEmpty && l.menuItemId != null)
          RedeemableLine(
            itemId: l.menuItemId!,
            name: l.name,
            qty: l.qty,
            ticketLineId: l.id,
          ),
    ];
    _update(
      (s) => _withSession(s, bridge).copyWith(
        paymentMethods: methods,
        discounts: discounts,
        loyaltyProgramme: programme,
        orgLogoPath: bridge.orgLogoLocalPath(),
        summary: summary,
        redeemableLines: redeemable,
      ),
    );
    await _loadShift();
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
          loyaltyAnyItem: scan.anyItem,
          loyaltyAnyItemCost: scan.anyItemCost,
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

  /// Cover one more unit of a line with a reward, or take the cover off.
  ///
  /// Refuses to tick past the balance — the server would reject the whole sale,
  /// and finding that out at the moment of payment is the worst time.
  void toggleReward(int lineIndex) {
    final s = state;
    final reward = s.rewardForLine(lineIndex);
    if (reward == null) return;
    final next = Map<int, int>.from(s.redemptions);
    final current = next[lineIndex] ?? 0;
    final qty = s.redeemableLines[lineIndex].qty;
    if (current >= qty) {
      next.remove(lineIndex);
    } else {
      if (s.balanceAfterRedemptions < reward.costAmount) return;
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

  // ── tender picks (the drawer's collection state) ─────────────────────────

  void selectMethod(String id) =>
      _update((s) => s.copyWith(selectedMethodId: id));

  void setTendered(int minor) =>
      _update((s) => s.copyWith(tenderedMinor: minor));

  /// "Add tip ›" — reveal the amount row. Closing it drops the tip.
  void openTip() => _update((s) => s.copyWith(tipOpen: true));

  void closeTip() => _update(
    (s) => s.copyWith(tipOpen: false, tipMinor: 0, tipMethodId: null),
  );

  void setTip(int minor) => _update((s) => s.copyWith(tipMinor: minor));

  void setTipMethod(String id) => _update((s) => s.copyWith(tipMethodId: id));

  void toggleSplit() => _update((s) => s.copyWith(splitMode: !s.splitMode));

  void setSplitAmount(String id, int minor) {
    _update((s) => s.copyWith(splitAmounts: {...s.splitAmounts, id: minor}));
  }

  /// Surface (or clear) a failure inside the drawer — settle flows push
  /// their own op errors here so they present above the terminal button.
  void setError(String? message) => _update((s) => s.copyWith(error: message));

  // ── discount ─────────────────────────────────────────────────────────────

  /// Apply or clear the CART discount, then re-read the applied id and the
  /// totals so the hero updates live (natives' setDiscount).
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

  /// Pick the discount for a BILL. Nothing is priced here — the server
  /// applies it at settle and the hero keeps showing the subtotal, with the
  /// row saying "applied at charge" so nobody expects the figure to move.
  void setBillDiscount(DiscountView? discount) =>
      _update((s) => s.copyWith(billDiscount: discount));

  /// Either kind, for the row: the cart's applied discount or the bill's pick.
  DiscountView? get pickedDiscount {
    final s = state;
    if (s.isBill) return s.billDiscount;
    return s.discounts.where((d) => d.id == s.cartDiscountId).firstOrNull;
  }

  // ── the one terminal act ─────────────────────────────────────────────────

  /// Exact cash: fill the tendered amount with the due and charge in the
  /// same tap. The 3-tap counter sale is tile → Charge → Exact.
  Future<void> chargeExact() async {
    if (!state.canChargeExact) return;
    setTendered(state.dueCashMinor);
    await charge();
  }

  /// Take the money, whichever caller this is. On success [CheckoutState
  /// .outcome] is set (the sheet resolves with it) and the receipt prints;
  /// on refusal the server's sentence lands in [CheckoutState.error] and
  /// the drawer stays open.
  Future<void> charge() async {
    final s = state;
    if (!s.canCharge) return;
    final method = s.splitMode ? s.splitPrimary : s.effectiveMethodId;
    if (method == null) return;
    final bridge = _bridge;
    _update((st) => st.copyWith(isPlacingOrder: true, error: null));
    try {
      final outcome = await switch (s.target) {
        OnlineChargeTarget(:final order) => _chargeOnline(order, method),
        BillChargeTarget(:final ticket, :final tableLabel) => _chargeBill(
          ticket,
          method,
          tableLabel: tableLabel,
        ),
        CartChargeTarget() || null => _chargeCart(method),
      };
      if (!_live) return;
      _update(
        (st) => st.copyWith(
          outcome: outcome,
          receipt: outcome.receipt,
          printState: PrintState.idle,
        ),
      );
      MadarHaptics.success();
      ref.read(shellProvider.notifier).refresh();
      // Auto-print — the Done card's Reprint is for REPRINTS. Never fails
      // the sale: it reports a state and the card shows it.
      await printReceipt();
    } on MadarError catch (e) {
      _raise(bridge, e);
    } finally {
      if (_live) _update((st) => st.copyWith(isPlacingOrder: false));
    }
  }

  /// Place the cart as an order via the core (online or queued offline).
  /// Mirrors the natives' placeOrder split/tendered mapping: split legs
  /// zero the tendered amount, a non-cash single payment tenders 0.
  Future<ChargeOutcome> _chargeCart(String method) async {
    final s = state;
    final receipt = await _bridge.checkout(
      input: CheckoutInput(
        paymentMethodId: method,
        amountTenderedMinor: !s.splitMode && s.isCash ? s.tenderedMinor : 0,
        tipMinor: s.tipMinor,
        tipPaymentMethodId: s.tipMinor > 0 ? s.tipMethodId : null,
        splits: s.splitMode ? s.splitLegs : const [],
        // WHICH lines, never a price. The server looks each reward up in the
        // branch's catalogue, checks the balance against the whole basket, and
        // refuses the sale outright if it does not cover it.
        loyaltyCustomerId: s.redemptions.isEmpty ? null : s.loyaltyMember?.id,
        loyaltyRedemptions: s.redemptionInputs,
      ),
    );
    return ChargeOutcome(
      target: s.target ?? const CartChargeTarget(),
      queued: receipt.queuedOffline,
      amountMinor: receipt.totalMinor + receipt.tipMinor,
      methodLabel: receipt.paymentLabel,
      isCash: receipt.isCash,
      currency: s.currency,
      createdAt: receipt.createdAt,
      receipt: receipt,
      orderKey: receipt.localOrderId,
      orderNumber: receipt.orderNumber,
      changeMinor: receipt.changeMinor,
      loyaltyCustomerId: s.loyaltyMember?.id,
    );
  }

  /// Settle the ticket into a paid order on this shift. The order id comes
  /// back once the server acked — then its receipt is fetched and printed;
  /// null means queued offline, where no order exists yet.
  Future<ChargeOutcome> _chargeBill(
    TicketView ticket,
    String method, {
    String? tableLabel,
  }) async {
    final s = state;
    final bridge = _bridge;
    final shiftId = s.shiftId!;
    final tendered = s.isCash && s.tenderedMinor > 0 ? s.tenderedMinor : null;
    final discount = s.billDiscount;
    final orderId = await bridge.settleTicket(
      ticketId: ticket.id,
      shiftId: shiftId,
      paymentMethodId: method,
      amountTenderedMinor: tendered,
      tipMinor: s.tipMinor > 0 ? s.tipMinor : null,
      tipPaymentMethodId: s.tipMinor > 0 ? (s.tipMethodId ?? method) : null,
      discountId: discount?.id,
      discountType: discount?.dtype,
      discountValue: discount?.value,
      loyaltyCustomerId: s.redemptions.isEmpty ? null : s.loyaltyMember?.id,
      loyaltyRedemptions: s.redemptionInputs,
      splits: s.splitLegs,
    );
    ReceiptView? receipt;
    if (orderId != null) {
      // Best-effort: the money is taken; a receipt that cannot be fetched is
      // a reprint from history, not a failed charge.
      receipt = await _quiet(() => bridge.orderReceiptView(orderId: orderId));
    }
    final total = receipt?.totalMinor ?? s.dueMinor;
    return ChargeOutcome(
      target: s.target!,
      queued: orderId == null,
      amountMinor: total + (receipt?.tipMinor ?? s.tipMinor),
      methodLabel: receipt?.paymentLabel ?? (s.effectiveMethod?.name ?? ''),
      isCash: receipt?.isCash ?? s.isCash,
      currency: s.currency,
      createdAt: receipt?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
      receipt: receipt,
      orderId: orderId,
      orderNumber: receipt?.orderNumber,
      changeMinor: receipt?.changeMinor ?? (s.showsChange ? s.changeMinor : 0),
      tableId: ticket.tableId,
      tableLabel: tableLabel,
      loyaltyCustomerId: s.loyaltyMember?.id,
    );
  }

  /// Finalize the online order into a real sale on this shift — a method
  /// and nothing else, then the new order's receipt.
  Future<ChargeOutcome> _chargeOnline(
    DeliveryOrderView order,
    String method,
  ) async {
    final s = state;
    final bridge = _bridge;
    final res = await bridge.deliveryFinalize(
      id: order.id,
      paymentMethodId: method,
    );
    final receipt = await _quiet(
      () => bridge.orderReceiptView(orderId: res.orderId),
    );
    return ChargeOutcome(
      target: s.target!,
      queued: false,
      amountMinor: receipt?.totalMinor ?? order.totalMinor,
      methodLabel: receipt?.paymentLabel ?? (s.effectiveMethod?.name ?? ''),
      isCash: receipt?.isCash ?? s.isCash,
      currency: s.currency,
      createdAt: receipt?.createdAt ?? order.createdAt,
      receipt: receipt,
      orderId: res.orderId,
      orderNumber: receipt?.orderNumber,
    );
  }

  /// The legacy drawer's terminal action: a cart checkout from a
  /// [CheckoutResult]. New callers use [charge].
  Future<void> placeOrder(CheckoutResult result) async {
    _update(
      (s) => s.copyWith(
        selectedMethodId: result.primaryMethodId,
        tenderedMinor: result.tenderedMinor,
        tipMinor: result.tipMinor,
        tipMethodId: result.tipPaymentMethodId,
        splitMode: result.splits.isNotEmpty,
        splitAmounts: {
          for (final leg in result.splits) leg.paymentMethodId: leg.amountMinor,
        },
      ),
    );
    final bridge = _bridge;
    _update((s) => s.copyWith(isPlacingOrder: true, error: null));
    try {
      final receipt = await bridge.checkout(
        input: CheckoutInput(
          paymentMethodId: result.primaryMethodId,
          amountTenderedMinor: result.splits.isEmpty && result.isCash
              ? result.tenderedMinor
              : 0,
          tipMinor: result.tipMinor,
          tipPaymentMethodId: result.tipPaymentMethodId,
          customerName: result.customerName,
          notes: result.notes,
          splits: result.splits,
          loyaltyCustomerId: state.redemptions.isEmpty
              ? null
              : state.loyaltyMember?.id,
          loyaltyRedemptions: state.redemptionInputs,
        ),
      );
      if (!_live) return;
      _update((s) => s.copyWith(receipt: receipt, printState: PrintState.idle));
      MadarHaptics.success();
      ref.read(shellProvider.notifier).refresh();
      await printReceipt();
    } on MadarError catch (e) {
      _raise(bridge, e);
    } finally {
      if (_live) _update((s) => s.copyWith(isPlacingOrder: false));
    }
  }

  /// Print the session's receipt (best-effort). Pops the till on a cash sale
  /// — only on the original auto-print; a reprint passes [kickDrawer] false.
  Future<void> printReceipt({bool kickDrawer = true}) async {
    final r = state.receipt;
    if (r == null) return;
    _update((s) => s.copyWith(printState: PrintState.printing));
    final result = await printReceiptView(
      _bridge,
      ref.read(printerServiceProvider),
      r,
      kickDrawer: kickDrawer,
    );
    _update((s) => s.copyWith(printState: result));
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  CheckoutSummary _summaryOf(CartTotals totals) {
    return CheckoutSummary(
      subtotalMinor: totals.subtotalMinor,
      discountMinor: totals.discountMinor,
      taxMinor: totals.taxMinor,
      serviceChargeMinor: totals.serviceChargeMinor,
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

/// THE charge session — autoDispose so every presented drawer starts fresh.
final NotifierProvider<CheckoutNotifier, CheckoutState> checkoutProvider =
    NotifierProvider.autoDispose(CheckoutNotifier.new);
