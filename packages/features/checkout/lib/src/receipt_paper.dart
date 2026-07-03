import 'package:app_core/app_core.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// On-screen receipt preview — a white "thermal paper" card rendered from the
// core's ReceiptView so the teller sees exactly what will print BEFORE
// sending it. Port of the natives' ReceiptPaper.kt / the ESC/POS layout in
// receipt.rs. Theme-invariant BY DESIGN: a receipt is always white paper
// with dark ink (the natives hardcode the same palette in both themes).

const Color _paper = Color(0xFFFFFFFF);
const Color _ink = Color(0xFF1A1A1A);
const Color _faint = Color(0xFF6B6B6B);
const Color _rule = Color(0xFFCCCCCC);

/// The voided stamp's red (natives: 0xFFB71C1C).
const Color _voidRed = Color(0xFFB71C1C);

/// Paper card metrics (natives: 360.dp cap, 10.dp corners, 18.dp padding,
/// 6.dp row gap).
const double _paperMaxWidth = 360;
const double _paperRadius = 10;
const double _paperPad = 18;
const double _paperGap = 6;

/// Org logo box (natives: max 60×220.dp, 6.dp bottom gap) — aspect-preserved
/// so a wide wordmark or a square mark both render without cropping.
const double _logoMaxHeight = 60;
const double _logoMaxWidth = 220;

/// Type sizes on the paper (natives: 15/13/12/11.sp).
const double _storeSize = 15;
const double _boldRowSize = 13;
const double _rowSize = 12;
const double _metaSize = 11;

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
    this.orgLogoUrl,
    super.key,
  });

  final ReceiptView receipt;
  final String storeName;
  final String currency;
  final String? orgLogoUrl;

  String _money(int minor) => Money.format(minor, currency: currency);

  /// "Order #12" when the server assigned a number, else the local order
  /// id's first uuid segment (the natives' orderTitle).
  String _orderTitle(String label) {
    final number = receipt.orderNumber;
    if (number != null) return '$label #$number';
    return '$label ${receipt.localOrderId.split('-').first.toUpperCase()}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    String tr(String key) => bridge.tr(key: key);
    final r = receipt;
    final logo = orgLogoUrl;
    final deliveryNotes = r.deliveryNotes;
    return Container(
      constraints: const BoxConstraints(maxWidth: _paperMaxWidth),
      padding: const EdgeInsetsDirectional.all(_paperPad),
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(_paperRadius),
        border: Border.all(color: _rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: _paperGap,
        children: [
          Column(
            spacing: _paperGap,
            children: [
              // Org brand mark at the top of the paper. Blank/unreachable →
              // just the store name; nothing draws while loading or on
              // failure (the natives' Coil behavior). Persistently disk-cached
              // so it still renders on an offline reprint / after restart.
              if (logo != null && logo.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: _paperGap,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: _logoMaxHeight,
                      maxWidth: _logoMaxWidth,
                    ),
                    child: Image(
                      image: CachedNetworkImageProvider(logo),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              if (r.isVoided)
                _Mono(
                  '*** ${tr('receipt.voided')} ***',
                  size: _boldRowSize,
                  weight: FontWeight.w700,
                  color: _voidRed,
                ),
              _Mono(
                storeName.trim().isEmpty ? 'MADAR' : storeName.toUpperCase(),
                size: _storeSize,
                weight: FontWeight.w700,
              ),
              if (r.isDelivery && r.deliveryChannel != null)
                _Mono(
                  '— ${(r.deliveryChannel == 'in_mall' ? tr('delivery.in_mall') : tr('receipt.delivery')).toUpperCase()} —',
                  size: _metaSize,
                  color: _faint,
                ),
            ],
          ),
          const _Rule(),
          _MoneyRow(
            left: _orderTitle(tr('receipt.order')),
            right: bridge.formatTime(
              rfc3339: r.createdAt,
              style: TimeStyle.receipt,
            ),
          ),
          if (r.orderRef != null)
            _MoneyRow(left: '${tr('receipt.ref')}: ${r.orderRef}', right: ''),
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
          for (final line in r.lines) _LineBlock(line: line, money: _money),
          const _Rule(),
          _MoneyRow(
            left: tr('order.subtotal'),
            right: _money(r.subtotalMinor),
          ),
          if (r.discountMinor > 0)
            _MoneyRow(
              left: tr('order.discount'),
              right: '−${_money(r.discountMinor)}',
            ),
          if (r.taxMinor > 0)
            _MoneyRow(left: tr('order.tax'), right: _money(r.taxMinor)),
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
          if (r.tipMinor > 0)
            _MoneyRow(left: tr('order.tip'), right: _money(r.tipMinor)),
          if (r.isCash) ...[
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
              _Mono(
                r.paymentLabel.toUpperCase(),
                size: _metaSize,
                weight: FontWeight.w600,
              ),
              if (r.tellerName != null)
                _Mono(
                  '${tr('receipt.served_by')} ${r.tellerName}',
                  size: _metaSize,
                  color: _faint,
                ),
              _Mono(tr('receipt.thank_you'), size: _rowSize),
            ],
          ),
        ],
      ),
    );
  }
}

/// One receipt line: `qty× name (size) … amount`, then its modifiers — a
/// bundle indents its components with their own addons/optionals.
class _LineBlock extends StatelessWidget {
  const _LineBlock({required this.line, required this.money});

  final ReceiptLineView line;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: _paperGap,
      children: [
        _MoneyRow(
          left: '${line.qty}× ${_nameWithSize(line.name, line.sizeLabel)}',
          right: money(line.lineTotalMinor),
        ),
        if (line.isBundle)
          for (final c in line.components) ...[
            _Mono(
              '  – ${_nameWithSize(c.name, c.sizeLabel)}',
              size: _rowSize,
              color: _faint,
              align: TextAlign.start,
            ),
            for (final m in c.addons)
              _ModRow(prefix: '    + ', modifier: m, money: money),
            for (final m in c.optionals)
              _ModRow(prefix: '    + ', modifier: m, money: money),
          ]
        else ...[
          for (final m in line.addons)
            _ModRow(prefix: '  + ', modifier: m, money: money),
          for (final m in line.optionals)
            _ModRow(prefix: '  + ', modifier: m, money: money),
        ],
      ],
    );
  }
}

/// A priced modifier row — faint, indented, `+amount` only when charged.
class _ModRow extends StatelessWidget {
  const _ModRow({
    required this.prefix,
    required this.modifier,
    required this.money,
  });

  final String prefix;
  final ReceiptModifierView modifier;
  final String Function(int minor) money;

  @override
  Widget build(BuildContext context) {
    return _MoneyRow(
      left: '$prefix${modifier.name}',
      right: modifier.priceMinor > 0 ? '+${money(modifier.priceMinor)}' : '',
      faint: true,
    );
  }
}

String _nameWithSize(String base, String? size) =>
    size == null || size.isEmpty ? base : '$base ($size)';

/// Centered ink text in the paper's mono-feel scale (tabular figures).
class _Mono extends StatelessWidget {
  const _Mono(
    this.text, {
    required this.size,
    this.weight = FontWeight.w400,
    this.color = _ink,
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
        child: ColoredBox(color: _rule),
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
  });

  final String left;
  final String right;
  final bool bold;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final color = faint ? _faint : _ink;
    final style = MadarType.bodySm.copyWith(
      fontSize: bold ? _boldRowSize : _rowSize,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(left, style: style)),
        if (right.isNotEmpty)
          Text(right, textDirection: TextDirection.ltr, style: style),
      ],
    );
  }
}
