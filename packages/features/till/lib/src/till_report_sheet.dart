/// The X / Z report — a till's figures on screen, with Print.
///
/// On the spec (docs/design/SPEC.md §15): the kit header (the report, whose
/// till, when it opened, whether the figures are the server's), stat cards
/// for the takings and the drawer, the payment methods and the drawer's cash
/// movements as tables, the arithmetic as summary lines, and the till's
/// orders — collapsed until asked for — in the same table Orders uses.
///
/// It used to be a picture of thermal paper: 11–13 pt figures, fixed ink in
/// both themes, and hand-built rows that agreed with no other screen. The
/// PRINTED report is still the core's (`renderTillReport`); this is the one
/// a person reads. Report, orders and print state live in
/// [tillReportProvider].
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart' show ReceiptSheet;
import 'package:feature_history/feature_history.dart' show OrdersTable;
import 'package:feature_till/src/till_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The report sheet — Print WITHOUT closing the till. Shows the CURRENT
/// till's report by default, a pre-fetched [report] (Past tills), or a
/// named [tillId]'s (the till just closed). Works with no printer.
class TillReportSheet extends ConsumerStatefulWidget {
  /// Creates the report; a null [report] loads it.
  const TillReportSheet({
    super.key,
    this.report,
    this.tillId,
    this.closed = false,
  });

  /// Shown straight after a close: the title says the till is closed.
  final bool closed;

  /// A pre-fetched report, or null to load one on entry.
  final TillReportView? report;

  /// The till whose orders (and, with no [report], figures) are shown; null
  /// is the current till.
  final String? tillId;

  @override
  ConsumerState<TillReportSheet> createState() => _TillReportSheetState();
}

class _TillReportSheetState extends ConsumerState<TillReportSheet> {
  /// The presentation's provider key, minted once so the family state is
  /// stable across rebuilds.
  late final TillReportRequest _request = TillReportRequest(
    report: widget.report,
    tillId: widget.tillId,
  );

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final state = ref.watch(tillReportProvider(_request));
    final notifier = ref.read(tillReportProvider(_request).notifier);
    final report = state.report;
    final layout = context.madarLayout;
    final subtitle = report == null
        ? null
        : [
            report.tellerName,
            '${t('till.open_since')} ${MadarFormat.isolate(bridge.formatStamp(rfc3339: report.openedAt))}',
          ].join(' · ');

    final Widget body;
    if (report == null && state.loadError != null) {
      body = ErrorState(
        message: state.loadError!.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: notifier.retry,
      );
    } else if (report == null) {
      body = const Padding(
        padding: EdgeInsetsDirectional.all(Space.xl),
        child: SkeletonScope(
          child: Column(
            spacing: Space.lg,
            children: [SkeletonBlock(height: 120), SkeletonList(count: 4)],
          ),
        ),
      );
    } else {
      body = SingleChildScrollView(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: layout.gutter,
          vertical: Space.lg,
        ),
        child: _Report(report: report, request: _request),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            layout.gutter,
            Space.md,
            layout.gutter,
            0,
          ),
          child: MadarHeader(
            title: t(
              widget.closed ? 'till.closed_report_title' : 'till.report_title',
            ),
            subtitle: subtitle,
            actions: [
              if (report != null && !report.fromServer)
                Center(
                  child: MadarStatusPill(
                    MadarStatus(t('chrome.offline'), tone: MadarTone.warning),
                  ),
                ),
              MadarHeaderAction(
                glyph: MadarGlyph.close,
                tooltip: t('common.close'),
                onTap: () => MadarSheet.close<void>(context),
              ),
            ],
          ),
        ),
        Expanded(child: body),
        const MadarHairline(),
        Padding(
          padding: EdgeInsetsDirectional.all(layout.gutter),
          child: Row(
            spacing: Space.md,
            children: [
              Expanded(
                child: _printFeedback(state.print, t) ?? const SizedBox(),
              ),
              MadarButton(
                label: state.print == TillPrintState.printing
                    ? t('receipt.printing')
                    : t('till.print_report'),
                glyph: MadarGlyph.printer,
                size: MadarButtonSize.compact,
                loading: state.print == TillPrintState.printing,
                enabled: report != null,
                onTap: () => unawaited(notifier.printReport()),
              ),
              MadarButton(
                label: t('common.done'),
                variant: MadarButtonVariant.secondary,
                size: MadarButtonSize.compact,
                onTap: () => MadarSheet.close<void>(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Did the report print, find no printer, or fail — in words, beside the
  /// button that did it.
  Widget? _printFeedback(TillPrintState print, String Function(String) t) {
    final status = switch (print) {
      TillPrintState.printed => MadarStatus(
        t('receipt.printed'),
        tone: MadarTone.success,
      ),
      TillPrintState.noPrinter => MadarStatus(
        t('receipt.no_printer'),
        tone: MadarTone.warning,
      ),
      TillPrintState.failed => MadarStatus(
        t('receipt.print_failed'),
        tone: MadarTone.danger,
      ),
      TillPrintState.idle || TillPrintState.printing => null,
    };
    return status == null
        ? null
        : Align(
            alignment: AlignmentDirectional.centerStart,
            child: MadarStatusPill(status),
          );
  }
}

/// The figures.
class _Report extends ConsumerWidget {
  const _Report({required this.report, required this.request});

  final TillReportView report;
  final TillReportRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final r = report;
    final phone = context.madarLayout.isPhone;
    final declared = r.closingCashDeclaredMinor;
    // Counted minus expected: negative is a shortfall.
    final diff = declared == null ? null : declared - r.expectedCashMinor;

    Widget section(String label, Widget child, {Widget? trailing}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(text: label, trailing: trailing),
        child,
      ],
    );

    final cards = <Widget>[
      MadarStatCard(
        label: t('till.payments'),
        minor: r.totalPaymentsMinor,
        currency: currency,
        compact: phone,
      ),
      MadarStatCard(
        label: t('till.expected_cash'),
        minor: r.expectedCashMinor,
        currency: currency,
        compact: phone,
      ),
      if (declared != null)
        MadarStatCard(
          label: t('till.counted_cash'),
          minor: declared,
          currency: currency,
          compact: phone,
          status: diff == 0
              ? MadarStatus(t('shifts.balanced'), tone: MadarTone.success)
              : diff! < 0
              ? MadarStatus(t('shifts.short'), tone: MadarTone.danger)
              : MadarStatus(t('shifts.over'), tone: MadarTone.warning),
        ),
    ];

    final lines = <Widget>[
      MadarSummaryLine(
        label: t('till.opening_cash'),
        minor: r.openingCashMinor,
        currency: currency,
      ),
      if (r.openingCashWasEdited && r.openingCashOriginalMinor != null)
        MadarSummaryLine(
          label: [
            t('till.opening_mismatch'),
            if ((r.openingCashEditReason ?? '').trim().isNotEmpty)
              r.openingCashEditReason!.trim(),
          ].join(' · '),
          minor: r.openingCashMinor - r.openingCashOriginalMinor!,
          currency: currency,
          signed: true,
          tone: MadarTone.warning,
        ),
      MadarSummaryLine(
        label: t('till.payments'),
        minor: r.totalPaymentsMinor,
        currency: currency,
      ),
      if (r.cashInMinor > 0)
        MadarSummaryLine(
          label: t('till.cash_in'),
          minor: r.cashInMinor,
          currency: currency,
          signed: true,
        ),
      if (r.cashOutMinor > 0)
        MadarSummaryLine(
          label: t('till.cash_out'),
          minor: -r.cashOutMinor,
          currency: currency,
        ),
      if (r.voidedAmountMinor > 0)
        MadarSummaryLine(
          label: t('history.voided'),
          minor: -r.voidedAmountMinor,
          currency: currency,
          muted: true,
        ),
      // Money given back from this drawer — its own line, with the cash slice
      // broken out because that is the only part the count can see.
      if (r.refundsIssuedMinor > 0)
        MadarSummaryLine(
          label:
              '${t('till.refunds')} · ${MadarFormat.ltr('${r.refundsIssuedCount}')}',
          minor: -r.refundsIssuedMinor,
          currency: currency,
        ),
      if (r.refundsIssuedMinor > 0 &&
          r.refundsIssuedCashMinor != r.refundsIssuedMinor)
        MadarSummaryLine(
          label: t('till.refunds_cash'),
          minor: -r.refundsIssuedCashMinor,
          currency: currency,
          muted: true,
        ),
      if (r.cashInRefundedSalesMinor > 0)
        MadarSummaryLine(
          label: t('till.cash_in_refunded'),
          minor: r.cashInRefundedSalesMinor,
          currency: currency,
          muted: true,
        ),
      MadarSummaryLine(
        label: t('till.expected_cash'),
        minor: r.expectedCashMinor,
        currency: currency,
        emphasis: true,
      ),
      if (declared != null && diff != null) ...[
        MadarSummaryLine(
          label: t('till.counted_cash'),
          minor: declared,
          currency: currency,
        ),
        MadarSummaryLine(
          label: t('till.difference'),
          minor: diff,
          currency: currency,
          signed: true,
          tone: diff == 0
              ? MadarTone.success
              : diff < 0
              ? MadarTone.danger
              : MadarTone.warning,
        ),
      ],
    ];

    // Facts about the till that are not money: the device it ran on and its
    // order numbers, the bills still open when it closed, and its flags.
    final colors = context.madarColors;
    final facts = <String>[
      if (r.deviceCode case final code?)
        [
          '${t('till.z_device')} ${MadarFormat.ltr(code)}',
          if (r.orderNumberFirst != null && r.orderNumberLast != null)
            MadarFormat.ltr(
              '$code-${r.orderNumberFirst}…$code-${r.orderNumberLast}',
            ),
        ].join(' · '),
      if ((r.oldBillsCount ?? 0) > 0)
        '${t('till.z_old_bills')} ${MadarFormat.ltr('${r.oldBillsCount}')}',
    ];
    final flags = <MadarStatus>[
      if (r.openedWhileAnotherOpen)
        MadarStatus(t('till.flagged_badge'), tone: MadarTone.warning),
      if (r.verification == 'unverified')
        MadarStatus(t('till.unverified_badge'), tone: MadarTone.warning),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        if (flags.isNotEmpty || facts.isNotEmpty)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in flags) MadarStatusPill(f),
              for (final f in facts)
                Text(
                  f,
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        if (phone)
          Column(spacing: Space.md, children: cards)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.lg,
            children: [for (final c in cards) Expanded(child: c)],
          ),
        section(
          t('till.payment_methods'),
          MadarDataTable<TillReportPaymentLine>(
            scrollable: false,
            columns: [
              MadarColumn(
                id: 'method',
                label: t('history.col_payment'),
                text: (l) => bridge.paymentMethodLabel(code: l.method),
                flex: 3,
                emphasis: true,
                phone: MadarPhoneRole.title,
              ),
              MadarColumn(
                id: 'count',
                label: t('till.orders_col'),
                text: (l) => '${l.orderCount}',
                width: 96,
                align: MadarColumnAlign.end,
                mono: true,
                muted: true,
                phone: MadarPhoneRole.meta,
              ),
              MadarColumn.money(
                id: 'total',
                label: t('order.total'),
                minor: (l) => l.totalMinor,
                currency: currency,
                width: 160,
              ),
            ],
            state: MadarTableState.data(r.paymentLines),
            rowKey: (l) => l.method,
            empty: MadarEmptyContent(title: t('till.report_no_sales')),
          ),
        ),
        if (r.reconciliation.isNotEmpty)
          section(
            t('till.z_reconciliation'),
            MadarDataTable<ReconciliationLineView>(
              scrollable: false,
              columns: [
                MadarColumn(
                  id: 'method',
                  label: t('history.col_payment'),
                  text: (l) => [
                    l.label,
                    if ((l.note ?? '').trim().isNotEmpty) l.note!.trim(),
                  ].join(' · '),
                  flex: 3,
                  emphasis: true,
                  phone: MadarPhoneRole.title,
                ),
                MadarColumn.money(
                  id: 'system',
                  label: t('till.reconcile_system'),
                  minor: (l) => l.systemTotalMinor,
                  currency: currency,
                  width: 150,
                ),
                MadarColumn(
                  id: 'declared',
                  label: t('till.reconcile_amount'),
                  text: (l) => l.declaredAmountMinor == null
                      ? '—'
                      : bridge.formatMoney(
                          minor: l.declaredAmountMinor!,
                          currency: currency,
                          signed: false,
                        ),
                  width: 150,
                  align: MadarColumnAlign.end,
                  mono: true,
                  priority: 1,
                  phone: MadarPhoneRole.meta,
                ),
                MadarColumn.status(
                  id: 'status',
                  label: t('history.col_status'),
                  status: (l) => switch (l.status) {
                    'checked' => MadarStatus(
                      t('till.reconcile_checked'),
                      tone: MadarTone.success,
                    ),
                    'disagreed' => MadarStatus(
                      t('till.reconcile_disagree'),
                      tone: MadarTone.danger,
                    ),
                    _ => MadarStatus(t('till.reconcile_unreviewed')),
                  },
                  width: 170,
                ),
              ],
              state: MadarTableState.data(r.reconciliation),
              rowKey: (l) => l.method,
              empty: MadarEmptyContent(title: t('till.report_no_sales')),
            ),
          ),
        if (r.cashMovements.isNotEmpty)
          section(
            t('cash.title'),
            MadarDataTable<TillReportCashLine>(
              scrollable: false,
              columns: [
                MadarColumn(
                  id: 'note',
                  label: t('cash.note_col'),
                  text: (m) => m.note.trim().isEmpty ? m.movedByName : m.note,
                  flex: 3,
                  phone: MadarPhoneRole.title,
                ),
                MadarColumn(
                  id: 'who',
                  label: t('till.teller'),
                  text: (m) => m.movedByName,
                  flex: 2,
                  muted: true,
                  priority: 2,
                  phone: MadarPhoneRole.meta,
                ),
                MadarColumn(
                  id: 'time',
                  label: t('history.col_time'),
                  text: (m) => bridge.formatStamp(rfc3339: m.createdAt),
                  width: 120,
                  mono: true,
                  muted: true,
                  priority: 1,
                  phone: MadarPhoneRole.meta,
                ),
                MadarColumn.money(
                  id: 'amount',
                  label: t('cash.amount_col'),
                  minor: (m) => m.amountMinor,
                  currency: currency,
                  width: 160,
                ),
              ],
              state: MadarTableState.data(r.cashMovements),
              rowKey: (m) => '${m.createdAt}${m.amountMinor}${m.note}',
              empty: MadarEmptyContent(title: t('cash.empty')),
            ),
          ),
        section(
          t('till.drawer'),
          MadarCard.column(spacing: 0, children: lines),
        ),
        _Orders(request: request),
      ],
    );
  }
}

/// The till's orders, collapsed until asked for — they cost a round trip
/// and a lot of rows.
class _Orders extends ConsumerWidget {
  const _Orders({required this.request});

  final TillReportRequest request;

  Future<void> _preview(
    BuildContext context,
    MadarBridge bridge,
    OrderSummaryView order,
  ) async {
    final ReceiptView receipt;
    try {
      receipt = await bridge.orderReceiptView(orderId: order.id);
    } on MadarError {
      return;
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
    final state = ref.watch(tillReportProvider(request));
    final notifier = ref.read(tillReportProvider(request).notifier);
    final orders = state.orders;
    final MadarTableState<OrderSummaryView> table;
    if (orders == null && state.ordersError != null) {
      table = MadarTableState.error(
        message: state.ordersError!.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: notifier.retry,
      );
    } else if (orders == null) {
      table = const MadarTableState.loading(rows: 3);
    } else {
      table = MadarTableState.data(orders);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(
          text: t('shifts.orders'),
          trailing: MadarButton(
            label: t(state.expanded ? 'till.hide_orders' : 'till.show_orders'),
            glyph: state.expanded
                ? MadarGlyph.chevronUp
                : MadarGlyph.chevronDown,
            variant: MadarButtonVariant.ghost,
            size: MadarButtonSize.compact,
            onTap: notifier.toggleExpanded,
          ),
        ),
        if (state.expanded)
          OrdersTable(
            bridge: bridge,
            currency: bridge.currentSession()?.currencyCode ?? '',
            state: table,
            scrollable: false,
            empty: MadarEmptyContent(title: t('shifts.no_orders')),
            onTap: (o) => unawaited(_preview(context, bridge, o)),
            trailing: (context, o) => MadarGlyphTile(
              glyph: MadarGlyph.printer,
              semanticLabel: t('history.reprint'),
              onTap: () => unawaited(notifier.printOrder(o)),
            ),
          ),
      ],
    );
  }
}
