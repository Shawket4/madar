import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/receipt_printing.dart' show vatLabel;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// On-screen receipt preview — a white "thermal paper" card rendered from the
// core's ReceiptView so the teller sees exactly what will print BEFORE
// sending it. Port of the natives' ReceiptPaper.kt / the ESC/POS layout in
// receipt.rs. Theme-invariant BY DESIGN: a receipt is always white paper
// with dark ink (the natives hardcode the same palette in both themes).

/// Paper card metrics (natives: 360.dp cap, 10.dp corners, 18.dp padding,
/// 6.dp row gap).
const double _paperMaxWidth = 360;
const double _paperRadius = 10;
const double _paperPad = 18;
const double _paperGap = 6;

/// Org logo box — 50% over the old 60×220, aspect-preserved
/// so a wide wordmark or a square mark both render without cropping.
const double _logoMaxHeight = 135;
const double _logoMaxWidth = 480;

/// Type sizes on the paper — larger, like the printed receipt.
const double _storeSize = 14;
const double _orderNumberSize = 30;
const double _boldRowSize = 15;
const double _rowSize = 14;
const double _metaSize = 13;

/// The on-screen receipt paper — renders a [ReceiptView] as the printed
/// layout: org logo/name header, order + delivery meta, line items with
/// `qty× name … amount` columns, the totals block, and the payment footer.
/// Pure-DATA params; the bridge (strings + time formatting) comes from
/// the provider spine.
class ReceiptPaper extends ConsumerWidget {
  const ReceiptPaper({
    required this.receipt,
    required this.storeName,
    required this.currency,
    this.orgLogoPath,
    super.key,
  });

  final ReceiptView receipt;
  final String storeName;
  final String currency;

  /// Local file path of the core-cached org logo (offline-safe); null
  /// renders just the store name.
  final String? orgLogoPath;

  String _money(int minor) => Money.format(minor, currency: currency);

  /// "Order #36B-12" — the per-device number the core minted (or read back
  /// from the server's ref) — else "Order #12" when only the server number is
  /// known, else the local order id's first uuid segment (the natives'
  /// orderTitle).
  String _orderNumber() {
    if (receipt.displayNumber.isNotEmpty) return '#${receipt.displayNumber}';
    final number = receipt.orderNumber;
    if (number != null) return '#$number';
    return receipt.localOrderId.split('-').first.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String tr(String key) => bridge.tr(key: key);
    final r = receipt;
    final logo = orgLogoPath;
    final deliveryNotes = r.deliveryNotes;
    return Container(
      constraints: const BoxConstraints(maxWidth: _paperMaxWidth),
      padding: const EdgeInsetsDirectional.all(_paperPad),
      decoration: BoxDecoration(
        color: Paper.paper,
        borderRadius: BorderRadius.circular(_paperRadius),
        border: Border.all(color: Paper.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: _paperGap,
        children: [
          Column(
            spacing: _paperGap,
            children: [
              if (r.isVoided)
                _Mono(
                  '*** ${tr('receipt.voided')} ***',
                  size: _boldRowSize,
                  weight: FontWeight.w700,
                  color: Paper.danger,
                ),
              // Org brand mark, directly above the hairline — the CORE-cached
              // local file (downloaded during refresh_catalog); nothing draws
              // on failure, so an offline reprint just shows the store name.
              // Forced to solid black, as it prints — the preview shouldn't
              // show a color the paper can't.
              if (logo != null && logo.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: _logoMaxHeight,
                    maxWidth: _logoMaxWidth,
                  ),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Paper.ink,
                      BlendMode.srcIn,
                    ),
                    child: Image(
                      image: FileImage(File(logo)),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
            ],
          ),
          const _Rule(),
          // The branch name, smaller, directly below the hairline.
          Column(
            spacing: _paperGap,
            children: [
              _Mono(
                storeName.trim().isEmpty ? 'MADAR' : storeName.toUpperCase(),
                size: _storeSize,
                weight: FontWeight.w700,
              ),
              if (r.isDelivery && r.deliveryChannel != null)
                _Mono(
                  '— ${(r.deliveryChannel == 'in_mall' ? tr('delivery.in_mall') : tr('receipt.delivery')).toUpperCase()} —',
                  size: _metaSize,
                  color: Paper.faint,
                ),
            ],
          ),
          const _Rule(),
          // The order number, big and boxed — the printed receipt's header.
          Column(
            spacing: _paperGap,
            children: [
              _Mono(
                tr('receipt.order').toUpperCase(),
                size: _metaSize,
                weight: FontWeight.w700,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Paper.ink, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.lg,
                    vertical: Space.xs,
                  ),
                  child: _Mono(
                    _orderNumber(),
                    size: _orderNumberSize,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              _Mono(
                bridge.formatTime(
                  rfc3339: r.createdAt,
                  style: TimeStyle.receipt,
                ),
                size: _metaSize,
                weight: FontWeight.w700,
              ),
              if (r.orderRef != null)
                _Mono(
                  // The core's word carries its own colon ("Ref:", "مرجع:").
                  '${tr('receipt.ref')} ${r.orderRef}',
                  size: _metaSize,
                  weight: FontWeight.w700,
                ),
            ],
          ),
          const _Rule(),
          if (r.isDelivery) ...[
            if (r.customerName != null)
              _MoneyRow(left: tr('receipt.customer'), right: r.customerName!),
            if (r.customerPhone != null)
              _MoneyRow(left: tr('receipt.phone'), right: r.customerPhone!),
            if (r.deliveryAddress != null)
              _Mono(
                '${tr('receipt.address')} ${r.deliveryAddress}',
                size: _rowSize,
                align: TextAlign.start,
              ),
            if (r.deliveryZone != null)
              _MoneyRow(left: tr('receipt.zone'), right: r.deliveryZone!),
            if (r.deliveryRef != null)
              _MoneyRow(
                left: tr('receipt.delivery_ref'),
                right: r.deliveryRef!,
              ),
            if (r.paymentHint != null)
              _MoneyRow(
                left: tr('receipt.payment_hint'),
                right: r.paymentHint!,
              ),
            if (deliveryNotes != null && deliveryNotes.trim().isNotEmpty)
              _Mono(
                '${tr('receipt.notes')} $deliveryNotes',
                size: _rowSize,
                align: TextAlign.start,
              ),
            const _Rule(),
          ],
          for (final line in r.lines)
            if (line.kind == 'combo')
              _ComboBlock(line: line, money: _money)
            else
              _LineBlock(line: line, money: _money),
          const _Rule(),
          // With deals, the subtotal reads the lines at their normal prices
          // and each deal is its own row under it, as the printed receipt has
          // it (the core's `subtotal_minor` is net of them).
          _MoneyRow(
            left: tr('order.subtotal'),
            right: _money(
              r.subtotalMinor +
                  r.deals.fold<int>(0, (sum, d) => sum + d.discountMinor),
            ),
          ),
          for (final d in r.deals)
            _MoneyRow(
              key: ValueKey('receipt-deal-${d.name}'),
              left: d.name,
              right: '−${_money(d.discountMinor)}',
            ),
          if (r.discountMinor > 0)
            _MoneyRow(
              left: tr('order.discount'),
              right: '−${_money(r.discountMinor)}',
            ),
          // The service charge before the tax, as the printed receipt has it:
          // a charge the customer did not choose is stated on its own line.
          if (r.serviceChargeMinor > 0)
            _MoneyRow(
              left: tr('order.service_charge'),
              right: _money(r.serviceChargeMinor),
            ),
          // Stated the SAME way in both modes now — "VAT (14%)" — at the
          // bill's OWN frozen rate, never today's session (a reprint of an
          // older sale must read the rate that actually applied to it).
          if (r.taxMinor > 0)
            _MoneyRow(left: vatLabel(tr, r.taxRate), right: _money(r.taxMinor)),
          if (r.deliveryFeeMinor > 0)
            _MoneyRow(
              left: tr('receipt.delivery_fee'),
              right: _money(r.deliveryFeeMinor),
            ),
          _MoneyRow(
            left: tr('order.total').toUpperCase(),
            right: _money(r.totalMinor),
            bold: true,
          ),
          if (r.taxInclusive)
            _Mono(
              '${tr('receipt.prices_include_vat')} (${Money.ratePercent(r.taxRate)}%)',
              size: _rowSize,
              align: TextAlign.start,
            ),
          if (r.serviceChargeWaivedMinor > 0) ...[
            _MoneyRow(
              left: tr('receipt.service_waived'),
              right: '−${_money(r.serviceChargeWaivedMinor)}',
              faint: true,
            ),
            if (r.serviceChargeWaivedByName != null)
              _Mono(
                r.serviceChargeWaivedByName!,
                size: _rowSize,
                align: TextAlign.start,
              ),
          ],
          if (r.tipMinor > 0)
            _MoneyRow(left: tr('order.tip'), right: _money(r.tipMinor)),
          // A split lists what each method paid. The core reports cash handed
          // over and change for the sale as a whole; a split with no cash leg
          // has none, and "Cash 0.00 / Change 0.00" was a lie.
          if (r.payments.isNotEmpty) ...[
            for (final leg in r.payments)
              _MoneyRow(left: leg.label, right: _money(leg.amountMinor)),
            if (r.amountTenderedMinor > 0 && r.changeMinor > 0) ...[
              _MoneyRow(
                left: tr('receipt.cash'),
                right: _money(r.amountTenderedMinor),
                faint: true,
              ),
              _MoneyRow(left: tr('order.change'), right: _money(r.changeMinor)),
            ],
          ] else if (r.isCash) ...[
            _MoneyRow(
              left: tr('receipt.cash'),
              right: _money(r.amountTenderedMinor),
            ),
            _MoneyRow(left: tr('order.change'), right: _money(r.changeMinor)),
          ],
          const _Rule(),
          Column(
            spacing: _paperGap,
            children: [
              // The payment method, then only the org's footer (or the
              // default thank-you) — as printed.
              _Mono(
                r.paymentLabel.toUpperCase(),
                size: _rowSize,
                weight: FontWeight.w700,
              ),
              _Mono(
                bridge.receiptFooter(),
                size: _rowSize,
                weight: FontWeight.w700,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One receipt line, as printed: the base price for ONE unit, each paid
/// modifier with what it adds to one unit, then "2 × 95.00 … 190.00". A line
/// with no paid modifiers stays one row; a line whose per-unit split does not
/// divide exactly (a reward) shows its total only.
class _LineBlock extends StatelessWidget {
  const _LineBlock({required this.line, required this.money});

  final ReceiptLineView line;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    final qty = line.qty < 1 ? 1 : line.qty;
    final mods = [...line.addons, ...line.optionals];
    final paid = mods.fold<int>(
      0,
      (sum, m) => sum + (m.priceMinor > 0 ? m.priceMinor : 0),
    );
    final perUnit = line.lineTotalMinor % qty == 0
        ? line.lineTotalMinor ~/ qty
        : null;
    final base = perUnit == null ? null : perUnit - paid;
    final priced = base != null && base >= 0 && paid > 0;
    final name = _nameWithSize(line.name, line.sizeLabel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: _paperGap,
      children: [
        _MoneyRow(
          left: priced || qty == 1 ? name : '$qty× $name',
          right: money(priced ? base : line.lineTotalMinor),
          bold: true,
        ),
        for (final m in mods)
          _ModRow(prefix: '  + ', modifier: m, money: money, priced: priced),
        if (priced)
          _MoneyRow(
            left: '$qty × ${money(perUnit!)}',
            right: money(line.lineTotalMinor),
            bold: true,
          ),
        // A staff drink: the line above is its NORMAL price; the pool's comp
        // is a line discount under it (already off the subtotal), exactly as
        // the printed receipt has it. The label and the figure are the core's.
        if (line.staffLabel case final staff?)
          _MoneyRow(
            key: const ValueKey('receipt-staff-comp'),
            left: '  ★ $staff',
            right: '-${money(line.staffCompMinor)}',
          ),
      ],
    );
  }
}

/// A combo, as printed (C12): `n× <combo> …… n×P`, then each of its items
/// indented with its size and `+surcharge` when it cost more, and its add-ons
/// indented once more with their prices.
class _ComboBlock extends StatelessWidget {
  const _ComboBlock({required this.line, required this.money});

  final ReceiptLineView line;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('receipt-combo-${line.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: _paperGap,
      children: [
        _MoneyRow(
          left: '${line.qty}× ${line.name}',
          right: money(line.unitPriceMinor * line.qty),
          bold: true,
        ),
        for (final p in line.parts) ...[
          _MoneyRow(
            left: '  ${p.qty}× ${_nameWithSize(p.name, p.sizeLabel)}',
            right: p.surchargeMinor > 0 ? '+${money(p.surchargeMinor)}' : '',
          ),
          for (final m in [...p.addons, ...p.optionals])
            _ModRow(prefix: '    + ', modifier: m, money: money, priced: true),
        ],
      ],
    );
  }
}

/// A modifier row — indented; `+amount` (already × its count) only when the
/// line shows its per-unit math.
class _ModRow extends StatelessWidget {
  const _ModRow({
    required this.prefix,
    required this.modifier,
    required this.money,
    required this.priced,
  });

  final String prefix;
  final ReceiptModifierView modifier;
  final String Function(int minor) money;
  final bool priced;

  @override
  Widget build(BuildContext context) {
    return _MoneyRow(
      left: '$prefix${modifier.name}',
      right: priced && modifier.priceMinor > 0
          ? '+${money(modifier.priceMinor)}'
          : '',
      faint: true,
    );
  }
}

// The catalog's sentinel for an item with no real size choice — noise on
// the receipt preview, not a size the customer picked.
bool _isOneSize(String s) {
  final t = s.trim().toLowerCase();
  return t == 'one_size' || t == 'one size';
}

String _nameWithSize(String base, String? size) =>
    size == null || size.isEmpty || _isOneSize(size) ? base : '$base ($size)';

/// Centered ink text in the paper's mono-feel scale (tabular figures).
class _Mono extends StatelessWidget {
  const _Mono(
    this.text, {
    required this.size,
    this.weight = FontWeight.w400,
    this.color = Paper.ink,
    this.align = TextAlign.center,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color color;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: MadarType.bodySm.copyWith(
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A hairline paper rule.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsetsDirectional.symmetric(vertical: 1),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: Paper.rule),
      ),
    );
  }
}

/// A left-label / right-amount row — the amount keeps LTR digits and
/// tabular figures so the column aligns like thermal output.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.left,
    required this.right,
    this.bold = false,
    this.faint = false,
    super.key,
  });

  final String left;
  final String right;
  final bool bold;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final color = faint ? Paper.faint : Paper.ink;
    final size = bold ? _boldRowSize : _rowSize;
    final weight = bold ? FontWeight.w700 : FontWeight.w400;
    final style = MadarType.bodySm.copyWith(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
    // Figures in Plex Mono (spec §4), isolated LTR so an Arabic paper still
    // reads `−12.50` and the column's digits line up like thermal output.
    final figure = MadarType.money.copyWith(
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: color,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: _paperGap * 2,
      children: [
        Expanded(child: Text(left, style: style)),
        if (right.isNotEmpty)
          Text(right, textDirection: TextDirection.ltr, style: figure),
      ],
    );
  }
}
