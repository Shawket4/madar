/// Drawers — every till at the branch, on a manager's Till.
///
/// Each drawer is a bill row (docs/design/SPEC.md §7): tapping it opens its
/// report on screen, with Print in the sheet; the print tile on the row
/// prints it straight away and says, for a moment, what the printer did.
/// Both are visible — no long press to discover.
///
/// What is NOT here, on purpose: Force-close. The wire has
/// `force_close_till`, the bridge does not, and a button that cannot work
/// is worse than no button — so the card says so in one line instead.
/// The till's NAME is not on `TillSummaryView` either, so a row is led by
/// the teller, not the drawer.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart' show printerBrandOf;
import 'package:feature_till/src/till_history_screen.dart' show tillStatus;
import 'package:feature_till/src/till_providers.dart';
import 'package:feature_till/src/till_report_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// How many drawers the card lists before pointing at Past tills.
const int _maxDrawerRows = 8;

/// ESC/POS character columns — retained for API stability; the raster width
/// actually printed comes from the device's paper config (see
/// `MadarCore::render_till_report`).
const int _printWidth = 32;

/// A print result fades back to the plain status tag on its own — a manager
/// firing off several drawer printouts shouldn't have to dismiss anything.
const Duration _resultFade = Duration(seconds: 2);

/// Every drawer at the branch, open ones first. Pass [onSeeAll] to route the
/// overflow at Past tills.
class DrawersCard extends ConsumerWidget {
  /// Creates the card.
  const DrawersCard({super.key, this.onSeeAll});

  /// Opens Past tills when the list is longer than the card shows.
  final VoidCallback? onSeeAll;

  /// LONG PRESS / preview glyph: fetch the drawer's report and open it in
  /// the shared sheet — the report ITSELF is the preview, Print lives in its
  /// footer.
  Future<void> _preview(
    BuildContext context,
    WidgetRef ref,
    TillSummaryView till,
  ) async {
    MadarHaptics.selection();
    final report = await ref
        .read(tillProvider.notifier)
        .fetchDrawerReport(till.id);
    if (report == null || !context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => TillReportSheet(report: report, tillId: till.id),
    );
  }

  /// SINGLE TAP: render the summary report in the core (collapsed, matching
  /// the preview's default — the natives never auto-expand the orders
  /// breakdown either) and stream it straight to the configured printer.
  /// Returns null when another row's fetch is already in flight
  /// (`fetchDrawerReport`'s own guard) so the row shows nothing rather than
  /// a false failure.
  Future<PrintOutcome?> _printNow(WidgetRef ref, TillSummaryView till) async {
    final report = await ref
        .read(tillProvider.notifier)
        .fetchDrawerReport(till.id);
    if (report == null) return null;
    final bridge = ref.read(bridgeProvider);
    final config = bridge.deviceConfig();
    final bytes = await bridge.renderTillReport(
      report: report,
      storeName: config.branchName ?? '',
      currency: bridge.currentSession()?.currencyCode ?? '',
      width: _printWidth,
      brand: printerBrandOf(config.printerBrand),
      orders: const [],
    );
    return await ref.read(printerServiceProvider).printBytes(bytes);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final drawers = ref.watch(tillProvider.select((s) => s.drawers));
    final loading = ref.watch(tillProvider.select((s) => s.loading));
    final loadingId = ref.watch(
      tillProvider.select((s) => s.drawerReportLoadingId),
    );
    final shown = drawers.length > _maxDrawerRows
        ? drawers.sublist(0, _maxDrawerRows)
        : drawers;
    final open = drawers.where((d) => d.isOpen).length;

    final Widget card;
    if (loading && drawers.isEmpty) {
      card = const MadarCard(
        flush: true,
        child: SkeletonScope(child: SkeletonList(count: 3)),
      );
    } else if (drawers.isEmpty) {
      card = MadarCard(
        child: EmptyState(icon: 'tray', title: t('shifts.empty')),
      );
    } else {
      card = MadarCard.column(
        flush: true,
        children: [
          for (final (i, d) in shown.indexed) ...[
            if (i > 0) const MadarHairline.row(),
            _Drawer(
              till: d,
              currency: currency,
              bridge: bridge,
              loading: loadingId == d.id,
              onPrintNow: () => _printNow(ref, d),
              onPreview: () => unawaited(_preview(context, ref, d)),
            ),
          ],
          // Honest about the one thing the design asks for that the bridge
          // cannot do yet.
          const MadarHairline.row(),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.card,
              vertical: Space.md,
            ),
            child: Text(
              t('till.force_close_unavailable'),
              style: MadarType.bodySm.copyWith(
                color: context.madarColors.textMuted,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(
          text: t('till.drawers'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              Text(
                '${MadarFormat.ltr('$open')} ${t('tills.open_now')}',
                style: MadarType.bodySm.copyWith(
                  color: context.madarColors.textSecondary,
                ),
              ),
              if (drawers.length > shown.length && onSeeAll != null)
                MadarButton(
                  label: t('chrome.see_all'),
                  variant: MadarButtonVariant.ghost,
                  size: MadarButtonSize.compact,
                  onTap: onSeeAll!,
                ),
            ],
          ),
        ),
        card,
      ],
    );
  }
}

/// One drawer as a bill row: teller, when it opened, the declared close,
/// its state (or, for a moment, what its printout did). Tapping the row
/// opens the report; the print tile prints it straight away.
class _Drawer extends StatefulWidget {
  const _Drawer({
    required this.till,
    required this.currency,
    required this.bridge,
    required this.loading,
    required this.onPrintNow,
    required this.onPreview,
  });

  final TillSummaryView till;
  final String currency;
  final MadarBridge bridge;

  /// True while THIS drawer's report is being fetched.
  final bool loading;
  final Future<PrintOutcome?> Function() onPrintNow;
  final VoidCallback onPreview;

  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> {
  bool _printing = false;
  PrintOutcome? _result;

  Future<void> _print() async {
    if (_printing || widget.loading) return;
    setState(() {
      _printing = true;
      _result = null;
    });
    final outcome = await widget.onPrintNow();
    if (!mounted) return;
    setState(() {
      _printing = false;
      _result = outcome;
    });
    if (outcome == null) return;
    unawaited(
      Future<void>.delayed(_resultFade, () {
        if (mounted && _result == outcome) setState(() => _result = null);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.till;
    final bridge = widget.bridge;
    String t(String key) => bridge.tr(key: key);
    final busy = widget.loading || _printing;
    final status = switch (_result) {
      PrintOutcome.printed => MadarStatus(
        t('receipt.printed'),
        tone: MadarTone.success,
      ),
      PrintOutcome.noPrinter => MadarStatus(
        t('receipt.no_printer'),
        tone: MadarTone.warning,
      ),
      PrintOutcome.failed => MadarStatus(
        t('receipt.print_failed'),
        tone: MadarTone.danger,
      ),
      null => tillStatus(bridge, s),
    };
    return MadarListRow.bill(
      title: s.tellerName ?? '—',
      meta:
          '${t('till.opened_at')} '
          '${MadarFormat.isolate(bridge.formatStamp(rfc3339: s.openedAt))}',
      minor: s.closingDeclaredMinor,
      currency: widget.currency,
      status: status,
      rail: switch (status.tone) {
        MadarTone.danger || MadarTone.warning => status.tone,
        _ => null,
      },
      onTap: busy ? null : widget.onPreview,
      trailing: busy
          ? const SizedBox.square(
              dimension: Metrics.glyphTile,
              child: Center(child: MadarSpinner()),
            )
          : MadarGlyphTile(
              glyph: MadarGlyph.printer,
              semanticLabel: t('till.print_report'),
              onTap: () => unawaited(_print()),
            ),
    );
  }
}
