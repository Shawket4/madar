import 'package:design_system/design_system.dart';
import 'package:feature_incoming/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Shared "what's actually in this order" surface for the Orders channel.
// Both the Open-tickets tab (real TicketView.lines) and the Delivery tab
// (the delivery order's lines + money breakdown + context) route through
// the SAME layout: a context header, a line-items card, and a totals
// block. Read-only — the settle / lifecycle actions live on the cards +
// the CheckoutDrawer. Port of the natives' OrderDetailsSheet.kt.

// Native metrics (OrderDetailsSheet.kt) kept verbatim.

/// Qty badge vertical inset (natives: 3.dp).
const double _qtyBadgeVPad = 3;

/// Context-chip vertical inset (natives: 6.dp).
const double _contextChipVPad = 6;

/// Delivery-notes inset vertical padding (natives: 7–8.dp band).
const double _noteVPad = 7;

/// Grand-total figure size (natives: 20.sp Black).
const double _totalSize = 20;

/// Ticket details — the covering + table/guests context, the real line
/// items (qty × name, size, modifiers, per-line price), and the total.
/// Rendered as the body of a LARGE MadarSheet; an optional [footer] (e.g.
/// the Settle CTA) pins under the scrolling details.
class TicketDetailsSheet extends StatelessWidget {
  const TicketDetailsSheet({
    required this.ticket,
    required this.currency,
    required this.tr,
    this.footer,
    super.key,
  });

  final TicketView ticket;
  final String currency;
  final String Function(String key) tr;

  /// Pinned CTA under the details (stays on screen while details scroll).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final ctx = <(String, String)>[
      // Who took the table — the waiter who opened the ticket.
      if (ticket.waiterName case final w? when w.isNotEmpty)
        ('fork.knife', '${tr('order.waiter')}: $w'),
      if (ticket.customerName case final name? when name.isNotEmpty)
        ('person.fill', name),
      if (ticket.tableId case final table? when table.isNotEmpty)
        ('square.grid.2x2', '${tr('order.table')} $table'),
      if (ticket.guestCount case final covers? when covers > 0)
        ('person.2.fill', '$covers ${tr('waiter.covers')}'),
    ];
    return _SheetScaffold(
      footer: footer,
      children: [
        // Title row — ticket ref + live status chip.
        Row(
          spacing: Space.sm,
          children: [
            MadarIcon('doc.text', tint: colors.accent, size: IconSize.lg),
            Flexible(
              child: Text(
                ticket.ticketRef ?? tr('waiter.ticket'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.h2.copyWith(color: colors.textPrimary),
              ),
            ),
            StatusChip(
              label: tr('ticket.status.${ticket.status}'),
              tone: ticketStatusTone(ticket.status),
            ),
            if (ticket.queuedOffline)
              StatusChip(
                label: tr('waiter.queued'),
                tone: ChipTone.warning,
                icon: 'tray.and.arrow.up',
              ),
          ],
        ),
        // Context chips — waiter / customer / table / covers, when present.
        if (ctx.isNotEmpty)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final (icon, label) in ctx)
                _ContextChip(icon: icon, label: label),
            ],
          ),
        // Line items card — the real ticket lines. Voided lines strike.
        OrderLinesCard(lines: ticket.lines, currency: currency, tr: tr),
        // Totals — a ticket carries a single frozen subtotal (== total).
        TotalsBlock(
          rows: const [],
          totalMinor: ticket.subtotalMinor,
          currency: currency,
          totalLabel: tr('order.total'),
        ),
      ],
    );
  }
}

/// Delivery details — customer/address/channel context, the warning-tinted
/// delivery instructions, the real priced lines (frozen cart snapshot,
/// SAME card tickets use), and the full money breakdown. An optional
/// [footer] (e.g. the Finalize CTA) pins under the scrolling details.
class DeliveryDetailsSheet extends StatelessWidget {
  const DeliveryDetailsSheet({
    required this.order,
    required this.currency,
    required this.tr,
    this.footer,
    super.key,
  });

  final DeliveryOrderView order;
  final String currency;
  final String Function(String key) tr;

  /// Pinned CTA under the details (stays on screen while details scroll).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final o = order;
    final address = o.address;
    final paymentHint = o.paymentHint;
    return _SheetScaffold(
      footer: footer,
      children: [
        // Title row — order ref + status + channel.
        Row(
          spacing: Space.sm,
          children: [
            MadarIcon('bicycle', tint: colors.accent, size: IconSize.lg),
            Flexible(
              child: Text(
                o.orderRef ?? tr('delivery.title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.h2.copyWith(color: colors.textPrimary),
              ),
            ),
            StatusChip(
              label: tr('delivery.status.${o.status}'),
              tone: deliveryStatusTone(o.status),
            ),
            StatusChip(label: tr('delivery.${o.channel}')),
          ],
        ),
        // Context — customer name/phone, address, payment hint.
        IncomingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              _DetailRow(
                icon: 'person.fill',
                label: tr('receipt.customer'),
                value: o.customerName,
              ),
              if (o.customerPhone.isNotEmpty)
                _DetailRow(
                  icon: 'phone.fill',
                  label: tr('receipt.phone'),
                  value: o.customerPhone,
                ),
              if (address != null && address.isNotEmpty)
                _DetailRow(
                  icon: 'mappin.and.ellipse',
                  label: _stripColon(tr('receipt.address')),
                  value: address,
                ),
              if (paymentHint != null && paymentHint.isNotEmpty)
                _DetailRow(
                  icon: 'creditcard',
                  label: tr('order.payment_method'),
                  value: paymentHint,
                ),
            ],
          ),
        ),
        // Customer delivery instructions — warning-tinted, can't be missed.
        if (o.deliveryNotes case final note? when note.isNotEmpty)
          DeliveryNoteInset(note: note),
        // Line items — through the SAME card tickets use.
        OrderLinesCard(lines: o.lines, currency: currency, tr: tr),
        // Money breakdown — the delivery projection gives a full total.
        TotalsBlock(
          rows: [
            (
              tr('order.subtotal'),
              Money.format(o.subtotalMinor, currency: currency),
            ),
            if (o.discountMinor > 0)
              (
                tr('order.discount'),
                '−${Money.format(o.discountMinor, currency: currency)}',
              ),
            if (o.deliveryFeeMinor > 0)
              (
                tr('receipt.delivery_fee'),
                Money.format(o.deliveryFeeMinor, currency: currency),
              ),
          ],
          totalMinor: o.totalMinor,
          currency: currency,
          totalLabel: tr('order.total'),
        ),
      ],
    );
  }
}

/// The common sheet body: the details scroll, an optional footer pins.
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({required this.children, this.footer});

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: children,
            ),
          ),
        ),
        if (footer case final footer?)
          Padding(
            padding: const EdgeInsetsDirectional.all(Space.lg),
            child: footer,
          ),
      ],
    );
  }
}

/// Warning-tinted delivery-instructions inset ("leave at door", "call on
/// arrival") — fulfillment-critical text the dispatcher can't miss.
class DeliveryNoteInset extends StatelessWidget {
  const DeliveryNoteInset({required this.note, super.key});

  final String note;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.sm,
        vertical: _noteVPad,
      ),
      decoration: BoxDecoration(
        color: colors.warningBg,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.xs,
        children: [
          MadarIcon('text.bubble', tint: colors.warning, size: IconSize.sm),
          Expanded(
            child: Text(
              note,
              style: MadarType.label.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Line-items card — one row per [TicketLineView]: `qty× name`, size +
/// modifiers under it, and the per-line price on the trailing edge. Voided
/// lines strike through.
class OrderLinesCard extends StatelessWidget {
  const OrderLinesCard({
    required this.lines,
    required this.currency,
    required this.tr,
    super.key,
  });

  final List<TicketLineView> lines;
  final String currency;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return IncomingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            tr('order.items').toUpperCase(),
            style: MadarType.label.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
            ),
          ),
          if (lines.isEmpty)
            Text(
              tr('order.cart_empty'),
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            )
          else
            for (final line in lines)
              _OrderLineRow(line: line, currency: currency),
        ],
      ),
    );
  }
}

/// A single order line — qty badge + name (+ size / modifiers) + total.
class _OrderLineRow extends StatelessWidget {
  const _OrderLineRow({required this.line, required this.currency});

  final TicketLineView line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final strike = line.voided ? TextDecoration.lineThrough : null;
    final nameColor = line.voided ? colors.textMuted : colors.textPrimary;
    final size = line.sizeLabel;
    final detail = <String>[
      if (size != null && size.isNotEmpty) size,
      ...line.modifiers,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        // Qty badge — teal pill so the count reads at a glance.
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.sm,
            vertical: _qtyBadgeVPad,
          ),
          decoration: BoxDecoration(
            color: colors.accentBg,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: Text(
            '${line.qty}×',
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.accent,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs / 2,
            children: [
              Text(
                line.name,
                style: MadarType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: nameColor,
                  decoration: strike,
                ),
              ),
              // Size + modifiers as a light secondary line.
              if (detail.isNotEmpty)
                Text(
                  detail.join(' · '),
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                    decoration: strike,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(top: Space.xs / 2),
          child: MoneyText(
            line.lineTotalMinor,
            currency: currency,
            style: MadarType.money,
            color: nameColor,
          ),
        ),
      ],
    );
  }
}

/// Totals block — light muted breakdown rows above a tinted-teal grand
/// total (the hero figure), matching the CheckoutDrawer's summary card.
class TotalsBlock extends StatelessWidget {
  const TotalsBlock({
    required this.rows,
    required this.totalMinor,
    required this.currency,
    required this.totalLabel,
    super.key,
  });

  /// (label, formatted value) breakdown rows above the total.
  final List<(String, String)> rows;
  final int totalMinor;
  final String currency;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return IncomingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xs,
        children: [
          for (final (label, value) in rows)
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: MadarType.bodySm.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  value,
                  textDirection: TextDirection.ltr,
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: Space.xs),
            child: Container(
              padding: const EdgeInsetsDirectional.all(Space.md),
              decoration: BoxDecoration(
                color: colors.accentBg,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      totalLabel,
                      style: MadarType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ),
                  MoneyText(
                    totalMinor,
                    currency: currency,
                    style: MadarType.money.copyWith(
                      fontSize: _totalSize,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled context row — leading icon + label + end-aligned value.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final String icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.sm,
      children: [
        MadarIcon(icon, tint: colors.textMuted),
        Text(
          label,
          style: MadarType.label.copyWith(color: colors.textMuted),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A pill of context (waiter / customer / table / covers) with an icon.
class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.icon, required this.label});

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: _contextChipVPad,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          MadarIcon(icon, tint: colors.textSecondary, size: IconSize.sm),
          Text(
            label,
            style: MadarType.label.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Ticket status → chip tone (ready → success, queued → warning, settled →
/// neutral, else accent) — the natives' ticketStatusTone.
ChipTone ticketStatusTone(String status) => switch (status) {
  'ready' => ChipTone.success,
  'queued' => ChipTone.warning,
  'settled' => ChipTone.neutral,
  _ => ChipTone.accent,
};

/// Delivery status → chip tone for the DETAILS sheet (the natives'
/// deliveryDetailTone).
ChipTone deliveryStatusTone(String status) => switch (status) {
  'ready' || 'delivered' => ChipTone.success,
  'preparing' => ChipTone.warning,
  'cancelled' || 'rejected' => ChipTone.danger,
  _ => ChipTone.accent,
};

/// "Address:" → "Address" (the natives' removeSuffix(":")).
String _stripColon(String label) =>
    label.endsWith(':') ? label.substring(0, label.length - 1) : label;
