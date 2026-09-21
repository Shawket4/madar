import 'package:feature_checkout/src/receipt_printing.dart';
import 'package:flutter/foundation.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// What is being charged. One drawer, three callers — a counter cart, a
/// table's bill, an online order — and the thing that differs between them
/// is not the chrome but which bridge call takes the money and what that
/// call can carry. The target names the caller; the session reads the rest
/// off it.
@immutable
sealed class ChargeTarget {
  const ChargeTarget();

  /// The Sell tab's cart. `checkout()` — the one path that carries splits,
  /// a live discount, tip, cash tendered and rewards by line position.
  ///
  /// [tableId] names WHICH cart: null is takeaway, an id is that table's own
  /// cart. There is no active cart in the core; every call says which.
  ///
  /// [customerId] is the customer already picked on the cart, if one was:
  /// the drawer opens with them on the sale.
  const factory ChargeTarget.cart({
    String? tableId,
    String? label,
    String? customerId,
  }) = CartChargeTarget;

  /// A table's bill (an open ticket). `settleTicket()` — tip, discount,
  /// rewards by line id, a service charge waiver, and split legs.
  const factory ChargeTarget.bill(TicketView ticket, {String? tableLabel}) =
      BillChargeTarget;

  /// An online order. `deliveryFinalize()` — a payment method and nothing
  /// else: no tendered, no tip, no discount, no split, no member.
  const factory ChargeTarget.online(DeliveryOrderView order) =
      OnlineChargeTarget;
}

class CartChargeTarget extends ChargeTarget {
  const CartChargeTarget({this.tableId, this.label, this.customerId});

  /// The cart being charged (null = takeaway).
  final String? tableId;

  /// What the header calls the sale, already localised ("Takeaway"). Null
  /// falls back to the feature's own word.
  final String? label;

  /// The customer picked on the cart before Charge, if one was.
  final String? customerId;
}

class BillChargeTarget extends ChargeTarget {
  const BillChargeTarget(this.ticket, {this.tableLabel});

  final TicketView ticket;

  /// The table's label on the floor ("T5"). The ticket carries only the
  /// table's id, so the caller — who has the floor — passes the word.
  final String? tableLabel;
}

class OnlineChargeTarget extends ChargeTarget {
  const OnlineChargeTarget(this.order);

  final DeliveryOrderView order;
}

/// What Charge resolved with. Null from `showCharge` means the teller closed
/// the drawer without taking money.
@immutable
class ChargeOutcome {
  const ChargeOutcome({
    required this.target,
    required this.queued,
    required this.amountMinor,
    required this.methodLabel,
    required this.isCash,
    required this.currency,
    required this.createdAt,
    this.receipt,
    this.orderId,
    this.orderKey,
    this.orderNumber,
    this.changeMinor = 0,
    this.tableId,
    this.tableLabel,
    this.loyaltyCustomerId,
    this.loyaltyOffered = false,
    this.printState = PrintState.idle,
    this.printJob,
  });

  final ChargeTarget target;

  /// The sale is in the outbox, not on the server. The Done card says
  /// "Queued", never "Sale #".
  final bool queued;

  /// What was taken, tip included — the figure on the Done card.
  final int amountMinor;
  final String methodLabel;
  final bool isCash;
  final String currency;

  /// RFC3339; what the award window is measured from.
  final String createdAt;

  /// The receipt to print. Present for every cart sale (the core builds one
  /// offline too) and for a bill or online order once the server acked;
  /// absent for a bill settle that is still queued — no order exists yet and
  /// paper for it would be a lie.
  final ReceiptView? receipt;

  /// The server's order id, once known.
  final String? orderId;

  /// The client-minted key of a cart sale, which the server may not have
  /// yet. What `loyaltyAward` takes for a just-rung sale.
  final String? orderKey;
  final int? orderNumber;
  final int changeMinor;

  /// The table the bill sat on — the Done card asks whether it is cleared.
  final String? tableId;
  final String? tableLabel;

  /// The member whose card was scanned to pay; Add points then needs no
  /// second scan.
  final String? loyaltyCustomerId;

  /// The branch runs a loyalty programme, as the Charge session read it. The
  /// Done card offers Add points on this — it has no session of its own to
  /// ask, and asking the provider after the sheet closed read a fresh, empty
  /// session that never knew about the programme.
  final bool loyaltyOffered;

  /// How the auto-print went, so the Done card can say "Printed" or "Not
  /// printed — no printer" without a session to ask.
  final PrintState printState;

  /// The auto-print still running in the background, when there is one. It
  /// always completes (a timeout and every failure resolve to a state), and
  /// the Done card shows "Printing…" until it does.
  final Future<PrintState>? printJob;

  /// The Done card can offer Add points: something names the sale.
  bool get canAwardPoints => orderId != null || orderKey != null;

  ChargeOutcome withPrintState(PrintState state) =>
      _copy(printState: state, printJob: null);

  ChargeOutcome withPrintJob(Future<PrintState> job) =>
      _copy(printState: PrintState.printing, printJob: job);

  ChargeOutcome _copy({
    required PrintState printState,
    required Future<PrintState>? printJob,
  }) => ChargeOutcome(
    target: target,
    queued: queued,
    amountMinor: amountMinor,
    methodLabel: methodLabel,
    isCash: isCash,
    currency: currency,
    createdAt: createdAt,
    receipt: receipt,
    orderId: orderId,
    orderKey: orderKey,
    orderNumber: orderNumber,
    changeMinor: changeMinor,
    tableId: tableId,
    tableLabel: tableLabel,
    loyaltyCustomerId: loyaltyCustomerId,
    loyaltyOffered: loyaltyOffered,
    printState: printState,
    printJob: printJob,
  );
}
