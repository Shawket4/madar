/// `/settings/payment-methods` Payment methods (SET-PAY-001..041; web
/// `features/payment-methods/payment-methods-page.tsx`): the org's methods
/// with stats, search, the active switch, Excel export and the editor
/// (`?edit=<id>|new`), and the Availability tab (per branch, teller and
/// device allow-lists).
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. Nothing is gated in the client: the
/// rail hides the pane without `payment_methods.edit`, and by URL the page
/// renders and the server refuses what the person may not do (SET-PAY-037).
library;

import 'package:dashboard_api/dashboard_api.dart' show OrgPaymentMethod;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'availability_tab.dart';
import 'payment_method_dialog.dart';
import 'pm_data.dart';

/// The page's two tabs (page state, not in the URL).
enum PmTab { methods, availability }

class PaymentMethodsPage extends ConsumerStatefulWidget {
  const PaymentMethodsPage({this.edit, super.key});

  /// `?edit=<id>|new` (SET-SHL-012, SET-PAY-012): the editor to open.
  final String? edit;

  @override
  ConsumerState<PaymentMethodsPage> createState() => _PaymentMethodsPageState();
}

class _PaymentMethodsPageState extends ConsumerState<PaymentMethodsPage>
    with DashRememberedState {
  PmTab _tab = PmTab.methods;

  // ── memory: the tab comes back with the page (`DashRememberedState`);
  // the methods table keeps its own search and sort (its page bucket). ──

  @override
  String get memoryKey => 'setup.paymentMethods';

  @override
  Map<String, Object?> get rememberedValues => {'tab': _tab.name};

  @override
  void restoreRemembered(DashMemo m) =>
      _tab = m.enumOr('tab', PmTab.values, PmTab.methods);
  bool _exporting = false;

  /// The editor is up (opened from `?edit`).
  bool _dialogOpen = false;

  /// `usePageSearch().update({edit})`: the param replaced in place, the
  /// scope params kept.
  void _setEdit(String? id) {
    final uri = GoRouterState.of(context).uri;
    final q = Map<String, String>.of(uri.queryParameters)..remove('edit');
    if (id != null) q['edit'] = id;
    context.go(
      Uri(path: uri.path, queryParameters: q.isEmpty ? null : q).toString(),
    );
  }

  /// Opens the editor `?edit` names, once; closing it removes `?edit`. A
  /// deep link to a method waits for the list; an unknown id opens nothing.
  void _syncDialog(List<OrgPaymentMethod>? methods) {
    final editId = widget.edit;
    if (_dialogOpen || editId == null) return;
    OrgPaymentMethod? editing;
    if (editId != 'new') {
      editing = methods?.where((m) => m.id == editId).firstOrNull;
      if (editing == null) return;
    }
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showPaymentMethodDialog(context, editing);
      _dialogOpen = false;
      if (mounted &&
          GoRouterState.of(context).uri.queryParameters['edit'] != null) {
        _setEdit(null);
      }
    });
  }

  Future<void> _toggle(OrgPaymentMethod m) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).paymentMethods;
    final bus = ref.read(realtimeBusProvider);
    try {
      await (m.isActive
          ? api.deactivatePaymentMethod(id: m.id)
          : api.activatePaymentMethod(id: m.id));
      invalidatePaymentMethods(bus);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  Future<void> _export(List<OrgPaymentMethod> methods) async {
    final t = ref.read(tProvider);
    final lang = ref.read(localeProvider);
    final brand = ref.read(publicBrandProvider).value;
    final title = t('settings.paymentMethods');
    setState(() => _exporting = true);
    final toast = DashToast.loading(context, t('excel.generating'));
    final outcome = await ref
        .read(exporterProvider)
        .exportToExcel(
          ExcelConfig(
            filename: 'Madar-PaymentMethods',
            logoUrl: exportLogoUrl(brand),
            sheets: [
              ExcelSheet<OrgPaymentMethod>(
                name: title,
                title: title,
                rows: methods,
                columns: [
                  ExcelColumn(
                    header: t('settings.pm.id'),
                    accessor: (m) => m.name,
                    type: ExcelColumnType.text,
                    width: 22,
                  ),
                  ExcelColumn(
                    header: t('common.name'),
                    accessor: (m) => labelOf(m, lang),
                    type: ExcelColumnType.text,
                    width: 28,
                  ),
                  ExcelColumn(
                    header: t('common.type'),
                    accessor: (m) => t(
                      m.isCash ? 'settings.pm.cashBase' : 'settings.pm.nonCash',
                    ),
                    type: ExcelColumnType.text,
                    width: 14,
                  ),
                  ExcelColumn(
                    header: t('common.status'),
                    accessor: (m) =>
                        t(m.isActive ? 'common.active' : 'common.inactive'),
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

  /// The Availability tab's reads, warmed on the tab's intent (the list is
  /// already held).
  void _warmTab(PmTab tab, String orgId) {
    if (tab != PmTab.availability) return;
    ref.warm(pmUsersProvider(orgId));
    final branchId = ref.read(currentScopeProvider).branchId;
    if (branchId == null) return;
    ref.warm(pmAvailabilityProvider(branchId));
    ref.warm(pmDevicesProvider(branchId));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final title = t('settings.paymentMethods');
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return DashPageScaffold(
        title: title,
        width: DashPageWidth.reading,
        body: DashEmptyState(
          key: const ValueKey('pm-pick-org'),
          icon: 'credit-card',
          title: t('users.pickOrg'),
        ),
      );
    }
    // The export's logo (the shop's own on the branding tier).
    ref.watch(publicBrandProvider);
    final list = ref.watch(paymentMethodsProvider);
    final methods = list.value ?? const <OrgPaymentMethod>[];
    // Never a flash of "No results": the skeleton through the automatic
    // retries, then the error, kept (Retry spinning) while a Retry runs.
    final loading = list.awaitingFirst;
    final error = list.failedFirst ? list.error : null;
    _syncDialog(list.value);

    return DashPageScaffold(
      title: title,
      subtitle: t('settings.paymentMethodsHint'),
      width: DashPageWidth.reading,
      actions: [
        DashExportButton(
          key: const ValueKey('pm-export'),
          onExport: () => _export(methods),
          loading: _exporting,
          enabled: methods.isNotEmpty,
        ),
        DashButton(
          key: const ValueKey('pm-add'),
          label: t('common.add'),
          icon: 'plus',
          onPressed: () => _setEdit('new'),
        ),
      ],
      tabs: DashPageTabs<PmTab>(
        key: const ValueKey('pm-tabs'),
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        onIntent: (v) => _warmTab(v, orgId),
        tabs: [
          DashTab(value: PmTab.methods, label: title),
          DashTab(
            value: PmTab.availability,
            label: t('paymentMethods.availability.title'),
          ),
        ],
      ),
      body: _tab == PmTab.availability
          ? const AvailabilityTab()
          : _MethodsView(
              methods: methods,
              loading: loading,
              error: error,
              retrying: list.isLoading,
              onRetry: () => ref.invalidate(paymentMethodsProvider),
              onEdit: (m) => _setEdit(m.id),
              onToggle: _toggle,
            ),
    );
  }
}

/// The stats and the table (the "Payment Methods" tab).
class _MethodsView extends ConsumerWidget {
  const _MethodsView({
    required this.methods,
    required this.loading,
    required this.error,
    required this.retrying,
    required this.onRetry,
    required this.onEdit,
    required this.onToggle,
  });

  final List<OrgPaymentMethod> methods;
  final bool loading;
  final Object? error;
  final bool retrying;
  final VoidCallback onRetry;
  final ValueChanged<OrgPaymentMethod> onEdit;
  final ValueChanged<OrgPaymentMethod> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final active = methods.where((m) => m.isActive).length;
    final stats = [
      DashStatCard(
        label: t('common.total'),
        value: methods.length,
        loading: loading,
      ),
      DashStatCard(
        label: t('common.active'),
        value: active,
        tone: DashTone.success,
        loading: loading,
      ),
      DashStatCard(
        label: t('common.inactive'),
        value: methods.length - active,
        tone: DashTone.warning,
        loading: loading,
      ),
      DashStatCard(
        label: t('settings.pm.systemMethods'),
        value: methods.where(isSystemMethod).length,
        tone: DashTone.info,
        loading: loading,
      ),
    ];
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        // `grid-cols-2 lg:grid-cols-4`, but four only where the pane gives
        // each card room (beside the settings rail at 1024 it does not).
        LayoutBuilder(
          builder: (context, box) => PmGrid(
            columns: wide && box.maxWidth >= _fourStatsWidth ? 4 : 2,
            children: stats,
          ),
        ),
        _MethodsTable(
          methods: methods,
          loading: loading,
          errorText: error == null ? null : errorMessage(error, t),
          retrying: retrying,
          onRetry: onRetry,
          onEdit: onEdit,
          onToggle: onToggle,
        ),
      ],
    );
  }
}

/// The pane width from which the four stats share one row.
const double _fourStatsWidth = DashBreakpoints.sm;

/// Equal cells in rows ([columns] a row, `gap-3`).
class PmGrid extends StatelessWidget {
  const PmGrid({required this.columns, required this.children, super.key});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.md,
    children: [
      for (var i = 0; i < children.length; i += columns)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
        ),
    ],
  );
}

class _MethodsTable extends ConsumerWidget {
  const _MethodsTable({
    required this.methods,
    required this.loading,
    required this.errorText,
    required this.retrying,
    required this.onRetry,
    required this.onEdit,
    required this.onToggle,
  });

  final List<OrgPaymentMethod> methods;
  final bool loading;
  final String? errorText;
  final bool retrying;
  final VoidCallback onRetry;
  final ValueChanged<OrgPaymentMethod> onEdit;
  final ValueChanged<OrgPaymentMethod> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    return DashDataTable<OrgPaymentMethod>(
      key: const ValueKey('pm-table'),
      rows: methods,
      rowKey: (m) => m.id,
      loading: loading,
      errorMessage: errorText,
      retrying: retrying,
      onRetry: onRetry,
      onRowTap: onEdit,
      hideViewOptions: true,
      searchPlaceholder: t('common.search'),
      rowSemanticLabel: (m) => labelOf(m, lang),
      empty: DashEmptyState(icon: 'credit-card', title: t('common.noResults')),
      columns: [
        // Searched by the identifier, not the label (the column's accessor).
        DashColumn<OrgPaymentMethod>(
          id: 'name',
          label: t('common.name'),
          phone: DashPhoneRole.title,
          flex: 3,
          minWidth: 200,
          text: (m) => m.name,
          cell: (context, m) => PmNameCell(method: m),
        ),
        DashColumn<OrgPaymentMethod>(
          id: 'is_cash',
          label: t('common.type'),
          searchable: false,
          cell: (context, m) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashBadge(
              t(m.isCash ? 'settings.pm.cashBase' : 'settings.pm.nonCash'),
              tone: m.isCash ? DashTone.success : DashTone.neutral,
            ),
          ),
        ),
        DashColumn<OrgPaymentMethod>(
          id: 'visible_in_integrations',
          label: t('settings.pm.partners'),
          searchable: false,
          cell: (context, m) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: m.visibleInIntegrations
                ? Text(
                    '—',
                    style: DashType.small.copyWith(color: c.textSecondary),
                  )
                : DashStatusPill(
                    key: ValueKey('pm-hidden-${m.id}'),
                    label: t('settings.pm.hiddenFromPartners'),
                    icon: 'eye-off',
                    small: true,
                  ),
          ),
        ),
        DashColumn<OrgPaymentMethod>(
          id: 'is_active',
          label: t('common.status'),
          searchable: false,
          minWidth: 160,
          cell: (context, m) => Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              DashSwitch(
                key: ValueKey('pm-active-${m.id}'),
                value: m.isActive,
                semanticLabel: labelOf(m, lang),
                onChanged: (_) => onToggle(m),
              ),
              Flexible(
                child: DashBadge(
                  t(m.isActive ? 'common.active' : 'common.inactive'),
                  tone: m.isActive ? DashTone.success : DashTone.neutral,
                ),
              ),
            ],
          ),
        ),
        // The web's `actions` column: an empty header, the pencil in a cell
        // (on a phone it is the card's unlabelled cell).
        DashColumn<OrgPaymentMethod>(
          id: 'actions',
          label: '',
          width: DashMetrics.target + Space.lg,
          hideable: false,
          searchable: false,
          align: DashAlign.end,
          cell: (context, m) => DashIconButton(
            key: ValueKey('pm-edit-${m.id}'),
            icon: 'pencil',
            semanticLabel: t('common.edit'),
            onPressed: () => onEdit(m),
          ),
        ),
      ],
    );
  }
}

/// The Name cell: the method's colour disc with its glyph, the label in the
/// active language, and "System" under a built-in method.
class PmNameCell extends ConsumerWidget {
  const PmNameCell({required this.method, super.key});

  final OrgPaymentMethod method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        PmDisc(method: method),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MadarClippedText(
                labelOf(method, lang),
                textDirection: dashTextDirectionOf(labelOf(method, lang)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyMedium.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isSystemMethod(method))
                Text(
                  t('settings.pm.system'),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A method's round swatch (32, `size-8`) with its glyph: the method's own
/// hex colour, or the third chart colour when it is not a hex.
class PmDisc extends StatelessWidget {
  const PmDisc({required this.method, super.key});

  final OrgPaymentMethod method;

  static const double size = Space.xxl;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: method.color.startsWith('#')
          ? hexColor(method.color)
          : dashSeriesColor(context, 2),
    ),
    alignment: Alignment.center,
    // Identity colours stay the same in both themes, so the glyph is white.
    child: DashIcon(pmGlyph(method.icon), size: 14, color: Colors.white),
  );
}
