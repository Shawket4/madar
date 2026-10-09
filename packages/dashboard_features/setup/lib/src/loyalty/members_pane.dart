/// The members of the programme (the web's `members/members-pane.tsx` over
/// `customers/customers-list.tsx` locked to members, SET-LOY-052 … 063, 082):
/// server search, "Came from", the load-more window, the export, the
/// platform's wallet inspector, and the card a row opens.
///
/// The source follows what the viewer may see: `/customers?member=true` for
/// someone with `customers.view`, the loyalty members endpoint for someone
/// holding only `loyalty.members.list`.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'google_object_dialog.dart';
import 'loyalty_data.dart';
import 'member_sheet.dart';

class MembersPane extends ConsumerStatefulWidget {
  const MembersPane({required this.branchId, super.key});

  /// The branch whose programme a balance is read under (null = the org's).
  final String? branchId;

  @override
  ConsumerState<MembersPane> createState() => _MembersPaneState();
}

class _MembersPaneState extends ConsumerState<MembersPane> {
  String _q = '';
  String? _source;
  int _pages = 1;
  bool _exporting = false;
  String? _openId;

  /// The last window that arrived, shown while a new one loads
  /// (`placeholderData: keepPreviousData`).
  List<PersonRow>? _previous;

  int _limit(MembersSource s) => math.min(
    membersPageSize * _pages,
    s == MembersSource.customers ? customersLimitMax : membersLimitMax,
  );

  MemberCustomersQuery _customersKey({String? source, int? limit}) => (
    q: _q,
    source: source ?? _source,
    limit: limit ?? _limit(MembersSource.customers),
  );

  MembersQuery _membersKey() =>
      (branchId: widget.branchId, q: _q, limit: _limit(MembersSource.members));

  /// A new search or filter starts the window over.
  void _reset(VoidCallback change) => setState(() {
    change();
    _pages = 1;
  });

  Future<void> _open(PersonRow r) async {
    setState(() => _openId = r.id);
    await showMemberSheet(
      context,
      id: r.id,
      name: r.name,
      branchId: widget.branchId,
    );
    if (mounted) setState(() => _openId = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final access = ref.watch(loyaltyAccessProvider);
    final c = context.madarColors;
    final source = membersSourceOf(access);
    if (source == null) {
      return DashEmptyState(
        key: const ValueKey('loyalty-members-restricted'),
        title: t('loyalty.membersRestricted'),
        description: t('loyalty.membersRestrictedHint'),
      );
    }
    final fromCustomers = source == MembersSource.customers;

    // Points or orders, for someone who may read the programme.
    final program = fromCustomers && access.canReadProgram
        ? ref.watch(loyaltySettingsProvider(widget.branchId)).value
        : null;
    final mode = program == null ? null : loyaltyModeOf(program);
    final showBalance = fromCustomers && mode != null;

    final AsyncValue<Object> list;
    List<PersonRow>? data;
    int? total;
    if (fromCustomers) {
      final q = ref.watch(memberCustomersProvider(_customersKey()));
      list = q;
      data = q.value == null
          ? null
          : [for (final cu in q.value!) PersonRow.ofCustomer(cu, mode)];
    } else {
      final q = ref.watch(loyaltyMembersProvider(_membersKey()));
      list = q;
      data = q.value == null
          ? null
          : [for (final m in q.value!.members) PersonRow.ofMember(m)];
      total = q.value?.total;
    }
    if (data != null) _previous = data;
    final failed = list.failedFirst;
    final rows = failed ? const <PersonRow>[] : (data ?? _previous ?? const []);
    final loading = list.awaitingFirst && _previous == null;
    final limit = _limit(source);
    final hasMore =
        rows.length >= limit &&
        limit < (fromCustomers ? customersLimitMax : membersLimitMax);

    Widget dash() =>
        Text('—', style: DashType.body.copyWith(color: c.textSecondary));
    String balanceText(PersonRow r) => r.balance == null || r.mode == null
        ? '—'
        : '${fmt.fmtNumber(r.balance)} ${loyaltyUnit(t, r.mode!, r.balance)}';

    final name = DashColumn<PersonRow>(
      id: 'name',
      label: t('customers.name'),
      phone: DashPhoneRole.title,
      flex: 2,
      minWidth: 180,
      text: (r) => r.name,
      cell: (context, r) => MadarClippedText(
        r.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: autoDirection(r.name),
        style: DashType.bodyMedium.copyWith(color: c.textPrimary),
      ),
    );
    final phone = DashColumn<PersonRow>(
      id: 'phone',
      label: t('customers.phone'),
      minWidth: 164,
      text: (r) => formatPhoneDisplay(r.phone),
      cell: (context, r) => (r.phone ?? '').isEmpty
          ? dash()
          : Text(
              formatPhoneDisplay(r.phone),
              textDirection: TextDirection.ltr,
              maxLines: 1,
              softWrap: false,
              style: DashType.mono.copyWith(
                fontSize: 14,
                color: c.textPrimary,
              ),
            ),
    );
    final balance = DashColumn<PersonRow>(
      id: 'balance',
      label: t('loyalty.balance'),
      numeric: true,
      minWidth: 110,
      text: balanceText,
      cell: (context, r) => r.balance == null || r.mode == null
          ? dash()
          : Text(
              dashFigure(balanceText(r)),
              style: DashType.mono.copyWith(color: c.textPrimary),
            ),
    );
    final columns = fromCustomers
        ? <DashColumn<PersonRow>>[
            name,
            phone,
            if (showBalance) balance,
            DashColumn(
              id: 'source',
              label: t('customers.source.label'),
              phone: DashPhoneRole.hidden,
              minWidth: 120,
              text: (r) => isCustomerSource(r.customer?.source)
                  ? t('customers.source.${r.customer!.source}')
                  : '—',
              cell: (context, r) => isCustomerSource(r.customer?.source)
                  ? Text(
                      t('customers.source.${r.customer!.source}'),
                      style: DashType.body.copyWith(color: c.textSecondary),
                    )
                  : dash(),
            ),
            DashColumn(
              id: 'orders',
              label: t('customers.orders'),
              numeric: true,
              minWidth: 90,
              text: (r) => fmt.fmtNumber(r.customer?.ordersCount ?? 0),
            ),
            DashColumn(
              id: 'spent',
              label: t('customers.totalSpent'),
              numeric: true,
              minWidth: 130,
              text: (r) => fmt.fmtMoney(r.customer?.totalSpent ?? 0),
            ),
            DashColumn(
              id: 'lastVisit',
              label: t('customers.lastVisit'),
              numeric: true,
              minWidth: 120,
              text: (r) => r.customer?.lastOrderAt == null
                  ? '—'
                  : fmt.fmtDate(r.customer!.lastOrderAt),
            ),
          ]
        : <DashColumn<PersonRow>>[
            name,
            phone,
            balance,
            DashColumn(
              id: 'progress',
              label: t('loyalty.progress'),
              minWidth: 150,
              text: (r) => r.member == null
                  ? '—'
                  : r.member!.canRedeem
                  ? t('loyalty.rewardReady')
                  : loyaltyCost(
                      t,
                      r.mode ?? 'points',
                      r.member!.pointsToNextReward,
                    ),
              cell: (context, r) {
                final m = r.member;
                if (m == null) return dash();
                return m.canRedeem
                    ? DashStatusPill(
                        label: t('loyalty.rewardReady'),
                        tone: DashTone.success,
                      )
                    : Text(
                        loyaltyCost(t, r.mode ?? 'points', m.pointsToNextReward),
                        style: DashType.body.copyWith(color: c.textSecondary),
                      );
              },
            ),
            DashColumn(
              id: 'joined',
              label: t('loyalty.joined'),
              numeric: true,
              minWidth: 120,
              text: (r) =>
                  r.member == null ? '—' : fmt.fmtDate(r.member!.enrolledAt),
            ),
          ];

    final filtered = _q.isNotEmpty || _source != null;
    return DashPeopleList<PersonRow>(
      key: const ValueKey('loyalty-members'),
      layout: DashPeopleSearchLayout.above,
      searchValue: _q,
      searchPlaceholder: t('customers.searchPlaceholder'),
      onSearchChanged: (v) => _reset(() => _q = v.trim()),
      filters: [
        if (fromCustomers)
          DashFilterSelect<String>(
            label: t('customers.source.label'),
            allLabel: t('customers.source.all'),
            minWidth: MediaQuery.sizeOf(context).width < DashBreakpoints.sm
                ? double.infinity
                : 176,
            options: [
              for (final s in customerSources)
                DashOption(value: s, label: t('customers.source.$s')),
            ],
            value: _source,
            onChanged: (v) => _reset(() => _source = v),
            onOptionIntent: (v) => ref.warm(
              memberCustomersProvider(
                (q: _q, source: v, limit: membersPageSize),
              ),
            ),
          ),
      ],
      actions: [
        DashExportButton(
          key: const ValueKey('loyalty-members-export'),
          loading: _exporting,
          enabled: rows.isNotEmpty && !_exporting,
          onExport: () =>
              _export(source: source, mode: mode, showBalance: showBalance),
        ),
      ],
      footer: total != null && total > rows.length
          ? DashListCount(
              t('loyalty.showingOf', args: {'shown': rows.length, 'total': total}),
            )
          : null,
      table: (toolbar) => DashDataTable<PersonRow>(
        columns: columns,
        rows: rows,
        rowKey: (r) => r.id,
        loading: loading,
        errorMessage: failed ? errorMessage(list.error, t) : null,
        onRetry: () => fromCustomers
            ? ref.invalidate(memberCustomersProvider(_customersKey()))
            : ref.invalidate(loyaltyMembersProvider(_membersKey())),
        onRowTap: _open,
        onRowIntent: (r) => ref.warm(
          loyaltyMemberProvider((id: r.id, branchId: widget.branchId)),
        ),
        selectedRowKey: _openId,
        hideViewOptions: true,
        toolbar: toolbar,
        rowSemanticLabel: (r) => r.name,
        loadMore: DashLoadMore(
          hasMore: hasMore,
          loading: list.isLoading,
          onLoadMore: () => setState(() => _pages++),
        ),
        rowActions: access.canInspectWallet
            ? (context, r) => DashIconButton(
                icon: 'wallet',
                semanticLabel: t('loyalty.googleObject'),
                onPressed: () => showGoogleObjectDialog(
                  context,
                  memberId: r.id,
                  memberName: r.name,
                ),
              )
            : null,
        empty: DashEmptyState(
          icon: 'users',
          title: filtered ? t('loyalty.noMembersMatch') : t('loyalty.noMembers'),
          description: filtered
              ? t('customers.emptySearchHint')
              : t('loyalty.noMembersHint'),
        ),
      ),
    );
  }

  /// The file walks the same endpoint under the same search and filters,
  /// from the top — never the window on screen.
  Future<void> _export({
    required MembersSource source,
    required String? mode,
    required bool showBalance,
  }) async {
    final t = ref.read(tProvider);
    final transport = ref.read(transportProvider);
    final exporter = ref.read(exporterProvider);
    final q = _q;
    final from = _source;
    final branchId = widget.branchId;
    setState(() => _exporting = true);
    try {
      final api = apiWithHeaders(transport, exportRequestHeaders);
      final List<PersonRow> people;
      if (source == MembersSource.customers) {
        final all = await fetchAllPages<Customer>(
          (offset, limit) async => ExportPage(
            await api.customers.listCustomers(
              q: q.isEmpty ? null : q,
              member: true,
              source: from,
              limit: limit,
              offset: offset,
            ),
          ),
        );
        people = [for (final cu in all) PersonRow.ofCustomer(cu, mode)];
      } else {
        final all = await fetchAllPages<MemberView>((offset, limit) async {
          final page = await api.loyalty.listLoyaltyMembers(
            branchId: branchId,
            q: q.isEmpty ? null : q,
            limit: limit,
            offset: offset,
          );
          return ExportPage(page.members, total: page.total);
        });
        people = [for (final m in all) PersonRow.ofMember(m)];
      }
      final balanceCols = <ExcelColumn<PersonRow>>[
        ExcelColumn(
          header: t('loyalty.balance'),
          accessor: (r) => r.balance,
          type: ExcelColumnType.integer,
          width: 12,
        ),
        ExcelColumn(
          header: t('loyalty.balanceUnit'),
          accessor: (r) =>
              r.mode != null && r.balance != null ? loyaltyUnit(t, r.mode!) : '',
          type: ExcelColumnType.text,
          width: 12,
        ),
      ];
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
        if (source == MembersSource.customers) ...[
          if (showBalance) ...balanceCols,
          ExcelColumn(
            header: t('customers.source.label'),
            accessor: (r) => isCustomerSource(r.customer?.source)
                ? t('customers.source.${r.customer!.source}')
                : '',
            type: ExcelColumnType.text,
            width: 16,
          ),
          ExcelColumn(
            header: t('customers.orders'),
            accessor: (r) => r.customer?.ordersCount ?? 0,
            type: ExcelColumnType.integer,
            width: 10,
          ),
          ExcelColumn(
            header: t('customers.totalSpent'),
            accessor: (r) => r.customer?.totalSpent ?? 0,
            type: ExcelColumnType.money,
            width: 16,
          ),
          ExcelColumn(
            header: t('customers.lastVisit'),
            accessor: (r) => r.customer?.lastOrderAt,
            type: ExcelColumnType.date,
            width: 16,
          ),
        ] else ...[
          ...balanceCols,
          ExcelColumn(
            header: t('loyalty.progress'),
            accessor: (r) => r.member == null
                ? ''
                : r.member!.canRedeem
                ? t('loyalty.rewardReady')
                : loyaltyCost(t, r.mode ?? 'points', r.member!.pointsToNextReward),
            type: ExcelColumnType.text,
            width: 20,
          ),
          ExcelColumn(
            header: t('loyalty.joined'),
            accessor: (r) => r.member?.enrolledAt,
            type: ExcelColumnType.date,
            width: 16,
          ),
        ],
      ];
      final title = t('loyalty.members');
      // `useExportLogo`: the shop's own on the branding tier.
      final brand = ref.read(publicBrandProvider).value;
      final logoUrl = brand?.logoUrl?.trim() ?? '';
      if (!mounted) return;
      if (people.isEmpty) {
        DashToast.error(context, const ExportNothing().message(t));
        return;
      }
      final toast = DashToast.loading(context, t('excel.generating'));
      final outcome = await exporter.exportToExcel(
        ExcelConfig(
          filename: 'Madar-Loyalty-Members',
          logoUrl: brand != null && brand.customBranding && logoUrl.isNotEmpty
              ? logoUrl
              : null,
          sheets: [
            ExcelSheet<PersonRow>(
              name: title,
              title: title,
              subtitle: q.isEmpty ? null : q,
              rows: people,
              columns: columns,
            ),
          ],
        ),
      );
      toast.update(
        outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
        outcome.message(t),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(
          context,
          e is ExportTooLargeError ? e.message(t) : errorMessage(e, t),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
