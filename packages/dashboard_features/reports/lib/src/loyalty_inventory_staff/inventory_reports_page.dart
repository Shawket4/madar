/// `/reports/inventory` Inventory reports (REP-INV rows): tabs Consumption,
/// Shrinkage, Waste, PO lead time, Low stock
/// (`features/inventory/inventory-reports-page.tsx`, `reports-page.tsx`,
/// `low-stock-tab.tsx`).
///
/// The page's own `<Restricted>` answers without `inventory.read`
/// (REP-INV-001). Only the open tab's report is asked for, from the branch
/// or the org endpoint per the "This branch" / "Whole organization" toggle
/// (REP-INV-005/007); Low stock follows the scope bar instead (REP-INV-015).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'inventory_low_stock.dart';
import 'lis_providers.dart';
import 'lis_support.dart';

/// The route's page (`DashRoute.builder`).
Widget inventoryReportsPageBuilder(BuildContext context, GoRouterState state) =>
    const InventoryReportsPage();

/// The tabs (REP-INV-003/004), page state; default Consumption. PO lead time
/// needs `purchasing.orders.read` as well as the page's `inventory.read`.
const List<DashRouteTab> inventoryReportTabs = [
  DashRouteTab(id: 'consumption', labelKey: 'inventory.reports.consumption'),
  DashRouteTab(id: 'shrinkage', labelKey: 'inventory.reports.shrinkage'),
  DashRouteTab(id: 'waste', labelKey: 'inventory.reports.wasteReport'),
  DashRouteTab(
    id: 'poLeadTime',
    labelKey: 'inventory.reports.poLeadTime',
    caps: [Cap.purchasingOrdersRead],
  ),
  DashRouteTab(id: 'lowStock', labelKey: 'reports.operations.tabs.lowStock'),
];

/// The tabs with the scope toggle (every one but Low stock).
const Set<String> _scopedTabs = {
  'consumption',
  'shrinkage',
  'waste',
  'poLeadTime',
};

/// The lead-time KPI's width on wide screens (`lg:max-w-md`).
const double _leadStripMaxWidth = 448;

/// A shrinkage reason: "unexplained" reads "Other"; an unknown code as is.
String shrinkageReason(Translator t, String reason) {
  if (reason == 'unexplained') return t('inventory.varianceReasons.other');
  final key = 'inventory.varianceReasons.$reason';
  return t.exists(key) ? t(key) : reason;
}

/// A waste reason; an unknown code as is.
String wasteReason(Translator t, String reason) {
  final key = 'inventory.waste.reasons.$reason';
  return t.exists(key) ? t(key) : reason;
}

class InventoryReportsPage extends ConsumerStatefulWidget {
  const InventoryReportsPage({super.key});

  @override
  ConsumerState<InventoryReportsPage> createState() =>
      _InventoryReportsPageState();
}

class _InventoryReportsPageState extends ConsumerState<InventoryReportsPage>
    with DashRememberedState {
  /// Set on open (or remembered); it does not follow the scope bar
  /// (REP-INV-005).
  late InventoryScope _scope;
  String _tab = 'consumption';
  bool _exporting = false;

  // The tab and the branch/org toggle come back with the page.
  @override
  String get memoryKey => 'reports.inventory';

  @override
  Map<String, Object?> get rememberedValues => {
    'tab': _tab,
    'scope': _scope.name,
  };

  @override
  void restoreRemembered(DashMemo m) {
    _tab = m.getOr('tab', 'consumption');
    _scope =
        m.enumOrNull('scope', InventoryScope.values) ??
        initialInventoryScope(ref.read(currentScopeProvider));
  }

  /// A read the web keeps enabled only on its open tab with something to
  /// ask: neither loading nor failed otherwise, and never requested.
  AsyncValue<T?> _read<T>(
    bool open,
    InvKey? k,
    ProviderListenable<AsyncValue<T>> Function(InvKey k) provider,
  ) => open && k != null ? ref.watch(provider(k)) : AsyncData<T?>(null);

  /// Intent: warms what opening [tab] under [inv] reads, as [build] asks.
  void _warmTab(String tab, InventoryScope inv) {
    final s = ref.read(currentScopeProvider);
    if (tab == 'lowStock') {
      final k = s.lowStockKey;
      if (k != null) ref.warm(invLowStockProvider(k));
      return;
    }
    final k = s.invKey(inv);
    if (k == null) return;
    switch (tab) {
      case 'shrinkage':
        ref.warm(invShrinkageProvider(k));
      case 'waste':
        ref.warm(invWasteProvider(k));
      case 'poLeadTime':
        if (ref.read(authzProvider).can(Cap.purchasingOrdersRead)) {
          ref.warm(invLeadTimeProvider(k));
        }
      default:
        ref.warm(invConsumptionProvider(k));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final title = t('inventory.reports.title');
    final gate = lisGate(
      ref,
      title: title,
      canSee: (a) => a.can(Cap.inventoryRead),
    );
    if (gate != null) return gate;
    final scope = ref.watch(currentScopeProvider);
    final canLead = ref.watch(
      authzProvider.select((a) => a.can(Cap.purchasingOrdersRead)),
    );
    if (scope.orgId == null) {
      return DashPageScaffold(
        title: title,
        body: DashEmptyState(icon: 'boxes', title: t('inventory.pickOrg')),
      );
    }
    final tabs = [
      for (final tab in inventoryReportTabs)
        if (tab.id != 'poLeadTime' || canLead) tab,
    ];
    final tab = tabs.any((x) => x.id == _tab) ? _tab : tabs.first.id;
    final k = scope.invKey(_scope);
    final branchGate = _scope == InventoryScope.branch && scope.isAllBranches;

    final consumption = _read(
      tab == 'consumption',
      k,
      invConsumptionProvider.call,
    );
    final shrinkage = _read(tab == 'shrinkage', k, invShrinkageProvider.call);
    final waste = _read(tab == 'waste', k, invWasteProvider.call);
    final lead = _read(
      tab == 'poLeadTime' && canLead,
      k,
      invLeadTimeProvider.call,
    );
    final count = switch (tab) {
      'consumption' => consumption.value?.length ?? 0,
      'shrinkage' => shrinkage.value?.length ?? 0,
      'waste' => waste.value?.length ?? 0,
      _ => lead.value?.bySupplier.length ?? 0,
    };
    final noData = t('inventory.reports.noDataPeriod');
    void retry(void Function(InvKey k) again) {
      if (k != null) again(k);
    }

    final Widget body;
    if (branchGate && tab != 'lowStock') {
      body = DashEmptyState(icon: 'store', title: t('inventory.pickBranch'));
    } else {
      body = switch (tab) {
        'shrinkage' => _ShrinkageTable(
          q: shrinkage,
          noData: noData,
          onRetry: () => retry((k) => ref.invalidate(invShrinkageProvider(k))),
        ),
        'waste' => _WasteTable(
          q: waste,
          noData: noData,
          onRetry: () => retry((k) => ref.invalidate(invWasteProvider(k))),
        ),
        'poLeadTime' => _LeadTimeTab(
          q: lead,
          noData: noData,
          onRetry: () => retry((k) => ref.invalidate(invLeadTimeProvider(k))),
        ),
        'lowStock' => const InventoryLowStockTab(),
        _ => _ConsumptionTable(
          q: consumption,
          noData: noData,
          onRetry: () =>
              retry((k) => ref.invalidate(invConsumptionProvider(k))),
        ),
      };
    }

    ExcelConfig config() {
      final sheet = inventoryExportSheet(
        tab: tab,
        isBranch: _scope == InventoryScope.branch,
        t: t,
        consumption: consumption.value,
        shrinkage: shrinkage.value,
        waste: waste.value,
        lead: lead.value,
      );
      return ExcelConfig(
        filename: 'Madar-${sheet.title}',
        logoUrl: exportLogoUrl(ref.read(publicBrandProvider).value),
        sheets: [sheet],
      );
    }

    return DashPageScaffold(
      title: title,
      subtitleWidget: const ReportPeriodSubtitle(),
      actions: [
        if (tab != 'lowStock')
          DashExportButton(
            key: const ValueKey('inv-export'),
            loading: _exporting,
            enabled: !branchGate && count > 0,
            onExport: () async {
              final c = config();
              setState(() => _exporting = true);
              try {
                await lisExportExcel(context, ref, c);
              } finally {
                if (mounted) setState(() => _exporting = false);
              }
            },
            onExportCsv: () => lisExportCsv(context, ref, config()),
          ),
      ],
      tabs: DashPageTabs<String>(
        value: tab,
        onChanged: (v) => setState(() => _tab = v),
        onIntent: (v) => _warmTab(v, _scope),
        tabs: [
          for (final x in tabs) DashTab(value: x.id, label: t(x.labelKey)),
        ],
      ),
      filters: _scopedTabs.contains(tab)
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: InventoryScopeToggle(
                key: const ValueKey('inv-scope'),
                value: _scope,
                onChanged: (v) => setState(() => _scope = v),
                onIntent: (v) => _warmTab(tab, v),
              ),
            )
          : null,
      body: KeyedSubtree(key: ValueKey('inv-tab-$tab'), child: body),
    );
  }
}

/// REP-INV-008: Ingredient, Quantity, Consumed value.
class _ConsumptionTable extends ConsumerWidget {
  const _ConsumptionTable({
    required this.q,
    required this.noData,
    required this.onRetry,
  });

  final AsyncValue<List<ConsumptionRow>?> q;
  final String noData;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    return InventoryReportTable(
      emptyTitle: noData,
      loading: q.awaitingFirst,
      retrying: q.isLoading,
      error: q.failed ? q.error : null,
      onRetry: onRetry,
      head: [
        ReportHead(t('inventory.reports.ingredient')),
        ReportHead(t('inventory.reports.qty'), numeric: true),
        ReportHead(t('inventory.reports.consumedValue'), numeric: true),
      ],
      rows: [
        for (final r in q.value ?? const <ConsumptionRow>[])
          ReportRow(
            key: r.orgIngredientId,
            cells: [
              r.ingredientName,
              invQty(f, r.consumedQty, r.unit),
              f.fmtMoney(r.consumedValue),
            ],
          ),
      ],
    );
  }
}

/// REP-INV-009: Ingredient, Reason, Quantity, Value.
class _ShrinkageTable extends ConsumerWidget {
  const _ShrinkageTable({
    required this.q,
    required this.noData,
    required this.onRetry,
  });

  final AsyncValue<List<ShrinkageRow>?> q;
  final String noData;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    return InventoryReportTable(
      emptyTitle: noData,
      loading: q.awaitingFirst,
      retrying: q.isLoading,
      error: q.failed ? q.error : null,
      onRetry: onRetry,
      head: [
        ReportHead(t('inventory.reports.ingredient')),
        ReportHead(t('inventory.reports.reason')),
        ReportHead(t('inventory.reports.qty'), numeric: true),
        ReportHead(t('inventory.reports.value'), numeric: true),
      ],
      rows: [
        for (final (i, r) in (q.value ?? const <ShrinkageRow>[]).indexed)
          ReportRow(
            key: '${r.orgIngredientId}-${r.reason}-$i',
            cells: [
              r.ingredientName,
              shrinkageReason(t, r.reason),
              invQty(f, r.shrinkageQty, r.unit),
              f.fmtMoney(r.shrinkageValue),
            ],
          ),
      ],
    );
  }
}

/// REP-INV-010: Ingredient, Reason, Quantity, Waste value.
class _WasteTable extends ConsumerWidget {
  const _WasteTable({
    required this.q,
    required this.noData,
    required this.onRetry,
  });

  final AsyncValue<List<WasteReportRow>?> q;
  final String noData;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    return InventoryReportTable(
      emptyTitle: noData,
      loading: q.awaitingFirst,
      retrying: q.isLoading,
      error: q.failed ? q.error : null,
      onRetry: onRetry,
      head: [
        ReportHead(t('inventory.reports.ingredient')),
        ReportHead(t('inventory.reports.reason')),
        ReportHead(t('inventory.reports.qty'), numeric: true),
        ReportHead(t('inventory.reports.wasteValue'), numeric: true),
      ],
      rows: [
        for (final (i, r) in (q.value ?? const <WasteReportRow>[]).indexed)
          ReportRow(
            key: '${r.orgIngredientId}-${r.reason}-$i',
            cells: [
              r.ingredientName,
              wasteReason(t, r.reason),
              invQty(f, r.wasteQty, r.unit),
              f.fmtMoney(r.wasteValue),
            ],
          ),
      ],
    );
  }
}

/// REP-INV-011: the overall average (1 dp) over a Supplier / Orders
/// received / Avg lead time table.
class _LeadTimeTab extends ConsumerWidget {
  const _LeadTimeTab({
    required this.q,
    required this.noData,
    required this.onRetry,
  });

  final AsyncValue<PoLeadTimeReport?> q;
  final String noData;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    String days(num v) =>
        f.fmtNumber(v, const NumberOptions(maximumFractionDigits: 1));
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wide ? _leadStripMaxWidth : double.infinity,
            ),
            child: DashLedgerStrip(
              items: [
                DashLedgerItem(
                  key: 'overall',
                  label: t('inventory.reports.avgLeadDays'),
                  valueText: days(q.value?.overallAvgDays ?? 0),
                  icon: 'calendar-range',
                  loading: q.awaitingFirst,
                ),
              ],
            ),
          ),
        ),
        InventoryReportTable(
          emptyTitle: noData,
          loading: q.awaitingFirst,
          retrying: q.isLoading,
          error: q.failed ? q.error : null,
          onRetry: onRetry,
          head: [
            ReportHead(t('inventory.reports.supplier')),
            ReportHead(t('inventory.reports.ordersReceived'), numeric: true),
            ReportHead(t('inventory.reports.avgLeadDays'), numeric: true),
          ],
          rows: [
            for (final (i, r)
                in (q.value?.bySupplier ?? const <PoLeadTimeRow>[]).indexed)
              ReportRow(
                key: r.supplierId ?? '${r.supplierName}-$i',
                cells: [
                  r.supplierName,
                  f.fmtNumber(r.ordersReceived),
                  days(r.avgLeadTimeDays),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// `buildInventoryExportSheet` (REP-INV-013/014): the open tab's rows, the
/// sheet titled by the tab, its subtitle the scope's words.
ExcelSheet<List<Object?>> inventoryExportSheet({
  required String tab,
  required bool isBranch,
  required Translator t,
  List<ConsumptionRow>? consumption,
  List<ShrinkageRow>? shrinkage,
  List<WasteReportRow>? waste,
  PoLeadTimeReport? lead,
}) {
  ExcelColumn<List<Object?>> col(
    int i,
    String header,
    ExcelColumnType type,
    double width,
  ) => ExcelColumn(
    header: header,
    accessor: (r) => r[i],
    type: type,
    width: width,
  );
  final item = t('inventory.reports.ingredient');
  final reason = t('inventory.reports.reason');
  final qty = t('inventory.reports.qty');
  final unit = t('inventory.catalog.unit');
  const text = ExcelColumnType.text;
  const number = ExcelColumnType.number;
  const money = ExcelColumnType.money;
  final String title;
  final List<ExcelColumn<List<Object?>>> cols;
  final List<List<Object?>> rows;
  switch (tab) {
    case 'consumption':
      title = t('inventory.reports.consumption');
      cols = [
        col(0, item, text, 28),
        col(1, qty, number, 14),
        col(2, unit, text, 10),
        col(3, t('inventory.reports.consumedValue'), money, 16),
      ];
      rows = [
        for (final r in consumption ?? const <ConsumptionRow>[])
          [r.ingredientName, r.consumedQty, fmtUnit(r.unit), r.consumedValue],
      ];
    case 'shrinkage':
      title = t('inventory.reports.shrinkage');
      cols = [
        col(0, item, text, 28),
        col(1, reason, text, 18),
        col(2, qty, number, 14),
        col(3, unit, text, 10),
        col(4, t('inventory.reports.value'), money, 14),
      ];
      rows = [
        for (final r in shrinkage ?? const <ShrinkageRow>[])
          [
            r.ingredientName,
            shrinkageReason(t, r.reason),
            r.shrinkageQty,
            fmtUnit(r.unit),
            r.shrinkageValue,
          ],
      ];
    case 'waste':
      title = t('inventory.reports.wasteReport');
      cols = [
        col(0, item, text, 28),
        col(1, reason, text, 18),
        col(2, qty, number, 14),
        col(3, unit, text, 10),
        col(4, t('inventory.reports.wasteValue'), money, 14),
      ];
      rows = [
        for (final r in waste ?? const <WasteReportRow>[])
          [
            r.ingredientName,
            wasteReason(t, r.reason),
            r.wasteQty,
            fmtUnit(r.unit),
            r.wasteValue,
          ],
      ];
    default:
      title = t('inventory.reports.poLeadTime');
      cols = [
        col(0, t('inventory.reports.supplier'), text, 28),
        col(1, t('inventory.reports.ordersReceived'), number, 14),
        col(2, t('inventory.reports.avgLeadDays'), number, 18),
      ];
      rows = [
        for (final r in lead?.bySupplier ?? const <PoLeadTimeRow>[])
          [r.supplierName, r.ordersReceived, r.avgLeadTimeDays],
      ];
  }
  return ExcelSheet<List<Object?>>(
    name: title,
    title: title,
    subtitle: isBranch
        ? t('inventory.reports.branch')
        : t('inventory.reports.org'),
    columns: cols,
    rows: rows,
  );
}
