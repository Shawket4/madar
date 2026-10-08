/// The Sessions tab (REP-TIL-008 … -016, -024): one row per till session,
/// the drawer reconciliation a manager reads at the end of a day.
///
/// The cash columns add up on purpose: Opening + Net cash + Pay-ins −
/// Pay-outs − Cash drops + Adjustments is Expected, so a variance is always
/// traceable to a line above it.
///
/// - Every column is labelled (the Columns menu lists all 17; the phone card
///   names each field), the first, Business date, titles the phone card.
/// - The search matches what each column READS (the web's global filter):
///   teller and branch names, the branch code, `YYYY-MM-DD` business dates,
///   ISO timestamps and piastre figures, never the formatted text.
/// - 50 rows a page.
/// - A money figure that is not known yet reads "—", never zero.
library;

import 'package:dashboard_api/dashboard_api.dart' show TillSessionRow;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/report_shared.dart';
import 'tills_lib.dart';
import 'tills_parts.dart';

/// The key of one cell (`till:<till_id>:<column id>`), for tests and the
/// screen reader's order.
ValueKey<String> tillCellKey(String tillId, String column) =>
    ValueKey('till:$tillId:$column');

class TillSessionsTable extends ConsumerWidget {
  const TillSessionsTable({required this.load, super.key});

  final TillsLoad load;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;

    Widget plain(TillSessionRow r, String id, String text) => KeyedSubtree(
      key: tillCellKey(r.tillId, id),
      child: MadarClippedText(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );

    Widget figure(TillSessionRow r, String id, String text) => KeyedSubtree(
      key: tillCellKey(r.tillId, id),
      child: Text(dashFigure(text), maxLines: 1, softWrap: false),
    );

    // Unknown (null) reads as no match, as the web's accessor hands the
    // filter `undefined`.
    String raw(Object? v) => v == null ? '' : '$v';

    DashColumn<TillSessionRow> money(
      String id,
      String label,
      int? Function(TillSessionRow r) value,
    ) => DashColumn<TillSessionRow>(
      id: id,
      label: label,
      numeric: true,
      minWidth: 128,
      text: (r) => raw(value(r)),
      cell: (context, r) => figure(r, id, f.fmtMoney(value(r))),
    );

    final columns = <DashColumn<TillSessionRow>>[
      DashColumn(
        id: 'business_date',
        label: t('reports.tills.businessDate'),
        minWidth: 136,
        phone: DashPhoneRole.title,
        text: (r) => r.businessDate,
        cell: (context, r) =>
            plain(r, 'business_date', fmtBusinessDate(f, r.businessDate)),
      ),
      DashColumn(
        id: 'branch_name',
        label: t('reports.tills.branch'),
        minWidth: 128,
        text: (r) => r.branchName,
        cell: (context, r) => plain(r, 'branch_name', r.branchName),
      ),
      DashColumn(
        id: 'branch_code',
        label: t('reports.tills.branchRef'),
        minWidth: 112,
        text: (r) => r.branchCode,
        // REP-TIL-013: a branch with no code.
        cell: (context, r) =>
            plain(r, 'branch_code', r.branchCode.isEmpty ? '—' : r.branchCode),
      ),
      DashColumn(
        id: 'teller_name',
        label: t('reports.tills.user'),
        minWidth: 144,
        text: (r) => r.tellerName,
        cell: (context, r) => plain(r, 'teller_name', r.tellerName),
      ),
      DashColumn(
        id: 'opened_at',
        label: t('reports.tills.openedAt'),
        minWidth: 160,
        text: (r) => isoString(r.openedAt),
        cell: (context, r) => plain(r, 'opened_at', f.fmtDateTime(r.openedAt)),
      ),
      money(
        'opening_cash',
        t('reports.tills.openingAmount'),
        (r) => r.openingCash,
      ),
      money(
        'net_cash_payment',
        t('reports.tills.netCash'),
        (r) => r.netCashPayment,
      ),
      money('pay_ins', t('reports.tills.payIns'), (r) => r.payIns),
      money('pay_outs', t('reports.tills.payOuts'), (r) => r.payOuts),
      money('cash_drops', t('reports.tills.cashDrops'), (r) => r.cashDrops),
      // REP-TIL-011: corrections that name no pay-in, pay-out or drop;
      // always signed, part of the add-up.
      DashColumn(
        id: 'cash_adjustments',
        label: t('reports.tills.adjustments'),
        numeric: true,
        minWidth: 128,
        text: (r) => raw(r.cashAdjustments),
        cell: (context, r) =>
            figure(r, 'cash_adjustments', f.fmtMoneySigned(r.cashAdjustments)),
      ),
      money(
        'closing_cash_declared',
        t('reports.tills.closingAmount'),
        (r) => r.closingCashDeclared,
      ),
      money(
        'closing_cash_system',
        t('reports.tills.expectedAmount'),
        (r) => r.closingCashSystem,
      ),
      // REP-TIL-010.
      DashColumn(
        id: 'cash_discrepancy',
        label: t('reports.tills.variance'),
        numeric: true,
        minWidth: 136,
        text: (r) => raw(r.cashDiscrepancy),
        cell: (context, r) => KeyedSubtree(
          key: tillCellKey(r.tillId, 'cash_discrepancy'),
          child: TillVariance(value: r.cashDiscrepancy),
        ),
      ),
      DashColumn(
        id: 'orders_count',
        label: t('reports.tills.orders'),
        numeric: true,
        minWidth: 96,
        text: (r) => raw(r.ordersCount),
        cell: (context, r) =>
            figure(r, 'orders_count', f.fmtNumber(r.ordersCount)),
      ),
      money('net_sales', t('reports.tills.sales'), (r) => r.netSales),
      // REP-TIL-012.
      DashColumn(
        id: 'closed_at',
        label: t('reports.tills.closedAt'),
        minWidth: 216,
        text: (r) => r.closedAt == null ? '' : isoString(r.closedAt!),
        cell: (context, r) {
          final closed = r.closedAt;
          final Widget child;
          if (isOpen(r) || closed == null) {
            child = TillOutlineBadge(t('reports.tills.stillOpen'));
          } else {
            child = Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(f.fmtDateTime(closed), maxLines: 1, softWrap: false),
                // No teller count behind this close, which is why Declared
                // and Variance are blank: say so rather than a silent dash.
                if (isForceClosed(r))
                  TillOutlineBadge(t('reports.tills.forceClosed')),
              ],
            );
          }
          return KeyedSubtree(
            key: tillCellKey(r.tillId, 'closed_at'),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: c.textPrimary),
              child: child,
            ),
          );
        },
      ),
    ];

    return DashDataTable<TillSessionRow>(
      columns: columns,
      rows: load.rows,
      rowKey: (r) => r.tillId,
      loading: load.loading,
      errorMessage: load.error,
      onRetry: load.onRetry,
      pageSize: 50,
      searchPlaceholder: t('reports.tills.search'),
      empty: DashEmptyState(title: t('reports.tills.empty')),
    );
  }
}

/// A variance figure: "—" when unknown; zero unsigned; short in a
/// destructive tint with a true minus, over in a warning tint with a plus.
/// The tint is never the only carrier: the sign says which, and so does a
/// word for a screen reader ("Short" / "Over").
class TillVariance extends ConsumerWidget {
  const TillVariance({required this.value, super.key});

  final int? value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final v = value;
    if (v == null) return const Text('—', maxLines: 1);
    final shown = dashFigure(f.fmtMoneySigned(v));
    if (v == 0) return Text(shown, maxLines: 1, softWrap: false);
    final short = v < 0;
    // Pulled halfway to the foreground: the raw tokens are too light to read
    // at this size.
    final tone = Color.lerp(short ? c.danger : c.warning, c.textPrimary, 0.5);
    final word = short ? t('tills.short') : t('tills.over');
    return Semantics(
      label: '$word ${f.fmtMoneySigned(v)}',
      excludeSemantics: true,
      child: Text(
        shown,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(color: tone, fontWeight: FontWeight.w500),
      ),
    );
  }
}
