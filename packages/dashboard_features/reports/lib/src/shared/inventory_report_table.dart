/// The table the inventory-backed reports share (the web's `ReportTable`,
/// `features/inventory/reports-page.tsx:357-387`): Consumption, Shrinkage,
/// Waste and PO lead time on the Inventory reports page (REP-INV-012), and
/// Supplier spend on Financial (REP-FIN-068).
///
/// Every cell is already text; the first column is bold and is the phone
/// card's title; 25 rows a page; no Columns menu; no search; empty →
/// EmptyState (BarChart3) with the page's words.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A header cell: its words and whether the column holds figures.
class ReportHead {
  const ReportHead(this.label, {this.numeric = false});

  final String label;
  final bool numeric;
}

/// A row: a stable key and one text per [ReportHead].
class ReportRow {
  const ReportRow({required this.key, required this.cells});

  final String key;
  final List<String> cells;
}

class InventoryReportTable extends ConsumerWidget {
  const InventoryReportTable({
    required this.head,
    required this.rows,
    required this.emptyTitle,
    this.loading = false,
    this.error,
    this.onRetry,
    super.key,
  });

  final List<ReportHead> head;
  final List<ReportRow> rows;

  /// The empty state's title (`inventory.reports.noDataPeriod` on every
  /// web use).
  final String emptyTitle;
  final bool loading;

  /// The failed load, if any (its words are shown with Retry).
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return DashDataTable<ReportRow>(
      rowKey: (r) => r.key,
      rows: rows,
      loading: loading,
      errorMessage: error == null ? null : errorMessage(error, t),
      onRetry: onRetry,
      pageSize: 25,
      hideViewOptions: true,
      empty: DashEmptyState(icon: 'bar-chart-3', title: emptyTitle),
      columns: [
        for (final (i, h) in head.indexed)
          DashColumn<ReportRow>(
            id: 'c$i',
            label: h.label,
            numeric: h.numeric,
            phone: i == 0 ? DashPhoneRole.title : DashPhoneRole.auto,
            text: (r) => i < r.cells.length ? r.cells[i] : '',
            cell: i == 0
                ? (context, r) => Text(
                    r.cells.isEmpty ? '' : r.cells.first,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  )
                : null,
          ),
      ],
    );
  }
}
