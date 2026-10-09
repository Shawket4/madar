/// `/tills` (the web's `features/tills/tills-page.tsx`, SELL-TIL rows): the
/// KPI strip, "Open now", "All tills", the report panel (`?report=`), and the
/// open / close / cash movement / force close / delete actions. The legacy
/// `/shifts?…` is redirected here by the shell (SELL-ALL-007).
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show ForceCloseRequest, Till, TillPreFill;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'cash_movement_dialog.dart';
import 'close_till_dialog.dart';
import 'open_till_dialog.dart';
import 'till_report_sheet.dart';
import 'tills_data.dart';
import 'tills_sections.dart';
import '../shared/error_text.dart';
import '../shared/export_logo.dart';

class TillsPage extends ConsumerStatefulWidget {
  const TillsPage({this.query = const {}, super.key});

  /// The route's builder (routes.dart points here; the search params —
  /// `report`, `status`, `teller`, `device`, `flagged`, `today` — are this
  /// page's, SELL-TIL-008).
  static Widget route(BuildContext context, GoRouterState state) =>
      TillsPage(query: state.uri.queryParameters);

  /// The web's `prefetchRoute('/tills')`: the branch's open tills, the key
  /// the page watches on mount.
  static void prefetch(DashPrefetcher warm, Scope scope) {
    final branchId = scope.branchId;
    if (branchId != null) warm(openTillsProvider(branchId));
  }

  final Map<String, String> query;

  @override
  ConsumerState<TillsPage> createState() => _TillsPageState();
}

class _TillsPageState extends ConsumerState<TillsPage> {
  /// The till whose report is open (`?report=`), shared with the panel so a
  /// "See the other till" switches it in place.
  late final ValueNotifier<String?> _report = ValueNotifier(
    TillsSearch.fromQuery(widget.query).report,
  );
  bool _panelOpen = false;
  bool _exporting = false;

  TillsSearch get _search => TillsSearch.fromQuery(widget.query);

  @override
  void initState() {
    super.initState();
    _syncReport();
  }

  @override
  void didUpdateWidget(TillsPage old) {
    super.didUpdateWidget(old);
    // After this build: the panel lives in another route and rebuilds then.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncReport();
    });
  }

  @override
  void dispose() {
    _report.dispose();
    super.dispose();
  }

  /// The URL holds the open report (SELL-TIL-055): opening it shows the
  /// panel, clearing it closes the panel (the panel listens).
  void _syncReport() {
    final id = _search.report;
    if (_report.value != id) _report.value = id;
    if (id != null && !_panelOpen) {
      _panelOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showReport());
    }
  }

  Future<void> _showReport() async {
    if (!mounted || _report.value == null) {
      _panelOpen = false;
      return;
    }
    await showTillReport(
      context,
      tillId: _report,
      onOpenTill: (id) => _setSearch({'report': id}),
    );
    _panelOpen = false;
    // Closing the panel removes `?report=` (×, Escape, a tap outside).
    if (mounted && _search.report != null) _setSearch({'report': null});
  }

  /// `navigate({search: (p) => ({...p, ...patch}), replace: true})`.
  void _setSearch(Map<String, String?> patch) {
    if (!mounted) return;
    final router = GoRouter.of(context);
    final at = router.routerDelegate.currentConfiguration.uri;
    if (at.path != '/tills') return;
    final query = patchQuery(at.queryParameters, patch);
    router.go(
      Uri(
        path: '/tills',
        queryParameters: query.isEmpty ? null : query,
      ).toString(),
    );
  }

  void _openReport(String id) => _setSearch({'report': id});

  /// The device's local midnight today, as the web's `startOfToday()`
  /// (SELL-TIL-006: the device's clock, not the branch zone).
  DateTime _startOfToday() {
    final now = ref.read(clockProvider)().toLocal();
    return DateTime(now.year, now.month, now.day).toUtc();
  }

  TillsListKey _listKey(Scope scope, TillsSearch s) => (
    branchId: scope.scopeBranchId,
    status: s.status,
    tellerId: s.teller,
    deviceId: s.device,
    flagged: s.flagged,
    from: s.today ? _startOfToday() : null,
  );

  // ── Actions ──────────────────────────────────────────────────────────

  Future<void> _forceClose(Till till) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('tills.forceClose'),
      description: t('tills.forceCloseDesc'),
      destructive: true,
      confirmLabel: t('tills.forceClose'),
    );
    if (!ok || !mounted) return;
    final refresh = tillsInvalidator(ref);
    try {
      await ref
          .read(apiProvider)
          .tills
          .forceCloseTill(
            tillId: till.id,
            body: const ForceCloseRequest(explicitNulls: {'reason'}),
          );
      refresh();
      if (mounted) DashToast.success(context, t('tills.forceClosed'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, sellErrorText(e, t));
    }
  }

  Future<void> _delete(Till till) async {
    final t = ref.read(tProvider);
    final fmt = ref.read(formatProvider);
    final ok = await showDashConfirm(
      context,
      title: t('tills.deleteTitle'),
      description: t(
        'common.confirmDelete',
        args: {'name': fmt.fmtDateTime(till.openedAt)},
      ),
      destructive: true,
      confirmLabel: t('common.delete'),
    );
    if (!ok || !mounted) return;
    final refresh = tillsInvalidator(ref);
    try {
      await ref.read(apiProvider).tills.deleteTill(tillId: till.id);
      refresh();
      if (mounted) DashToast.success(context, t('tills.deleted'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, sellErrorText(e, t));
    }
  }

  /// The loaded rows, as they are, to `Madar-Tills-<today>.xlsx`
  /// (SELL-TIL-058/059).
  Future<void> _export(List<Till> rows) async {
    final t = ref.read(tProvider);
    setState(() => _exporting = true);
    try {
      final title = t('nav.tills');
      final config = ExcelConfig(
        filename: 'Madar-Tills',
        logoUrl: exportLogoOf(ref.read(publicBrandProvider).value),
        sheets: [
          ExcelSheet<Till>(
            name: title,
            title: title,
            rows: rows,
            columns: tillsExportColumns(t),
          ),
        ],
      );
      final toast = DashToast.loading(context, t('excel.generating'));
      final outcome = await ref.read(exporterProvider).exportToExcel(config);
      toast.update(
        outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
        outcome.message(t),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, sellErrorText(e, t));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final scope = ref.watch(currentScopeProvider);
    final branchId = scope.branchId;
    final search = _search;
    final canForceClose = ref.watch(
      authzStateProvider.select((a) => a.can(Cap.tillForceClose)),
    );
    final canDelete = ref.watch(
      authzStateProvider.select((a) => a.can(Cap.tillDelete)),
    );

    // With All branches only the list is read (SELL-TIL-002/056).
    final AsyncValue<TillPreFill>? current = branchId == null
        ? null
        : ref.watch(tillPreFillProvider(branchId));
    final openNow = branchId == null
        ? null
        : ref.watch(openTillsProvider(branchId));
    final notice = branchId == null
        ? null
        : ref.watch(openBillsNoticeProvider(branchId));
    final key = _listKey(scope, search);
    final list = ref.watch(tillsListProvider(key));

    final rows = list.value?.data ?? const <Till>[];
    final pre = current?.value;
    final myOpen = branchId != null && pre != null && pre.hasOpenTill
        ? pre.openTill
        : null;

    List<DashMenuItem> rowMenu(Till s) => [
      DashMenuItem(
        label: t('tills.viewReport'),
        onSelected: () => _openReport(s.id),
        onIntent: () => warmTillReport(ref, s.id),
      ),
      if (s.status.value == 'open' && s.id == pre?.openTill?.id) ...[
        DashMenuItem(
          label: t('tills.cashMovement'),
          icon: 'wallet',
          onSelected: () => showCashMovementDialog(context, tillId: s.id),
        ),
        DashMenuItem(
          label: t('tills.closeTill'),
          onSelected: () => showCloseTillDialog(context, till: s),
          onIntent: () => ref.warm(closePreviewProvider(s.id)),
        ),
      ],
      if (canForceClose && s.status.value == 'open')
        DashMenuItem(
          label: t('tills.forceClose'),
          icon: 'x-circle',
          destructive: true,
          onSelected: () => _forceClose(s),
        ),
      if (canDelete)
        DashMenuItem(
          label: t('common.delete'),
          icon: 'trash-2',
          destructive: true,
          onSelected: () => _delete(s),
        ),
    ];

    final body = Column(
      key: const ValueKey('tills-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        if (branchId != null)
          TillsKpis(
            openNow: openNow!,
            notice: notice!,
            rows: rows,
            listLoading: list.awaitingFirst,
          ),
        if (branchId != null)
          OpenNowSection(
            openNow: openNow!,
            notice: notice!.value,
            onOpen: _openReport,
            onRetry: () => ref.invalidate(openTillsProvider(branchId)),
          ),
        AllTillsSection(
          list: list,
          rows: rows,
          showBranch: scope.isAllBranches,
          onOpenReport: _openReport,
          onRetry: () => ref.invalidate(tillsListProvider(key)),
          menu: rowMenu,
        ),
      ],
    );

    return DashPageScaffold(
      title: t('nav.tills'),
      subtitle: t('tills.subtitle'),
      actions: [
        DashExportButton(
          key: const ValueKey('tills-export'),
          loading: _exporting,
          enabled: rows.isNotEmpty && !_exporting,
          onExport: () => _export(rows),
        ),
        if (branchId != null && myOpen == null)
          DashButton(
            key: const ValueKey('open-till'),
            label: t('tills.openTill'),
            icon: 'plus-circle',
            onPressed: () => showOpenTillDialog(context, branchId: branchId),
          ),
      ],
      filters: TillFilters(
        search: search,
        rows: rows,
        onChange: _setSearch,
        onIntent: (patch) => ref.warm(
          tillsListProvider(
            _listKey(
              scope,
              TillsSearch.fromQuery(patchQuery(widget.query, patch)),
            ),
          ),
        ),
      ),
      body: body,
    );
  }
}

/// The export's columns (SELL-TIL-059), as the web's `handleExport`.
List<ExcelColumn<Till>> tillsExportColumns(Translator t) => [
  ExcelColumn(
    header: t('tills.opened'),
    accessor: (s) => s.openedAt,
    type: ExcelColumnType.dateTime,
    width: 20,
  ),
  ExcelColumn(
    header: t('tills.teller'),
    accessor: (s) => s.tellerName,
    type: ExcelColumnType.text,
    width: 22,
  ),
  ExcelColumn(
    header: t('tills.device'),
    accessor: (s) => s.deviceCode ?? '',
    type: ExcelColumnType.text,
    width: 10,
  ),
  ExcelColumn(
    header: t('common.status'),
    accessor: (s) => tillStatusLabel(t, s.status.value),
    type: ExcelColumnType.text,
    width: 14,
  ),
  ExcelColumn(
    header: t('tills.openingCash'),
    accessor: (s) => s.openingCash,
    type: ExcelColumnType.money,
    width: 14,
  ),
  ExcelColumn(
    header: t('tills.closingCash'),
    accessor: (s) => s.closingCashDeclared,
    type: ExcelColumnType.money,
    width: 14,
  ),
  ExcelColumn(
    header: t('tills.discrepancy'),
    accessor: (s) => s.cashDiscrepancy,
    type: ExcelColumnType.money,
    width: 14,
  ),
  ExcelColumn(
    header: t('tills.flagged'),
    accessor: (s) => s.openedWhileAnotherOpen ? '✓' : '',
    type: ExcelColumnType.text,
    width: 10,
  ),
  ExcelColumn(
    header: t('tills.reconciliation.title'),
    accessor: (s) => s.disagreementCount == 0 ? '' : '${s.disagreementCount}',
    type: ExcelColumnType.text,
    width: 10,
  ),
];
