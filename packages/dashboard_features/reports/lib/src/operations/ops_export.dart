/// The Operations header export (`features/analytics/analytics-export-button.tsx`,
/// REP-OPS-004/005, 056…061, REP-ALL-010…014, 025…027): Excel or CSV of the
/// rows the Items, Tellers, Waiters and Branches tabs show.
///
/// The rows are re-read for the export (limit 1000, `X-Madar-Export: 1`, so
/// the backend counts it against the person's export budget and may answer
/// 429). Only the Excel path spins the button; its "Gathering data…" toast
/// appears once the re-read is in.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AddonSalesRow,
        BranchComparison,
        CombinedItemSalesRow,
        DashboardApi,
        TellerStats,
        WaiterStats;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'ops_support.dart';

/// The tabs that export (`EXPORTABLE`, Channel being Financial's).
const Set<String> opsExportTabs = {'items', 'tellers', 'waiters', 'branches'};

/// How many rows an export asks for (`EXPORT_LIMIT`, the reports' clamp).
const int opsExportLimit = 1000;

/// The sheets of [tab]'s export, re-read through [api] (the export client).
Future<List<ExcelSheet<Object?>>> opsExportSheets({
  required String tab,
  required DashboardApi api,
  required Scope scope,
  required Translator t,
  required String lang,
}) async {
  final from = DateTime.parse(scope.from);
  final to = DateTime.parse(scope.to);
  final branchId = scope.scopeBranchId;
  switch (tab) {
    case 'items':
      final (items, addons) = await (
        api.reports.branchCombinedItemSales(
          branchId: branchId,
          from: from,
          to: to,
          limit: opsExportLimit,
        ),
        api.reports.branchAddonSales(
          branchId: branchId,
          from: from,
          to: to,
          limit: opsExportLimit,
        ),
      ).wait;
      return [
        ExcelSheet<CombinedItemSalesRow>(
          name: t('analytics.tabs.items'),
          title: t('analytics.tabs.items'),
          totals: true,
          rows: items,
          columns: [
            ExcelColumn(
              header: t('common.name'),
              accessor: (r) =>
                  translatedName(r.itemName, r.itemNameTranslations, lang),
              type: ExcelColumnType.text,
              width: 32,
            ),
            ExcelColumn(
              header: t('analytics.totalSold'),
              accessor: (r) => r.totalQty,
              type: ExcelColumnType.number,
              width: 14,
              total: true,
            ),
          ],
        ),
        ExcelSheet<AddonSalesRow>(
          name: t('analytics.addonSales'),
          title: t('analytics.addonSales'),
          totals: true,
          rows: addons,
          columns: [
            ExcelColumn(
              header: t('common.name'),
              accessor: (a) =>
                  translatedName(a.addonName, a.addonNameTranslations, lang),
              type: ExcelColumnType.text,
              width: 32,
            ),
            ExcelColumn(
              header: t('analytics.sold'),
              accessor: (a) => a.quantitySold,
              type: ExcelColumnType.number,
              width: 14,
              total: true,
            ),
            ExcelColumn(
              header: t('dashboard.revenue'),
              accessor: (a) => a.revenue,
              type: ExcelColumnType.money,
              width: 16,
              total: true,
            ),
          ],
        ),
      ];
    case 'tellers':
      final rows = await api.reports.branchTellerStats(
        branchId: branchId,
        from: from,
        to: to,
        limit: opsExportLimit,
      );
      final title = t('analytics.tellerDetails');
      return [
        ExcelSheet<TellerStats>(
          name: title,
          title: title,
          totals: true,
          rows: rows,
          columns: [
            ExcelColumn(
              header: t('users.role'),
              accessor: (r) => r.tellerName,
              type: ExcelColumnType.text,
              width: 26,
            ),
            ExcelColumn(
              header: t('dashboard.orders'),
              accessor: (r) => r.orders,
              type: ExcelColumnType.integer,
              width: 12,
              total: true,
            ),
            ExcelColumn(
              header: t('dashboard.revenue'),
              accessor: (r) => r.revenue,
              type: ExcelColumnType.money,
              width: 16,
              total: true,
            ),
            ExcelColumn(
              header: t('analytics.aov'),
              accessor: (r) => r.avgOrderValue,
              type: ExcelColumnType.money,
              width: 14,
            ),
            ExcelColumn(
              header: t('orders.voided'),
              accessor: (r) => r.voided,
              type: ExcelColumnType.integer,
              width: 12,
              total: true,
            ),
            ExcelColumn(
              header: t('nav.tills'),
              accessor: (r) => r.shifts,
              type: ExcelColumnType.integer,
              width: 12,
              total: true,
            ),
          ],
        ),
      ];
    case 'waiters':
      final report = await api.reports.branchWaiterStats(
        branchId: branchId,
        from: from,
        to: to,
        limit: opsExportLimit,
      );
      final title = t('analytics.waiterDetails');
      return [
        ExcelSheet<WaiterStats>(
          name: title,
          title: title,
          // The screen's caption, with the raw figures.
          subtitle: t(
            'analytics.waiterCoverage',
            args: {
              'attributed': report.attributedOrders,
              'total': report.totalOrders,
            },
          ),
          totals: true,
          rows: report.waiters,
          columns: [
            ExcelColumn(
              header: t('tills.waiter'),
              accessor: (r) => r.waiterName,
              type: ExcelColumnType.text,
              width: 26,
            ),
            ExcelColumn(
              header: t('dashboard.orders'),
              accessor: (r) => r.orders,
              type: ExcelColumnType.integer,
              width: 12,
              total: true,
            ),
            ExcelColumn(
              header: t('dashboard.revenue'),
              accessor: (r) => r.revenue,
              type: ExcelColumnType.money,
              width: 16,
              total: true,
            ),
            ExcelColumn(
              header: t('analytics.aov'),
              accessor: (r) => r.avgOrderValue,
              type: ExcelColumnType.money,
              width: 14,
            ),
            ExcelColumn(
              header: t('analytics.itemsSold'),
              accessor: (r) => r.lineItems,
              type: ExcelColumnType.integer,
              width: 14,
              total: true,
            ),
            ExcelColumn(
              header: t('analytics.itemsPerOrder'),
              accessor: (r) => r.avgItemsPerOrder,
              type: ExcelColumnType.number,
              width: 14,
            ),
            ExcelColumn(
              header: t('orders.voided'),
              accessor: (r) => r.voided,
              type: ExcelColumnType.integer,
              width: 12,
              total: true,
            ),
          ],
        ),
      ];
    default:
      final report = await api.reports.orgBranchComparison(
        orgId: scope.orgId ?? '',
        from: from,
        to: to,
        limit: opsExportLimit,
      );
      final title = t('analytics.branchDetails');
      return [
        ExcelSheet<BranchComparison>(
          name: title,
          title: title,
          totals: true,
          rows: report.branches,
          columns: [
            ExcelColumn(
              header: t('nav.branches'),
              accessor: (b) => b.branchName,
              type: ExcelColumnType.text,
              width: 26,
            ),
            ExcelColumn(
              header: t('dashboard.orders'),
              accessor: (b) => b.totalOrders,
              type: ExcelColumnType.integer,
              width: 12,
              total: true,
            ),
            ExcelColumn(
              header: t('dashboard.revenue'),
              accessor: (b) => b.totalRevenue,
              type: ExcelColumnType.money,
              width: 16,
              total: true,
            ),
            ExcelColumn(
              header: t('analytics.aov'),
              accessor: (b) => b.avgOrderValue,
              type: ExcelColumnType.money,
              width: 14,
            ),
            // A 0-100 figure; Excel's percent format wants the ratio.
            ExcelColumn(
              header: t('analytics.voidRate'),
              accessor: (b) => b.voidRatePct / 100,
              type: ExcelColumnType.percent,
              width: 12,
            ),
          ],
        ),
      ];
  }
}

/// The header's Export Excel / Export CSV menu for [tab]. Disabled only
/// when the scope is missing (no org on Branches).
class OpsExportButton extends ConsumerStatefulWidget {
  const OpsExportButton({required this.tab, super.key});

  final String tab;

  @override
  ConsumerState<OpsExportButton> createState() => _OpsExportButtonState();
}

class _OpsExportButtonState extends ConsumerState<OpsExportButton> {
  bool _exporting = false;

  String get _filename => 'Madar-Analytics-${widget.tab}';

  Future<List<ExcelSheet<Object?>>> _sheets() => opsExportSheets(
    tab: widget.tab,
    api: ref.read(exportApiProvider),
    scope: ref.read(currentScopeProvider),
    t: ref.read(tProvider),
    lang: ref.read(localeProvider),
  );

  String? _logo() {
    final brand = ref.read(publicBrandProvider).value;
    final logo = brand?.logoUrl?.trim();
    return (brand?.customBranding ?? false) && logo != null && logo.isNotEmpty
        ? logo
        : null;
  }

  Future<void> _excel() async {
    final t = ref.read(tProvider);
    final exporter = ref.read(exporterProvider);
    final scope = ref.read(currentScopeProvider);
    setState(() => _exporting = true);
    try {
      final sheets = await _sheets();
      if (!mounted) return;
      if (sheets.every((s) => s.rows.isEmpty)) {
        DashToast.error(context, const ExportNothing().message(t));
        return;
      }
      final toast = DashToast.loading(
        context,
        t('excel.generating', defaultValue: 'Gathering data…'),
      );
      final outcome = await exporter.exportToExcel(
        ExcelConfig(
          filename: _filename,
          logoUrl: _logo(),
          meta: t(scope.preset.labelKey, defaultValue: scope.preset.fallback),
          sheets: sheets,
        ),
      );
      toast.update(
        outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
        outcome.message(t),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, opsErrorText(e, t));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _csv() async {
    final t = ref.read(tProvider);
    final exporter = ref.read(exporterProvider);
    try {
      final sheets = await _sheets();
      final outcome = await exporter.exportToCsv(
        ExcelConfig(filename: _filename, sheets: sheets),
      );
      if (!mounted) return;
      if (outcome is ExportDone) {
        DashToast.success(context, outcome.message(t));
      } else {
        DashToast.error(context, outcome.message(t));
      }
    } on Object catch (e) {
      if (mounted) DashToast.error(context, opsErrorText(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(currentScopeProvider);
    final missing = widget.tab == 'branches' ? scope.orgId == null : false;
    return DashExportButton(
      key: const ValueKey('ops-export'),
      onExport: _excel,
      onExportCsv: _csv,
      loading: _exporting,
      enabled: !missing,
    );
  }
}
