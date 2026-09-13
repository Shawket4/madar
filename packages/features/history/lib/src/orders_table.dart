/// THE orders table — one set of columns for every list of sales in the
/// till: the Orders screen, and the orders nested under a past shift. They
/// used to be two hand-built row widgets that agreed on nothing (the owner's
/// "Past shifts and Orders look nothing alike"); now a sale reads the same
/// wherever it is listed. docs/design/SPEC.md §8, §15.
library;

import 'package:design_system/design_system.dart';
import 'package:feature_history/src/history_strings.dart';
import 'package:feature_history/src/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// A sale's status as a pill: what the core's status says, never colour
/// alone. Settled sales read "Paid".
MadarStatus orderStatus(MadarBridge bridge, OrderSummaryView o) {
  String t(String key) => historyTr(bridge, key);
  return switch (SaleState.of(o)) {
    SaleState.voided => MadarStatus(
      t('history.voided'),
      glyph: MadarGlyph.close,
    ),
    SaleState.failed => MadarStatus(
      t('history.failed'),
      tone: MadarTone.danger,
    ),
    SaleState.queued => MadarStatus(
      t('history.queued'),
      tone: MadarTone.warning,
      glyph: MadarGlyph.half,
    ),
    null => switch (o.status) {
      'refunded' => MadarStatus(t('history.refunded'), tone: MadarTone.danger),
      'partially_refunded' => MadarStatus(
        t('history.status_part_refunded'),
        tone: MadarTone.warning,
      ),
      // Settled, but rung offline against a menu that has since moved —
      // worth a look, so it is said where Paid would be.
      _ when o.priceFlagged => MadarStatus(
        t('history.price_flagged'),
        tone: MadarTone.warning,
        glyph: MadarGlyph.percent,
      ),
      _ => MadarStatus(t('history.status_paid'), tone: MadarTone.success),
    },
  };
}

/// The rail a sale's row carries: none for a settled sale, the pill's tone
/// otherwise — so the rows that need a look stand out down the edge.
MadarTone? orderRail(MadarBridge bridge, OrderSummaryView o) {
  final tone = orderStatus(bridge, o).tone;
  return tone == MadarTone.success ? null : tone;
}

/// The columns: #, Time, Type, Payment, Total, Status. Time is the core's
/// branch-zone stamp (`18:02` today, `Sep 12 · 18:02` before).
List<MadarColumn<OrderSummaryView>> orderColumns(
  MadarBridge bridge, {
  required String currency,
}) {
  String t(String key) => historyTr(bridge, key);
  return [
    MadarColumn(
      id: 'number',
      label: t('history.col_number'),
      text: (o) => saleNumber(bridge, o),
      width: 96,
      mono: true,
      emphasis: true,
      phone: MadarPhoneRole.title,
    ),
    MadarColumn(
      id: 'time',
      label: t('history.col_time'),
      text: (o) => bridge.formatStamp(rfc3339: o.createdAt),
      flex: 2,
      mono: true,
      muted: true,
      priority: 2,
      phone: MadarPhoneRole.meta,
    ),
    MadarColumn(
      id: 'type',
      label: t('history.col_type'),
      text: (o) => orderTypeLabel(bridge, o.orderType),
      flex: 2,
      priority: 4,
      phone: MadarPhoneRole.meta,
    ),
    MadarColumn(
      id: 'payment',
      label: t('history.col_payment'),
      text: (o) => bridge.paymentMethodLabel(code: o.paymentLabel),
      flex: 2,
      priority: 3,
      phone: MadarPhoneRole.meta,
    ),
    MadarColumn.money(
      id: 'total',
      label: t('order.total'),
      minor: (o) => o.totalMinor,
      currency: currency,
      width: 140,
    ),
    MadarColumn.status(
      id: 'status',
      label: t('history.col_status'),
      status: (o) => orderStatus(bridge, o),
      width: 168,
      priority: 1,
    ),
  ];
}

/// A table of sales. The Orders screen passes [onTap] and [selectedId]; a
/// past shift nests one with `framed: false, scrollable: false` and a print
/// [trailing].
class OrdersTable extends StatelessWidget {
  const OrdersTable({
    required this.bridge,
    required this.currency,
    required this.state,
    required this.empty,
    this.onTap,
    this.selectedId,
    this.trailing,
    this.framed = true,
    this.scrollable = true,
    this.collapse,
    super.key,
  });

  final MadarBridge bridge;
  final String currency;
  final MadarTableState<OrderSummaryView> state;
  final MadarEmptyContent empty;
  final ValueChanged<OrderSummaryView>? onTap;
  final String? selectedId;
  final Widget? Function(BuildContext context, OrderSummaryView o)? trailing;
  final bool framed;
  final bool scrollable;
  final bool? collapse;

  @override
  Widget build(BuildContext context) {
    return MadarDataTable<OrderSummaryView>(
      columns: orderColumns(bridge, currency: currency),
      state: state,
      rowKey: (o) => o.id,
      empty: empty,
      onTap: onTap,
      selected: selectedId == null ? null : (o) => o.id == selectedId,
      rail: (o) => orderRail(bridge, o),
      trailing: trailing,
      loadMoreLabel: historyTr(bridge, 'search.load_more'),
      framed: framed,
      scrollable: scrollable,
      collapse: collapse,
    );
  }
}
