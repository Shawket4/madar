import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/checkout_drawer.dart';
import 'package:flutter/foundation.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Thermal receipt width in characters — the natives' `32u` raster width.
const int kReceiptChars = 32;

/// Default JetDirect (raw-TCP) printer port, used when the device config
/// carries no explicit port (the natives' `parsePrinter` fallback).
const int kJetDirectPort = 9100;

/// Print lifecycle of the receipt confirmation — the natives' `PrintState`.
enum PrintState { idle, printing, printed, failed, noPrinter }

/// Screen-local mirror of the natives' AppModel checkout slice: payment
/// methods + discounts (org config), the live cart totals, the applied
/// discount, checkout-in-flight state, the placed receipt, and the print
/// lifecycle. All money math and order assembly live in the core; this only
/// sequences bridge calls and notifies the widgets.
class CheckoutController extends ChangeNotifier {
  CheckoutController({required this.core, required this.onStateChanged});

  final MadarCore core;

  /// Shell callback — fired after a successful checkout (the cart empties
  /// and the shift history/stats move).
  final VoidCallback onStateChanged;

  MadarBridge get bridge => core.bridge;

  String tr(String key) => bridge.tr(key: key);

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── session + device ───────────────────────────────────────────────────────
  SessionSnapshot? get session => bridge.currentSession();

  String get currency => session?.currencyCode ?? '';

  String get branchName => bridge.deviceConfig().branchName ?? '';

  // ── org config + cart mirrors ──────────────────────────────────────────────
  List<PaymentMethodView> paymentMethods = const [];
  List<DiscountView> discounts = const [];
  CartTotals cartTotals = const CartTotals(
    itemCount: 0,
    subtotalMinor: 0,
    discountMinor: 0,
    taxMinor: 0,
    totalMinor: 0,
  );
  String? cartDiscountId;
  String? orgLogoUrl;

  // ── checkout state ─────────────────────────────────────────────────────────
  ReceiptView? receipt;
  bool isPlacingOrder = false;
  PrintState printState = PrintState.idle;
  String? error;

  /// Mirror of the natives' on-appear load: payment methods, discounts, the
  /// applied cart discount, the org logo, and the live totals.
  Future<void> init() async {
    paymentMethods = await _quiet(bridge.listPaymentMethods) ?? const [];
    discounts = await _quiet(bridge.listDiscounts) ?? const [];
    cartDiscountId = await _quiet<String?>(bridge.cartDiscountId);
    orgLogoUrl = await _quiet<String?>(bridge.orgLogoUrl);
    await _refreshTotals();
    _notify();
  }

  Future<void> _refreshTotals() async {
    cartTotals = await _quiet(bridge.cartTotals) ?? cartTotals;
  }

  /// Apply or clear the cart discount, then re-read the applied id and the
  /// totals so the summary + hero total update live (natives' setDiscount).
  Future<void> setDiscount(String? id) async {
    await _quiet(() async {
      if (id != null) {
        await bridge.cartSetDiscount(discountId: id);
      } else {
        await bridge.cartClearDiscount();
      }
      return true;
    });
    cartDiscountId = await _quiet<String?>(bridge.cartDiscountId);
    await _refreshTotals();
    _notify();
  }

  /// Place the cart as an order via the core (online or queued offline). On
  /// success the core has emptied the cart; the receipt flips the sheet to
  /// the confirmation and the shell is notified. Mirrors the natives'
  /// placeOrder split/tendered mapping: split legs zero the tendered amount,
  /// a non-cash single payment tenders 0.
  Future<void> placeOrder(CheckoutResult result) async {
    isPlacingOrder = true;
    error = null;
    _notify();
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
      receipt = await bridge.checkout(input: input);
      printState = PrintState.idle;
      MadarHaptics.success();
      onStateChanged();
      // Auto-print the receipt on checkout — the confirmation's Print button
      // is for REPRINTS. `printReceipt` no-ops with no printer configured and
      // swallows its own errors (sets PrintState.failed), so it can never
      // fail the placed order.
      await printReceipt();
    } on MadarError catch (e) {
      error = bridge.humanMessage(e);
    } finally {
      isPlacingOrder = false;
      _notify();
    }
  }

  /// Render the placed receipt in the core and stream it to the configured
  /// network printer (best-effort). Pops the till on a cash sale — only on
  /// the original auto-print; a reprint passes [kickDrawer] = false.
  Future<void> printReceipt({bool kickDrawer = true}) async {
    final r = receipt;
    if (r == null) return;
    final config = bridge.deviceConfig();
    final host = config.printerHost?.trim() ?? '';
    if (host.isEmpty) {
      printState = PrintState.noPrinter;
      _notify();
      return;
    }
    final port = config.printerPort ?? kJetDirectPort;
    final brand = printerBrandOf(config.printerBrand);
    printState = PrintState.printing;
    _notify();
    try {
      final bytes = await bridge.renderReceipt(
        receipt: r,
        storeName: branchName,
        currency: currency,
        width: kReceiptChars,
        brand: brand,
      );
      await bridge.sendToPrinter(host: host, port: port, bytes: bytes);
      if (kickDrawer && r.isCash) {
        await _quiet(() async {
          final kick = await bridge.cashDrawerKick(brand: brand);
          await bridge.sendToPrinter(host: host, port: port, bytes: kick);
          return true;
        });
      }
      printState = PrintState.printed;
    } on Exception {
      printState = PrintState.failed;
    }
    _notify();
  }

  /// Run a bridge call whose failure the natives swallow (cache reads,
  /// best-effort refreshes) — returns null instead of surfacing the error.
  Future<T?> _quiet<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on MadarError {
      return null;
    }
  }
}

/// Device-config brand string (`epson`/`star`) → [PrinterBrand]; anything
/// else falls back to Epson (the natives' default dialect).
PrinterBrand printerBrandOf(String? brand) =>
    brand == 'star' ? PrinterBrand.star : PrinterBrand.epson;
