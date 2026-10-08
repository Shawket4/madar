/// `/orgs` Organizations (ADM-ORG-001..059): every organization with stats,
/// search, Excel export, the provision wizard (`?edit=new`) and the edit
/// dialog (`?edit=<id>`). Web: `features/orgs/orgs-page.tsx`.
///
/// No route guard and no `<Restricted>`: whoever reaches the address sees
/// the page frame and the server refuses the list (ADM-ORG-004).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show Org;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/row_action.dart';
import '../shared/tax_rate.dart';
import '../shared/url_params.dart';
import 'org_dialog.dart';
import 'org_errors.dart';
import 'org_logo.dart';
import 'orgs_providers.dart';
import 'provision_wizard.dart';

class OrgsPage extends ConsumerStatefulWidget {
  const OrgsPage({super.key});

  static const String path = '/orgs';

  @override
  ConsumerState<OrgsPage> createState() => _OrgsPageState();
}

class _OrgsPageState extends ConsumerState<OrgsPage> {
  /// The `?edit` value whose editor is showing (`new` = the wizard).
  String? _open;
  NavigatorState? _editorNavigator;
  bool _exporting = false;

  // ── The editor in the address (ADM-ORG-023, 024, 056) ─────────────────

  void _openEditor(String edit) => context.setQueryParams({'edit': edit});

  /// Opens the editor `?edit` names once it can (an id only once the list
  /// holds it; an unknown id opens nothing), and closes it when the address
  /// loses it.
  void _syncEditor(String? edit, List<Org>? orgs) {
    final open = _open;
    if (open != null) {
      if (edit != open) {
        final nav = _editorNavigator;
        _editorNavigator = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => nav?.maybePop());
      }
      return;
    }
    if (edit == null) return;
    Org? org;
    if (edit != 'new') {
      org = orgs?.firstWhereOrNull((o) => o.id == edit);
      if (org == null) return;
    }
    _open = edit;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _editorNavigator = Navigator.of(context, rootNavigator: true);
      if (org == null) {
        await showProvisionWizard(context);
      } else {
        await showOrgDialog(context, org: org);
      }
      _editorNavigator = null;
      if (!mounted) return;
      final still = context.queryParam('edit') == edit;
      setState(() => _open = null);
      if (still) context.setQueryParams({'edit': null});
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _delete(Org org) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('orgs.deleteTitle', args: {'name': org.name}),
      description: t('orgs.deleteDescription'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).orgs.deleteOrg(id: org.id);
      if (!mounted) return;
      invalidateOrgs(ref);
      DashToast.success(context, t('orgs.deletedToast'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
    }
  }

  /// The Excel file (ADM-ORG-022): the engine words every toast
  /// (ADM-APP-126); the header logo is the shop's own only on the branding
  /// tier.
  Future<void> _export(List<Org> orgs) async {
    final t = ref.read(tProvider);
    setState(() => _exporting = true);
    final toast = DashToast.loading(context, t('excel.generating'));
    ExportOutcome outcome;
    try {
      final brand = await ref.read(publicBrandProvider.future);
      final logo = brand != null && brand.customBranding ? brand.logoUrl : null;
      outcome = await ref
          .read(exporterProvider)
          .exportToExcel(
            ExcelConfig(
              filename: 'Madar-Organizations',
              logoUrl: logo,
              sheets: [
                ExcelSheet<Org>(
                  name: t('orgs.title'),
                  title: t('orgs.title'),
                  rows: orgs,
                  columns: [
                    ExcelColumn<Org>(
                      header: t('common.name'),
                      accessor: (o) => o.name,
                      type: ExcelColumnType.text,
                      width: 28,
                    ),
                    ExcelColumn<Org>(
                      header: t('orgs.slug'),
                      accessor: (o) => o.slug,
                      type: ExcelColumnType.text,
                      width: 20,
                    ),
                    ExcelColumn<Org>(
                      header: t('orgs.currency'),
                      accessor: (o) => o.currencyCode,
                      type: ExcelColumnType.text,
                      width: 12,
                    ),
                    ExcelColumn<Org>(
                      header: t('orgs.taxRate'),
                      accessor: (o) => fractionToPercent(o.taxRate),
                      type: ExcelColumnType.number,
                      width: 12,
                    ),
                    ExcelColumn<Org>(
                      header: t('common.status'),
                      accessor: (o) => o.isActive
                          ? t('common.active')
                          : t('common.inactive'),
                      type: ExcelColumnType.text,
                      width: 12,
                    ),
                  ],
                ),
              ],
            ),
          );
    } on Object catch (e) {
      outcome = ExportFailed(e);
    }
    toast.update(
      outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
      outcome.message(t),
    );
    if (mounted) setState(() => _exporting = false);
  }

  // ── The page ──────────────────────────────────────────────────────────

  List<DashColumn<Org>> _columns(Translator t) => [
    DashColumn<Org>(
      id: 'name',
      label: t('common.name'),
      // Search reads the name, the currency and the raw tax fraction; never
      // the slug (the web's global filter over the accessor values).
      text: (o) => o.name,
      cell: (context, o) => _NameCell(org: o),
      phone: DashPhoneRole.title,
      flex: 3,
      minWidth: 220,
    ),
    DashColumn<Org>(
      id: 'currency',
      label: t('orgs.currency'),
      text: (o) => o.currencyCode,
      cell: (context, o) => DashBadge(o.currencyCode, mono: true),
    ),
    DashColumn<Org>(
      id: 'tax',
      label: t('orgs.taxRate'),
      text: (o) => jsNumber(o.taxRate),
      numeric: true,
      cell: (context, o) => Text(
        dashFigure(formatRate(o.taxRate)),
        textDirection: TextDirection.ltr,
      ),
    ),
    DashColumn<Org>(
      id: 'branding',
      label: t('orgs.customBranding'),
      searchable: false,
      minWidth: 140,
      cell: (context, o) => o.customBranding
          ? DashStatusPill(label: t('common.on'), tone: DashTone.info)
          : Text(
              t('common.off'),
              style: DashType.small.copyWith(
                color: context.madarColors.textSecondary,
              ),
            ),
    ),
    DashColumn<Org>(
      id: 'status',
      label: t('common.status'),
      searchable: false,
      cell: (context, o) => o.isActive
          ? DashStatusPill(label: t('common.active'), tone: DashTone.success)
          : DashStatusPill(label: t('common.inactive')),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final list = ref.watch(orgsListProvider);
    final orgs = list.value ?? const <Org>[];
    final firstLoad = list.isLoading && !list.hasValue && !list.hasError;
    final failed = list.hasError && !list.hasValue;
    _syncEditor(context.queryParam('edit'), list.value);

    final avgTaxRatio = orgs.isEmpty
        ? null
        : orgs.fold<double>(0, (a, o) => a + o.taxRate) / orgs.length;

    return DashPageScaffold(
      title: t('orgs.title'),
      subtitle: t('orgs.subtitle'),
      actions: [
        DashExportButton(
          onExport: () => _export(orgs),
          loading: _exporting,
          enabled: orgs.isNotEmpty,
        ),
        DashButton(
          key: const ValueKey('orgs-new'),
          label: t('common.new'),
          icon: 'plus',
          onPressed: () => _openEditor('new'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xl,
        children: [
          _StatGrid(
            children: [
              DashStatCard(
                key: const ValueKey('orgs-stat-total'),
                label: t('common.total'),
                value: orgs.length,
                format: DashStatFormat.number,
                loading: firstLoad,
              ),
              DashStatCard(
                key: const ValueKey('orgs-stat-active'),
                label: t('common.active'),
                value: orgs.where((o) => o.isActive).length,
                format: DashStatFormat.number,
                loading: firstLoad,
              ),
              DashStatCard(
                key: const ValueKey('orgs-stat-inactive'),
                label: t('common.inactive'),
                value: orgs.where((o) => !o.isActive).length,
                format: DashStatFormat.number,
                loading: firstLoad,
              ),
              DashStatCard(
                key: const ValueKey('orgs-stat-avg-tax'),
                label: t('orgs.avgTax'),
                value: avgTaxRatio,
                valueText: avgTaxRatio == null ? '—' : null,
                format: DashStatFormat.percent,
                loading: firstLoad,
              ),
            ],
          ),
          DashDataTable<Org>(
            key: const ValueKey('orgs-table'),
            columns: _columns(t),
            rows: orgs,
            rowKey: (o) => o.id,
            loading: firstLoad,
            errorMessage: failed ? orgErrorWords(list.error, t) : null,
            onRetry: () => ref.invalidate(orgsListProvider),
            onRowTap: (o) => _openEditor(o.id),
            searchPlaceholder: t('common.search'),
            rowActionsWidth: DashMetrics.target * 2 + Space.sm,
            rowActions: (context, o) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AdminRowAction(
                  icon: 'pencil',
                  label: t('common.edit'),
                  onPressed: () => _openEditor(o.id),
                ),
                AdminRowAction(
                  icon: 'trash-2',
                  label: t('common.delete'),
                  destructive: true,
                  onPressed: () => _delete(o),
                ),
              ],
            ),
            empty: DashEmptyState(icon: 'building-2', title: t('orgs.empty')),
          ),
        ],
      ),
    );
  }
}

/// Two stat cards a row, four from 1024 wide (`grid-cols-2 lg:grid-cols-4`);
/// the cards of a row share its height.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final perRow = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg
        ? 4
        : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        for (var i = 0; i < children.length; i += perRow)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [
                for (var j = i; j < i + perRow && j < children.length; j++)
                  Expanded(child: children[j]),
              ],
            ),
          ),
      ],
    );
  }
}

/// The Name cell (and the phone card's title): the mark, the name in bold,
/// the slug in mono under it.
class _NameCell extends StatelessWidget {
  const _NameCell({required this.org});

  final Org org;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final slug = org.slug;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        OrgLogoTile(name: org.name, logoUrl: org.logoUrl),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MadarClippedText(
                org.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              if (slug != null && slug.isNotEmpty)
                MadarClippedText(
                  slug,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: DashType.mono.copyWith(
                    fontSize: DashType.small.fontSize,
                    color: c.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
