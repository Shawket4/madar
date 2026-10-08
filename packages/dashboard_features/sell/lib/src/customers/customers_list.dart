/// The people list (the web's `features/customers/customers-list.tsx`,
/// customers source): server search, "Came from", "Members only", the
/// load-more window, the export, the platform's wallet inspector, and the
/// sheet a row opens (SELL-CUS-004 … SELL-CUS-021).
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/phone.dart';
import 'customers_data.dart';
import 'google_object_dialog.dart';
import 'people_widgets.dart';
import 'person_surface.dart';

class CustomersList extends ConsumerStatefulWidget {
  const CustomersList({
    required this.openId,
    required this.onOpen,
    this.branchId,
    super.key,
  });

  /// The person whose sheet is open (the row is selected).
  final String? openId;

  /// A row was tapped.
  final ValueChanged<String> onOpen;

  /// The branch whose program a balance is read under (null = the org's).
  final String? branchId;

  @override
  ConsumerState<CustomersList> createState() => _CustomersListState();
}

class _CustomersListState extends ConsumerState<CustomersList> {
  String _q = '';
  bool _onlyMembers = false;
  String? _source;
  int _pages = 1;
  bool _exporting = false;

  /// The last window that arrived: shown while a new one loads
  /// (`placeholderData: keepPreviousData`).
  List<Customer>? _previous;

  int get _limit => (customersPageSize * _pages).clamp(1, customersLimitMax);

  bool get _filtered => _q.isNotEmpty || _onlyMembers || _source != null;

  CustomersQuery get _key => (
    q: _q,
    member: _onlyMembers ? true : null,
    source: _source,
    limit: _limit,
  );

  /// A new search or filter starts the window over.
  void _reset(VoidCallback change) => setState(() {
    change();
    _pages = 1;
  });

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final access = ref.watch(peopleAccessProvider);
    final c = context.madarColors;

    final program = access.canReadProgram
        ? ref.watch(loyaltySettingsProvider(widget.branchId)).value
        : null;
    final mode = program == null ? null : loyaltyModeOf(program);
    final showBalance = mode != null && program?.enabled == true;

    final list = ref.watch(customersListProvider(_key));
    final data = list.value;
    if (data != null) _previous = data;
    final shownData = data ?? _previous;
    final rows = [
      for (final r in shownData ?? const <Customer>[])
        PersonRow(customer: r, mode: mode),
    ];
    final loading = shownData == null && !list.hasError;
    final error = list.hasError && !list.isLoading
        ? peopleErrorMessage(list.error, t)
        : null;

    Widget dash() => const MutedDash();
    final columns = <DashColumn<PersonRow>>[
      DashColumn(
        id: 'name',
        label: t('customers.name'),
        phone: DashPhoneRole.title,
        flex: 2,
        minWidth: 180,
        text: (r) => r.name,
        cell: (context, r) => Row(
          spacing: Space.sm,
          children: [
            Flexible(
              child: MadarClippedText(
                r.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: autoDirection(r.name),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ),
            if (r.isMember) const MemberPill(),
          ],
        ),
      ),
      DashColumn(
        id: 'phone',
        label: t('customers.phone'),
        minWidth: 150,
        text: (r) => formatPhoneDisplay(r.phone),
        cell: (context, r) {
          final p = r.phone;
          return p == null || p.isEmpty ? dash() : PhoneText(p);
        },
      ),
      if (showBalance)
        DashColumn(
          id: 'balance',
          label: t('loyalty.balance'),
          numeric: true,
          minWidth: 110,
          text: (r) => r.balance == null
              ? '—'
              : loyaltyAmount(t, mode, r.balance!, fmt: fmt),
          cell: (context, r) => r.balance == null
              ? dash()
              : Text(
                  dashFigure(loyaltyAmount(t, mode, r.balance!, fmt: fmt)),
                  style: DashType.mono.copyWith(color: c.textPrimary),
                ),
        ),
      DashColumn(
        id: 'source',
        label: t('customers.source.label'),
        phone: DashPhoneRole.hidden,
        minWidth: 120,
        text: (r) => isCustomerSource(r.customer.source)
            ? t('customers.source.${r.customer.source}')
            : '—',
        cell: (context, r) => isCustomerSource(r.customer.source)
            ? Text(
                t('customers.source.${r.customer.source}'),
                style: DashType.body.copyWith(color: c.textSecondary),
              )
            : dash(),
      ),
      DashColumn(
        id: 'orders',
        label: t('customers.orders'),
        numeric: true,
        minWidth: 90,
        text: (r) => fmt.fmtNumber(r.customer.ordersCount),
      ),
      DashColumn(
        id: 'spent',
        label: t('customers.totalSpent'),
        numeric: true,
        minWidth: 130,
        text: (r) => fmt.fmtMoney(r.customer.totalSpent),
      ),
      DashColumn(
        id: 'lastVisit',
        label: t('customers.lastVisit'),
        numeric: true,
        minWidth: 120,
        text: (r) => r.customer.lastOrderAt == null
            ? '—'
            : fmt.fmtDate(r.customer.lastOrderAt),
      ),
    ];

    final hasMore = rows.length >= _limit && _limit < customersLimitMax;
    return DashPeopleList<PersonRow>(
      layout: DashPeopleSearchLayout.above,
      searchValue: _q,
      searchPlaceholder: t('customers.searchPlaceholder'),
      onSearchChanged: (v) => _reset(() => _q = v.trim()),
      filters: [
        DashFilterSelect<String>(
          label: t('customers.source.label'),
          allLabel: t('customers.source.all'),
          minWidth: 176,
          options: [
            for (final s in customerSources)
              DashOption(value: s, label: t('customers.source.$s')),
          ],
          value: _source,
          onChanged: (v) => _reset(() => _source = v),
        ),
        _MembersOnlySwitch(
          value: _onlyMembers,
          label: t('customers.membersOnly'),
          onChanged: (v) => _reset(() => _onlyMembers = v),
        ),
      ],
      actions: [
        DashExportButton(
          loading: _exporting,
          enabled: rows.isNotEmpty && !_exporting,
          onExport: () => _export(mode: mode, showBalance: showBalance),
        ),
      ],
      table: (toolbar) => DashDataTable<PersonRow>(
        columns: columns,
        rows: rows,
        rowKey: (r) => r.id,
        loading: loading,
        errorMessage: error,
        onRetry: () => ref.invalidate(customersListProvider(_key)),
        onRowTap: (r) => widget.onOpen(r.id),
        selectedRowKey: widget.openId,
        hideViewOptions: true,
        toolbar: toolbar,
        rowSemanticLabel: (r) => r.name,
        loadMore: DashLoadMore(
          hasMore: hasMore,
          loading: list.isLoading,
          onLoadMore: () => setState(() => _pages++),
        ),
        rowActions: access.canInspectWallet
            ? (context, r) => r.isMember
                  ? DashIconButton(
                      icon: 'wallet',
                      semanticLabel: t('loyalty.googleObject'),
                      onPressed: () => showGoogleObjectDialog(
                        context,
                        memberId: r.id,
                        memberName: r.name,
                      ),
                    )
                  : const SizedBox.shrink()
            : null,
        empty: DashEmptyState(
          icon: 'users',
          title: _filtered ? t('customers.emptySearch') : t('customers.empty'),
          description: _filtered
              ? t('customers.emptySearchHint')
              : t('customers.emptyHint'),
        ),
      ),
    );
  }

  /// The file walks the same endpoint under the same search and filters,
  /// from the top — never the window on screen (SELL-CUS-019/020).
  Future<void> _export({
    required String? mode,
    required bool showBalance,
  }) async {
    final t = ref.read(tProvider);
    final transport = ref.read(transportProvider);
    final exporter = ref.read(exporterProvider);
    final orgId = ref.read(orgIdProvider);
    final key = _key;
    setState(() => _exporting = true);
    try {
      final api = apiWithHeaders(transport, exportRequestHeaders);
      final people = await fetchAllPages<Customer>(
        (offset, limit) async => ExportPage(
          await api.customers.listCustomers(
            q: key.q.isEmpty ? null : key.q,
            member: key.member,
            source: key.source,
            limit: limit,
            offset: offset,
          ),
        ),
      );
      final rows = [for (final p in people) PersonRow(customer: p, mode: mode)];
      String yesNo(bool v) => v ? t('common.yes') : t('common.no');
      final columns = <ExcelColumn<PersonRow>>[
        ExcelColumn(
          header: t('customers.name'),
          accessor: (r) => r.name,
          type: ExcelColumnType.text,
          width: 26,
        ),
        ExcelColumn(
          header: t('customers.phone'),
          accessor: (r) => formatPhoneDisplay(r.phone),
          type: ExcelColumnType.text,
          width: 20,
        ),
        ExcelColumn(
          header: t('customers.member'),
          accessor: (r) => yesNo(r.isMember),
          type: ExcelColumnType.text,
          width: 10,
        ),
        if (showBalance && mode != null) ...[
          ExcelColumn(
            header: t('loyalty.balance'),
            accessor: (r) => r.balance,
            type: ExcelColumnType.integer,
            width: 12,
          ),
          ExcelColumn(
            header: t('loyalty.balanceUnit'),
            accessor: (r) => r.balance != null ? loyaltyUnit(t, mode) : '',
            type: ExcelColumnType.text,
            width: 12,
          ),
        ],
        ExcelColumn(
          header: t('customers.source.label'),
          accessor: (r) => isCustomerSource(r.customer.source)
              ? t('customers.source.${r.customer.source}')
              : '',
          type: ExcelColumnType.text,
          width: 16,
        ),
        ExcelColumn(
          header: t('customers.orders'),
          accessor: (r) => r.customer.ordersCount,
          type: ExcelColumnType.integer,
          width: 10,
        ),
        ExcelColumn(
          header: t('customers.totalSpent'),
          accessor: (r) => r.customer.totalSpent,
          type: ExcelColumnType.money,
          width: 16,
        ),
        ExcelColumn(
          header: t('customers.lastVisit'),
          accessor: (r) => r.customer.lastOrderAt,
          type: ExcelColumnType.date,
          width: 16,
        ),
      ];
      final title = t('customers.title');
      final logo = await _exportLogo(api, orgId);
      if (!mounted) return;
      await runExcelExport(
        context,
        exporter,
        t,
        ExcelConfig(
          filename: 'Madar-Customers',
          logoUrl: logo,
          sheets: [
            ExcelSheet<PersonRow>(
              name: title,
              title: title,
              subtitle: key.q.isEmpty ? null : key.q,
              rows: rows,
              columns: columns,
            ),
          ],
        ),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, peopleErrorMessage(e, t));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

/// The shop's own logo when it is on the branding tier, else null (Madar's)
/// — the web's `useExportLogo`, read through the tier-gated public brand.
Future<String?> _exportLogo(DashboardApi api, String? orgId) async {
  if (orgId == null) return null;
  try {
    final brand = await api.orgs.publicOrgBrand(orgId: orgId);
    return brand.customBranding ? brand.logoUrl : null;
  } on Object {
    return null;
  }
}

/// `exportToExcel`'s toasts around the exporter: "Nothing to export" for no
/// rows; otherwise a loading toast that becomes "Exported N rows" or
/// "Export failed".
Future<void> runExcelExport(
  BuildContext context,
  DashExporter exporter,
  Translator t,
  ExcelConfig config,
) async {
  if (config.sheets.every((s) => s.rowCount == 0)) {
    DashToast.error(context, const ExportNothing().message(t));
    return;
  }
  final toast = DashToast.loading(context, t('excel.generating'));
  final outcome = await exporter.exportToExcel(config);
  // The loading toast becomes the outcome, which then expires as any other.
  toast.update(
    outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
    outcome.message(t),
  );
}

/// "Members only" (`Switch` + `Label`): the whole row toggles.
class _MembersOnlySwitch extends StatelessWidget {
  const _MembersOnlySwitch({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => DashPressable(
    onTap: () => onChanged(!value),
    isButton: false,
    checked: value,
    semanticLabel: label,
    excludeChildSemantics: true,
    pressScale: false,
    builder: (context, s) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IgnorePointer(
          child: DashSwitch(
            value: value,
            onChanged: onChanged,
            semanticLabel: label,
          ),
        ),
        Text(
          label,
          style: DashType.body.copyWith(color: context.madarColors.textPrimary),
        ),
      ],
    ),
  );
}
