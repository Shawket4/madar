/// Till — where the drawer lives. The teller shell's fourth tab (and the
/// manager's, with every drawer at the branch). Home when there is no shift:
/// the open-shift card, not a wall. With a shift open: the drawer's
/// headline figures (sales, cash in till), the rows (Orders this shift,
/// Cash in / out, Print X report, Past shifts), and Close shift.
///
/// iPad (the primary target): header actions carry Print X / Close, the two
/// stat cards sit side by side, and the cash in / out panel is INLINE beside
/// the rows so a paid-out is Till → Pay out → Record with nothing pushed.
/// Phone: the same blocks in one column, Cash in / out as a row that pushes
/// the ledger, Close shift as the last button.
///
/// State lives in [tillProvider]; this screen renders and routes. What the
/// design draws that the bridge cannot back is not here: no refunds card
/// (no refunds on the report), no tips word, no Safe drop chip, no
/// Correct ›, no Force-close — each is noted where it would have been.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/cash_in_out_panel.dart';
import 'package:feature_shift/src/cash_movements_screen.dart';
import 'package:feature_shift/src/close_shift_screen.dart';
import 'package:feature_shift/src/drawers_card.dart';
import 'package:feature_shift/src/open_shift_screen.dart';
import 'package:feature_shift/src/shift_history_screen.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/material.dart' show MaterialPageRoute, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The inline cash panel's column width on a tablet (canvas: 480).
const double _cashColumnWidth = 480;

/// Ledger rows the inline panel shows before pointing at the full screen.
const int _inlineLedgerRows = 4;

/// A stat card's figure (canvas: 30, −0.5 tracking) and its meta line gap.
const double _statFigureSize = 30;
const double _statFigureTracking = -0.5;
const double _statGap = 6;

/// The Till tab. [onOpenOrders] routes "Orders this shift" to the history
/// package (the shell wires it; this package does not import history). The
/// row still shows the count when unwired — it is information — but does
/// not pretend to go anywhere.
class TillScreen extends ConsumerWidget {
  /// Creates the Till tab.
  const TillScreen({super.key, this.onOpenOrders});

  /// Opens this shift's orders list (feature_history). Null hides the
  /// row's chevron and disables the tap.
  final VoidCallback? onOpenOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final loading = ref.watch(tillProvider.select((s) => s.loading));
    final hasShift = ref.watch(tillProvider.select((s) => s.hasOpenShift));
    final isManager = ref.watch(tillProvider.select((s) => s.isManager));
    final toast = ref.watch(tillProvider.select((s) => s.toast));
    final Widget body;
    if (loading && !hasShift) {
      body = const Align(alignment: Alignment.topCenter, child: SkeletonList());
    } else if (!hasShift) {
      // No drawer: the tab IS the open-shift card. A manager still sees the
      // branch's drawers underneath — the morning check needs no float.
      body = OpenShiftScreen(
        embedded: true,
        below: isManager
            ? DrawersCard(onSeeAll: () => _push(context, ref, _pastShifts))
            : null,
      );
    } else {
      body = _DrawerHome(onOpenOrders: onOpenOrders);
    }
    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        children: [
          body,
          SafeArea(
            child: ToastHost(
              toast,
              onDismiss: (id) =>
                  ref.read(tillProvider.notifier).dismissToast(id),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _pastShifts() => const ShiftHistoryScreen();

/// Push a full-screen route over the shell and reload the drawer when it
/// pops — every one of these screens can move the drawer's figures.
void _push(BuildContext context, WidgetRef ref, Widget Function() build) {
  final notifier = ref.read(tillProvider.notifier);
  unawaited(
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => build()))
        .then((_) => notifier.refresh()),
  );
}

/// The drawer with a shift open — the two layouts share every block and
/// differ only in where the cash panel and the primary actions sit.
class _DrawerHome extends ConsumerWidget {
  const _DrawerHome({required this.onOpenOrders});

  final VoidCallback? onOpenOrders;

  Future<void> _printX(BuildContext context) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => const ShiftReportSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final layout = context.madarLayout;
    final shift = ref.watch(tillProvider.select((s) => s.shift))!;
    final tillName = ref.watch(tillProvider.select((s) => s.tillName));
    final isManager = ref.watch(tillProvider.select((s) => s.isManager));
    final since = bridge.formatTime(
      rfc3339: shift.openedAt,
      style: TimeStyle.time,
    );
    final title = tillName ?? t('till.title');
    final subtitle = '${shift.tellerName} · ${t('till.open_since')} $since';

    void closeShift() => _push(context, ref, CloseShiftScreen.new);
    void cashInOut() => _push(context, ref, CashMovementsScreen.new);
    void pastShifts() => _push(context, ref, _pastShifts);
    void printX() => unawaited(_printX(context));

    final rows = _ShiftRows(
      onOpenOrders: onOpenOrders,
      onCashInOut: cashInOut,
      onPrintX: layout.isTablet ? null : printX,
      onPastShifts: pastShifts,
    );
    final drawers = isManager ? DrawersCard(onSeeAll: pastShifts) : null;

    if (layout.isTablet) {
      return Padding(
        padding: EdgeInsetsDirectional.all(layout.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            MadarHeader(
              title: title,
              subtitle: subtitle,
              actions: [
                MadarButton(
                  label: t('till.print_x'),
                  glyph: MadarGlyph.printer,
                  variant: MadarButtonVariant.secondary,
                  size: MadarButtonSize.compact,
                  onTap: printX,
                ),
                MadarButton(
                  label: t('shift.close_title'),
                  glyph: MadarGlyph.lock,
                  variant: MadarButtonVariant.ink,
                  size: MadarButtonSize.compact,
                  onTap: closeShift,
                ),
              ],
            ),
            const _StatCards(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.lg,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: Space.lg,
                        children: [?drawers, rows],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _cashColumnWidth,
                    child: SingleChildScrollView(
                      child: CashInOutPanel(
                        maxRows: _inlineLedgerRows,
                        onSeeAll: cashInOut,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: EdgeInsetsDirectional.all(layout.gutter),
      children: [
        MadarHeader(title: title, subtitle: subtitle),
        const SizedBox(height: Space.lg),
        const _StatCards(),
        const SizedBox(height: Space.lg),
        if (drawers != null) ...[drawers, const SizedBox(height: Space.lg)],
        rows,
        const SizedBox(height: Space.xl),
        MadarButton(
          label: t('shift.close_title'),
          glyph: MadarGlyph.lock,
          variant: MadarButtonVariant.danger,
          onTap: closeShift,
        ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

/// Sales · count and Cash in till, side by side. Each says where its figure
/// comes from in the meta line, and says so when it is an offline figure —
/// the report's `fromServer` is false when the core could only add queued
/// cash sales to the float.
///
/// No refunds card: the report has no refunds. No tips: nothing on the wire.
class _StatCards extends ConsumerWidget {
  const _StatCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final report = ref.watch(tillProvider.select((s) => s.report));
    final stats = ref.watch(tillProvider.select((s) => s.stats));
    final queued = ref.watch(tillProvider.select((s) => s.queuedOrders));
    String money(int minor) => Money.format(minor, currency: currency);

    // "cash 1,420 · card 4,810" from the report's own method lines.
    final byMethod = report?.paymentLines
        .map((l) => '${l.method} ${money(l.totalMinor)}')
        .join(' · ');
    // The drawer's arithmetic, closed on the report's own expected figure:
    // cash sales is what the report added between the float, the pay-ins
    // and the pay-outs — so the line always sums to the number above it,
    // online or offline.
    String? arithmetic;
    if (report != null) {
      final cashSales =
          report.expectedCashMinor -
          report.openingCashMinor -
          report.cashInMinor +
          report.cashOutMinor;
      arithmetic =
          '${t('shift.opening_float')} ${money(report.openingCashMinor)}'
          ' + ${t('shift.cash_sales')} ${money(cashSales)}'
          '${report.cashInMinor > 0 ? ' + ${t('shift.paid_in')} ${money(report.cashInMinor)}' : ''}'
          '${report.cashOutMinor > 0 ? ' − ${t('shift.paid_out')} ${money(report.cashOutMinor)}' : ''}';
    }
    final cards = [
      _StatCard(
        label: t('till.sales'),
        count: stats?.orderCount,
        figure: stats == null ? null : money(stats.salesMinor),
        meta: byMethod,
        tag: queued > 0 ? '$queued ${t('chrome.queued')}' : null,
        tagTone: MadarTone.warning,
      ),
      _StatCard(
        label: t('till.cash_in_till'),
        figure: report == null ? null : money(report.expectedCashMinor),
        meta: arithmetic,
        tag: report != null && !report.fromServer ? t('chrome.offline') : null,
        tagTone: MadarTone.warning,
      ),
    ];
    // Side by side on a tablet. Stacked on a phone: two 30pt mono figures
    // do not both fit across 390 points, and a clipped figure on a drawer
    // is a wrong figure.
    if (context.madarLayout.isPhone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: cards,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.lg,
      children: [for (final c in cards) Expanded(child: c)],
    );
  }
}

/// One stat: tracked label (with an optional mono count), the figure at 30
/// in mono, a meta line, and an optional state tag.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.figure,
    this.count,
    this.meta,
    this.tag,
    this.tagTone = MadarTone.neutral,
  });

  final String label;
  final int? count;

  /// Null while loading → a dash, not a zero: an unloaded figure is not
  /// "no sales".
  final String? figure;
  final String? meta;
  final String? tag;
  final MadarTone tagTone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return MadarCard.column(
      spacing: _statGap,
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: Row(
                spacing: Space.sm,
                children: [
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.label.copyWith(
                        color: colors.textSecondary,
                        letterSpacing: MadarType.tracking,
                      ),
                    ),
                  ),
                  if (count != null)
                    Text(
                      '· $count',
                      textDirection: TextDirection.ltr,
                      style: MadarType.num.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (tag != null) MadarTag(label: tag!, tone: tagTone),
          ],
        ),
        // The figure shrinks before it clips — a narrow card still shows
        // the whole number.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              figure ?? '—',
              maxLines: 1,
              textDirection: TextDirection.ltr,
              style: MadarType.moneyDisplay.copyWith(
                fontSize: _statFigureSize,
                letterSpacing: _statFigureTracking,
                color: figure == null ? colors.textMuted : colors.textPrimary,
              ),
            ),
          ),
        ),
        if (meta != null)
          Text(
            meta!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}

/// "This shift" — the rows under the figures. Orders and Cash in / out carry
/// their counts; Print X report is a row only on the phone (the tablet has
/// it in the header).
class _ShiftRows extends ConsumerWidget {
  const _ShiftRows({
    required this.onOpenOrders,
    required this.onCashInOut,
    required this.onPrintX,
    required this.onPastShifts,
  });

  final VoidCallback? onOpenOrders;
  final VoidCallback onCashInOut;
  final VoidCallback? onPrintX;
  final VoidCallback onPastShifts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final orderCount = ref.watch(
      tillProvider.select((s) => s.stats?.orderCount),
    );
    final movementCount = ref.watch(
      tillProvider.select((s) => s.movements.length),
    );
    Widget num(int? n) => Text(
      n == null ? '—' : '$n',
      style: MadarType.money.copyWith(color: colors.textSecondary),
    );
    return MadarCard.column(
      flush: true,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
            vertical: Space.lg,
          ),
          child: MadarSectionHeader(text: t('till.this_shift')),
        ),
        const MadarHairline.row(),
        MadarRow(
          title: t('till.orders_this_shift'),
          glyph: MadarGlyph.receipt,
          value: num(orderCount),
          onTap: onOpenOrders,
          chevron: onOpenOrders != null,
        ),
        const MadarHairline.row(),
        MadarRow(
          title: t('cash.title'),
          glyph: MadarGlyph.wallet,
          value: num(movementCount),
          onTap: onCashInOut,
        ),
        if (onPrintX != null) ...[
          const MadarHairline.row(),
          MadarRow(
            title: t('till.print_x'),
            glyph: MadarGlyph.printer,
            onTap: onPrintX,
          ),
        ],
        const MadarHairline.row(),
        MadarRow(
          title: t('shifts.title'),
          glyph: MadarGlyph.clock,
          onTap: onPastShifts,
        ),
      ],
    );
  }
}
