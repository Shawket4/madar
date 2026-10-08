/// The home's figures computed from the seeded tables the way the backend
/// computes them (MadarRust `reports/handlers.rs`, `insights/handlers.rs`,
/// `tills/handlers.rs`, `orgs/onboarding.rs`), so every card agrees with
/// every other: the KPI revenue is the sum of the branch rows, the payment
/// mix adds up to it, the Talabat buckets are the delivery revenue, and the
/// trend's periods add up to the same total.
///
/// Pure functions over [MockDb] rows; the handlers in `register.dart` add the
/// capability checks and the request parsing.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import 'home_seed.dart';

/// The backend's "every branch in my org" id (`Uuid::nil()`).
const String nilBranchId = '00000000-0000-0000-0000-000000000000';

/// The four delivery channels, in the backend's fixed order
/// (`DELIVERY_CHANNELS`).
const List<String> deliveryChannels = ['in_mall', 'outside', 'umbrella', 'pickup'];

/// The backend's built-in margin target (`DEFAULT_TARGET_PCT`).
const double defaultTargetPct = 60;

const int _minSignalQty = 5;
const double _priceBufferPct = 5;
const int _priceRound = 100;

bool _sold(MockRow o) {
  final s = o['status'];
  return s != 'voided' && s != 'refunded';
}

final Expando<DateTime> _createdAt = Expando('created_at');

/// `created_at` of a row, parsed once.
DateTime createdAtOf(MockRow row) =>
    _createdAt[row] ??= DateTime.parse(row['created_at']! as String);

int _int(Object? v) => v is num ? v.toInt() : 0;

/// The orders of [branchIds] created in [from, to] (either end open).
List<MockRow> ordersIn(
  MockDb db,
  Iterable<String> branchIds, {
  DateTime? from,
  DateTime? to,
}) {
  final ids = branchIds.toSet();
  return [
    for (final o in db['orders'].rows)
      if (ids.contains(o['branch_id']) &&
          (from == null || !createdAtOf(o).isBefore(from)) &&
          (to == null || !createdAtOf(o).isAfter(to)))
        o,
  ];
}

/// Goods money per tender (`order_payments` by method): tips are never in a
/// bucket.
Map<String, int> revenueByMethod(Iterable<MockRow> orders) {
  final out = <String, int>{};
  for (final o in orders) {
    if (!_sold(o)) continue;
    final legs = o['payment_legs'];
    if (legs is List && legs.isNotEmpty) {
      for (final l in legs) {
        if (l is! Map) continue;
        final m = l['method'] as String? ?? 'cash';
        out[m] = (out[m] ?? 0) + _int(l['amount']);
      }
    } else {
      final m = o['payment_method'] as String? ?? 'cash';
      out[m] = (out[m] ?? 0) + _int(o['total_amount']);
    }
  }
  return out;
}

/// The money figures every sales report shares.
class SalesTotals {
  SalesTotals(Iterable<MockRow> orders) {
    for (final o in orders) {
      if (!_sold(o)) {
        if (o['status'] == 'voided') voided++;
        continue;
      }
      count++;
      revenue += _int(o['total_amount']);
      subtotal += _int(o['subtotal']);
      discount += _int(o['discount_amount']);
      tax += _int(o['tax_amount']);
      serviceCharge += _int(o['service_charge_amount']);
      deliveryFees += _int(o['delivery_fee']);
      final tip = _int(o['tip_amount']);
      tips += tip;
      final tipMethod =
          o['tip_payment_method'] as String? ?? o['payment_method'] as String?;
      final tipCash = o['tip_is_cash'] as bool? ?? tipMethod == 'cash';
      if (tipCash) cashTips += tip;
    }
  }

  int count = 0;
  int voided = 0;
  int revenue = 0;
  int subtotal = 0;
  int discount = 0;
  int tax = 0;
  int serviceCharge = 0;
  int deliveryFees = 0;
  int tips = 0;
  int cashTips = 0;
}

// ── Order lines (snapshot of the seed's lines, built once) ───────────────

/// One order line as the ledger reads it.
class HomeLine {
  const HomeLine({
    required this.itemId,
    required this.sizeLabel,
    required this.itemName,
    required this.quantity,
    required this.lineTotal,
    required this.addons,
  });

  final String itemId;

  /// `one_size` for a single-size item (`COALESCE(size_label, 'one_size')`).
  final String sizeLabel;
  final String itemName;
  final int quantity;
  final int lineTotal;

  /// Add-on units on the line.
  final int addons;
}

final Map<String, List<HomeLine>> _linesCache = {};

/// The lines of order [orderId] (the seed's; an order created at run time
/// has none here).
List<HomeLine> linesOf(String orderId) => _linesCache[orderId] ??= [
  for (final l in MockSeed.instance.orderItems(orderId))
    if (l.menuItemId != null)
      HomeLine(
        itemId: l.menuItemId!,
        sizeLabel: l.sizeLabel ?? 'one_size',
        itemName: l.itemName,
        quantity: l.quantity,
        lineTotal: l.lineTotal,
        addons: l.addons.fold(0, (s, a) => s + a.quantity),
      ),
];

// ── Reports ───────────────────────────────────────────────────────────────

/// `GET /reports/branches/{id}/sales` over [orders] (already scoped).
BranchSalesReport branchSalesReport({
  required String branchId,
  required String branchName,
  required List<MockRow> orders,
  DateTime? from,
  DateTime? to,
  int topLimit = 10,
}) {
  final t = SalesTotals(orders);
  final byItem = <String, (String, int, int, String?)>{};
  var lineItems = 0;
  for (final o in orders) {
    if (!_sold(o)) continue;
    for (final l in linesOf(o['id']! as String)) {
      lineItems += l.quantity;
      final prev = byItem[l.itemId];
      byItem[l.itemId] = (
        l.itemName,
        (prev?.$2 ?? 0) + l.quantity,
        (prev?.$3 ?? 0) + l.lineTotal,
        homeCategoryOf(l.itemId),
      );
    }
  }
  ItemSales item(MapEntry<String, (String, int, int, String?)> e) => ItemSales(
    menuItemId: e.key,
    itemName: e.value.$1,
    itemNameTranslations: homeItemNames(e.key),
    quantitySold: e.value.$2,
    revenue: e.value.$3,
  );
  final ranked = byItem.entries.toList()
    ..sort((a, b) => b.value.$3.compareTo(a.value.$3));
  final categories = <String, List<MapEntry<String, (String, int, int, String?)>>>{};
  for (final e in ranked) {
    categories.putIfAbsent(e.value.$4 ?? '', () => []).add(e);
  }
  return BranchSalesReport(
    branchId: branchId,
    branchName: branchName,
    from: from,
    to: to,
    totalOrders: t.count,
    voidedOrders: t.voided,
    subtotal: t.subtotal,
    totalDiscount: t.discount,
    totalTax: t.tax,
    totalRevenue: t.revenue,
    grossSales: t.revenue,
    refundedAmount: 0,
    totalServiceCharge: t.serviceCharge,
    serviceChargeWaivedCount: 0,
    serviceChargeWaivedAmount: 0,
    totalDeliveryFees: t.deliveryFees,
    totalLineItems: lineItems,
    totalTips: t.tips,
    cashTips: t.cashTips,
    revenueByMethod: revenueByMethod(orders),
    topItems: [for (final e in ranked.take(topLimit)) item(e)],
    byCategory: [
      for (final c in categories.entries)
        CategorySales(
          categoryId: c.key.isEmpty ? null : c.key,
          categoryName: homeCategoryName(c.key),
          categoryNameTranslations: homeCategoryNames(c.key),
          itemCount: c.value.length,
          quantitySold: c.value.fold(0, (s, e) => s + e.value.$2),
          revenue: c.value.fold(0, (s, e) => s + e.value.$3),
          items: [for (final e in c.value) item(e)],
        ),
    ],
  );
}

String _two(int v) => v.toString().padLeft(2, '0');

/// The bucket an instant falls in, as the backend writes it: a naive
/// wall-clock string in the scope's zone (`YYYY-MM-DDTHH:MM:SS`).
String periodOf(DateTime utc, String granularity) {
  final w = MockClock.wall(utc);
  final day = '${w.year}-${_two(w.month)}-${_two(w.day)}';
  return switch (granularity) {
    'hourly' => '${day}T${_two(w.hour)}:00:00',
    'monthly' => '${w.year}-${_two(w.month)}-01T00:00:00',
    _ => '${day}T00:00:00',
  };
}

/// `GET /reports/branches/{id}/sales/timeseries`: only the periods that had
/// orders, oldest first.
List<TimeseriesPoint> salesTimeseries(
  List<MockRow> orders,
  String granularity,
) {
  final buckets = <String, List<MockRow>>{};
  for (final o in orders) {
    buckets.putIfAbsent(periodOf(createdAtOf(o), granularity), () => []).add(o);
  }
  final keys = buckets.keys.toList()..sort();
  return [
    for (final k in keys)
      () {
        final rows = buckets[k]!;
        final t = SalesTotals(rows);
        var lines = 0;
        var addons = 0;
        for (final o in rows) {
          if (!_sold(o)) continue;
          for (final l in linesOf(o['id']! as String)) {
            lines += l.quantity;
            addons += l.addons;
          }
        }
        return TimeseriesPoint(
          period: k,
          orders: t.count,
          revenue: t.revenue,
          refunded: 0,
          voided: t.voided,
          discount: t.discount,
          tax: t.tax,
          revenueByMethod: revenueByMethod(rows),
          lineItems: lines,
          addons: addons,
        );
      }(),
  ];
}

/// One comparison row per branch of the org (zero-sale branches included).
BranchComparison branchComparisonRow(
  MockRow branch,
  List<MockRow> orders,
) {
  final t = SalesTotals(orders);
  return BranchComparison(
    branchId: branch['id']! as String,
    branchName: branch['name']! as String,
    totalOrders: t.count,
    voidedOrders: t.voided,
    totalRevenue: t.revenue,
    grossSales: t.revenue,
    refundedAmount: 0,
    revenueByMethod: revenueByMethod(orders),
    totalTips: t.tips,
    cashTips: t.cashTips,
    avgOrderValue: t.count == 0 ? 0 : t.revenue ~/ t.count,
    voidRatePct: t.count + t.voided == 0
        ? 0
        : t.voided / (t.count + t.voided) * 100,
  );
}

// ── Delivery ──────────────────────────────────────────────────────────────

/// The delivery orders of the scope. A `delivery_orders` table (another
/// area's) wins; otherwise the seed's delivery orders are its orders of type
/// `delivery`: a completed one was delivered, a voided one cancelled.
List<({String channel, String status, int total, int fee})> deliveryOrdersIn(
  MockDb db,
  Iterable<String> branchIds, {
  DateTime? from,
  DateTime? to,
}) {
  final ids = branchIds.toSet();
  bool inRange(MockRow r) =>
      ids.contains(r['branch_id']) &&
      (from == null || !createdAtOf(r).isBefore(from)) &&
      (to == null || !createdAtOf(r).isAfter(to));
  if (db.hasTable('delivery_orders') && db['delivery_orders'].length > 0) {
    return [
      for (final r in db['delivery_orders'].rows)
        if (inRange(r))
          (
            channel: r['channel'] as String? ?? 'outside',
            status: r['status'] as String? ?? '',
            total: _int(r['total']),
            fee: _int(r['delivery_fee']),
          ),
    ];
  }
  return [
    for (final o in ordersIn(db, branchIds, from: from, to: to))
      if (o['order_type'] == 'delivery')
        (
          channel: o['delivery_channel'] as String? ?? 'outside',
          status: switch (o['status']) {
            'voided' || 'refunded' || 'cancelled' => 'cancelled',
            _ => 'delivered',
          },
          total: _int(o['total_amount']),
          fee: _int(o['delivery_fee']),
        ),
  ];
}

/// `GET /reports/branches/{id}/delivery-sales`: the four channels, zero-filled.
DeliverySalesReport deliverySalesReport(
  List<({String channel, String status, int total, int fee})> rows, {
  DateTime? from,
  DateTime? to,
}) {
  final channels = [
    for (final name in deliveryChannels)
      () {
        final mine = rows.where((r) => r.channel == name);
        final delivered = mine.where((r) => r.status == 'delivered');
        final orders = delivered.length;
        final revenue = delivered.fold(0, (s, r) => s + r.total);
        final fees = delivered.fold(0, (s, r) => s + r.fee);
        return DeliveryChannelSales(
          channel: name,
          orders: orders,
          revenue: revenue,
          deliveryFees: fees,
          goodsRevenue: revenue - fees,
          avgOrderValue: orders == 0 ? 0 : revenue ~/ orders,
          cancelledOrders: mine.where((r) => r.status == 'cancelled').length,
        );
      }(),
  ];
  final orders = channels.fold(0, (s, c) => s + c.orders);
  final revenue = channels.fold(0, (s, c) => s + c.revenue);
  final fees = channels.fold(0, (s, c) => s + c.deliveryFees);
  return DeliverySalesReport(
    from: from,
    to: to,
    totalOrders: orders,
    totalRevenue: revenue,
    totalDeliveryFees: fees,
    totalGoodsRevenue: revenue - fees,
    cancelledOrders: channels.fold(0, (s, c) => s + c.cancelledOrders),
    avgOrderValue: orders == 0 ? 0 : revenue ~/ orders,
    channels: channels,
  );
}

// ── Margin watch (the profitability ledger, snapshot basis) ──────────────

class _Agg {
  int qty = 0;
  int revenue = 0;
  String name = '';
}

Map<(String, String), _Agg> _salesAgg(List<MockRow> orders) {
  final out = <(String, String), _Agg>{};
  for (final o in orders) {
    if (!_sold(o)) continue;
    for (final l in linesOf(o['id']! as String)) {
      final a = out[(l.itemId, l.sizeLabel)] ??= _Agg();
      a
        ..qty += l.quantity
        ..revenue += l.lineTotal
        ..name = l.itemName;
    }
  }
  return out;
}

/// The ledger the margin watch reads (`build_ledger`): one row per item and
/// size on the menu or sold in the window, the signals, the totals, ranked
/// by known margin.
({List<MarginLedgerRow> rows, LedgerTotals totals, int openSignals, int rowsCostUnknown})
marginLedger({
  required List<MockRow> orders,
  required List<MockRow> prevOrders,
  required bool windowed,
  double targetPct = defaultTargetPct,
}) {
  final sales = _salesAgg(orders);
  final prev = _salesAgg(prevOrders);
  final keys = <(String, String)>{...homeCatalogSkus(), ...sales.keys};
  final rows = <MarginLedgerRow>[];
  // Upper-quartile quantity among the rows that sold.
  final sold = [
    for (final a in sales.values)
      if (a.qty > 0) a.qty,
  ]..sort();
  final q3 = sold.isEmpty ? 1 << 62 : sold[(sold.length - 1) * 3 ~/ 4];
  var openSignals = 0;
  for (final k in keys) {
    final s = sales[k];
    final p = prev[k];
    final qty = s?.qty ?? 0;
    final revenue = s?.revenue ?? 0;
    final unitCost = homeUnitCost(k.$1, k.$2);
    final cost = unitCost == null || qty == 0 ? null : unitCost * qty;
    final margin = cost == null ? null : revenue - cost;
    final pct = cost != null && revenue > 0
        ? (revenue - cost) / revenue * 100
        : null;
    final prevCost = unitCost == null || p == null ? null : unitCost * p.qty;
    final flags = <Signal>[];
    if (margin != null && qty > 0 && margin < 0) {
      flags.add(
        Signal(
          kind: 'below_cost',
          link: 'pricing',
          params: {'margin': margin, 'revenue': revenue, 'cost': cost},
        ),
      );
    } else if (pct != null && pct < targetPct && qty >= _minSignalQty) {
      flags.add(
        Signal(
          kind: 'below_target',
          link: 'pricing',
          params: {
            'margin_pct': (pct * 10).round() / 10,
            'target_pct': targetPct,
          },
        ),
      );
    }
    if (pct != null &&
        qty >= q3 &&
        pct < targetPct - _priceBufferPct &&
        cost != null &&
        qty >= _minSignalQty) {
      final unit = cost / qty;
      final target = unit / (1 - targetPct / 100);
      final suggested = (target / _priceRound).ceil() * _priceRound;
      flags.add(
        Signal(
          kind: 'price_candidate',
          link: 'pricing',
          params: {
            'margin_pct': (pct * 10).round() / 10,
            'target_pct': targetPct,
            'suggested_price': suggested,
            'last_worked': null,
          },
        ),
      );
    }
    final onMenu = homeCatalogSkus().contains(k);
    if (onMenu && qty == 0 && windowed) {
      flags.add(
        const Signal(kind: 'removal_candidate', link: 'studio', params: {}),
      );
    }
    if (onMenu && unitCost == null) {
      flags.add(
        const Signal(
          kind: 'recipe_incomplete',
          link: 'studio_recipe',
          params: {},
        ),
      );
    }
    openSignals += flags.length;
    rows.add(
      MarginLedgerRow(
        menuItemId: k.$1,
        sizeLabel: k.$2,
        itemName: s?.name ?? homeItemName(k.$1),
        categoryId: homeCategoryOf(k.$1),
        categoryName: homeCategoryName(homeCategoryOf(k.$1) ?? ''),
        onMenu: onMenu,
        quantitySold: qty,
        revenue: revenue,
        cost: cost,
        margin: margin,
        marginPct: pct,
        prevQuantity: p?.qty ?? 0,
        prevMargin: prevCost == null || p == null ? null : p.revenue - prevCost,
        flags: flags,
      ),
    );
  }
  final revenue = rows.fold(0, (s, r) => s + r.revenue);
  final costKnown = rows.fold(0, (s, r) => s + (r.cost ?? 0));
  final marginKnown = rows.fold(0, (s, r) => s + (r.margin ?? 0));
  final revenueKnown = rows
      .where((r) => r.cost != null)
      .fold(0, (s, r) => s + r.revenue);
  final revenueCostUnknown = rows
      .where((r) => r.cost == null && r.quantitySold > 0)
      .fold(0, (s, r) => s + r.revenue);
  final prevRevenue = prev.values.fold(0, (s, a) => s + a.revenue);
  final prevMarginKnown = rows.fold(0, (s, r) => s + (r.prevMargin ?? 0));
  var belowTargetGap = 0;
  for (final r in rows) {
    final m = r.margin;
    final pct = r.marginPct;
    if (m != null && pct != null && pct < targetPct) {
      belowTargetGap += (targetPct / 100 * r.revenue - m).toInt();
    }
  }
  final shared = [
    for (final r in rows)
      MarginLedgerRow.fromJson({
        ...r.toJson(),
        if (marginKnown > 0 && r.margin != null)
          'margin_share_pct': (r.margin! / marginKnown * 1000).round() / 10,
      }),
  ];
  shared.sort((a, b) {
    final x = a.margin;
    final y = b.margin;
    if (x != null && y != null) return y.compareTo(x);
    if (x != null) return -1;
    if (y != null) return 1;
    return b.revenue.compareTo(a.revenue);
  });
  return (
    rows: shared,
    totals: LedgerTotals(
      revenue: revenue,
      costKnown: costKnown,
      marginKnown: marginKnown,
      marginPct: revenueKnown > 0 ? marginKnown / revenueKnown * 100 : null,
      revenueCostUnknown: revenueCostUnknown,
      prevRevenue: prevRevenue,
      prevMarginKnown: prevMarginKnown,
      belowTargetGap: belowTargetGap,
    ),
    openSignals: openSignals,
    rowsCostUnknown: rows
        .where((r) => r.quantitySold > 0 && r.cost == null)
        .length,
  );
}

/// `GET /insights/branches/{id}/margin-watch`: the totals, the three best
/// and three worst known margins, the tallies.
MarginWatch marginWatch({
  required String branchId,
  required List<MockRow> orders,
  required List<MockRow> prevOrders,
  DateTime? from,
  DateTime? to,
}) {
  final l = marginLedger(
    orders: orders,
    prevOrders: prevOrders,
    windowed: from != null,
  );
  final known = [
    for (final r in l.rows)
      if (r.margin != null) r,
  ];
  return MarginWatch(
    branchId: branchId,
    from: from,
    to: to,
    targetPct: defaultTargetPct,
    totals: l.totals,
    top: known.take(3).toList(),
    bottom: known.reversed.take(3).toList(),
    openSignals: l.openSignals,
    rowsCostUnknown: l.rowsCostUnknown,
  );
}

/// The previous equal-length window (`build_ledger`): [from − (to − from), from].
(DateTime, DateTime)? previousWindow(DateTime? from, DateTime? to, DateTime now) {
  if (from == null) return null;
  final end = to ?? now;
  if (!end.isAfter(from)) return null;
  return (from.subtract(end.difference(from)), from);
}
