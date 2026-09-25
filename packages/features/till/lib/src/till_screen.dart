/// Till — where the drawer lives. The teller shell's Till tab (and the
/// manager's, with every drawer at the branch). Home when there is no till:
/// the open-till form, not a wall.
///
/// On the spec (docs/design/SPEC.md §15): full width, the tab glyph and the
/// screen's name in the header (never the till's name — that is data, and it
/// is in the top bar), who holds the drawer since when underneath. The
/// figures as stat cards; the till's links as `.nav` rows; the latest cash
/// movements as a ledger. Print X report and Close till are header actions
/// on a tablet and rows / the last button on a phone. Preview is a row of its
/// own — never a long press nobody finds.
///
/// State lives in [tillProvider]; this screen renders and routes.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/src/cash_in_out_panel.dart';
import 'package:feature_till/src/cash_movements_screen.dart';
import 'package:feature_till/src/cash_spot_screen.dart';
import 'package:feature_till/src/close_till_screen.dart';
import 'package:feature_till/src/drawers_card.dart';
import 'package:feature_till/src/figures_hidden.dart';
import 'package:feature_till/src/manager_actions.dart';
import 'package:feature_till/src/open_till_screen.dart';
import 'package:feature_till/src/till_history_screen.dart';
import 'package:feature_till/src/till_notices.dart';
import 'package:feature_till/src/till_providers.dart';
import 'package:feature_till/src/till_punch_sheet.dart';
import 'package:feature_till/src/waste_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Ledger rows the Till shows before pointing at Cash in / out.
const int _recentMovements = 4;

/// The Till tab. [onOpenOrders] routes "Orders this till" to the history
/// package (the shell wires it). The row still shows the count when
/// unwired — it is information — but does not pretend to go anywhere.
class TillScreen extends ConsumerWidget {
  /// Creates the Till tab.
  const TillScreen({super.key, this.onOpenOrders});

  /// Opens this till's orders. Null leaves the row without a destination.
  final VoidCallback? onOpenOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(tillProvider.select((s) => s.loading));
    final hasTill = ref.watch(tillProvider.select((s) => s.hasOpenTill));
    final isManager = ref.watch(tillProvider.select((s) => s.isManager));
    final toast = ref.watch(tillProvider.select((s) => s.toast));
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final layout = context.madarLayout;
    final till = ref.watch(tillProvider.select((s) => s.till));

    String? subtitle;
    var actions = const <Widget>[];
    if (hasTill && till != null) {
      final since = bridge.formatStamp(rfc3339: till.openedAt);
      subtitle =
          '${till.tellerName} · ${t('till.open_since')} ${MadarFormat.isolate(since)}';
      if (layout.isTablet) {
        actions = [
          // Cash spot replaces the X preview and print (owner design
          // 2026-09-16 item 5): visible to everyone, a PIN when needed.
          MadarButton(
            label: t('spot.button'),
            glyph: MadarGlyph.wallet,
            variant: MadarButtonVariant.secondary,
            size: MadarButtonSize.compact,
            onTap: () => unawaited(
              openCashSpot(
                context,
                ref,
              ).then((_) => ref.read(tillProvider.notifier).refresh()),
            ),
          ),
          MadarButton(
            label: t('till.close_title'),
            glyph: MadarGlyph.lock,
            variant: MadarButtonVariant.ink,
            size: MadarButtonSize.compact,
            onTap: () => _push(context, ref, CloseTillScreen.new),
          ),
        ];
      }
    }

    final Widget body;
    final MadarContentWidth width;
    if (loading && !hasTill) {
      width = MadarContentWidth.full;
      body = const Align(
        alignment: AlignmentDirectional.topStart,
        child: SkeletonList(),
      );
    } else if (!hasTill) {
      // No drawer: the tab IS the open-till form. A manager still sees the
      // branch's drawers underneath — the morning check needs no float.
      width = MadarContentWidth.form;
      // Waste needs no drawer (it is stock, not money): offered here too,
      // under the same capability check as with a till open.
      final wasteRow = bridge.canRecordWaste()
          ? MadarCard.column(
              flush: true,
              children: [
                MadarListRow.nav(
                  title: t('waste.title'),
                  glyph: MadarGlyph.trash,
                  onTap: () => _push(context, ref, WasteScreen.new),
                ),
              ],
            )
          : null;
      // The manager-actions list stays reachable with NO drawer open: a
      // refused op waiting on a manager is exactly the kind of thing that
      // strands a device on this screen, and burying it until a till opens
      // would make the lock a dead end.
      body = OpenTillScreen(
        embedded: true,
        below: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xl,
          children: [
            const ManagerActionsBanner(),
            ?wasteRow,
            if (isManager)
              DrawersCard(onSeeAll: () => _push(context, ref, _pastTills)),
          ],
        ),
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
      // Pulled: the manual sync, then the drawer re-read from the local rows.
      body: MadarRefresh(
        nested: true,
        onRefresh: () =>
            pullThenReread(ref, ref.read(tillProvider.notifier).refresh),
        child: body,
      ),
      overlay: ToastHost(
        toast,
        onDismiss: (id) => ref.read(tillProvider.notifier).dismissToast(id),
      ),
    );
  }
}

Widget _pastTills() => const TillHistoryScreen();

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

/// The drawer with a till open.
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
    void pastTills() => _push(context, ref, _pastTills);
    // Hidden unless the person holds the capability or may ask a manager.
    final canWaste = bridge.canRecordWaste();

    final links = _Links(
      onOpenOrders: onOpenOrders,
      onCashInOut: cashInOut,
      onWaste: canWaste ? () => _push(context, ref, WasteScreen.new) : null,
      onPastTills: pastTills,
    );
    final ledger = CashLedger(
      title: t('cash.title'),
      maxRows: _recentMovements,
      onSeeAll: cashInOut,
    );
    final drawers = isManager ? DrawersCard(onSeeAll: pastTills) : null;
    const branch = _BranchTills();
    final notice = ref.watch(tillProvider.select((s) => s.notice));
    final noticeBanner = notice != null && notice.openBillsCount > 0
        ? OpenBillsNoticeBanner(notice: notice)
        : null;

    if (layout.isTablet) {
      return LayoutBuilder(
        builder: (context, c) {
          // Two columns where both keep a readable width; one otherwise
          // (an iPad in portrait).
          final twoUp = c.maxWidth >= Responsive.desktop - Space.xxl * 4;
          return SingleChildScrollView(
            physics: MadarRefresh.physics,
            padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xl,
              children: [
                const ManagerActionsBanner(),
                ?noticeBanner,
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
                branch,
                ?drawers,
              ],
            ),
          );
        },
      );
    }

    return ListView(
      physics: MadarRefresh.physics,
      padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
      children: [
        const ManagerActionsBanner(),
        if (noticeBanner != null) ...[
          noticeBanner,
          const SizedBox(height: Space.xl),
        ],
        const _StatCards(),
        const SizedBox(height: Space.xl),
        links,
        const SizedBox(height: Space.xl),
        ledger,
        const SizedBox(height: Space.xl),
        branch,
        if (drawers != null) ...[const SizedBox(height: Space.xl), drawers],
        const SizedBox(height: Space.xl),
        MadarButton(
          label: t('till.close_title'),
          glyph: MadarGlyph.lock,
          variant: MadarButtonVariant.danger,
          onTap: () => _push(context, ref, CloseTillScreen.new),
        ),
      ],
    );
  }
}

/// Sales and Cash in till. Each says where its figure comes from in its
/// meta line, and says so when it is an offline figure.
class _StatCards extends ConsumerWidget {
  const _StatCards();

  /// One breakdown term, isolated so its signed figure keeps its own
  /// direction beside its neighbours, and unbreakable so a wrap (or a row on
  /// a phone) falls BETWEEN terms, never inside "Paid out −EGP 90.00".
  static String _term(String term) => term.replaceAll(' ', '\u00A0');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    // `till.cash_spot_check` is "may see this till's money figures": without
    // it NO aggregate is shown here — not the sales total, not the tenders,
    // not the drawer. One panel says so, and Cash spot still offers the PIN.
    if (!bridge.tillFiguresVisible()) {
      return FiguresHiddenPanel(
        titleKey: 'till.this_shift',
        action: MadarButton(
          label: t('spot.button'),
          glyph: MadarGlyph.wallet,
          variant: MadarButtonVariant.secondary,
          onTap: () => unawaited(
            openCashSpot(
              context,
              ref,
            ).then((_) => ref.read(tillProvider.notifier).refresh()),
          ),
        ),
      );
    }
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final report = ref.watch(tillProvider.select((s) => s.report));
    final stats = ref.watch(tillProvider.select((s) => s.stats));
    final queued = ref.watch(tillProvider.select((s) => s.queuedOrders));
    // The core's string is already safe in a sentence (Arabic isolates its
    // figure); wrapping it again flipped the label and the minus.
    String money(int minor) =>
        bridge.formatMoney(minor: minor, currency: currency, signed: false);

    // On a phone the breakdown is rows: a wrapped line left a "·" hanging
    // at its edge.
    final sep = context.madarLayout.isPhone ? '\n' : ' · ';
    // "Cash EGP 1,420.00 · Card EGP 4,810.00" from the report's own lines.
    final byMethod = report?.paymentLines
        .map(
          (l) =>
              '${bridge.paymentMethodLabel(code: l.method)} ${money(l.totalMinor)}',
        )
        .map(_term)
        .join(sep);
    // The drawer's arithmetic, closed on the report's own expected figure.
    String? arithmetic;
    if (report != null) {
      final cashSales = bridge.tillCashSalesMinor(report: report);
      arithmetic = [
        '${t('till.opening_float')} ${money(report.openingCashMinor)}',
        '${t('till.cash_sales')} ${money(cashSales)}',
        if (report.cashInMinor > 0)
          '${t('till.paid_in')} ${money(report.cashInMinor)}',
        if (report.cashOutMinor > 0)
          '${t('till.paid_out')} ${money(-report.cashOutMinor)}',
      ].map(_term).join(sep);
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

/// "This till" — where the drawer's pages are.
/// Clock someone in or out with their PIN (CL-13), then say what happened.
Future<void> _punch(BuildContext context, MadarBridge bridge) async {
  final res = await showTillPunch(context);
  if (res == null || !context.mounted) return;
  await showMadarModal<void>(
    context,
    builder: (sheet) => MadarModalBody(
      title: res.message,
      primary: MadarModalAction(
        bridge.tr(key: 'common.done'),
        () => Navigator.of(sheet).maybePop(),
      ),
    ),
  );
}

class _Links extends ConsumerWidget {
  const _Links({
    required this.onOpenOrders,
    required this.onCashInOut,
    required this.onWaste,
    required this.onPastTills,
  });

  final VoidCallback? onOpenOrders;
  final VoidCallback onCashInOut;

  /// Record waste; null hides the row (no capability, no ask-a-manager).
  final VoidCallback? onWaste;
  final VoidCallback onPastTills;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    // The count of this shift's sales is a shift aggregate: hidden with the
    // rest of the figures. The row still goes to the orders.
    final orderCount = ref.bridge.tillFiguresVisible()
        ? ref.watch(tillProvider.select((s) => s.stats?.orderCount))
        : null;
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
            if (onWaste != null) ...[
              const MadarHairline.row(),
              MadarListRow.nav(
                title: t('waste.title'),
                glyph: MadarGlyph.trash,
                onTap: onWaste,
              ),
            ],
            if (tillDawamOn(bridge)) ...[
              const MadarHairline.row(),
              MadarListRow.nav(
                title: t('staff.till_punch'),
                glyph: MadarGlyph.clock,
                onTap: () => unawaited(_punch(context, bridge)),
              ),
            ],
            const MadarHairline.row(),
            MadarListRow.nav(
              title: t('spot.button'),
              glyph: MadarGlyph.wallet,
              onTap: () => unawaited(
                openCashSpot(
                  context,
                  ref,
                ).then((_) => ref.read(tillProvider.notifier).refresh()),
              ),
            ),
            const MadarHairline.row(),
            MadarListRow.nav(
              title: t('tills.title'),
              glyph: MadarGlyph.clock,
              onTap: onPastTills,
            ),
          ],
        ),
      ],
    );
  }
}

/// "Open tills in this branch": every person with a till open right now,
/// on which device, since when — this device's first. The core merges the
/// server's list with what LAN peers announce. A manager can force-close
/// another device's till from here (behind a confirm).
class _BranchTills extends ConsumerWidget {
  const _BranchTills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final tills = ref.watch(tillProvider.select((s) => s.branchTills));
    final canForceClose = ref.watch(
      tillProvider.select((s) => s.canForceClose),
    );
    final closingId = ref.watch(tillProvider.select((s) => s.forceClosingId));
    if (tills.isEmpty) return const SizedBox.shrink();
    final ordered = [
      ...tills.where((b) => b.isThisDevice),
      ...tills.where((b) => !b.isThisDevice),
    ];

    Future<void> forceClose(BranchOpenTillView b) async {
      final notifier = ref.read(tillProvider.notifier);
      final yes = await showMadarConfirm(
        context,
        title: t('till.force_close_elsewhere'),
        body: b.tellerName,
        confirmLabel: t('till.force_close_elsewhere'),
        cancelLabel: t('common.cancel'),
      );
      if (yes) {
        await notifier.forceClose(b.tillId, t('till.force_close_elsewhere'));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(
          text: t('till.branch_open_tills'),
          trailing: Text(
            MadarFormat.ltr('${tills.length}'),
            style: MadarType.numMd,
          ),
        ),
        MadarCard.column(
          flush: true,
          children: [
            for (final (i, b) in ordered.indexed) ...[
              if (i > 0) const MadarHairline.row(),
              MadarRow(
                title: b.tellerName,
                subtitle: [
                  if (b.isThisDevice)
                    t('till.this_device')
                  else if (b.deviceLabel ?? b.deviceCode case final d?)
                    MadarFormat.isolate(d),
                  '${t('till.open_since')} ${MadarFormat.isolate(bridge.formatStamp(rfc3339: b.openedAt))}',
                ].join(' · '),
                leading: const MadarGlyphIcon(
                  MadarGlyph.wallet,
                  size: IconSize.xl,
                ),
                trailing: canForceClose && !b.isThisDevice
                    ? MadarButton(
                        label: t('till.force_close_elsewhere'),
                        variant: MadarButtonVariant.ghost,
                        size: MadarButtonSize.compact,
                        loading: closingId == b.tillId,
                        onTap: () => unawaited(forceClose(b)),
                      )
                    : null,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
