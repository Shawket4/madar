/// The pieces of the Today page (web `today-page.tsx`): its data in one place
/// ([TodayData]), the first-run card, the KPI strip, the low-stock table, and
/// the Arriving today / Today's waste lists.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart'
    show
        BranchStockRow,
        InventoryValuationReport,
        LowStockRow,
        PurchaseOrder,
        StockMovement,
        Stocktake;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../purchasing/purchase_order_dialog.dart';
import '../purchasing/receive_dialog.dart';
import '../shared/inventory_data.dart';
import '../shared/inventory_labels.dart';
import '../shared/inventory_lib.dart';
import '../shared/on_hand.dart';
import '../waste/waste_dialog.dart';
import 'today_providers.dart';

// ── Data ────────────────────────────────────────────────────────────────────

/// Everything Today reads, for the org (and the branch, when one is picked),
/// with the figures the web works out from it (`today-page.tsx:59-81`).
class TodayData {
  TodayData._({
    required this.orgId,
    required this.branchId,
    required this.valuation,
    required this.lowStock,
    required this.orders,
    required this.stock,
    required this.stocktakes,
    required this.waste,
    required this.bounds,
    required this.now,
    required this.retryLowStock,
    required this.retryOrders,
    required this.retryWaste,
  });

  /// Reads what the web reads: branch-scoped endpoints with a branch picked,
  /// the org's roll-ups with all branches; branch stock, counts and waste
  /// only for a branch; orders, suppliers and the catalog always (the last
  /// two warm the purchase-order dialog, as the web passes them in).
  factory TodayData.watch(
    WidgetRef ref, {
    required String orgId,
    required String? branchId,
  }) {
    final bounds = ref.watch(todayBoundsProvider);
    final ordersKey = (orgId: orgId, expectedBefore: bounds.endIso);
    ref.watch(inventorySuppliersProvider(orgId));
    ref.watch(inventoryCatalogProvider(orgId));
    final b = branchId;
    return TodayData._(
      orgId: orgId,
      branchId: b,
      valuation: b != null
          ? ref.watch(todayBranchValuationProvider(b))
          : ref.watch(todayOrgValuationProvider(orgId)),
      lowStock: b != null
          ? ref.watch(todayBranchLowStockProvider(b))
          : ref.watch(todayOrgLowStockProvider(orgId)),
      orders: ref.watch(todayOrdersProvider(ordersKey)),
      stock: b == null ? null : ref.watch(branchStockProvider(b)),
      stocktakes: b == null ? null : ref.watch(stocktakesProvider(b)),
      waste: b == null ? null : ref.watch(todayWasteProvider(b)),
      bounds: bounds,
      now: ref.watch(clockProvider)(),
      retryLowStock: () => b != null
          ? ref.invalidate(todayBranchLowStockProvider(b))
          : ref.invalidate(todayOrgLowStockProvider(orgId)),
      retryOrders: () => ref.invalidate(todayOrdersProvider(ordersKey)),
      retryWaste: () {
        if (b != null) ref.invalidate(todayWasteProvider(b));
      },
    );
  }

  final String orgId;

  /// The picked branch; null = all branches.
  final String? branchId;
  final AsyncValue<InventoryValuationReport> valuation;
  final AsyncValue<List<LowStockRow>> lowStock;
  final AsyncValue<List<PurchaseOrder>> orders;
  final AsyncValue<List<BranchStockRow>>? stock;
  final AsyncValue<List<Stocktake>>? stocktakes;
  final AsyncValue<List<StockMovement>>? waste;
  final TodayBounds bounds;
  final DateTime now;
  final VoidCallback retryLowStock;
  final VoidCallback retryOrders;
  final VoidCallback retryWaste;

  bool get allBranches => branchId == null;

  /// The low-stock rows (none while loading or after a failed read).
  List<LowStockRow> get lowRows => lowStock.value ?? const [];

  /// Rows at or under zero (`on_hand <= 0`).
  int get criticalCount => lowRows.where((r) => r.onHand <= 0).length;

  /// Orders on their way by the end of today, every branch of the org.
  List<PurchaseOrder> get arriving => arrivingOrders(orders.value ?? const []);

  /// Waste the server received today at the picked branch.
  List<StockMovement> get todaysWaste =>
      wasteSince(waste?.value ?? const [], bounds.start);

  /// Rows never counted or counted more than 14 days ago; null for all
  /// branches. A failed read counts no rows (0, not "—").
  int? get countsDueCount => allBranches
      ? null
      : countsDue([
          for (final r in stock?.value ?? const <BranchStockRow>[])
            r.lastCountedAt?.toIso8601String(),
        ], now);

  /// The branch has never finalized a count: only once its counts are in
  /// (not while loading, not after a failed read).
  bool get firstRun {
    final list = stocktakes?.value;
    if (allBranches || list == null) return false;
    return needsFirstCount([for (final s in list) s.status]);
  }
}

// ── First run ───────────────────────────────────────────────────────────────

/// "Start by counting this branch" (INV-TOD-005): the hint and a way into a
/// first count. Text over the button below 640 wide, beside it above.
class TodayFirstRunCard extends ConsumerWidget {
  const TodayFirstRunCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final narrow = MediaQuery.sizeOf(context).width < DashBreakpoints.sm;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        Text(
          t('inventory.today.firstRunTitle'),
          style: DashType.bodyStrong.copyWith(
            fontSize: DashType.sectionTitle.fontSize,
            color: c.textPrimary,
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: DashMetrics.proseWide),
          child: Text(
            t('inventory.today.firstRunHint'),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
    final button = DashButton(
      key: const ValueKey('today-first-count'),
      label: t('inventory.today.startFirstCount'),
      icon: 'clipboard-list',
      expand: narrow,
      onPressed: () => context.go('/inventory/counts'),
    );
    return DashCard(
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [text, button],
            )
          : Row(
              spacing: Space.md,
              children: [
                Expanded(child: text),
                button,
              ],
            ),
    );
  }
}

// ── KPIs ────────────────────────────────────────────────────────────────────

/// Stock value · Low stock · Deliveries · Counts due (INV-TOD-006…010). A
/// failed read never shows here: its figure reads as zero (the sections
/// below carry the errors, INV-TOD-037).
class TodayKpiStrip extends ConsumerWidget {
  const TodayKpiStrip({required this.data, super.key});

  final TodayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final v = data.valuation.value;
    final due = data.countsDueCount;
    return TodayReveal(
      child: DashLedgerStrip(
        items: [
          DashLedgerItem(
            key: 'value',
            label: t('inventory.today.stockValue'),
            icon: 'wallet',
            value: v?.totalValue ?? 0,
            format: DashStatFormat.money,
            loading: data.valuation.firstLoad,
            hint: v == null
                ? null
                : t(
                    'inventory.today.unknownCost',
                    count: v.unknownCostCount,
                  ),
          ),
          DashLedgerItem(
            key: 'low',
            label: t('inventory.today.lowStock'),
            icon: 'alert-triangle',
            tone: DashTone.warning,
            value: data.lowRows.length,
            format: DashStatFormat.number,
            loading: data.lowStock.firstLoad,
            hint: t('inventory.today.critical', count: data.criticalCount),
          ),
          DashLedgerItem(
            key: 'deliveries',
            label: t('inventory.today.deliveries'),
            icon: 'truck',
            value: data.arriving.length,
            format: DashStatFormat.number,
            loading: data.orders.firstLoad,
            hint: t('inventory.today.arrivingToday'),
          ),
          DashLedgerItem(
            key: 'counts',
            label: t('inventory.today.countsDue'),
            icon: 'calendar-clock',
            value: due,
            valueText: due == null ? '—' : null,
            format: DashStatFormat.number,
            loading: !data.allBranches && (data.stock?.firstLoad ?? false),
            hint: t('inventory.today.countsOverdue'),
          ),
        ],
      ),
    );
  }
}

/// Fades the strip up into place once (the web staggers its cards in); still
/// under reduced motion.
class TodayReveal extends StatefulWidget {
  const TodayReveal({required this.child, super.key});

  final Widget child;

  @override
  State<TodayReveal> createState() => _TodayRevealState();
}

class _TodayRevealState extends State<TodayReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DashMotion.slow,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DashMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: DashMotion.ease);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

// ── Low stock ───────────────────────────────────────────────────────────────

/// "Low stock — reorder soon" (INV-TOD-011…016, 035, 036).
class TodayLowStockSection extends ConsumerWidget {
  const TodayLowStockSection({required this.data, super.key});

  final TodayData data;

  /// Room for the row's "Create PO" button.
  static const double actionsWidth = Space.xxl * 5 + Space.lg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final low = data.lowStock;
    final hideCount = low.firstLoad || low.hasError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(
          icon: 'alert-triangle',
          title: t('inventory.today.lowStockHeading'),
          count: hideCount ? null : data.lowRows.length,
          trailing: DashButton(
            key: const ValueKey('today-view-all'),
            label: t('inventory.today.viewAll'),
            variant: DashButtonVariant.ghost,
            size: DashButtonSize.compact,
            trailingIcon: DashIcon.forward(context),
            onPressed: () => context.go('/inventory/ingredients'),
          ),
        ),
        DashDataTable<LowStockRow>(
          key: const ValueKey('today-low-stock'),
          rows: data.lowRows,
          rowKey: lowStockRowKey,
          loading: low.firstLoad,
          errorMessage: low.hasError ? errorMessage(low.error, t) : null,
          onRetry: data.retryLowStock,
          pageSize: 12,
          hideViewOptions: true,
          rowActionsWidth: actionsWidth,
          rowActions: (context, r) => DashButton(
            key: ValueKey('today-create-po-${lowStockRowKey(r)}'),
            label: t('inventory.today.createPo'),
            icon: 'shopping-cart',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: () => openReorderPo(context, r),
          ),
          empty: DashEmptyState(
            icon: 'package-check',
            title: data.firstRun
                ? t('inventory.today.noParsYet')
                : t('inventory.today.allGood'),
          ),
          columns: [
            DashColumn<LowStockRow>(
              id: 'name',
              label: t('inventory.catalog.name'),
              phone: DashPhoneRole.title,
              flex: 2,
              minWidth: 200,
              text: (r) => r.ingredientName,
              cell: (context, r) => _NameCell(row: r),
            ),
            DashColumn<LowStockRow>(
              id: 'branch',
              label: t('inventory.reports.branchName'),
              text: (r) => r.branchName,
            ),
            DashColumn<LowStockRow>(
              id: 'onHand',
              label: t('inventory.today.onHand'),
              numeric: true,
              text: (r) => qtyWithUnit(f, r.onHand, r.unit),
              cell: (context, r) => OnHand(
                qty: r.onHand,
                unit: r.unit,
                style: DashType.mono,
              ),
            ),
            DashColumn<LowStockRow>(
              id: 'par',
              label: t('inventory.today.reorderPoint'),
              numeric: true,
              text: (r) => qtyWithUnit(f, r.parMin, r.unit),
            ),
            DashColumn<LowStockRow>(
              id: 'suggested',
              label: t('inventory.today.suggested'),
              numeric: true,
              text: (r) => qtyWithUnit(f, r.suggestedQty, r.unit),
            ),
            DashColumn<LowStockRow>(
              id: 'supplier',
              label: t('inventory.catalog.supplier'),
              text: (r) => r.supplierName ?? '—',
              cell: (context, r) => MadarClippedText(
                r.supplierName ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: r.supplierName == null
                    ? DashType.body.copyWith(color: c.textSecondary)
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A low-stock row's identity: the same ingredient shows once per branch
/// with all branches (INV-TOD-035).
String lowStockRowKey(LowStockRow r) => '${r.branchId}-${r.orgIngredientId}';

/// "Create PO" on a low-stock row (INV-TOD-013): a new purchase order FOR
/// THE ROW'S BRANCH (with all branches too), the ingredient's default
/// supplier picked and one line of `max(1, ceil(suggested))` stock units.
Future<void> openReorderPo(BuildContext context, LowStockRow r) async {
  await showPurchaseOrderDialog(
    context,
    branchId: r.branchId,
    prefill: PurchaseOrderPrefill(
      supplierId: r.supplierId,
      lines: [
        PurchaseOrderPrefillLine(
          orgIngredientId: r.orgIngredientId,
          quantity: reorderQuantity(r.suggestedQty).toDouble(),
        ),
      ],
    ),
  );
}

/// `Math.max(1, Math.ceil(suggested_qty))`.
int reorderQuantity(double suggested) => math.max(1, suggested.ceil());

class _NameCell extends ConsumerWidget {
  const _NameCell({required this.row});

  final LowStockRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final critical = row.onHand <= 0;
    final base = DefaultTextStyle.of(context).style;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          row.ingredientName,
          style: base.copyWith(fontWeight: FontWeight.w500),
        ),
        critical
            ? DashStatusPill(
                label: t('inventory.today.statusCritical'),
                tone: DashTone.danger,
                icon: 'octagon-x',
                small: true,
              )
            : DashStatusPill(
                label: t('inventory.today.statusLow'),
                tone: DashTone.warning,
                small: true,
              ),
      ],
    );
  }
}

// ── Arriving today ──────────────────────────────────────────────────────────

/// "Arriving today" (INV-TOD-017…021): the first eight orders on their way,
/// each with a way to receive it.
class TodayArrivingSection extends ConsumerWidget {
  const TodayArrivingSection({required this.data, super.key});

  final TodayData data;

  /// How many orders the list shows.
  static const int shown = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final q = data.orders;
    final Widget body;
    if (q.hasError) {
      body = DashErrorState(
        title: t('inventory.today.deliveriesFailed'),
        onRetry: data.retryOrders,
      );
    } else if (q.firstLoad) {
      body = const TodayListSkeleton();
    } else if (data.arriving.isEmpty) {
      body = TodayQuietEmpty(title: t('inventory.today.noDeliveries'));
    } else {
      body = DashListCard(
        key: const ValueKey('today-arriving'),
        children: [
          for (final p in data.arriving.take(shown))
            DashListRow(
              key: ValueKey('today-arriving-${p.id}'),
              icon: 'truck',
              title: '${orderLabel(p)} · ${p.supplierName ?? '—'}',
              meta: ltr(f.fmtDate(p.expectedAt)),
              trailing: DashButton(
                key: ValueKey('today-receive-${p.id}'),
                label: t('inventory.today.receive'),
                icon: 'package-check',
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: () =>
                    showReceiveDialog(context, purchaseOrderId: p.id),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(icon: 'truck', title: t('inventory.today.arriving')),
        body,
      ],
    );
  }
}

/// An order's name in a list: its reference, else `#` and the first eight
/// characters of its id (kept left-to-right in Arabic).
String orderLabel(PurchaseOrder p) {
  final ref = p.reference;
  if (ref != null && ref.isNotEmpty) return ref;
  return ltr('#${p.id.substring(0, math.min(8, p.id.length))}');
}

// ── Today's waste ───────────────────────────────────────────────────────────

/// "Today's waste" (INV-TOD-022…027): what the picked branch logged today
/// and a way to log more.
class TodayWasteSection extends ConsumerWidget {
  const TodayWasteSection({required this.data, super.key});

  final TodayData data;

  /// How many lines the list shows.
  static const int shown = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final branchId = data.branchId;
    final q = data.waste;
    final Widget body;
    if (branchId == null || q == null) {
      body = TodayQuietEmpty(title: t('inventory.pickBranch'));
    } else if (q.hasError) {
      body = DashErrorState(
        title: t('inventory.today.wasteFailed'),
        onRetry: data.retryWaste,
      );
    } else if (q.firstLoad) {
      body = const TodayListSkeleton();
    } else if (data.todaysWaste.isEmpty) {
      body = TodayQuietEmpty(title: t('inventory.today.noWasteToday'));
    } else {
      body = DashListCard(
        key: const ValueKey('today-waste'),
        children: [
          for (final m in data.todaysWaste.take(shown))
            DashListRow(
              key: ValueKey('today-waste-${m.id}'),
              variant: DashListRowVariant.ledger,
              signIn: false,
              title: m.ingredientName,
              meta: (m.reason ?? '').isEmpty
                  ? null
                  : wasteReasonLabel(t, m.reason!),
              value: qtyWithUnit(f, m.quantity.abs(), m.unit),
              numericValue: true,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSectionHeader(
          icon: 'trash-2',
          title: t('inventory.today.todaysWaste'),
          trailing: DashButton(
            key: const ValueKey('today-log-waste'),
            label: t('inventory.today.logWaste'),
            icon: 'trash-2',
            variant: DashButtonVariant.outline,
            size: DashButtonSize.compact,
            onPressed: branchId == null
                ? null
                : () => showRecordWasteDialog(context, branchId: branchId),
          ),
        ),
        body,
      ],
    );
  }
}

// ── States ──────────────────────────────────────────────────────────────────

/// A list's loading rows (the web's `ListSkeleton`): three rows of a glyph
/// tile and two bars.
class TodayListSkeleton extends StatelessWidget {
  const TodayListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    return DashListCard(
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            constraints: const BoxConstraints(minHeight: DashMetrics.listRow),
            padding: EdgeInsets.symmetric(
              horizontal: wide ? Space.card : Space.lg,
              vertical: Space.sm + DashMetrics.hair,
            ),
            child: const Row(
              spacing: Space.md,
              children: [
                DashSkeleton(
                  width: Space.xxl + Space.xs,
                  height: Space.xxl + Space.xs,
                  radius: Radii.sm,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs + DashMetrics.hair,
                    children: [
                      DashSkeleton(width: Space.xxl * 5),
                      DashSkeleton(width: Space.xxl * 3, height: Space.md),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The web's compact `EmptyState` (`py-8`): a framed sentence, no glyph.
class TodayQuietEmpty extends StatelessWidget {
  const TodayQuietEmpty({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.xxl,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: DashType.sectionTitle.copyWith(color: c.textPrimary),
      ),
    );
  }
}
