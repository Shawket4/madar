/// `/reports/bundles` Bundles (REP-BUN rows): each combo and each deal as one
/// line — how many sold, in how many orders, what they took, what the same
/// items ring at separately, the saving that gave away, the cost and the
/// margin — with the combo Mix dialog
/// (`features/reports/bundles/bundles-report-page.tsx`, `mix-dialog.tsx`).
library;

import 'package:dashboard_api/dashboard_api.dart' show BundlesRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/report_shared.dart';
import 'bundles_mix_dialog.dart';
import 'bundles_providers.dart';
import 'unit_support.dart';

/// The route's page (`DashRoute.builder`).
Widget bundlesReportPageBuilder(BuildContext context, GoRouterState state) =>
    const BundlesReportPage();

/// Combos or deals (`BundleKind`).
enum BundleKind {
  combo,
  deal;

  /// The `kind` query value.
  String get wire => name;
}

class BundlesReportPage extends ConsumerStatefulWidget {
  const BundlesReportPage({super.key});

  @override
  ConsumerState<BundlesReportPage> createState() => _BundlesReportPageState();
}

class _BundlesReportPageState extends ConsumerState<BundlesReportPage> {
  BundleKind _kind = BundleKind.combo;
  bool _exporting = false;

  bool get _combos => _kind == BundleKind.combo;

  /// `getTranslatedName(row, lang)`.
  String _name(BundlesRow r, String lang) =>
      translatedName(r.name, r.nameTranslations, lang);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final scope = ref.watch(currentScopeProvider);
    final canSee = ref.watch(
      authzProvider.select((a) => a.can(Cap.reportsBundles)),
    );
    final title = t('reports.bundles.title');
    final refused = reportRestricted(ref, title: title, canSee: canSee);
    if (refused != null) return refused;

    final query = (
      from: localDateParam(f, scope.from),
      to: localDateParam(f, scope.to),
      branchId: scope.branchId,
      kind: _kind.wire,
    );
    final q = watchWhen(ref, canSee, bundlesReportProvider(query));
    final logo = exportLogoUrl(ref);
    final rows = q.hasError ? const <BundlesRow>[] : (q.value?.rows ?? const <BundlesRow>[]);
    final totals = q.value?.totals;
    final loading = q.firstLoad;
    final lang = t.lang;

    final soldLabel = _combos
        ? t('reports.bundles.col.sold')
        : t('reports.bundles.col.applied');
    // A row with an unknown cost makes the total cost a floor, not a figure:
    // no margin, as on the rows (REP-BUN-006).
    final marginText =
        totals != null &&
            totals.revenue > 0 &&
            !(q.value?.rows ?? const <BundlesRow>[]).any((r) => r.costMissing)
        ? fmtRateWire(f, (totals.revenue - totals.cost) / totals.revenue)
        : '—';

    return DashPageScaffold(
      title: title,
      subtitle: t('reports.bundles.subtitle'),
      actions: [
        DashExportButton(
          loading: _exporting,
          enabled: rows.isNotEmpty,
          onExport: () => _export(query, rows, scope, logo),
        ),
      ],
      filters: Align(
        alignment: AlignmentDirectional.centerStart,
        child: DashSegmentedControl<BundleKind>(
          value: _kind,
          onChanged: (k) => setState(() => _kind = k),
          options: [
            DashOption(
              value: BundleKind.combo,
              label: t('reports.bundles.combos'),
            ),
            DashOption(value: BundleKind.deal, label: t('reports.bundles.deals')),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          DashLedgerStrip(
            items: [
              DashLedgerItem(
                key: 'sold',
                label: soldLabel,
                value: totals?.sold ?? 0,
                format: DashStatFormat.number,
                loading: loading,
              ),
              DashLedgerItem(
                key: 'revenue',
                label: t('reports.bundles.col.revenue'),
                value: totals?.revenue ?? 0,
                format: DashStatFormat.money,
                loading: loading,
              ),
              DashLedgerItem(
                key: 'saving',
                label: t('reports.bundles.col.saving'),
                value: totals?.saving ?? 0,
                format: DashStatFormat.money,
                loading: loading,
              ),
              DashLedgerItem(
                key: 'margin',
                label: t('reports.bundles.col.margin'),
                valueText: marginText,
                loading: loading,
              ),
            ],
          ),
          DashDataTable<BundlesRow>(
            rows: rows,
            rowKey: (r) => '${r.kind}:${r.id}',
            loading: loading,
            errorMessage: q.hasError ? errorMessage(q.error, t) : null,
            onRetry: () => ref.invalidate(bundlesReportProvider(query)),
            onRowTap: _combos
                ? (r) => _openMix(r, query, _name(r, lang))
                : null,
            rowSemanticLabel: (r) => _name(r, lang),
            empty: DashEmptyState(
              icon: 'layers',
              title: _combos
                  ? t('reports.bundles.emptyCombos')
                  : t('reports.bundles.emptyDeals'),
              description: t('reports.bundles.emptyHint'),
            ),
            columns: _columns(t, f, soldLabel),
          ),
        ],
      ),
    );
  }

  List<DashColumn<BundlesRow>> _columns(
    Translator t,
    DashFormat f,
    String soldLabel,
  ) {
    final c = context.madarColors;
    final lang = t.lang;
    return [
      DashColumn<BundlesRow>(
        id: 'name',
        // No label of its own on the web: not in the Columns menu.
        label: _combos
            ? t('reports.bundles.col.combo')
            : t('reports.bundles.col.deal'),
        hideable: false,
        phone: DashPhoneRole.title,
        flex: 2,
        minWidth: 180,
        text: (r) => _name(r, lang),
        cell: (context, r) => Text(
          _name(r, lang),
          style: DashType.bodyMedium.copyWith(color: c.textPrimary),
        ),
      ),
      DashColumn<BundlesRow>(
        id: 'sold',
        label: soldLabel,
        numeric: true,
        minWidth: 88,
        text: (r) => f.fmtNumber(r.sold),
      ),
      DashColumn<BundlesRow>(
        id: 'orders',
        label: t('reports.bundles.col.orders'),
        numeric: true,
        minWidth: 88,
        text: (r) => f.fmtNumber(r.orders),
      ),
      DashColumn<BundlesRow>(
        id: 'revenue',
        label: t('reports.bundles.col.revenue'),
        numeric: true,
        text: (r) => f.fmtMoney(r.revenue),
        cell: (context, r) => Text(
          dashFigure(f.fmtMoney(r.revenue)),
          style: DashType.monoStrong.copyWith(color: c.textPrimary),
        ),
      ),
      DashColumn<BundlesRow>(
        id: 'list',
        label: t('reports.bundles.col.listValue'),
        numeric: true,
        text: (r) => f.fmtMoney(r.listValue),
      ),
      DashColumn<BundlesRow>(
        id: 'saving',
        label: t('reports.bundles.col.saving'),
        numeric: true,
        text: (r) => f.fmtMoney(r.saving),
      ),
      DashColumn<BundlesRow>(
        id: 'cost',
        label: t('reports.bundles.col.cost'),
        numeric: true,
        // A cost partly unknown is a floor (REP-BUN-008).
        text: (r) => '${r.costMissing ? '≥ ' : ''}${f.fmtMoney(r.cost)}',
      ),
      DashColumn<BundlesRow>(
        id: 'margin',
        label: t('reports.bundles.col.margin'),
        numeric: true,
        minWidth: 88,
        text: (r) => r.costMissing ? '—' : fmtRateWire(f, r.margin),
      ),
    ];
  }

  void _openMix(BundlesRow row, BundlesQuery query, String name) {
    showDashDialog<void>(
      context,
      width: BundlesMixDialog.width,
      builder: (context) => BundlesMixDialog(
        name: name,
        query: (
          comboId: row.id,
          from: query.from,
          to: query.to,
          branchId: query.branchId,
        ),
      ),
    );
  }

  /// REP-BUN-018/019: the rows as one sheet, money in pounds, the margin a
  /// fraction (blank when the cost is unknown), totals except Orders.
  Future<void> _export(
    BundlesQuery query,
    List<BundlesRow> rows,
    Scope scope,
    String? logo,
  ) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final lang = t.lang;
    setState(() => _exporting = true);
    try {
      final config = ExcelConfig(
        filename:
            'Madar-Bundles-${_combos ? 'Combos' : 'Deals'}-${query.from}_${query.to}',
        logoUrl: logo,
        sheets: [
          ExcelSheet<BundlesRow>(
            name: _combos
                ? t('reports.bundles.combos')
                : t('reports.bundles.deals'),
            title: t('reports.bundles.title'),
            subtitle: t(
              'reports.bundles.period',
              args: {'from': f.fmtDate(scope.from), 'to': f.fmtDate(scope.to)},
            ),
            rows: rows,
            totals: true,
            columns: bundlesExportColumns(t, combos: _combos, lang: lang),
          ),
        ],
      );
      await runExcelExport(context, ref, config);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// The export's columns (`handleExport`), in the web's order and types.
List<ExcelColumn<BundlesRow>> bundlesExportColumns(
  Translator t, {
  required bool combos,
  required String lang,
}) => [
  ExcelColumn<BundlesRow>(
    header: combos
        ? t('reports.bundles.col.combo')
        : t('reports.bundles.col.deal'),
    accessor: (r) => translatedName(r.name, r.nameTranslations, lang),
    type: ExcelColumnType.text,
    width: 30,
  ),
  ExcelColumn<BundlesRow>(
    header: combos
        ? t('reports.bundles.col.sold')
        : t('reports.bundles.col.applied'),
    accessor: (r) => r.sold,
    type: ExcelColumnType.integer,
    width: 10,
    total: true,
  ),
  // Not totalled: one order can hold several combos or deals.
  ExcelColumn<BundlesRow>(
    header: t('reports.bundles.col.orders'),
    accessor: (r) => r.orders,
    type: ExcelColumnType.integer,
    width: 10,
  ),
  ExcelColumn<BundlesRow>(
    header: t('reports.bundles.col.revenue'),
    accessor: (r) => r.revenue,
    type: ExcelColumnType.money,
    width: 16,
    total: true,
  ),
  ExcelColumn<BundlesRow>(
    header: t('reports.bundles.col.listValue'),
    accessor: (r) => r.listValue,
    type: ExcelColumnType.money,
    width: 16,
    total: true,
  ),
  ExcelColumn<BundlesRow>(
    header: t('reports.bundles.col.saving'),
    accessor: (r) => r.saving,
    type: ExcelColumnType.money,
    width: 16,
    total: true,
  ),
  ExcelColumn<BundlesRow>(
    header: t('reports.bundles.col.cost'),
    accessor: (r) => r.cost,
    type: ExcelColumnType.money,
    width: 16,
    total: true,
  ),
  ExcelColumn<BundlesRow>(
    header: t('reports.bundles.col.margin'),
    accessor: (r) => r.costMissing ? null : rateOfWire(r.margin),
    type: ExcelColumnType.percent,
    width: 10,
  ),
];
