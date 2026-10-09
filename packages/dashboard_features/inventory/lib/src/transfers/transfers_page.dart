/// Transfers (`/inventory/transfers`, INV-TRF-001…012, INV-ALL-027/028; web
/// `transfers-page.tsx` at af50aa63): the transfer documents touching the
/// scoped location (or every location the person works at), by status and
/// direction, and the org's received differences. A row opens the transfer
/// drawer; "New transfer" and, at a warehouse, "Replenish a branch" open the
/// transfer and replenish dialogs.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show
        Branch,
        BranchKind,
        StockTransfer,
        StockTransferLine,
        TransferDifferenceRow,
        TransferLineInput,
        TransferLocation;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_export.dart';
import '../shared/inventory_labels.dart';
import 'replenish_dialog.dart';
import 'transfer_dialog.dart';
import 'transfer_drawer.dart';
import 'transfers_data.dart';

/// The page's own view of the org (INV-TRF-002): the active locations this
/// person works at (warehouses included on Inventory), none without an org.
List<Branch> transferBranches(WidgetRef ref) => ref.watch(orgIdProvider) == null
    ? const []
    : ref.watch(activeBranchesProvider) ?? const [];

class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends ConsumerState<TransfersPage> {
  /// The status tab and the direction (null = both ways); per visit.
  String _tab = 'all';
  String? _dir;
  bool _exporting = false;

  TransfersKey _key(Scope s, {String? tab, String? dir}) =>
      s.transfersKey(direction: dir ?? _dir, status: tabStatus(tab ?? _tab));

  /// INV-TRF-007: every page of the list (same scope, direction and status),
  /// one row per line, as `Madar-Transfers-<date>.xlsx`.
  Future<void> _export(TransfersKey key) async {
    final t = ref.read(tProvider);
    final transport = ref.read(transportProvider);
    setState(() => _exporting = true);
    try {
      final rows = await fetchAllTransfers(transport, key);
      if (!mounted) return;
      await inventoryExportExcel(context, ref, _config(t, rows));
    } on ExportTooLargeError catch (e) {
      if (mounted) DashToast.error(context, e.message(t));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  ExcelConfig _config(Translator t, List<StockTransfer> rows) {
    final flat = [
      for (final tr in rows)
        for (final l in tr.lines) (tr: tr, l: l),
    ];
    ExcelColumn<Object?> col(
      String header,
      Object? Function(StockTransfer tr, StockTransferLine l) value,
      ExcelColumnType type,
      double width,
    ) => ExcelColumn<Object?>(
      header: header,
      accessor: (r) {
        final row = r! as ({StockTransfer tr, StockTransferLine l});
        return value(row.tr, row.l);
      },
      type: type,
      width: width,
    );
    const text = ExcelColumnType.text, number = ExcelColumnType.number;
    return ExcelConfig(
      filename: 'Madar-Transfers',
      logoUrl: inventoryExportLogo(ref),
      sheets: [
        ExcelSheet<Object?>(
          name: t('inventory.transfers.title'),
          title: t('inventory.transfers.title'),
          rows: flat,
          columns: [
            col(
              t('inventory.transfers.reference'),
              (tr, _) => tr.reference,
              text,
              10,
            ),
            col(
              t('common.date'),
              (tr, _) => tr.created.at,
              ExcelColumnType.dateTime,
              20,
            ),
            col(
              t('common.status'),
              (tr, _) => transferStatusLabel(t, tr.status.value),
              text,
              12,
            ),
            col(
              t('inventory.transfers.from'),
              (tr, _) => tr.sourceBranchName,
              text,
              22,
            ),
            col(
              t('inventory.transfers.to'),
              (tr, _) => tr.destinationBranchName,
              text,
              22,
            ),
            col(
              t('inventory.transfers.ingredient'),
              (_, l) => l.ingredientName,
              text,
              26,
            ),
            col(t('inventory.transfers.sent'), (_, l) => l.qtySent, number, 10),
            col(
              t('inventory.transfers.received'),
              (_, l) => l.qtyReceived,
              number,
              10,
            ),
            col(
              t('inventory.catalog.unit'),
              (_, l) => fmtUnit(l.unit),
              text,
              8,
            ),
            col(
              t('inventory.transfers.note'),
              (tr, _) => tr.note ?? '',
              text,
              30,
            ),
          ],
        ),
      ],
    );
  }

  /// INV-TRF-009: the drawer on [tr], kept open after a step moves it out
  /// of the current tab.
  void _open(StockTransfer tr) => showTransferDrawer(
    context,
    transfer: tr,
    listKey: _key(ref.read(currentScopeProvider)),
  );

  /// INV-TRF-003/040: the transfer dialog in send mode from "here"; its
  /// result opens in the drawer.
  Future<void> _newTransfer(
    Branch? here, {
    String? dest,
    List<TransferLineInput>? lines,
  }) async {
    final tr = await showTransferDialog(
      context,
      defaultSourceId: here?.id,
      defaultDestinationId: dest,
      prefillLines: lines,
    );
    if (tr != null && mounted) _open(tr);
  }

  /// INV-TRF-004/040: the replenish dialog; its picked lines open the
  /// transfer dialog from the warehouse.
  Future<void> _replenish(
    Branch here,
    List<({String id, String name})> to,
  ) async {
    final pick = await showReplenishDialog(
      context,
      warehouse: here,
      branches: to,
    );
    if (pick != null && mounted) {
      await _newTransfer(here, dest: pick.dest, lines: pick.lines);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final scope = ref.watch(currentScopeProvider);
    final orgId = scope.orgId;
    final active = transferBranches(ref);
    final here = active.firstWhereOrNull((b) => b.id == scope.branchId);
    final canCreate = ref.watch(
      authzProvider.select((a) => a.can(Cap.inventoryTransfersCreate)),
    );
    // Only with the cap (INV-TRF-041): someone who cannot send never asks.
    final locations = orgId != null && canCreate
        ? ref.watch(transferLocationsProvider(orgId)).value
        : null;
    final selling = [
      for (final l in locations ?? const <TransferLocation>[])
        if (l.kind == 'branch') (id: l.id, name: l.name),
    ];
    final canCreateHere =
        here != null &&
        (ref.watch(authzAtProvider(here.id)).value ?? Authz.none).can(
          Cap.inventoryTransfersCreate,
        );
    final diffTab = _tab == 'differences';
    final key = _key(scope);
    final list = diffTab ? null : ref.watch(transfersProvider(key));
    final dkey = scope.differencesKey;
    final diffs = diffTab && dkey != null
        ? ref.watch(transferDifferencesProvider(dkey))
        : null;
    final rows = list?.value ?? const <StockTransfer>[];

    /// The dialog's first reads in send mode from "here".
    void warmNew() {
      if (here == null) return;
      ref
        ..warm(branchStockProvider(here.id))
        ..warm(authzAtProvider(here.id));
    }

    return DashPageScaffold(
      title: t('inventory.transfers.title'),
      actions: [
        DashExportButton(
          key: const ValueKey('transfers-export'),
          loading: _exporting,
          enabled: !diffTab && rows.isNotEmpty,
          onExport: () => _export(key),
        ),
        if (here != null &&
            here.kind == BranchKind.warehouse &&
            canCreateHere &&
            selling.isNotEmpty)
          DashButton(
            key: const ValueKey('transfers-replenish'),
            label: t('inventory.transfers.replenish'),
            // ponytail: the kit has no package-search glyph; `package` stands in.
            icon: 'package',
            variant: DashButtonVariant.outline,
            onIntent: selling.length == 1
                ? () => ref.warm(
                    replenishmentProvider((
                      warehouseId: here.id,
                      branchId: selling.single.id,
                    )),
                  )
                : null,
            onPressed: () => _replenish(here, selling),
          ),
        if (canCreate)
          DashButton(
            key: const ValueKey('transfers-new'),
            label: t('inventory.transfers.create'),
            icon: 'plus-circle',
            onIntent: warmNew,
            onPressed: () => _newTransfer(here),
          ),
      ],
      filters: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DashSegmentedControl<String>(
            key: const ValueKey('transfers-status'),
            value: _tab,
            semanticLabel: t('common.status'),
            options: [
              for (final s in transferTabs)
                DashOption(
                  value: s,
                  label: switch (s) {
                    'all' => t('inventory.transfers.all'),
                    'differences' => t('inventory.transfers.differences'),
                    _ => transferStatusLabel(t, s),
                  },
                ),
            ],
            onIntent: (s) {
              if (s != 'differences') {
                ref.warm(transfersProvider(_key(scope, tab: s)));
              } else if (dkey != null) {
                ref.warm(transferDifferencesProvider(dkey));
              }
            },
            onChanged: (s) => setState(() => _tab = s),
          ),
          if (!diffTab)
            DashSegmentedControl<String?>(
              key: const ValueKey('transfers-direction'),
              value: _dir,
              semanticLabel: t('inventory.transfers.direction'),
              options: [
                for (final d in transferDirections)
                  DashOption(
                    value: d,
                    label: t('inventory.transfers.${d ?? 'bothWays'}'),
                  ),
              ],
              onIntent: (d) => ref.warm(
                transfersProvider(
                  scope.transfersKey(direction: d, status: tabStatus(_tab)),
                ),
              ),
              onChanged: (d) => setState(() => _dir = d),
            ),
        ],
      ),
      body: diffTab
          ? DifferencesTable(
              rows: diffs?.value ?? const [],
              loading: diffs?.awaitingFirst ?? false,
              errorText: diffs != null && diffs.failedFirst
                  ? errorMessage(diffs.error, t)
                  : null,
              onRetry: () => ref.invalidate(transferDifferencesProvider(dkey!)),
            )
          : TransfersTable(
              rows: rows,
              loading: list!.awaitingFirst,
              // Kept while Retry runs (no false "No transfers found" between).
              errorText: list.failedFirst ? errorMessage(list.error, t) : null,
              onRetry: () => ref.invalidate(transfersProvider(key)),
              onOpen: _open,
              onIntent: (tr) => warmDrawer(ref, tr),
            ),
    );
  }
}

/// A route `<source> → <destination>`, a Warehouse glyph before a warehouse
/// side when [kinds], the arrow mirrored in RTL.
class TransferRoute extends StatelessWidget {
  const TransferRoute({
    required this.source,
    required this.destination,
    this.sourceWarehouse = false,
    this.destinationWarehouse = false,
    this.style,
    super.key,
  });

  final String source;
  final String destination;
  final bool sourceWarehouse;
  final bool destinationWarehouse;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    Widget glyph(String name) =>
        DashIcon(name, size: IconSize.xs, color: c.textMuted);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.xs,
      runSpacing: Space.xs,
      children: [
        if (sourceWarehouse) glyph('warehouse'),
        Text(source, style: style),
        glyph(DashIcon.arrowForward(context)),
        if (destinationWarehouse) glyph('warehouse'),
        Text(destination, style: style),
      ],
    );
  }
}

/// The list (INV-TRF-008/010/012): Ref, Date, Direction, Items, Status; 10
/// a page; a row opens the drawer. Below 760 each row is a card led by the
/// reference.
class TransfersTable extends ConsumerWidget {
  const TransfersTable({
    required this.rows,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    required this.onOpen,
    required this.onIntent,
    super.key,
  });

  final List<StockTransfer> rows;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;
  final ValueChanged<StockTransfer> onOpen;
  final ValueChanged<StockTransfer> onIntent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return DashDataTable<StockTransfer>(
      key: const ValueKey('transfers-table'),
      rows: rows,
      rowKey: (tr) => tr.id,
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      onRowTap: onOpen,
      onRowIntent: onIntent,
      empty: DashEmptyState(
        icon: 'arrow-left-right',
        title: t('inventory.transfers.noTransfers'),
      ),
      columns: [
        DashColumn(
          id: 'reference',
          label: t('inventory.transfers.reference'),
          cell: (context, tr) => Text(
            tr.reference,
            style: DashType.mono.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          phone: DashPhoneRole.title,
          width: Space.xxl * 3,
        ),
        DashColumn(
          id: 'date',
          label: t('common.date'),
          cell: (context, tr) => Text(f.fmtDateTime(transferWhen(tr))),
          numeric: true,
          align: DashAlign.start,
          // "30 Sept, 12:15 PM" uncut, as the web's nowrap cell.
          width: Space.xxl * 6,
        ),
        DashColumn(
          id: 'route',
          label: t('inventory.transfers.direction'),
          cell: (context, tr) => TransferRoute(
            source: tr.sourceBranchName,
            destination: tr.destinationBranchName,
            sourceWarehouse: tr.sourceKind == BranchKind.warehouse,
            destinationWarehouse: tr.destinationKind == BranchKind.warehouse,
          ),
          minWidth: Space.xxl * 6,
        ),
        DashColumn(
          id: 'items',
          label: t('inventory.transfers.items'),
          cell: (context, tr) => MadarClippedText(
            lineSummary(f, tr),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          minWidth: Space.xxl * 6,
        ),
        DashColumn(
          id: 'status',
          label: t('common.status'),
          cell: (context, tr) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashStatusPill(
              label: transferStatusLabel(t, tr.status.value),
              tone: transferTone(tr.status.value),
            ),
          ),
          width: Space.xxl * 4 + Space.lg,
        ),
      ],
    );
  }
}

/// The Differences tab (INV-TRF-011): received lines that differ from what
/// was sent; no row click.
class DifferencesTable extends ConsumerWidget {
  const DifferencesTable({
    required this.rows,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    super.key,
  });

  final List<TransferDifferenceRow> rows;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return DashDataTable<TransferDifferenceRow>(
      key: const ValueKey('transfers-differences'),
      rows: rows,
      rowKey: (r) => '${r.transferId}:${r.orgIngredientId}',
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      empty: DashEmptyState(
        icon: 'arrow-left-right',
        title: t('inventory.transfers.noDifferences'),
        description: t('inventory.transfers.noDifferencesHint'),
      ),
      columns: [
        DashColumn(
          id: 'reference',
          label: t('inventory.transfers.reference'),
          cell: (context, r) => Text(
            r.reference,
            style: DashType.mono.copyWith(color: c.textPrimary),
          ),
          phone: DashPhoneRole.title,
          width: Space.xxl * 3,
        ),
        DashColumn(
          id: 'received_at',
          label: t('inventory.transfers.received'),
          cell: (context, r) => Text(f.fmtDateTime(r.receivedAt)),
          numeric: true,
          align: DashAlign.start,
          width: Space.xxl * 6,
        ),
        DashColumn(
          id: 'route',
          label: t('inventory.transfers.direction'),
          cell: (context, r) => TransferRoute(
            source: r.sourceBranchName,
            destination: r.destinationBranchName,
          ),
          minWidth: Space.xxl * 6,
        ),
        DashColumn(
          id: 'ingredient_name',
          label: t('inventory.transfers.ingredient'),
          cell: (context, r) => Text(r.ingredientName),
          minWidth: Space.xxl * 5,
        ),
        DashColumn(
          id: 'difference',
          label: t('inventory.transfers.difference'),
          cell: (context, r) => Text(
            '${r.difference > 0 ? '+' : ''}'
            '${qtyWithUnit(f, r.difference, r.unit)}',
          ),
          numeric: true,
          width: Space.xxl * 4,
        ),
        DashColumn(
          id: 'value_difference',
          label: t('inventory.transfers.value'),
          cell: (context, r) =>
              Text(f.fmtMoney(r.valueDifference, signed: true)),
          numeric: true,
          width: Space.xxl * 4,
        ),
        DashColumn(
          id: 'note',
          label: t('inventory.transfers.note'),
          cell: (context, r) => Text(r.note ?? '—'),
          minWidth: Space.xxl * 5,
        ),
      ],
    );
  }
}
