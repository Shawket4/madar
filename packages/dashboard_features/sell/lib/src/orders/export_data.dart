/// The Orders export's rules, as pure functions (the web's
/// `features/orders/export/{presets,build-filename,build-meta,build-sheets,
/// columns}.ts`, SELL-ORD-072 … SELL-ORD-085, SELL-ORD-089).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show OrderExport, OrderItemFull, PaymentLeg;
import 'package:dashboard_core/dashboard_core.dart';

import 'order_lines.dart';

/// One sheet family of the workbook.
enum ExportGrain { order, lineItem, payment, deduction }

extension ExportGrainWire on ExportGrain {
  String get wire => switch (this) {
    ExportGrain.order => 'order',
    ExportGrain.lineItem => 'line_item',
    ExportGrain.payment => 'payment',
    ExportGrain.deduction => 'deduction',
  };
}

/// A preset card: its sheets and the filters it forces.
class ExportPreset {
  const ExportPreset({
    required this.id,
    required this.key,
    required this.icon,
    required this.grains,
    this.status,
    this.payment,
  });

  final String id;

  /// `ordersExport.presets.<key>.{label,desc}`.
  final String key;
  final String icon;
  final List<ExportGrain> grains;
  final String? status;
  final String? payment;
}

const List<ExportPreset> exportPresets = [
  ExportPreset(
    id: 'accountant_daily',
    key: 'accountantDaily',
    icon: 'receipt',
    grains: [ExportGrain.order],
    status: 'completed',
  ),
  ExportPreset(
    id: 'talabat_reconcile',
    key: 'talabatReconcile',
    icon: 'bike',
    grains: [ExportGrain.order],
    payment: 'talabat_online,talabat_cash',
  ),
  ExportPreset(
    id: 'till_handoff',
    key: 'tillHandoff',
    icon: 'clipboard-check',
    grains: [ExportGrain.order, ExportGrain.payment],
  ),
  ExportPreset(
    id: 'ingredient_consumption',
    key: 'ingredientConsumption',
    icon: 'leaf',
    grains: [ExportGrain.deduction],
    status: 'completed',
  ),
  ExportPreset(
    id: 'custom',
    key: 'custom',
    icon: 'sliders-horizontal',
    grains: [ExportGrain.order],
  ),
];

/// The page's filters as the export reads them.
class OrdersExportFilters {
  const OrdersExportFilters({
    this.branchId,
    this.from,
    this.to,
    this.status,
    this.payment,
    this.teller,
    this.waiter,
    this.till,
  });

  final String? branchId;
  final String? from;
  final String? to;
  final String? status;
  final String? payment;
  final String? teller;
  final String? waiter;
  final String? till;

  /// The page's filters with [p]'s overrides on top.
  OrdersExportFilters merged(ExportPreset p) => OrdersExportFilters(
    branchId: branchId,
    from: from,
    to: to,
    status: p.status ?? status,
    payment: p.payment ?? payment,
    teller: teller,
    waiter: waiter,
    till: till,
  );
}

String _slugify(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// The branch's slug for the file name; "branch" without a name.
String branchSlug(String branchName) =>
    branchName.isEmpty ? 'branch' : _slugify(branchName);

/// `buildFilename`: `<preset>-<branch>-<from>_to_<to>` (the instants' first
/// ten characters) or today's ISO date without a range.
String exportFilename({
  required String presetId,
  required String branchSlug,
  required String? from,
  required String? to,
  required DateTime now,
}) {
  final range = from != null && to != null
      ? '${from.substring(0, 10)}_to_${to.substring(0, 10)}'
      : isoString(now).substring(0, 10);
  return '${_slugify(presetId)}-$branchSlug-$range';
}

/// `buildMeta`: "Branch: Zamalek · 08 Sept 2026 → 08 Oct 2026 · Card ·
/// Completed" (payment and status only when set; a key the tables lack
/// reads raw, SELL-ORD-089).
String exportMeta({
  required Translator t,
  required DashFormat fmt,
  required String branchName,
  required OrdersExportFilters f,
}) {
  final parts = <String>['${t('orders.branch')}: $branchName'];
  if (f.from != null && f.to != null) {
    parts.add('${fmt.fmtDate(f.from)} → ${fmt.fmtDate(f.to)}');
  } else {
    parts.add(t('orders.allTime'));
  }
  if (f.payment != null) parts.add(_or(t, 'payments.${f.payment}', f.payment!));
  if (f.status != null) parts.add(_or(t, 'orderStatus.${f.status}', f.status!));
  return parts.join(' · ');
}

String _or(Translator t, String key, String raw) =>
    t.exists(key) ? t(key) : raw;

/// `paymentText`: a split sale lists each leg with its amount.
String paymentText(
  Translator t,
  DashFormat fmt,
  String method,
  List<PaymentLeg> legs,
) => legs.length > 1
    ? legs
          .map(
            (l) =>
                '${_or(t, 'payments.${l.method}', l.method)} ${fmt.fmtMoney(l.amount)}',
          )
          .join(' + ')
    : _or(t, 'payments.$method', method);

String _ref(OrderExport o) =>
    orderPlainRef(orderRef: o.orderRef, orderNumber: o.orderNumber);

class LineItemRow {
  const LineItemRow({
    required this.order,
    required this.line,
    required this.itemName,
    required this.addons,
    required this.optionals,
  });

  final OrderExport order;
  final OrderItemFull line;
  final String itemName;
  final String addons;
  final String optionals;
}

class PaymentRow {
  const PaymentRow({
    required this.ref,
    required this.createdAt,
    required this.orderTotal,
    required this.method,
    required this.amount,
    required this.reference,
  });

  final String ref;
  final DateTime createdAt;
  final int orderTotal;
  final String method;
  final int amount;
  final String? reference;
}

class DeductionRow {
  const DeductionRow({
    required this.ref,
    required this.createdAt,
    required this.itemName,
    required this.d,
  });

  final String ref;
  final DateTime createdAt;
  final String itemName;
  final Deduction d;
}

class DeductionTotal {
  DeductionTotal(this.ingredientName, this.unit, this.totalQuantity);

  final String ingredientName;
  final String unit;
  double totalQuantity;
  int occurrences = 1;
}

/// `buildSheets`: the chosen sheets, in the workbook's order, each with a
/// totals row.
List<ExcelSheet<Object?>> buildExportSheets({
  required List<OrderExport> orders,
  required Set<ExportGrain> grains,
  required Translator t,
  required DashFormat fmt,
  required String lang,
}) {
  final sheets = <ExcelSheet<Object?>>[];
  String name(OrderItemFull it) =>
      translatedName(it.itemName, it.nameTranslations, lang);
  ExcelSheet<T> sheet<T>(String key, List<ExcelColumn<T>> cols, List<T> rows) =>
      ExcelSheet<T>(
        name: t('ordersExport.sheets.$key'),
        title: t('ordersExport.sheets.$key'),
        columns: cols,
        rows: rows,
        totals: true,
      );
  final dash = '—';

  if (grains.contains(ExportGrain.order)) {
    sheets.add(
      sheet<OrderExport>('orders', [
        ExcelColumn(
          header: t('orders.orderRef'),
          accessor: _ref,
          type: ExcelColumnType.text,
          width: 16,
        ),
        ExcelColumn(
          header: t('orders.date'),
          accessor: (o) => o.createdAt,
          type: ExcelColumnType.dateTime,
          width: 20,
        ),
        ExcelColumn(
          header: t('tills.teller'),
          // Who sold: the person picked at checkout, else the signed-in one.
          accessor: (o) => o.seller.teller,
          type: ExcelColumnType.text,
          width: 18,
        ),
        ExcelColumn(
          header: t('tills.waiter'),
          accessor: (o) => (o.waiterName ?? '').isEmpty ? dash : o.waiterName,
          type: ExcelColumnType.text,
          width: 18,
        ),
        ExcelColumn(
          header: t('orders.customer'),
          accessor: (o) =>
              (o.customerName ?? '').isEmpty ? dash : o.customerName,
          type: ExcelColumnType.text,
          width: 18,
        ),
        ExcelColumn(
          header: t('orders.paymentMethod'),
          accessor: (o) => paymentText(t, fmt, o.paymentMethod, o.paymentLegs),
          type: ExcelColumnType.text,
          width: 18,
        ),
        ExcelColumn(
          header: t('orders.exportStaffComp'),
          accessor: (o) => orderStaffComp(o.items),
          type: ExcelColumnType.money,
          width: 20,
          total: true,
        ),
        ExcelColumn(
          header: t('common.subtotal'),
          accessor: (o) => o.subtotal,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.discount'),
          accessor: (o) => o.discountAmount,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.tax'),
          accessor: (o) => o.taxAmount,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.tip'),
          accessor: (o) => o.tipAmount ?? 0,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.deliveryFee'),
          accessor: (o) => o.deliveryFee,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('common.total'),
          accessor: (o) => o.totalAmount,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.type'),
          accessor: (o) => o.orderType == 'delivery'
              ? t('orders.delivery')
              : t('orders.dineIn'),
          type: ExcelColumnType.text,
          width: 14,
        ),
        ExcelColumn(
          header: t('orders.location'),
          accessor: (o) => o.deliveryLat != null && o.deliveryLng != null
              ? 'https://www.google.com/maps/search/?api=1&query=${o.deliveryLat},${o.deliveryLng}'
              : dash,
          type: ExcelColumnType.text,
          width: 34,
        ),
        ExcelColumn(
          header: t('common.status'),
          accessor: (o) => _or(t, 'orderStatus.${o.status}', o.status),
          type: ExcelColumnType.text,
          width: 15,
        ),
        ExcelColumn(
          header: t('orders.voidReason'),
          accessor: (o) => o.voidReason == null
              ? dash
              : _or(t, 'orders.voidReasons.${o.voidReason}', o.voidReason!),
          type: ExcelColumnType.text,
          width: 20,
        ),
      ], orders),
    );
  }

  if (grains.contains(ExportGrain.lineItem)) {
    final rows = [
      for (final o in orders)
        for (final it in o.items)
          LineItemRow(
            order: o,
            line: it,
            itemName: name(it),
            addons: it.addons
                .map(
                  (a) =>
                      '+ ${translatedName(a.addonName, a.nameTranslations, lang)}${a.quantity > 1 ? ' ×${a.quantity}' : ''}',
                )
                .join(', '),
            optionals: it.optionals
                .map(
                  (x) => translatedName(x.fieldName, x.nameTranslations, lang),
                )
                .join(', '),
          ),
    ];
    sheets.add(
      sheet<LineItemRow>('lineItems', [
        ExcelColumn(
          header: t('orders.orderRef'),
          accessor: (r) => _ref(r.order),
          type: ExcelColumnType.text,
          width: 16,
        ),
        ExcelColumn(
          header: t('orders.date'),
          accessor: (r) => r.order.createdAt,
          type: ExcelColumnType.dateTime,
          width: 20,
        ),
        ExcelColumn(
          header: t('orders.paymentMethod'),
          accessor: (r) =>
              paymentText(t, fmt, r.order.paymentMethod, r.order.paymentLegs),
          type: ExcelColumnType.text,
          width: 18,
        ),
        ExcelColumn(
          header: t('tills.waiter'),
          accessor: (r) =>
              (r.order.waiterName ?? '').isEmpty ? dash : r.order.waiterName,
          type: ExcelColumnType.text,
          width: 18,
        ),
        ExcelColumn(
          header: t('menu.item'),
          accessor: (r) => r.itemName,
          type: ExcelColumnType.text,
          width: 22,
        ),
        ExcelColumn(
          header: t('menu.size'),
          accessor: (r) =>
              (r.line.sizeLabel ?? '').isEmpty ? dash : r.line.sizeLabel,
          type: ExcelColumnType.text,
          width: 12,
        ),
        ExcelColumn(
          header: t('common.qty'),
          accessor: (r) => r.line.quantity,
          type: ExcelColumnType.number,
          width: 10,
          total: true,
        ),
        ExcelColumn(
          header: t('common.price'),
          accessor: (r) => r.line.unitPrice,
          type: ExcelColumnType.money,
          width: 15,
        ),
        ExcelColumn(
          header: t('common.total'),
          accessor: (r) => r.line.lineTotal,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.exportStaffComp'),
          accessor: (r) => (r.line.staffCompMinor ?? 0) < 0
              ? 0
              : (r.line.staffCompMinor ?? 0),
          type: ExcelColumnType.money,
          width: 20,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.exportStaffCharged'),
          accessor: (r) => staffDrinkLine(r.line)?.charged,
          type: ExcelColumnType.money,
          width: 24,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.cogs'),
          accessor: (r) => r.line.lineCost,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('menu.addons'),
          accessor: (r) => r.addons.isEmpty ? dash : r.addons,
          type: ExcelColumnType.text,
          width: 25,
        ),
        ExcelColumn(
          header: t('menu.optionals'),
          accessor: (r) => r.optionals.isEmpty ? dash : r.optionals,
          type: ExcelColumnType.text,
          width: 25,
        ),
        ExcelColumn(
          header: t('common.notes'),
          accessor: (r) => (r.line.notes ?? '').isEmpty ? dash : r.line.notes,
          type: ExcelColumnType.text,
          width: 20,
        ),
      ], rows),
    );
  }

  if (grains.contains(ExportGrain.payment)) {
    final rows = [
      for (final o in orders)
        for (final p in o.payments)
          PaymentRow(
            ref: _ref(o),
            createdAt: o.createdAt,
            orderTotal: o.totalAmount,
            method: p.method,
            amount: p.amount,
            reference: p.reference,
          ),
    ];
    sheets.add(
      sheet<PaymentRow>('payments', [
        ExcelColumn(
          header: t('orders.orderRef'),
          accessor: (r) => r.ref,
          type: ExcelColumnType.text,
          width: 16,
        ),
        ExcelColumn(
          header: t('orders.date'),
          accessor: (r) => r.createdAt,
          type: ExcelColumnType.dateTime,
          width: 20,
        ),
        ExcelColumn(
          header: t('common.total'),
          accessor: (r) => r.orderTotal,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.paymentMethod'),
          accessor: (r) => _or(t, 'payments.${r.method}', r.method),
          type: ExcelColumnType.text,
          width: 18,
        ),
        ExcelColumn(
          header: t('common.amount'),
          accessor: (r) => r.amount,
          type: ExcelColumnType.money,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('orders.reference'),
          accessor: (r) => (r.reference ?? '').isEmpty ? dash : r.reference,
          type: ExcelColumnType.text,
          width: 18,
        ),
      ], rows),
    );
  }

  if (grains.contains(ExportGrain.deduction)) {
    final raw = [
      for (final o in orders)
        for (final it in o.items)
          for (final d in deductionsOf(it))
            DeductionRow(
              ref: _ref(o),
              createdAt: o.createdAt,
              itemName: name(it),
              d: d,
            ),
    ];
    String unit(String u) => _or(t, 'inventoryUnits.$u', u);
    sheets.add(
      sheet<DeductionRow>('deductionsRaw', [
        ExcelColumn(
          header: t('orders.orderRef'),
          accessor: (r) => r.ref,
          type: ExcelColumnType.text,
          width: 16,
        ),
        ExcelColumn(
          header: t('orders.date'),
          accessor: (r) => r.createdAt,
          type: ExcelColumnType.dateTime,
          width: 20,
        ),
        ExcelColumn(
          header: t('menu.item'),
          accessor: (r) => r.itemName,
          type: ExcelColumnType.text,
          width: 22,
        ),
        ExcelColumn(
          header: t('inventory.ingredient'),
          accessor: (r) => r.d.ingredientName,
          type: ExcelColumnType.text,
          width: 22,
        ),
        ExcelColumn(
          header: t('common.qty'),
          accessor: (r) => r.d.quantity,
          type: ExcelColumnType.number,
          width: 12,
          total: true,
        ),
        ExcelColumn(
          header: t('inventory.unit'),
          accessor: (r) => unit(r.d.unit),
          type: ExcelColumnType.text,
          width: 10,
        ),
        ExcelColumn(
          header: t('common.source'),
          accessor: (r) => r.d.source,
          type: ExcelColumnType.text,
          width: 15,
        ),
        ExcelColumn(
          header: t('common.category'),
          accessor: (r) => r.d.category,
          type: ExcelColumnType.text,
          width: 15,
        ),
      ], raw),
    );
    final agg = <String, DeductionTotal>{};
    for (final r in raw) {
      final key = '${r.d.ingredientName}|${r.d.unit}';
      final prev = agg[key];
      if (prev == null) {
        agg[key] = DeductionTotal(r.d.ingredientName, r.d.unit, r.d.quantity);
      } else {
        prev
          ..totalQuantity += r.d.quantity
          ..occurrences += 1;
      }
    }
    final totals = agg.values.toList()
      ..sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));
    sheets.add(
      sheet<DeductionTotal>('deductionsAgg', [
        ExcelColumn(
          header: t('inventory.ingredient'),
          accessor: (r) => r.ingredientName,
          type: ExcelColumnType.text,
          width: 25,
        ),
        ExcelColumn(
          header: t('orders.totalUsage'),
          accessor: (r) => r.totalQuantity,
          type: ExcelColumnType.number,
          width: 15,
          total: true,
        ),
        ExcelColumn(
          header: t('inventory.unit'),
          accessor: (r) => unit(r.unit),
          type: ExcelColumnType.text,
          width: 12,
        ),
        ExcelColumn(
          header: t('orders.occurrences'),
          accessor: (r) => r.occurrences,
          type: ExcelColumnType.integer,
          width: 12,
          total: true,
        ),
      ], totals),
    );
  }
  return sheets;
}
