import 'dart:async';

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
    this.serviceChargeWaivedMinor = 0,
  });

  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int serviceChargeMinor;
  final int deliveryFeeMinor;
  final int totalMinor;

  /// The service charge the waiver took off this bill (not in the total).
  final int serviceChargeWaivedMinor;
}

/// Why the Charge bar is dimmed, if it is. The sheet turns it into words.
enum ChargeBlock {
  /// Ready — the bar is lit.
  none,

  /// The session is still loading (methods, the till lookup). Nothing may
  /// charge yet: a bill charged before the till answered had no till id.
  loading,

  /// The payment methods could not be loaded, or the branch has none.
  noMethods,

  /// No open till on this till. The bar says so instead of the figure.
  noTill,

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
    this.cartDiscount,
    this.billDiscount,
    this.billDiscountCleared = false,
    this.billDiscountApproval,
    this.waiveService = false,
    this.canWaiveService = false,
    this.orgLogoPath,
    this.currency = '',
    this.branchName = '',
    this.summary = const CheckoutSummary(subtotalMinor: 0, totalMinor: 0),
    this.taxInclusive = true,
    this.serviceChargeRate = 0,
    this.taxRate = 0,
    this.tillId,
    this.loaded = false,
    this.tender = const TenderSummaryView(
      chargeTotalMinor: 0,
      dueCashMinor: 0,
      changeMinor: 0,
      shortMinor: 0,
      splitAllocatedMinor: 0,
      splitRemainingMinor: 0,
      dueLabelKey: 'order.total',
      dueIsSubtotal: false,
      showsChange: true,
    ),
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
    this.dineIn = false,
    this.splitMode = false,
    this.splitAmounts = const {},
    this.baseSummary,
    this.rewardLines = const [],
    this.loyaltyScan,
    this.rewardPicks = const [],
    this.rewardBoard,
    this.rewardRedemptions = const [],
    this.loyaltyBusy = false,
    this.loyaltyError,
    this.loyaltyProgramme,
    this.customer,
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

  /// The cart's discount as the core holds it: a preset, or an amount /
  /// percentage typed by hand, and who approved it.
  final CartDiscountView? cartDiscount;

  /// The discount picked for a BILL. The core re-prices the bill under it
  /// (`billWithRewards`), so the hero, the change and the split legs collect
  /// exactly what the settle books.
  final DiscountView? billDiscount;

  /// "No discount" picked on a bill: the waiter's discount is cleared (the
  /// settle sends `none`), rather than inherited.
  final bool billDiscountCleared;

  /// The manager's approval for this BILL's discount, when it is over the
  /// cashier's cap. Minted at the charge tap (the only place with a context to
  /// show the PIN sheet) and carried to `settleTicket`, which refuses without
  /// it and sends it on the queued settle for the server to verify again.
  final ApprovalView? billDiscountApproval;

  /// The service charge is removed from this bill. Only offered when
  /// [canWaiveService].
  final bool waiveService;

  /// The signed-in PIN user's effective `orders:waive_service` grant, read
  /// from the core — never the role's name.
  final bool canWaiveService;

  /// Local file path of the core-cached org logo (offline-safe).
  final String? orgLogoPath;
  final String currency;
  final String branchName;

  /// What's being charged — live cart totals in a cart session, the ticket
  /// subtotal for a bill, the frozen totals for an online order.
  final CheckoutSummary summary;

  /// The tax policy for the wording under the hero: a bill's own frozen
  /// figures, the session's for a counter cart (which carries no service
  /// charge — takeaway).
  final bool taxInclusive;
  final double serviceChargeRate;
  final double taxRate;

  /// The till this sale books onto, or null when none is open. It is the
  /// shell's (`shellProvider.till`, the one owner), seeded when the session
  /// starts and kept in step by [CheckoutNotifier]'s subscription — never a
  /// lookup of this sheet's own, so it is known from the first frame and
  /// cannot lag a till opened or closed while the drawer is up.
  final String? tillId;

  /// The session's reads have answered (methods, discounts, programme).
  final bool loaded;

  /// The core's figures for the tender in hand — kept in step with every
  /// pick by [CheckoutNotifier], never computed here.
  final TenderSummaryView tender;

  // ── charge lifecycle ──────────────────────────────────────────────────────
  final ReceiptView? receipt;

  /// Set the moment money is taken. The sheet resolves with it.
  final ChargeOutcome? outcome;
  final bool isPlacingOrder;
  final PrintState printState;
  final UiText? error;

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

  /// The customer is drinking in, so no cup, lid or straw comes off stock.
  /// Defaults to false — a pickup. Independent of the floor: a counter shop
  /// with no tables can say it, which is the whole point. It never moves a
  /// total; the service charge stays tied to a table.
  final bool dineIn;
  final bool splitMode;
  final Map<String, int> splitAmounts;

  // ── Loyalty rewards on this basket ────────────────────────────────────────
  // Redeeming happens HERE, before payment, because a reward changes what is
  // owed. Earning is the opposite — a separate button after the sale, open for
  // 24 hours. Pay less now, collect after.

  /// What this session's rewards could cover — the core's projection of the
  /// cart's lines (by position) or the bill's live lines (by id).
  final List<RewardLineInput> rewardLines;

  /// The last lookup (or refresh) of the attached member: balance, catalogue,
  /// the shop's per-order cap. Null until a card is scanned.
  final LoyaltyScanView? loyaltyScan;

  /// The member whose balance is being spent, once scanned.
  LoyaltyMemberView? get loyaltyMember => loyaltyScan?.member;

  /// The branch's programme — whether one runs at all, and what it is called.
  /// Null until the read lands; [loyaltyOffered] treats that as "not yet".
  final LoyaltyProgrammeView? loyaltyProgramme;

  /// May the till offer to attach a member? Only where a programme actually
  /// runs.
  bool get loyaltyOffered => loyaltyProgramme?.enabled ?? false;

  /// The rewards the teller asked for, as taps.
  final List<RewardPick> rewardPicks;

  /// The core's verdict on [rewardPicks]: which lines are claimable, why one
  /// cannot take another, what survives the cap and the balance, what it
  /// costs and what it takes off the bill. Null with no member attached.
  final RewardBoardView? rewardBoard;

  /// The surviving picks in the shape checkout/settle sends.
  final List<CheckoutRedemption> rewardRedemptions;

  /// The summary before rewards (the cart's totals, the server's bill) — what
  /// [summary] is re-priced from whenever the rewards change.
  final CheckoutSummary? baseSummary;

  final bool loyaltyBusy;

  // ── Manual customer (phase 6) ─────────────────────────────────────────────
  /// The customer this counter sale is for, when the teller attached one.
  /// Separate from the loyalty member: no balance, just who bought it.
  final CustomerView? customer;

  /// Why the last scan failed. Never blocks the sale — a card that will not
  /// scan must not stop a customer from paying.
  final UiText? loyaltyError;

  // ── derived: which caller ─────────────────────────────────────────────────

  bool get isCart => target is CartChargeTarget;

  /// The cart a cart session charges (null = takeaway, or not a cart).
  String? get cartTableId => switch (target) {
    CartChargeTarget(:final tableId) => tableId,
    _ => null,
  };
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

  bool get tillOpen => tillId != null;

  // ── derived: the money ────────────────────────────────────────────────────

  /// The figure in the hero. A bill the server has priced (`ticket.bill`)
  /// shows its full TOTAL and is labelled Total; only a fire still in the
  /// outbox, which nobody has priced, falls back to its subtotal and says so.
  int get dueMinor => summary.totalMinor;
  bool get dueIsPriced => switch (target) {
    BillChargeTarget(:final ticket) => ticket.bill != null,
    _ => true,
  };

  /// The hero's word and whether change is honest — the core's decision.
  bool get heroIsSubtotal => tender.dueIsSubtotal;
  String get heroLabelKey => tender.dueLabelKey;
  bool get showsChange => tender.showsChange;

  /// What the Charge bar takes — the due plus the tip, split or not.
  int get chargeTotalMinor => tender.chargeTotalMinor;

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

  /// The method the tip rides. One rule for every caller: the teller's pick,
  /// else whatever the sale itself is booked against — the split's largest
  /// leg in split mode. A cart and a bill used to default it differently.
  String? get effectiveTipMethodId =>
      tipMethodId ?? (splitMode ? splitPrimary : effectiveMethodId);

  /// A tip paid by cash comes out of the same drawer, so it is due with the
  /// bill. The tip can ride a DIFFERENT method than the order (card order +
  /// cash tip), so this reads the TIP method's kind.
  bool get tipIsCash =>
      paymentMethods
          .where((m) => m.id == effectiveTipMethodId)
          .firstOrNull
          ?.isCash ??
      isCash;

  /// What the cash in hand must reach.
  int get dueCashMinor => tender.dueCashMinor;
  int get changeMinor => tender.changeMinor;
  int get shortMinor => tender.shortMinor;

  int get splitAllocated => tender.splitAllocatedMinor;
  int get splitRemaining => tender.splitRemainingMinor;

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
    if (isPlacingOrder || outcome != null) return ChargeBlock.charging;
    if (!loaded) return ChargeBlock.loading;
    if (!tillOpen) return ChargeBlock.noTill;
    if (paymentMethods.isEmpty) return ChargeBlock.noMethods;
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

  /// Exact cash is the lit primary: it needs only a till and cash to be
  /// the method.
  bool get canChargeExact =>
      !isPlacingOrder &&
      outcome == null &&
      loaded &&
      tillOpen &&
      !splitMode &&
      takesTender &&
      isCash;

  CheckoutState copyWith({
    Object? target = _unset,
    List<PaymentMethodView>? paymentMethods,
    List<DiscountView>? discounts,
    Object? cartDiscountId = _unset,
    Object? cartDiscount = _unset,
    Object? billDiscount = _unset,
    bool? billDiscountCleared,
    Object? billDiscountApproval = _unset,
    bool? waiveService,
    bool? canWaiveService,
    Object? orgLogoPath = _unset,
    String? currency,
    String? branchName,
    CheckoutSummary? summary,
    bool? taxInclusive,
    double? serviceChargeRate,
    double? taxRate,
    Object? tillId = _unset,
    bool? loaded,
    TenderSummaryView? tender,
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
    bool? dineIn,
    bool? splitMode,
    Map<String, int>? splitAmounts,
    Object? baseSummary = _unset,
    List<RewardLineInput>? rewardLines,
    Object? loyaltyScan = _unset,
    List<RewardPick>? rewardPicks,
    Object? rewardBoard = _unset,
    List<CheckoutRedemption>? rewardRedemptions,
    bool? loyaltyBusy,
    Object? loyaltyError = _unset,
    LoyaltyProgrammeView? loyaltyProgramme,
    Object? customer = _unset,
  }) {
    return CheckoutState(
      target: target == _unset ? this.target : target as ChargeTarget?,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      discounts: discounts ?? this.discounts,
      loyaltyProgramme: loyaltyProgramme ?? this.loyaltyProgramme,
      cartDiscountId: cartDiscountId == _unset
          ? this.cartDiscountId
          : cartDiscountId as String?,
      cartDiscount: cartDiscount == _unset
          ? this.cartDiscount
          : cartDiscount as CartDiscountView?,
      billDiscount: billDiscount == _unset
          ? this.billDiscount
          : billDiscount as DiscountView?,
      billDiscountCleared: billDiscountCleared ?? this.billDiscountCleared,
      billDiscountApproval: billDiscountApproval == _unset
          ? this.billDiscountApproval
          : billDiscountApproval as ApprovalView?,
      waiveService: waiveService ?? this.waiveService,
      canWaiveService: canWaiveService ?? this.canWaiveService,
      orgLogoPath: orgLogoPath == _unset
          ? this.orgLogoPath
          : orgLogoPath as String?,
      currency: currency ?? this.currency,
      branchName: branchName ?? this.branchName,
      summary: summary ?? this.summary,
      taxInclusive: taxInclusive ?? this.taxInclusive,
      serviceChargeRate: serviceChargeRate ?? this.serviceChargeRate,
      taxRate: taxRate ?? this.taxRate,
      tillId: tillId == _unset ? this.tillId : tillId as String?,
      loaded: loaded ?? this.loaded,
      tender: tender ?? this.tender,
      receipt: receipt == _unset ? this.receipt : receipt as ReceiptView?,
      outcome: outcome == _unset ? this.outcome : outcome as ChargeOutcome?,
      isPlacingOrder: isPlacingOrder ?? this.isPlacingOrder,
      printState: printState ?? this.printState,
      error: error == _unset ? this.error : error as UiText?,
      selectedMethodId: selectedMethodId == _unset
          ? this.selectedMethodId
          : selectedMethodId as String?,
      tenderedMinor: tenderedMinor ?? this.tenderedMinor,
      tipOpen: tipOpen ?? this.tipOpen,
      tipMinor: tipMinor ?? this.tipMinor,
      tipMethodId: tipMethodId == _unset
          ? this.tipMethodId
          : tipMethodId as String?,
      dineIn: dineIn ?? this.dineIn,
      splitMode: splitMode ?? this.splitMode,
      splitAmounts: splitAmounts ?? this.splitAmounts,
      baseSummary: baseSummary == _unset
          ? this.baseSummary
          : baseSummary as CheckoutSummary?,
      rewardLines: rewardLines ?? this.rewardLines,
      loyaltyScan: loyaltyScan == _unset
          ? this.loyaltyScan
          : loyaltyScan as LoyaltyScanView?,
      rewardPicks: rewardPicks ?? this.rewardPicks,
      rewardBoard: rewardBoard == _unset
          ? this.rewardBoard
          : rewardBoard as RewardBoardView?,
      rewardRedemptions: rewardRedemptions ?? this.rewardRedemptions,
      loyaltyBusy: loyaltyBusy ?? this.loyaltyBusy,
      loyaltyError: loyaltyError == _unset
          ? this.loyaltyError
          : loyaltyError as UiText?,
      customer: customer == _unset ? this.customer : customer as CustomerView?,
    );
  }
}

/// The Charge session — one per presented drawer. [start] resets it
/// completely, so a sale never inherits the method, tip, split or member of
/// the one before it, even when the provider outlived that sheet.
///
/// Mirrors the natives' AppModel checkout slice: all money math and order
/// assembly live in the core; this only sequences bridge calls.
class CheckoutNotifier extends Notifier<CheckoutState> {
  /// Flips false on dispose — async continuations must not touch [state]
  /// (or [ref]) after the session is gone.
  bool _live = false;

  /// Bumped by [start]: a load still answering for the PREVIOUS session must
  /// not write into this one.
  int _session = 0;

  /// The cart this session reads and charges — takeaway unless the target
  /// names a table.
  String? get _cartTable => state.cartTableId;

  /// The charge in flight, if any — what [settledOutcome] waits on when the
  /// sheet was put away before the money landed.
  Future<void>? _inFlight;

  @override
  CheckoutState build() {
    _live = true;
    ref
      ..onDispose(() => _live = false)
      // The till is the shell's: a till opened or closed while the drawer is
      // up reaches the bar at once (the lock behind Charge follows it).
      ..listen(
        shellProvider.select((s) => s.till?.id),
        (_, id) => _update((s) => s.copyWith(tillId: id)),
      );
    return const CheckoutState();
  }

  MadarBridge get _bridge => ref.read(bridgeProvider);

  /// Guarded state write — async continuations may land after the session
  /// closed, and a disposed notifier must not touch [state]. Every write
  /// re-prices the tender through the core, so the figures are never stale.
  void _update(CheckoutState Function(CheckoutState s) transform) {
    if (!_live) return;
    state = _priced(transform(state));
  }

  CheckoutState _priced(CheckoutState unpriced) {
    final s = _rewarded(unpriced);
    final tender = _bridge.tenderSummary(
      dueMinor: s.dueMinor,
      tipMinor: s.tipMinor,
      tipIsCash: s.tipIsCash,
      tenderedMinor: s.tenderedMinor,
      splits: s.splitLegs,
      duePriced: s.dueIsPriced,
      addsOnTop:
          (s.serviceChargeRate > 0 && !s.waiveService) || !s.taxInclusive,
    );
    return tender == s.tender ? s : s.copyWith(tender: tender);
  }

  /// Run the rewards through the core: the board (claimable lines, reasons,
  /// cap, balance), the surviving redemptions, and the summary re-priced with
  /// the covered units off — covered first, then the discount, as the server
  /// records it. Charge, change, splits and the receipt all read that summary.
  CheckoutState _rewarded(CheckoutState s) {
    final scan = s.loyaltyScan;
    final base = s.baseSummary;
    final bridge = _bridge;
    RewardBoardView? board;
    var redemptions = const <CheckoutRedemption>[];
    if (scan != null) {
      board = bridge.rewardBoard(
        lines: s.rewardLines,
        scan: scan,
        picks: s.rewardPicks,
      );
      redemptions = bridge.rewardRedemptions(
        lines: s.rewardLines,
        picks: board.picks,
      );
    }
    var summary = base ?? s.summary;
    switch (s.target) {
      case CartChargeTarget(:final tableId) when redemptions.isNotEmpty:
        final t = _tryCore(
          () => bridge.cartTotalsWithRewards(
            tableId: tableId,
            redemptions: redemptions,
          ),
        );
        if (t != null) summary = _summaryOf(t);
      // A BILL is re-priced by the core whenever anything on it moves the
      // figure — a reward, a discount picked (or cleared) at the till, or the
      // service charge removed — rewards first, then the discount, then the
      // service charge on the remainder, then tax, as the server settles it.
      // It used to be re-priced only for rewards, so a discount picked on a
      // table left the due, the change and the split legs on the undiscounted
      // figure while the server booked the discounted one.
      case BillChargeTarget(:final ticket)
          when redemptions.isNotEmpty ||
              s.billDiscount != null ||
              s.billDiscountCleared ||
              s.waiveService:
        final d = s.billDiscount;
        final bill = _tryCore(
          () => bridge.billWithRewards(
            ticketId: ticket.id,
            redemptions: redemptions,
            discountType: d?.dtype ?? (s.billDiscountCleared ? 'none' : null),
            discountValue: d?.value,
            waiveService: s.waiveService,
          ),
        );
        if (bill != null) summary = _summaryOfBill(bill);
      default:
    }
    if (scan == null &&
        s.rewardBoard == null &&
        s.rewardRedemptions.isEmpty &&
        identical(summary, s.summary)) {
      return s;
    }
    return s.copyWith(
      rewardBoard: board,
      rewardRedemptions: redemptions,
      summary: summary,
    );
  }

  CheckoutSummary _summaryOfBill(TicketBillView bill) => CheckoutSummary(
    subtotalMinor: bill.subtotalMinor,
    discountMinor: bill.discountMinor,
    serviceChargeMinor: bill.serviceChargeMinor,
    taxMinor: bill.taxMinor,
    totalMinor: bill.totalMinor,
    serviceChargeWaivedMinor: bill.serviceChargeWaivedMinor,
  );

  T? _tryCore<T>(T Function() call) {
    try {
      return call();
    } on MadarError {
      return null;
    }
  }

  /// A write that belongs to session [session]; dropped if a newer one began.
  void _updateFor(
    int session,
    CheckoutState Function(CheckoutState s) transform,
  ) {
    if (session == _session) _update(transform);
  }

  /// Session snapshot fields shared by every session starter: currency,
  /// branch, the tax policy that decides the wording under the hero.
  CheckoutState _withSession(CheckoutState base, MadarBridge bridge) {
    final session = bridge.currentSession();
    return base.copyWith(
      currency: session?.currencyCode ?? '',
      branchName: bridge.deviceConfig().branchName ?? '',
      taxInclusive: session?.taxInclusive ?? true,
      // A counter cart is a takeaway: no service charge, whatever the branch
      // setting (the core prices it at zero). A bill overrides all three with
      // its own frozen figures in [_startBill].
      serviceChargeRate: 0,
      taxRate: session?.taxRate ?? 0,
    );
  }

  /// The methods this sale may take: the branch's, narrowed to what this
  /// teller and this device are allowed (the core intersects them). A
  /// failure is SAID — a dimmed bar with no reason reads as a broken till.
  Future<List<PaymentMethodView>> _loadMethods(int session) async {
    try {
      return await _bridge.availablePaymentMethods();
    } on MadarError catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
      _updateFor(session, (s) => s.copyWith(error: UiText.error(e)));
      return const [];
    }
  }

  // ── session starters ─────────────────────────────────────────────────────

  /// The teller changed who the sale is for in THIS session. An online order
  /// arrives with its customer already linked; only a change is sent after it.
  bool _customerTouched = false;

  /// Start a FRESH session for [target]. Everything the previous sale picked
  /// is dropped here: the provider can outlive a sheet (the Done card, a
  /// charge still landing), and `start` used to layer the new session over
  /// whatever the last one left.
  Future<void> start(ChargeTarget target) {
    _session += 1;
    _inFlight = null;
    _typedLegs.clear();
    _customerTouched = false;
    if (_live) {
      state = _priced(
        CheckoutState(
          target: target,
          tillId: ref.read(shellProvider).till?.id,
          // Chosen on the cart. A bill is the server's (it settles dine-in).
          dineIn: switch (target) {
            CartChargeTarget(:final tableId) => ref.read(
              dineInProvider(tableId),
            ),
            _ => false,
          },
        ),
      );
    }
    return switch (target) {
      CartChargeTarget(:final tableId, :final customerId) => _startCart(
        _session,
        tableId,
        customerId,
      ),
      BillChargeTarget(:final ticket) => _startBill(_session, ticket),
      OnlineChargeTarget(:final order) => _startOnline(_session, order),
    };
  }

  /// The cart session — payment methods, discounts, the applied cart
  /// discount, the org logo, the live cart totals as the summary, and the
  /// lines in the order the server indexes them (a reward names a line by
  /// its position, so this list and the wire order must be the same list).
  Future<void> _startCart(
    int session,
    String? tableId,
    String? pickedId,
  ) async {
    final bridge = _bridge;
    final methods = await _loadMethods(session);
    final discounts =
        await _quiet(bridge.listDiscounts) ?? const <DiscountView>[];
    final discountId = await _quiet<String?>(
      () => bridge.cartDiscountId(tableId: tableId),
    );
    final cartDiscount = await _quiet(
      () => bridge.cartDiscount(tableId: tableId),
    );
    final programme = await _quiet(bridge.loyaltySettings);
    final logo = bridge.orgLogoLocalPath();
    final totals = await _quiet(() => bridge.cartTotals(tableId: tableId));
    final redeemable =
        _tryCore(() => bridge.cartRewardLines(tableId: tableId)) ??
        const <RewardLineInput>[];
    // The customer picked on the cart, from the till's own list.
    final picked = pickedId == null
        ? null
        : _tryCore(() => bridge.customerById(id: pickedId));
    _updateFor(
      session,
      (s) => _withSession(s, bridge).copyWith(
        // Never over a pick made while this was loading.
        customer: _customerTouched ? s.customer : picked,
        paymentMethods: methods,
        discounts: discounts,
        loyaltyProgramme: programme,
        cartDiscountId: discountId,
        cartDiscount: cartDiscount,
        orgLogoPath: logo,
        rewardLines: redeemable,
        summary: totals == null ? null : _summaryOf(totals),
        baseSummary: totals == null ? null : _summaryOf(totals),
        loaded: true,
      ),
    );
  }

  /// A bill, priced by the SERVER.
  ///
  /// `ticket.bill` is absent only for a fire still in the outbox, which the
  /// server has never priced. Falling back to the subtotal there is honest —
  /// it is all that is known, and the hero says "Subtotal" — and such a
  /// ticket cannot be charged anyway.
  Future<void> _startBill(int session, TicketView ticket) {
    final bill = ticket.bill;
    return _startFixed(
      session,
      bill == null
          ? CheckoutSummary(
              subtotalMinor: ticket.subtotalMinor,
              totalMinor: ticket.subtotalMinor,
            )
          : _summaryOfBill(bill),
      ticketId: ticket.id,
      // Who the bill is already for: this device's choice, or the one the
      // server's bill names (a booking, a table-QR guest, another till).
      customerId: ticket.customerId,
      loadDiscounts: true,
      // The wording under the hero reads the BILL's frozen policy, not the
      // session's: a branch that changed a setting mid-service must not have
      // the sheet describe a different bill than the one being settled.
      billPolicy: bill,
    );
  }

  /// An online order: the frozen totals, and the methods. Nothing else —
  /// `deliveryFinalize` takes a method id and no more.
  Future<void> _startOnline(int session, DeliveryOrderView order) =>
      _startFixed(
        session,
        CheckoutSummary(
          subtotalMinor: order.subtotalMinor,
          discountMinor: order.discountMinor,
          deliveryFeeMinor: order.deliveryFeeMinor,
          totalMinor: order.totalMinor,
        ),
        // The customer the server linked the order to; finalize carries them
        // onto the sale by itself.
        customerId: order.customerId,
      );

  /// A session over a FIXED [summary] — loads the payment methods (and, for
  /// a bill, the discounts) and leaves the cart's discount slice untouched.
  Future<void> _startFixed(
    int session,
    CheckoutSummary summary, {

    /// The bill whose live lines rewards may cover. Dine-in is an open ticket
    /// now, so without these a table order could never redeem.
    String? ticketId,
    String? customerId,
    bool loadDiscounts = false,
    TicketBillView? billPolicy,
  }) async {
    final bridge = _bridge;
    // From the till's own list; a customer it does not hold is simply not
    // shown — the server still has them on the bill.
    final linked = customerId == null
        ? null
        : _tryCore(() => bridge.customerById(id: customerId));
    final methods = await _loadMethods(session);
    final discounts = loadDiscounts
        ? await _quiet(bridge.listDiscounts) ?? const <DiscountView>[]
        : const <DiscountView>[];
    final programme = await _quiet(bridge.loyaltySettings);
    // A voided line is not on the bill, and one that has not synced has no id
    // for the server to resolve — the core leaves both out.
    final redeemable = ticketId == null
        ? const <RewardLineInput>[]
        : _tryCore(() => bridge.ticketRewardLines(ticketId: ticketId)) ??
              const <RewardLineInput>[];
    _updateFor(
      session,
      (s) => _withSession(s, bridge).copyWith(
        taxInclusive: billPolicy?.taxInclusive,
        serviceChargeRate: billPolicy?.serviceChargeRate,
        taxRate: billPolicy?.taxRate,
        // Only a table's bill can have its service charge removed.
        canWaiveService: billPolicy != null && bridge.canWaiveServiceCharge(),
        paymentMethods: methods,
        discounts: discounts,
        loyaltyProgramme: programme,
        orgLogoPath: bridge.orgLogoLocalPath(),
        summary: summary,
        baseSummary: summary,
        rewardLines: redeemable,
        // Never over a pick made while this was loading.
        customer: _customerTouched ? s.customer : linked,
        loaded: true,
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
  Future<bool> scanLoyalty({String? token, String? phone}) => _attachMember(
    (bridge) => bridge.loyaltyLookup(token: token, phone: phone),
  );

  /// "Use their rewards": the customer already picked is a member, so their
  /// card is read by id and nobody scans anything a second time.
  Future<bool> useCustomerLoyalty() {
    final c = state.customer;
    final memberId = c?.loyaltyCustomerId;
    if (c == null || memberId == null) return Future.value(false);
    return _attachMember(
      (bridge) => bridge.loyaltyRefresh(customerId: memberId),
    );
  }

  /// A sale names ONE person. The member decides who: the core answers with
  /// the customer row that is them (or null when this till does not hold
  /// one), and a customer picked earlier who is somebody else is dropped.
  Future<bool> _attachMember(
    Future<LoyaltyScanView> Function(MadarBridge bridge) read,
  ) async {
    if (state.loyaltyBusy) return false;
    final bridge = _bridge;
    final session = _session;
    _update((s) => s.copyWith(loyaltyBusy: true, loyaltyError: null));
    try {
      final scan = await read(bridge);
      if (!_live || session != _session) return false;
      final person = _tryCore(
        () => bridge.customerForMember(memberId: scan.member.id),
      );
      _update(
        (s) => s.copyWith(
          loyaltyScan: scan,
          rewardPicks: const [],
          loyaltyError: null,
          customer: person,
        ),
      );
      MadarHaptics.success();
      return true;
    } on MadarError catch (e) {
      _updateFor(session, (s) => s.copyWith(loyaltyError: UiText.error(e)));
      return false;
    } finally {
      _updateFor(session, (s) => s.copyWith(loyaltyBusy: false));
    }
  }

  /// Cover one more unit of a line with a reward, or take the cover off.
  /// The core decides — the balance, the shop's per-order cap, the catalogue —
  /// and a line that can take no more says why on the row.
  void toggleReward(int lineIndex) {
    final s = state;
    final scan = s.loyaltyScan;
    if (scan == null) return;
    final next = _bridge.toggleReward(
      lines: s.rewardLines,
      scan: scan,
      picks: s.rewardBoard?.picks ?? s.rewardPicks,
      line: lineIndex,
    );
    _update((st) => st.copyWith(rewardPicks: next));
  }

  /// Re-read the attached member after the server (or the core's check
  /// against it) refused the rewards: the balance, catalogue and cap are the
  /// server's again, the board re-trims the picks, and the hero re-prices.
  Future<void> _refreshLoyalty() async {
    final member = state.loyaltyMember;
    if (member == null) return;
    final session = _session;
    final bridge = _bridge;
    try {
      final scan = await bridge.loyaltyRefresh(customerId: member.id);
      final lines = switch (state.target) {
        CartChargeTarget(:final tableId) => _tryCore(
          () => bridge.cartRewardLines(tableId: tableId),
        ),
        BillChargeTarget(:final ticket) => _tryCore(
          () => bridge.ticketRewardLines(ticketId: ticket.id),
        ),
        _ => null,
      };
      _updateFor(
        session,
        (s) =>
            s.copyWith(loyaltyScan: scan, rewardLines: lines ?? s.rewardLines),
      );
    } on MadarError catch (_) {
      // The refusal already said why; a failed refresh leaves the board as is.
    }
  }

  /// Attach a customer to this sale. A member already attached who is
  /// somebody else goes, and their rewards with them: one person per sale.
  void attachCustomer(CustomerView customer) {
    _update((s) {
      final memberId = s.loyaltyMember?.id;
      final same =
          memberId == null ||
          customer.id == memberId ||
          customer.loyaltyCustomerId == memberId;
      return same
          ? s.copyWith(customer: customer)
          : s.copyWith(
              customer: customer,
              loyaltyScan: null,
              rewardPicks: const [],
              loyaltyError: null,
            );
    });
    _rememberBillCustomer(customer.id);
  }

  /// A table's bill keeps its customer in the core from the moment they are
  /// picked: closing the drawer, or the app, does not lose them, and the
  /// settle carries them. A cart and an online order have nothing to keep.
  void _rememberBillCustomer(String? customerId) {
    _customerTouched = true;
    if (state.target case BillChargeTarget(:final ticket)) {
      _tryCore(
        () => _bridge.setTicketCustomer(
          ticketId: ticket.id,
          customerId: customerId,
        ),
      );
    }
  }

  /// Take the person off the sale — the customer AND the member, which are
  /// the same person. Either row's remove lands here.
  void clearCustomer() => clearLoyalty();

  /// Drop the member and every reward with them, and the customer they are.
  void clearLoyalty() {
    final had = state.customer != null;
    _update(
      (s) => s.copyWith(
        loyaltyScan: null,
        rewardPicks: const [],
        loyaltyError: null,
        customer: null,
      ),
    );
    if (had) _rememberBillCustomer(null);
  }

  // ── tender picks (the drawer's collection state) ─────────────────────────

  void selectMethod(String id) =>
      _update((s) => s.copyWith(selectedMethodId: id, error: null));

  void setTendered(int minor) =>
      _update((s) => s.copyWith(tenderedMinor: minor, error: null));

  /// "Add tip ›" — reveal the amount row. Closing it drops the tip.
  void openTip() => _update((s) => s.copyWith(tipOpen: true));

  void closeTip() => _update(
    (s) => s.copyWith(tipOpen: false, tipMinor: 0, tipMethodId: null),
  );

  void setTip(int minor) => _update((s) => s.copyWith(tipMinor: minor));

  void setTipMethod(String id) => _update((s) => s.copyWith(tipMethodId: id));

  /// Drinking in, or taking it away. Nothing else on the sale moves.
  void setDineIn({required bool dineIn}) {
    _update((s) => s.copyWith(dineIn: dineIn));
    // One choice, the cart's: flipping it here flips it on the cart too.
    if (state.target is CartChargeTarget) {
      ref.read(dineInProvider(state.cartTableId).notifier).set(dineIn: dineIn);
    }
  }

  /// Split on or off. Turning it OFF drops every leg: the amounts typed for a
  /// split must never ride along with the single payment that replaced it.
  void toggleSplit() {
    _typedLegs.clear();
    _restLeg = null;
    _update(
      (s) => s.copyWith(
        splitMode: !s.splitMode,
        splitAmounts: const {},
        error: null,
      ),
    );
  }

  /// The legs a person has typed into; every other leg is the core's to
  /// fill while it is the only one left open.
  final Set<String> _typedLegs = {};

  /// The leg that holds "the rest" — filled by the core, by auto-fill or
  /// "Rest here". When the due moves (a discount, the service charge) it is
  /// the one re-filled, so the legs keep adding up to what the settle books.
  String? _restLeg;

  List<CheckoutSplit> get _allLegs => [
    for (final m in state.paymentMethods)
      CheckoutSplit(
        paymentMethodId: m.id,
        amountMinor: state.splitAmounts[m.id] ?? 0,
      ),
  ];

  /// A typed leg. The core names the one open leg (if any) that takes what
  /// remains, so a two-way split is one amount typed instead of two.
  void setSplitAmount(String id, int minor) {
    _typedLegs.add(id);
    // A person typed over the leg that held the rest: it is theirs now, and a
    // later due change must not overwrite what they typed.
    if (_restLeg == id) _restLeg = null;
    _update(
      (s) =>
          s.copyWith(splitAmounts: {...s.splitAmounts, id: minor}, error: null),
    );
    final fill = _bridge.splitAutoFill(
      dueMinor: state.dueMinor,
      legs: _allLegs,
      typed: _typedLegs.toList(),
      typedId: id,
    );
    if (fill == null) return;
    _restLeg = fill.paymentMethodId;
    _setLeg(fill.paymentMethodId, fill.amountMinor);
  }

  /// "Rest here": the core's rest for [id]'s leg.
  void fillSplitRest(String id) {
    _typedLegs.add(id);
    _restLeg = id;
    _setLeg(
      id,
      _bridge.splitRestHere(
        dueMinor: state.dueMinor,
        legs: _allLegs,
        target: id,
      ),
    );
  }

  void _setLeg(String id, int minor) => _update(
    (st) =>
        st.copyWith(splitAmounts: {...st.splitAmounts, id: minor}, error: null),
  );

  /// Surface (or clear) a failure inside the drawer.
  void setError(UiText? message) => _update((s) => s.copyWith(error: message));

  // ── discount ─────────────────────────────────────────────────────────────

  /// Apply or clear the CART discount, then re-read the applied id and the
  /// totals so the hero updates live (natives' setDiscount).
  Future<void> setDiscount(String? id) async {
    final bridge = _bridge;
    final session = _session;
    await _quiet(() async {
      if (id != null) {
        await bridge.cartSetDiscount(tableId: _cartTable, discountId: id);
      } else {
        await bridge.cartClearDiscount(tableId: _cartTable);
      }
      return true;
    });
    await _reloadCartDiscount(session);
  }

  /// Re-read the cart's discount and totals after the discount sheet changed
  /// them (a preset, a typed amount or percent, an approval).
  Future<void> reloadCartDiscount() => _reloadCartDiscount(_session);

  Future<void> _reloadCartDiscount(int session) async {
    final bridge = _bridge;
    final discountId = await _quiet<String?>(
      () => bridge.cartDiscountId(tableId: _cartTable),
    );
    final discount = await _quiet(
      () => bridge.cartDiscount(tableId: _cartTable),
    );
    final totals = await _quiet(() => bridge.cartTotals(tableId: _cartTable));
    if (!_live) return;
    _updateFor(
      session,
      (s) => s.copyWith(
        cartDiscountId: discountId,
        cartDiscount: discount,
        summary: totals == null ? null : _summaryOf(totals),
        baseSummary: totals == null ? null : _summaryOf(totals),
      ),
    );
    // The cart's total just moved: the split's rest leg follows it, as it
    // does for a bill's discount — or the legs stay on the old figure and
    // the sale cannot be charged (or is charged short).
    if (_live) _refillSplit();
    ref.read(shellProvider.notifier).refresh();
  }

  /// Pick the discount for a BILL — or `null` for "No discount", which clears
  /// the waiter's too. The core re-prices the bill at once, so the hero, the
  /// change and the split legs all move to the figure the settle books.
  void setBillDiscount(DiscountView? discount) {
    _update(
      (s) => s.copyWith(
        billDiscount: discount,
        billDiscountCleared: discount == null,
        // A different discount is a different act: the manager approved the
        // OLD one, and an approval must never stretch to a figure nobody saw.
        billDiscountApproval: null,
      ),
    );
    _refillSplit();
  }

  /// The discount act this bill's settle would perform, judged offline against
  /// the cashier's own caps — `allow`, `needs_approval` or `deny`. A cart or an
  /// online order has no bill discount to gate, and answers `allow`.
  ///
  /// It is asked at the CHARGE tap rather than at the picker because a bill can
  /// carry a discount the cashier never touched: the waiter's, inherited in
  /// silence. That silence was the hole this closes.
  ActDecisionView? billDiscountDecision() {
    final s = state;
    final target = s.target;
    if (target is! BillChargeTarget) return null;
    final d = s.billDiscount;
    return _bridge.decideBillDiscount(
      ticketId: target.ticket.id,
      discountId: d?.id,
      discountType: d?.dtype ?? (s.billDiscountCleared ? 'none' : null),
      discountValue: d?.value,
    );
  }

  /// Mint the manager's approval for this bill's discount with their PIN.
  Future<ApprovalView> approveBillDiscount(String pin) {
    final s = state;
    final target = s.target! as BillChargeTarget;
    final d = s.billDiscount;
    return _bridge.approveBillDiscount(
      approverPin: pin,
      ticketId: target.ticket.id,
      discountId: d?.id,
      discountType: d?.dtype ?? (s.billDiscountCleared ? 'none' : null),
      discountValue: d?.value,
    );
  }

  /// Keep the approval a manager just gave, for the settle about to be queued.
  void setBillDiscountApproval(ApprovalView? approval) =>
      _update((s) => s.copyWith(billDiscountApproval: approval));

  /// Show the refusal the core gave for this bill's discount.
  void showDiscountRefusal(String reason) =>
      _update((s) => s.copyWith(error: UiText.raw(reason)));

  /// Remove (or restore) the service charge on this bill. Refused unless the
  /// signed-in user holds `orders:waive_service`; the server checks it again.
  void setWaiveService({required bool waive}) {
    if (waive && !state.canWaiveService) return;
    _update((s) => s.copyWith(waiveService: waive && s.isBill));
    _refillSplit();
  }

  /// The due just moved: the leg the core fills from the rest follows it, so
  /// a split never stays on the old figure.
  void _refillSplit() {
    final rest = _restLeg;
    if (!state.splitMode || rest == null) return;
    _setLeg(
      rest,
      _bridge.splitRestHere(
        dueMinor: state.dueMinor,
        legs: _allLegs,
        target: rest,
      ),
    );
  }

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

  /// The outcome of this session once any charge in flight has landed —
  /// null when nothing was charged. What `showCharge` falls back on when the
  /// sheet was put away mid-payment: the money is taken either way, and the
  /// Done flow (receipt, points, the table) must still follow.
  Future<ChargeOutcome?> settledOutcome() async {
    final inFlight = _inFlight;
    if (inFlight != null) await inFlight;
    return _live ? state.outcome : null;
  }

  /// Take the money, whichever caller this is. On success [CheckoutState
  /// .outcome] is set — carrying the receipt's print job, which runs in the
  /// background and never holds the sale up; on refusal the server's
  /// sentence lands in [CheckoutState.error] and the drawer stays open.
  Future<void> charge() {
    final running = _inFlight;
    if (running != null) return running;
    if (!state.canCharge) return Future.value();
    final job = _charge();
    _inFlight = job;
    return job.whenComplete(() {
      if (identical(_inFlight, job) && state.outcome == null) _inFlight = null;
    });
  }

  Future<void> _charge() async {
    final s = state;
    final method = s.splitMode ? s.splitPrimary : s.effectiveMethodId;
    if (method == null) return;
    final bridge = _bridge;
    // A bill books onto THIS device's till. `block` keeps the bar dimmed
    // without one; this is the lock behind it for any other caller.
    if (s.isBill && s.tillId == null) {
      _update(
        (st) => st.copyWith(error: const UiText.key('waiter.need_shift')),
      );
      return;
    }
    _update((st) => st.copyWith(isPlacingOrder: true, error: null));
    try {
      final taken = await switch (s.target) {
        OnlineChargeTarget(:final order) => _chargeOnline(s, order, method),
        BillChargeTarget(:final ticket, :final tableLabel) => _chargeBill(
          s,
          ticket,
          method,
          tableLabel: tableLabel,
        ),
        CartChargeTarget() || null => _chargeCart(s, method),
      };
      // Auto-print — the Done card's Reprint is for REPRINTS. It runs in the
      // background with a timeout and reports a state; a slow or dead printer
      // must never keep the sale from finishing.
      final receipt = taken.receipt;
      final outcome = receipt == null
          ? taken
          : taken.withPrintJob(
              printReceiptView(
                bridge,
                ref.read(printerServiceProvider),
                receipt,
                kickDrawer: true,
              ),
            );
      if (!_live) return;
      _update(
        (st) => st.copyWith(
          outcome: outcome,
          receipt: receipt,
          printState: receipt == null ? PrintState.idle : PrintState.printing,
          isPlacingOrder: false,
        ),
      );
      MadarHaptics.success();
      ref.read(shellProvider.notifier).refresh();
      ref.read(drawerTickProvider.notifier).bump();
      final job = outcome.printJob;
      if (job != null) {
        unawaited(
          job.then((printed) {
            // The session may be gone by now (the sheet and its hold are).
            if (_live && identical(state.outcome, outcome)) {
              _update((st) => st.copyWith(printState: printed));
            }
          }),
        );
      }
    } on MadarError catch (e) {
      _raise(bridge, e);
      // A refused reward is re-priced from the server's current card, so the
      // next tap charges what the server will accept.
      if (s.rewardRedemptions.isNotEmpty) unawaited(_refreshLoyalty());
    } finally {
      if (_live && state.isPlacingOrder) {
        _update((st) => st.copyWith(isPlacingOrder: false));
      }
    }
  }

  /// Place the cart as an order via the core (online or queued offline).
  /// Split legs zero the tendered amount; a non-cash single payment tenders 0.
  Future<ChargeOutcome> _chargeCart(CheckoutState s, String method) async {
    final receipt = await _bridge.checkout(
      tableId: s.cartTableId,
      input: CheckoutInput(
        paymentMethodId: method,
        amountTenderedMinor: !s.splitMode && s.isCash ? s.tenderedMinor : 0,
        tipMinor: s.tipMinor,
        tipPaymentMethodId: s.tipMinor > 0 ? s.effectiveTipMethodId : null,
        splits: s.splitMode ? s.splitLegs : const [],
        dineIn: s.dineIn,
        customerId: s.customer?.id,
        customerName: s.customer?.name,
        // WHICH lines, never a price. The server looks each reward up in the
        // branch's catalogue, checks the balance against the whole basket, and
        // refuses the sale outright if it does not cover it.
        loyaltyCustomerId: s.rewardRedemptions.isEmpty
            ? null
            : s.loyaltyMember?.id,
        loyaltyRedemptions: s.rewardRedemptions,
      ),
    );
    // The sale is taken: the next one on this cart starts at its default.
    ref.read(dineInProvider(s.cartTableId).notifier).reset();
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
      loyaltyOffered: s.loyaltyOffered,
    );
  }

  /// Settle the ticket into a paid order on this till. The order id comes
  /// back once the server acked — then its receipt is fetched and printed;
  /// null means queued offline, where no order exists yet.
  Future<ChargeOutcome> _chargeBill(
    CheckoutState s,
    TicketView ticket,
    String method, {
    String? tableLabel,
  }) async {
    final bridge = _bridge;
    // `_charge` refuses a bill with no till id before it gets here.
    final tillId = s.tillId!;
    final tendered = !s.splitMode && s.isCash && s.tenderedMinor > 0
        ? s.tenderedMinor
        : null;
    final discount = s.billDiscount;
    final orderId = await bridge.settleTicket(
      ticketId: ticket.id,
      tillId: tillId,
      paymentMethodId: method,
      amountTenderedMinor: tendered,
      tipMinor: s.tipMinor > 0 ? s.tipMinor : null,
      tipPaymentMethodId: s.tipMinor > 0 ? s.effectiveTipMethodId : null,
      discountId: discount?.id,
      discountType: discount?.dtype ?? (s.billDiscountCleared ? 'none' : null),
      discountValue: discount?.value,
      waiveService: s.waiveService,
      loyaltyCustomerId: s.rewardRedemptions.isEmpty
          ? null
          : s.loyaltyMember?.id,
      loyaltyRedemptions: s.rewardRedemptions,
      // Only a split sends legs. Amounts typed before split was switched off
      // are dropped by `toggleSplit`; this is the second lock on that door.
      splits: s.splitMode ? s.splitLegs : const [],
      discountApproval: s.billDiscountApproval,
      // The settle itself says who the bill is for — no attach follows it.
      customerId: s.customer?.id,
    );
    ReceiptView? receipt;
    if (orderId != null) {
      // Best-effort: the money is taken; a receipt that cannot be fetched is
      // a reprint from history, not a failed charge.
      receipt = await _quiet(() => bridge.orderReceiptView(orderId: orderId));
    }
    return ChargeOutcome(
      target: s.target!,
      queued: orderId == null,
      amountMinor: receipt == null
          ? s.chargeTotalMinor
          : receipt.totalMinor + receipt.tipMinor,
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
      loyaltyOffered: s.loyaltyOffered,
    );
  }

  /// Finalize the online order into a real sale on this till — a method
  /// and nothing else, then the new order's receipt.
  Future<ChargeOutcome> _chargeOnline(
    CheckoutState s,
    DeliveryOrderView order,
    String method,
  ) async {
    final bridge = _bridge;
    final res = await bridge.deliveryFinalize(
      id: order.id,
      paymentMethodId: method,
    );
    // Finalize carries the order's own customer. Only a CHANGE made on the
    // sheet follows it, as an attach (or a removal) queued behind the sale.
    if (_customerTouched && s.customer?.id != order.customerId) {
      _tryCore(
        () => bridge.attachCustomer(
          orderId: res.orderId,
          customerId: s.customer?.id,
        ),
      );
    }
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
      loyaltyOffered: s.loyaltyOffered,
    );
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
    _update((s) => s.copyWith(error: UiText.error(e)));
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

/// THE charge session — autoDispose; `showCharge` holds it for the life of
/// one presentation (so a charge still landing after the sheet is put away
/// reaches the Done card) and [CheckoutNotifier.start] resets it per sale.
final NotifierProvider<CheckoutNotifier, CheckoutState> checkoutProvider =
    NotifierProvider.autoDispose(CheckoutNotifier.new);
