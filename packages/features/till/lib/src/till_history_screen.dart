/// Past tills — the branch's tills on the spec's one table
/// (docs/design/SPEC.md §8, §15): Teller, Opened, Length, Declared,
/// Difference, Status, a print tile for the till's Z report, and each row
/// expanding to that till's orders in the SAME table Orders uses
/// ([OrdersTable]) — so a sale reads the same under a till as it does in
/// Orders.
///
/// The locally-open till is pinned on top (the natives'
/// `tillsWithLocalOpen`). All data and rules live in the core; state lives
/// in [tillHistoryProvider]; this screen renders.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart' show ReceiptSheet;
import 'package:feature_history/feature_history.dart' show OrdersTable;
import 'package:feature_till/src/till_providers.dart';
import 'package:feature_till/src/till_report_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The branch's till history, pushed from the Till. The header's back pops
/// it via `Navigator.maybePop`.
class TillHistoryScreen extends ConsumerWidget {
  /// Creates the till-history screen.
  const TillHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final toast = ref.watch(tillHistoryProvider.select((s) => s.toast));
    final branch = bridge.deviceConfig().branchName?.trim() ?? '';
    return MadarPageScaffold(
      title: t('tills.title'),
      subtitle: branch.isEmpty ? null : branch,
      width: MadarContentWidth.reading,
      body: const Padding(
        padding: EdgeInsetsDirectional.only(bottom: Space.xl),
        // Loose, so the card hugs its rows instead of filling the page.
        child: Align(alignment: AlignmentDirectional.topStart, child: _Tills()),
      ),
      overlay: ToastHost(
        toast,
        onDismiss: (id) =>
            ref.read(tillHistoryProvider.notifier).dismissToast(id),
      ),
    );
  }
}

/// The natives' `tillsWithLocalOpen`: prepend the locally-opened-but-
/// unsynced till if it isn't already on the page, so the live till always
/// shows.
List<TillSummaryView> _rowsWithLocalOpen(
  List<TillSummaryView> tills,
  TillView? live,
) {
  if (live == null || !live.isOpen || tills.any((s) => s.id == live.id)) {
    return tills;
  }
  final pinned = TillSummaryView(
    id: live.id,
    tellerName: live.tellerName,
    openedAt: live.openedAt,
    openingCashMinor: live.openingCashMinor,
    status: live.status,
    isOpen: live.isOpen,
    deviceCode: live.deviceCode,
    verification: live.verification,
    openedWhileAnotherOpen: live.openedWhileAnotherOpen,
  );
  return [pinned, ...tills];
}

/// A till's state as a pill: open, force-closed, or — once counted —
/// balanced, short or over by its declared difference.
MadarStatus tillStatus(MadarBridge bridge, TillSummaryView s) {
  String t(String key) => bridge.tr(key: key);
  if (s.isOpen) {
    return MadarStatus(t('tills.open_now'), tone: MadarTone.accent);
  }
  if (s.status == 'force_closed') {
    return MadarStatus(t('tills.force_closed'), tone: MadarTone.danger);
  }
  final d = s.discrepancyMinor;
  if (d == null) return MadarStatus(t('tills.closed'));
  if (d == 0) {
    return MadarStatus(t('tills.balanced'), tone: MadarTone.success);
  }
  return d < 0
      ? MadarStatus(t('tills.short'), tone: MadarTone.danger)
      : MadarStatus(t('tills.over'), tone: MadarTone.warning);
}

/// The one table. Rows expand to the till's orders, loaded on first open.
class _Tills extends ConsumerWidget {
  const _Tills();

  /// Open a till's Z report in the shared sheet — the live till loads the
  /// current report in-sheet; a past one is fetched first (a spinner in its
  /// print tile, a toast on failure).
  Future<void> _openReport(
    BuildContext context,
    WidgetRef ref,
    TillSummaryView s,
  ) async {
    final state = ref.read(tillHistoryProvider);
    if (state.reportLoadingId != null) return;
    if (s.isOpen && s.id == ref.read(shellProvider).till?.id) {
      await showMadarSheet<void>(
        context,
        size: SheetSize.large,
        builder: (_) => const TillReportSheet(),
      );
      return;
    }
    final report = await ref
        .read(tillHistoryProvider.notifier)
        .fetchReport(s.id);
    if (report == null || !context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => TillReportSheet(report: report, tillId: s.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final tills = ref.watch(tillHistoryProvider.select((s) => s.tills));
    // The live till pinned on top — the shell's, the one owner.
    final live = ref.watch(shellProvider.select((s) => s.till));
    final loading = ref.watch(tillHistoryProvider.select((s) => s.loading));
    final loadError = ref.watch(tillHistoryProvider.select((s) => s.loadError));
    final reportLoadingId = ref.watch(
      tillHistoryProvider.select((s) => s.reportLoadingId),
    );
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final notifier = ref.read(tillHistoryProvider.notifier);
    final rows = _rowsWithLocalOpen(tills, live);

    final MadarTableState<TillSummaryView> state;
    if (loading && rows.isEmpty) {
      state = const MadarTableState.loading();
    } else if (loadError != null && tills.isEmpty) {
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

    return MadarDataTable<TillSummaryView>(
      columns: [
        MadarColumn(
          id: 'teller',
          label: t('till.teller'),
          text: (s) => s.tellerName ?? '—',
          flex: 2,
          emphasis: true,
          phone: MadarPhoneRole.title,
        ),
        MadarColumn(
          id: 'opened',
          label: t('till.opened_at'),
          text: (s) => bridge.formatStamp(rfc3339: s.openedAt),
          flex: 3,
          mono: true,
          muted: true,
          phone: MadarPhoneRole.meta,
        ),
        MadarColumn(
          id: 'length',
          label: t('tills.length'),
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
          label: t('tills.declared'),
          text: (s) => money(s.closingDeclaredMinor),
          width: 144,
          align: MadarColumnAlign.end,
          mono: true,
          priority: 1,
          phone: MadarPhoneRole.value,
        ),
        MadarColumn(
          id: 'difference',
          label: t('till.difference'),
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
          status: (s) => tillStatus(bridge, s),
          width: 128,
        ),
      ],
      state: state,
      rowKey: (s) => s.id,
      empty: MadarEmptyContent(
        icon: 'clock.arrow.circlepath',
        title: t('tills.empty'),
        message: t('tills.empty_message'),
      ),
      rail: (s) => switch (tillStatus(bridge, s).tone) {
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
              semanticLabel: t('till.report_title'),
              onTap: () => unawaited(_openReport(context, ref, s)),
            ),
      expandedBuilder: (context, s) => _TillOrders(tillId: s.id),
      onExpansionChanged: (s, {required expanded}) {
        final st = ref.read(tillHistoryProvider);
        if (expanded && !st.ordersByTill.containsKey(s.id)) {
          unawaited(notifier.loadTillOrders(s.id));
        }
      },
    );
  }
}

/// A till's orders under its row: the Orders table, unframed, each sale
/// opening its receipt and printable from its own tile.
class _TillOrders extends ConsumerWidget {
  const _TillOrders({required this.tillId});

  final String tillId;

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
      tillHistoryProvider.select((s) => s.ordersByTill[tillId]),
    );
    final loading = ref.watch(
      tillHistoryProvider.select((s) => s.ordersLoadingId == tillId),
    );
    final error = ref.watch(
      tillHistoryProvider.select((s) => s.ordersErrors[tillId]),
    );
    final notifier = ref.read(tillHistoryProvider.notifier);
    final MadarTableState<OrderSummaryView> state;
    if (orders == null && error != null && !loading) {
      state = MadarTableState.error(
        message: error.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: () => unawaited(notifier.loadTillOrders(tillId)),
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
      empty: MadarEmptyContent(title: t('tills.no_orders')),
      onTap: (o) => unawaited(_preview(context, bridge, o)),
      trailing: (context, o) => MadarGlyphTile(
        glyph: MadarGlyph.printer,
        semanticLabel: t('history.reprint'),
        onTap: () => unawaited(notifier.printOrder(o)),
      ),
    );
  }
}
