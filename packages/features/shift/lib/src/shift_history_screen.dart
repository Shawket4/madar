/// Past shifts — the branch's shifts on the spec's one table
/// (docs/design/SPEC.md §8, §15): Teller, Opened, Length, Declared,
/// Difference, Status, a print tile for the shift's Z report, and each row
/// expanding to that shift's orders in the SAME table Orders uses
/// ([OrdersTable]) — so a sale reads the same under a shift as it does in
/// Orders.
///
/// The locally-open shift is pinned on top (the natives'
/// `shiftsWithLocalOpen`). All data and rules live in the core; state lives
/// in [shiftHistoryProvider]; this screen renders.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart' show ReceiptSheet;
import 'package:feature_history/feature_history.dart' show OrdersTable;
import 'package:feature_shift/src/shift_providers.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The branch's shift history, pushed from the Till. The header's back pops
/// it via `Navigator.maybePop`.
class ShiftHistoryScreen extends ConsumerWidget {
  /// Creates the shift-history screen.
  const ShiftHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final toast = ref.watch(shiftHistoryProvider.select((s) => s.toast));
    final branch = bridge.deviceConfig().branchName?.trim() ?? '';
    return MadarPageScaffold(
      title: t('shifts.title'),
      subtitle: branch.isEmpty ? null : branch,
      width: MadarContentWidth.reading,
      body: const Padding(
        padding: EdgeInsetsDirectional.only(bottom: Space.xl),
        // Loose, so the card hugs its rows instead of filling the page.
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: _ShiftsTable(),
        ),
      ),
      overlay: ToastHost(
        toast,
        onDismiss: (id) =>
            ref.read(shiftHistoryProvider.notifier).dismissToast(id),
      ),
    );
  }
}

/// The natives' `shiftsWithLocalOpen`: prepend the locally-opened-but-
/// unsynced shift if it isn't already on the page, so the live shift always
/// shows.
List<ShiftSummaryView> _rowsWithLocalOpen(
  List<ShiftSummaryView> shifts,
  ShiftView? live,
) {
  if (live == null || !live.isOpen || shifts.any((s) => s.id == live.id)) {
    return shifts;
  }
  final pinned = ShiftSummaryView(
    id: live.id,
    tellerName: live.tellerName,
    openedAt: live.openedAt,
    openingCashMinor: live.openingCashMinor,
    status: live.status,
    isOpen: live.isOpen,
  );
  return [pinned, ...shifts];
}

/// A shift's state as a pill: open, force-closed, or — once counted —
/// balanced, short or over by its declared difference.
MadarStatus shiftStatus(MadarBridge bridge, ShiftSummaryView s) {
  String t(String key) => bridge.tr(key: key);
  if (s.isOpen) {
    return MadarStatus(t('shifts.open_now'), tone: MadarTone.accent);
  }
  if (s.status == 'force_closed') {
    return MadarStatus(t('shifts.force_closed'), tone: MadarTone.danger);
  }
  final d = s.discrepancyMinor;
  if (d == null) return MadarStatus(t('shifts.closed'));
  if (d == 0) {
    return MadarStatus(t('shifts.balanced'), tone: MadarTone.success);
  }
  return d < 0
      ? MadarStatus(t('shifts.short'), tone: MadarTone.danger)
      : MadarStatus(t('shifts.over'), tone: MadarTone.warning);
}

/// The one table. Rows expand to the shift's orders, loaded on first open.
class _ShiftsTable extends ConsumerWidget {
  const _ShiftsTable();

  /// Open a shift's Z report in the shared sheet — the live shift loads the
  /// current report in-sheet; a past one is fetched first (a spinner in its
  /// print tile, a toast on failure).
  Future<void> _openReport(
    BuildContext context,
    WidgetRef ref,
    ShiftSummaryView s,
  ) async {
    final state = ref.read(shiftHistoryProvider);
    if (state.reportLoadingId != null) return;
    if (s.isOpen && s.id == state.live?.id) {
      await showMadarSheet<void>(
        context,
        size: SheetSize.large,
        builder: (_) => const ShiftReportSheet(),
      );
      return;
    }
    final report = await ref
        .read(shiftHistoryProvider.notifier)
        .fetchReport(s.id);
    if (report == null || !context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ShiftReportSheet(report: report, shiftId: s.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final shifts = ref.watch(shiftHistoryProvider.select((s) => s.shifts));
    final live = ref.watch(shiftHistoryProvider.select((s) => s.live));
    final loading = ref.watch(shiftHistoryProvider.select((s) => s.loading));
    final loadError = ref.watch(
      shiftHistoryProvider.select((s) => s.loadError),
    );
    final reportLoadingId = ref.watch(
      shiftHistoryProvider.select((s) => s.reportLoadingId),
    );
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final notifier = ref.read(shiftHistoryProvider.notifier);
    final rows = _rowsWithLocalOpen(shifts, live);

    final MadarTableState<ShiftSummaryView> state;
    if (loading && rows.isEmpty) {
      state = const MadarTableState.loading();
    } else if (loadError != null && shifts.isEmpty) {
      state = MadarTableState.error(
        message: loadError.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: () => unawaited(notifier.load()),
      );
    } else {
      state = MadarTableState.data(rows);
    }

    String money(int? minor, {bool signed = false}) => minor == null
        ? '—'
        : bridge.formatMoney(minor: minor, currency: currency, signed: signed);

    return MadarDataTable<ShiftSummaryView>(
      columns: [
        MadarColumn(
          id: 'teller',
          label: t('shift.teller'),
          text: (s) => s.tellerName ?? '—',
          flex: 2,
          emphasis: true,
          phone: MadarPhoneRole.title,
        ),
        MadarColumn(
          id: 'opened',
          label: t('shift.opened_at'),
          text: (s) => bridge.formatStamp(rfc3339: s.openedAt),
          flex: 3,
          mono: true,
          muted: true,
          phone: MadarPhoneRole.meta,
        ),
        MadarColumn(
          id: 'length',
          label: t('shifts.length'),
          text: (s) => s.closedAt == null
              ? bridge.formatElapsedSince(rfc3339: s.openedAt)
              : bridge.formatElapsed(
                  secs: DateTime.parse(
                    s.closedAt!,
                  ).difference(DateTime.parse(s.openedAt)).inSeconds,
                ),
          width: 104,
          mono: true,
          priority: 2,
          phone: MadarPhoneRole.meta,
        ),
        MadarColumn(
          id: 'declared',
          label: t('shifts.declared'),
          text: (s) => money(s.closingDeclaredMinor),
          width: 144,
          align: MadarColumnAlign.end,
          mono: true,
          priority: 1,
          phone: MadarPhoneRole.value,
        ),
        MadarColumn(
          id: 'difference',
          label: t('shift.difference'),
          text: (s) => money(s.discrepancyMinor, signed: true),
          width: 128,
          align: MadarColumnAlign.end,
          mono: true,
          muted: true,
          priority: 3,
          phone: MadarPhoneRole.hidden,
        ),
        MadarColumn.status(
          id: 'status',
          label: t('history.col_status'),
          status: (s) => shiftStatus(bridge, s),
          width: 128,
        ),
      ],
      state: state,
      rowKey: (s) => s.id,
      empty: MadarEmptyContent(
        icon: 'clock.arrow.circlepath',
        title: t('shifts.empty'),
        message: t('shifts.empty_message'),
      ),
      rail: (s) => switch (shiftStatus(bridge, s).tone) {
        MadarTone.danger => MadarTone.danger,
        MadarTone.warning => MadarTone.warning,
        _ => null,
      },
      trailing: (context, s) => reportLoadingId == s.id
          ? const SizedBox.square(
              dimension: Metrics.glyphTile,
              child: Center(child: MadarSpinner()),
            )
          : MadarGlyphTile(
              glyph: MadarGlyph.printer,
              semanticLabel: t('shift.report_title'),
              onTap: () => unawaited(_openReport(context, ref, s)),
            ),
      expandedBuilder: (context, s) => _ShiftOrders(shiftId: s.id),
      onExpansionChanged: (s, {required expanded}) {
        final st = ref.read(shiftHistoryProvider);
        if (expanded && !st.ordersByShift.containsKey(s.id)) {
          unawaited(notifier.loadShiftOrders(s.id));
        }
      },
    );
  }
}

/// A shift's orders under its row: the Orders table, unframed, each sale
/// opening its receipt and printable from its own tile.
class _ShiftOrders extends ConsumerWidget {
  const _ShiftOrders({required this.shiftId});

  final String shiftId;

  Future<void> _preview(
    BuildContext context,
    MadarBridge bridge,
    OrderSummaryView order,
  ) async {
    final ReceiptView receipt;
    try {
      receipt = await bridge.orderReceiptView(orderId: order.id);
    } on MadarError {
      return; // Best-effort — a missing cached receipt just no-ops.
    }
    if (!context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ReceiptSheet(receipt: receipt),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final orders = ref.watch(
      shiftHistoryProvider.select((s) => s.ordersByShift[shiftId]),
    );
    final loading = ref.watch(
      shiftHistoryProvider.select((s) => s.ordersLoadingId == shiftId),
    );
    final error = ref.watch(
      shiftHistoryProvider.select((s) => s.ordersErrors[shiftId]),
    );
    final notifier = ref.read(shiftHistoryProvider.notifier);
    final MadarTableState<OrderSummaryView> state;
    if (orders == null && error != null && !loading) {
      state = MadarTableState.error(
        message: error.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: () => unawaited(notifier.loadShiftOrders(shiftId)),
      );
    } else if (orders == null) {
      state = const MadarTableState.loading(rows: 3);
    } else {
      state = MadarTableState.data(orders);
    }
    return OrdersTable(
      bridge: bridge,
      currency: bridge.currentSession()?.currencyCode ?? '',
      state: state,
      framed: false,
      scrollable: false,
      empty: MadarEmptyContent(title: t('shifts.no_orders')),
      onTap: (o) => unawaited(_preview(context, bridge, o)),
      trailing: (context, o) => MadarGlyphTile(
        glyph: MadarGlyph.printer,
        semanticLabel: t('history.reprint'),
        onTap: () => unawaited(notifier.printOrder(o)),
      ),
    );
  }
}
