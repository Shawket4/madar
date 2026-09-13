/// Till — where the drawer lives. The teller shell's Till tab (and the
/// manager's, with every drawer at the branch). Home when there is no shift:
/// the open-shift form, not a wall.
///
/// On the spec (docs/design/SPEC.md §15): full width, the tab glyph and the
/// screen's name in the header (never the till's name — that is data, and it
/// is in the top bar), who holds the drawer since when underneath. The
/// figures as stat cards; the shift's links as `.nav` rows; the latest cash
/// movements as a ledger. Print X report and Close shift are header actions
/// on a tablet and rows / the last button on a phone. Preview is a row of its
/// own — never a long press nobody finds.
///
/// State lives in [tillProvider]; this screen renders and routes.
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
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ledger rows the Till shows before pointing at Cash in / out.
const int _recentMovements = 4;

/// The Till tab. [onOpenOrders] routes "Orders this shift" to the history
/// package (the shell wires it). The row still shows the count when
/// unwired — it is information — but does not pretend to go anywhere.
class TillScreen extends ConsumerWidget {
  /// Creates the Till tab.
  const TillScreen({super.key, this.onOpenOrders});

  /// Opens this shift's orders. Null leaves the row without a destination.
  final VoidCallback? onOpenOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(tillProvider.select((s) => s.loading));
    final hasShift = ref.watch(tillProvider.select((s) => s.hasOpenShift));
    final isManager = ref.watch(tillProvider.select((s) => s.isManager));
    final toast = ref.watch(tillProvider.select((s) => s.toast));
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final layout = context.madarLayout;
    final shift = ref.watch(tillProvider.select((s) => s.shift));
    final printingX = ref.watch(tillProvider.select((s) => s.printingX));

    String? subtitle;
    var actions = const <Widget>[];
    if (hasShift && shift != null) {
      final since = bridge.formatStamp(rfc3339: shift.openedAt);
      subtitle =
          '${shift.tellerName} · ${t('till.open_since')} ${MadarFormat.isolate(since)}';
      if (layout.isTablet) {
        actions = [
          MadarButton(
            label: t('till.print_x'),
            glyph: MadarGlyph.printer,
            variant: MadarButtonVariant.secondary,
            size: MadarButtonSize.compact,
            loading: printingX,
            onTap: () => unawaited(ref.read(tillProvider.notifier).printX()),
          ),
          MadarButton(
            label: t('shift.close_title'),
            glyph: MadarGlyph.lock,
            variant: MadarButtonVariant.ink,
            size: MadarButtonSize.compact,
            onTap: () => _push(context, ref, CloseShiftScreen.new),
          ),
        ];
      }
    }

    final Widget body;
    final MadarContentWidth width;
    if (loading && !hasShift) {
      width = MadarContentWidth.full;
      body = const Align(
        alignment: AlignmentDirectional.topStart,
        child: SkeletonList(),
      );
    } else if (!hasShift) {
      // No drawer: the tab IS the open-shift form. A manager still sees the
      // branch's drawers underneath — the morning check needs no float.
      width = MadarContentWidth.form;
      body = OpenShiftScreen(
        embedded: true,
        below: isManager
            ? DrawersCard(onSeeAll: () => _push(context, ref, _pastShifts))
            : null,
      );
    } else {
      width = MadarContentWidth.full;
      body = _DrawerHome(onOpenOrders: onOpenOrders);
    }

    // A tab body — the shell's top bar above it already paid the top inset.
    return MadarPageScaffold(
      safeTop: false,
      title: t('till.title'),
      subtitle: subtitle,
      actions: actions,
      width: width,
      body: body,
      overlay: ToastHost(
        toast,
        onDismiss: (id) => ref.read(tillProvider.notifier).dismissToast(id),
      ),
    );
  }
}

Widget _pastShifts() => const ShiftHistoryScreen();

/// The X report on screen, with its own Print.
Future<void> _previewX(BuildContext context) async {
  await showMadarSheet<void>(
    context,
    size: SheetSize.large,
    builder: (_) => const ShiftReportSheet(),
  );
}

/// Push a page and reload the drawer when it pops — every one of these
/// pages can move the drawer's figures.
void _push(BuildContext context, WidgetRef ref, Widget Function() build) {
  final notifier = ref.read(tillProvider.notifier);
  unawaited(
    MadarPages.push<void>(
      context,
      (_) => build(),
    ).then((_) => notifier.refresh()),
  );
}

/// The drawer with a shift open.
class _DrawerHome extends ConsumerWidget {
  const _DrawerHome({required this.onOpenOrders});

  final VoidCallback? onOpenOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final layout = context.madarLayout;
    final isManager = ref.watch(tillProvider.select((s) => s.isManager));

    void cashInOut() => _push(context, ref, CashMovementsScreen.new);
    void pastShifts() => _push(context, ref, _pastShifts);

    final links = _Links(
      onOpenOrders: onOpenOrders,
      onCashInOut: cashInOut,
      onPastShifts: pastShifts,
      withPrint: layout.isPhone,
    );
    final ledger = CashLedger(
      title: t('cash.title'),
      maxRows: _recentMovements,
      onSeeAll: cashInOut,
    );
    final drawers = isManager ? DrawersCard(onSeeAll: pastShifts) : null;

    if (layout.isTablet) {
      return LayoutBuilder(
        builder: (context, c) {
          // Two columns where both keep a readable width; one otherwise
          // (an iPad in portrait).
          final twoUp = c.maxWidth >= Responsive.desktop - Space.xxl * 4;
          return SingleChildScrollView(
            padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xl,
              children: [
                const _StatCards(),
                if (twoUp)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.lg,
                    children: [
                      Expanded(child: links),
                      Expanded(child: ledger),
                    ],
                  )
                else ...[
                  links,
                  ledger,
                ],
                ?drawers,
              ],
            ),
          );
        },
      );
    }

    return ListView(
      padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
      children: [
        const _StatCards(),
        const SizedBox(height: Space.xl),
        links,
        const SizedBox(height: Space.xl),
        ledger,
        if (drawers != null) ...[const SizedBox(height: Space.xl), drawers],
        const SizedBox(height: Space.xl),
        MadarButton(
          label: t('shift.close_title'),
          glyph: MadarGlyph.lock,
          variant: MadarButtonVariant.danger,
          onTap: () => _push(context, ref, CloseShiftScreen.new),
        ),
      ],
    );
  }
}

/// Sales and Cash in till. Each says where its figure comes from in its
/// meta line, and says so when it is an offline figure.
class _StatCards extends ConsumerWidget {
  const _StatCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final report = ref.watch(tillProvider.select((s) => s.report));
    final stats = ref.watch(tillProvider.select((s) => s.stats));
    final queued = ref.watch(tillProvider.select((s) => s.queuedOrders));
    String money(int minor) => MadarFormat.ltr(
      bridge.formatMoney(minor: minor, currency: currency, signed: false),
    );

    // "Cash EGP 1,420.00 · Card EGP 4,810.00" from the report's own lines.
    final byMethod = report?.paymentLines
        .map(
          (l) =>
              '${bridge.paymentMethodLabel(code: l.method)} ${money(l.totalMinor)}',
        )
        .join(' · ');
    // The drawer's arithmetic, closed on the report's own expected figure.
    String? arithmetic;
    if (report != null) {
      final cashSales = bridge.shiftCashSalesMinor(report: report);
      arithmetic = [
        '${t('shift.opening_float')} ${money(report.openingCashMinor)}',
        '${t('shift.cash_sales')} ${money(cashSales)}',
        if (report.cashInMinor > 0)
          '${t('shift.paid_in')} ${money(report.cashInMinor)}',
        if (report.cashOutMinor > 0)
          '${t('shift.paid_out')} ${money(-report.cashOutMinor)}',
      ].join(' · ');
    }
    final phone = context.madarLayout.isPhone;
    final Widget sales = stats == null
        ? const _StatSkeleton()
        : MadarStatCard(
            label: t('till.sales'),
            minor: stats.salesMinor,
            currency: currency,
            glyph: MadarGlyph.receipt,
            meta: byMethod,
            status: queued > 0
                ? MadarStatus(
                    '${MadarFormat.ltr('$queued')} ${t('chrome.queued')}',
                    tone: MadarTone.warning,
                  )
                : null,
          );
    final Widget cash = report == null
        ? const _StatSkeleton()
        : MadarStatCard(
            label: t('till.cash_in_till'),
            minor: report.expectedCashMinor,
            currency: currency,
            glyph: MadarGlyph.wallet,
            meta: arithmetic,
            status: report.fromServer
                ? null
                : MadarStatus(t('chrome.offline'), tone: MadarTone.warning),
          );
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [sales, cash],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Expanded(child: sales),
          Expanded(child: cash),
        ],
      ),
    );
  }
}

/// A stat card's shape while its figure loads — a dash would read as "no
/// sales".
class _StatSkeleton extends StatelessWidget {
  const _StatSkeleton();

  @override
  Widget build(BuildContext context) => const MadarCard(
    child: SkeletonScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          SkeletonBlock(height: 12, width: 96),
          SkeletonBlock(height: 30, width: 200),
          SkeletonBlock(height: 12),
        ],
      ),
    ),
  );
}

/// "This shift" — where the drawer's pages are.
class _Links extends ConsumerWidget {
  const _Links({
    required this.onOpenOrders,
    required this.onCashInOut,
    required this.onPastShifts,
    required this.withPrint,
  });

  final VoidCallback? onOpenOrders;
  final VoidCallback onCashInOut;
  final VoidCallback onPastShifts;

  /// The phone has no header actions: Print X is a row.
  final bool withPrint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final orderCount = ref.watch(
      tillProvider.select((s) => s.stats?.orderCount),
    );
    final movementCount = ref.watch(
      tillProvider.select((s) => s.movements.length),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(text: t('till.this_shift')),
        MadarCard.column(
          flush: true,
          children: [
            MadarListRow.nav(
              title: t('till.orders_this_shift'),
              glyph: MadarGlyph.receipt,
              valueText: orderCount == null
                  ? null
                  : MadarFormat.ltr('$orderCount'),
              onTap: onOpenOrders,
            ),
            const MadarHairline.row(),
            MadarListRow.nav(
              title: t('cash.title'),
              glyph: MadarGlyph.wallet,
              valueText: MadarFormat.ltr('$movementCount'),
              onTap: onCashInOut,
            ),
            const MadarHairline.row(),
            MadarListRow.nav(
              title: t('till.preview_x'),
              glyph: MadarGlyph.receipt,
              onTap: () => unawaited(_previewX(context)),
            ),
            if (withPrint) ...[
              const MadarHairline.row(),
              MadarListRow.nav(
                title: t('till.print_x'),
                glyph: MadarGlyph.printer,
                onTap: () =>
                    unawaited(ref.read(tillProvider.notifier).printX()),
              ),
            ],
            const MadarHairline.row(),
            MadarListRow.nav(
              title: t('shifts.title'),
              glyph: MadarGlyph.clock,
              onTap: onPastShifts,
            ),
          ],
        ),
      ],
    );
  }
}
