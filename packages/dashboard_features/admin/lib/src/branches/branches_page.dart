/// `/branches` Branches (ADM-BRA-001..037): the org's branches with stats,
/// search, Excel export and the branch dialog (`?edit=<id>|new`; the Dawam
/// set-up links to `/branches?edit=new`). A platform admin with no shop
/// picked sees "Select an organization" (ADM-BRA-002). Web:
/// `features/branches/branches-page.tsx`.
///
/// Nothing on the page is gated in the client: New, Edit and Delete show to
/// whoever reaches it, and the server refuses a write the person may not
/// make (ADM-BRA-017).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show Branch;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/pick_org_state.dart';
import '../shared/row_action.dart';
import '../shared/url_params.dart';
import 'branch_dialog.dart';
import 'branches_data.dart';

class BranchesPage extends ConsumerStatefulWidget {
  const BranchesPage({super.key});

  static const String path = '/branches';

  @override
  ConsumerState<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends ConsumerState<BranchesPage> {
  /// The editor is up (opened from `?edit`).
  bool _dialogOpen = false;
  bool _exporting = false;

  /// Opens the editor `?edit` names, once; closing it removes `?edit`.
  void _syncDialog(String? editId, List<Branch>? branches) {
    if (_dialogOpen || editId == null) return;
    final Branch? editing;
    if (editId == 'new') {
      editing = null;
    } else {
      // A deep link to a branch waits for the list (and a branch that is
      // not in it opens nothing, as on the web).
      editing = branches?.firstWhereOrNull((b) => b.id == editId);
      if (editing == null) return;
    }
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showBranchDialog(context, branch: editing);
      _dialogOpen = false;
      if (mounted && context.queryParam('edit') != null) {
        context.setQueryParams({'edit': null});
      }
    });
  }

  Future<void> _remove(Branch b) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('branches.deleteTitle', args: {'name': b.name}),
      description: t('branches.deleteDescription'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).branches.deleteBranch(id: b.id);
      invalidateBranches(ref);
      if (mounted) DashToast.success(context, t('branches.deletedToast'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, branchErrorText(e, t));
    }
  }

  Future<void> _export(List<Branch> branches) async {
    final t = ref.read(tProvider);
    final brand = ref.read(publicBrandProvider).value;
    setState(() => _exporting = true);
    final toast = DashToast.loading(context, t('excel.generating'));
    String dash(String? s) => hasText(s) ? s! : '—';
    final outcome = await ref
        .read(exporterProvider)
        .exportToExcel(
          ExcelConfig(
            filename: 'Madar-Branches',
            logoUrl: brand?.customBranding == true ? brand?.logoUrl : null,
            sheets: [
              ExcelSheet<Branch>(
                name: t('branches.title'),
                title: t('branches.title'),
                rows: branches,
                columns: [
                  ExcelColumn(
                    header: t('common.name'),
                    accessor: (b) => b.name,
                    type: ExcelColumnType.text,
                    width: 28,
                  ),
                  ExcelColumn(
                    header: t('branches.address'),
                    accessor: (b) => dash(b.address),
                    type: ExcelColumnType.text,
                    width: 32,
                  ),
                  ExcelColumn(
                    header: t('branches.phone'),
                    accessor: (b) => dash(b.phone),
                    type: ExcelColumnType.text,
                    width: 18,
                  ),
                  ExcelColumn(
                    header: t('branches.timezone'),
                    accessor: (b) => b.timezone,
                    type: ExcelColumnType.text,
                    width: 18,
                  ),
                  ExcelColumn(
                    header: t('branches.printer'),
                    accessor: printerExportCell,
                    type: ExcelColumnType.text,
                    width: 26,
                  ),
                  ExcelColumn(
                    header: t('common.status'),
                    accessor: (b) =>
                        t(b.isActive ? 'common.active' : 'common.inactive'),
                    type: ExcelColumnType.text,
                    width: 12,
                  ),
                ],
              ),
            ],
          ),
        );
    toast.update(
      outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
      outcome.message(t),
    );
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final title = t('branches.title');
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return PickOrgPage(
        title: title,
        icon: 'git-branch',
        message: t('branches.pickOrg'),
        description: t('branches.pickOrgDescription'),
      );
    }
    // The export's logo (the shop's own on the branding tier).
    ref.watch(publicBrandProvider);
    final list = ref.watch(adminBranchesProvider(orgId));
    final branches = list.value ?? const <Branch>[];
    final loading = list.isLoading && !list.hasValue;
    final error = !loading && list.hasError ? list.error : null;
    _syncDialog(context.queryParam('edit'), list.value);

    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    final stats = [
      DashStatCard(
        label: t('common.total'),
        value: branches.length,
        loading: loading,
      ),
      DashStatCard(
        label: t('common.active'),
        value: branches.where((b) => b.isActive).length,
        loading: loading,
      ),
      DashStatCard(
        label: t('branches.withPrinter'),
        value: branches.where((b) => b.printerBrand != null).length,
        loading: loading,
      ),
      DashStatCard(
        label: t('common.inactive'),
        value: branches.where((b) => !b.isActive).length,
        loading: loading,
      ),
    ];

    return DashPageScaffold(
      title: title,
      subtitle: t('branches.subtitle'),
      actions: [
        DashExportButton(
          onExport: () => _export(branches),
          loading: _exporting,
          enabled: branches.isNotEmpty,
        ),
        DashButton(
          key: const ValueKey('branches-new'),
          label: t('common.new'),
          icon: 'plus',
          onPressed: () => context.setQueryParams({'edit': 'new'}),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          _StatGrid(columns: wide ? 4 : 2, children: stats),
          _BranchesTable(
            branches: branches,
            loading: loading,
            errorText: error == null ? null : branchErrorText(error, t),
            onRetry: () => ref.invalidate(adminBranchesProvider(orgId)),
            onEdit: (b) => context.setQueryParams({'edit': b.id}),
            onDelete: _remove,
          ),
        ],
      ),
    );
  }
}

/// The stats in a grid of equal cells (`grid-cols-2 lg:grid-cols-4 gap-3`).
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.md,
    children: [
      for (var i = 0; i < children.length; i += columns)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            for (var j = i; j < i + columns; j++)
              Expanded(
                child: j < children.length
                    ? children[j]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
    ],
  );
}

/// The branches table (phone: one card per branch).
class _BranchesTable extends ConsumerWidget {
  const _BranchesTable({
    required this.branches,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Branch> branches;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;
  final ValueChanged<Branch> onEdit;
  final ValueChanged<Branch> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    // The shared table's search reads a column only when the first row
    // has a value there (TanStack's global filter rule).
    final first = branches.firstOrNull;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    return DashDataTable<Branch>(
      rows: branches,
      rowKey: (b) => b.id,
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      onRowTap: onEdit,
      rowSemanticLabel: (b) => b.name,
      searchPlaceholder: t('common.search'),
      empty: DashEmptyState(icon: 'git-branch', title: t('branches.empty')),
      rowActionsWidth: DashMetrics.target * 2 + Space.lg,
      rowActions: (context, b) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdminRowAction(
            icon: 'pencil',
            label: t('common.edit'),
            onPressed: () => onEdit(b),
          ),
          AdminRowAction(
            icon: 'trash-2',
            label: t('common.delete'),
            destructive: true,
            onPressed: () => onDelete(b),
          ),
        ],
      ),
      columns: [
        DashColumn<Branch>(
          id: 'name',
          label: t('common.name'),
          phone: DashPhoneRole.title,
          flex: 3,
          minWidth: 200,
          text: (b) => b.name,
          cell: (context, b) => _NameCell(branch: b),
        ),
        DashColumn<Branch>(
          id: 'phone',
          label: t('branches.phone'),
          numeric: true,
          align: DashAlign.start,
          flex: 2,
          searchable: hasText(first?.phone),
          text: (b) => b.phone ?? '',
          cell: (context, b) => hasText(b.phone)
              ? Text(
                  b.phone!,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Text('—', style: TextStyle(color: c.textSecondary)),
        ),
        DashColumn<Branch>(
          id: 'printer',
          label: t('branches.printer'),
          flex: 2,
          searchable: first?.printerBrand != null,
          text: (b) => b.printerBrand?.toJson() ?? '',
          cell: (context, b) {
            final brand = b.printerBrand;
            if (brand == null) return Text(t('branches.noPrinter'), style: muted);
            return Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                DashIcon('printer', size: IconSize.xs, color: c.textSecondary),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MadarClippedText(
                        printerBrandLabel(brand),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.smallStrong.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      MadarClippedText(
                        printerAddress(b),
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
          },
        ),
        DashColumn<Branch>(
          id: 'status',
          label: t('common.status'),
          flex: 1,
          searchable: false,
          text: (b) => t(b.isActive ? 'common.active' : 'common.inactive'),
          cell: (context, b) => DashStatusPill(
            label: t(b.isActive ? 'common.active' : 'common.inactive'),
            tone: b.isActive ? DashTone.success : DashTone.neutral,
          ),
        ),
      ],
    );
  }
}

/// The Name cell: a branch tile, the name, the address under it with a pin.
class _NameCell extends StatelessWidget {
  const _NameCell({required this.branch});

  final Branch branch;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final address = branch.address;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        Container(
          width: Space.xxl,
          height: Space.xxl,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          child: DashIcon(
            'git-branch',
            size: IconSize.sm,
            color: c.textSecondary,
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MadarClippedText(
                branch.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              if (hasText(address))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.xs,
                  children: [
                    DashIcon('map-pin', size: IconSize.xs, color: c.textSecondary),
                    Flexible(
                      child: MadarClippedText(
                        address!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.small.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
