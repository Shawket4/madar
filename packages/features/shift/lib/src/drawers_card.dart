/// Drawers — every shift at the branch, on a manager's Till.
///
/// SINGLE TAP on a drawer prints its Z-report straight away — a manager
/// reaching for this row wants the printout, not another screen to tap
/// Print from. LONG PRESS (or the small preview glyph) opens the same
/// report in the shared sheet instead, with its own Print button, for the
/// times the shape needs checking before paper is spent on it. The row
/// alone would hide that second gesture completely, so the preview glyph
/// stays — a person who never long-presses still has a way in.
///
/// What is NOT here, on purpose: Force-close. The wire has
/// `force_close_shift`, the bridge does not, and a button that cannot work
/// is worse than no button — so the card says so in one line instead.
/// The till's NAME is not on `ShiftSummaryView` either, so a row is led by
/// the teller, not the drawer.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart' show printerBrandOf;
import 'package:feature_shift/src/shift_providers.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Row report-fetch spinner (the history rows' 14 / 2).
const double _rowSpinnerSize = 14;
const double _rowSpinnerStroke = 2;

/// How many drawers the card lists before pointing at Past shifts.
const int _maxDrawerRows = 8;

/// ESC/POS character columns — retained for API stability; the raster width
/// actually printed comes from the device's paper config (see
/// `MadarCore::render_shift_report`).
const int _printWidth = 32;

/// A print result fades back to the plain status tag on its own — a manager
/// firing off several drawer printouts shouldn't have to dismiss anything.
const Duration _resultFade = Duration(seconds: 2);

/// Every drawer at the branch, open ones first. Pass [onSeeAll] to route the
/// overflow at Past shifts.
class DrawersCard extends ConsumerWidget {
  /// Creates the card.
  const DrawersCard({super.key, this.onSeeAll});

  /// Opens Past shifts when the list is longer than the card shows.
  final VoidCallback? onSeeAll;

  /// LONG PRESS / preview glyph: fetch the drawer's report and open it in
  /// the shared sheet — the report ITSELF is the preview, Print lives in its
  /// footer.
  Future<void> _preview(
    BuildContext context,
    WidgetRef ref,
    ShiftSummaryView shift,
  ) async {
    MadarHaptics.selection();
    final report = await ref
        .read(tillProvider.notifier)
        .fetchDrawerReport(shift.id);
    if (report == null || !context.mounted) return;
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ShiftReportSheet(report: report, shiftId: shift.id),
    );
  }

  /// SINGLE TAP: render the summary report in the core (collapsed, matching
  /// the preview's default — the natives never auto-expand the orders
  /// breakdown either) and stream it straight to the configured printer.
  /// Returns null when another row's fetch is already in flight
  /// (`fetchDrawerReport`'s own guard) so the row shows nothing rather than
  /// a false failure.
  Future<PrintOutcome?> _printNow(WidgetRef ref, ShiftSummaryView shift) async {
    final report = await ref
        .read(tillProvider.notifier)
        .fetchDrawerReport(shift.id);
    if (report == null) return null;
    final bridge = ref.read(bridgeProvider);
    final config = bridge.deviceConfig();
    final bytes = await bridge.renderShiftReport(
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
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final drawers = ref.watch(tillProvider.select((s) => s.drawers));
    final loading = ref.watch(tillProvider.select((s) => s.loading));
    final loadingId = ref.watch(
      tillProvider.select((s) => s.drawerReportLoadingId),
    );
    final branch = bridge.deviceConfig().branchName?.trim() ?? '';
    final shown = drawers.length > _maxDrawerRows
        ? drawers.sublist(0, _maxDrawerRows)
        : drawers;
    return MadarCard.column(
      flush: true,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
            vertical: Space.lg,
          ),
          child: MadarSectionHeader(
            text: branch.isEmpty
                ? t('till.drawers')
                : '${t('till.drawers')} · $branch',
            trailing: Text(
              '${drawers.where((d) => d.isOpen).length} ${t('shifts.open_now')}',
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        if (loading && drawers.isEmpty)
          const Padding(
            padding: EdgeInsetsDirectional.all(Space.lg),
            child: SkeletonList(count: 3),
          )
        else if (drawers.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Space.card,
              end: Space.card,
              bottom: Space.lg,
            ),
            child: Text(
              t('shifts.empty'),
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          )
        else
          for (final d in shown) ...[
            const MadarHairline.row(),
            _DrawerRow(
              shift: d,
              currency: currency,
              bridge: bridge,
              loading: loadingId == d.id,
              onPrintNow: () => _printNow(ref, d),
              onPreview: () => unawaited(_preview(context, ref, d)),
            ),
          ],
        if (drawers.length > shown.length && onSeeAll != null) ...[
          const MadarHairline.row(),
          MadarRow(
            title: t('shifts.title'),
            glyph: MadarGlyph.clock,
            value: Text('${drawers.length - shown.length}'),
            onTap: onSeeAll,
          ),
        ],
        const MadarHairline.row(),
        // Honest about the one thing the design asks for that the bridge
        // cannot do yet.
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
            vertical: Space.md,
          ),
          child: Text(
            t('till.force_close_unavailable'),
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// One drawer: the state bar carries open / closed / force-closed, the
/// teller leads, the opened time follows, the declared close (when there is
/// one) sits at the end under a state tag — replaced for a couple of
/// seconds by the print outcome when the row itself just printed.
class _DrawerRow extends StatefulWidget {
  const _DrawerRow({
    required this.shift,
    required this.currency,
    required this.bridge,
    required this.loading,
    required this.onPrintNow,
    required this.onPreview,
  });

  final ShiftSummaryView shift;
  final String currency;
  final MadarBridge bridge;

  /// True while THIS row's report is being fetched — for the print or for
  /// the preview, `fetchDrawerReport` cannot tell them apart and doesn't
  /// need to.
  final bool loading;

  /// SINGLE TAP.
  final Future<PrintOutcome?> Function() onPrintNow;

  /// LONG PRESS and the preview glyph.
  final VoidCallback onPreview;

  @override
  State<_DrawerRow> createState() => _DrawerRowState();
}

class _DrawerRowState extends State<_DrawerRow> {
  bool _printing = false;
  PrintOutcome? _result;

  Future<void> _handlePrintNow() async {
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
    final colors = context.madarColors;
    final s = widget.shift;
    String t(String key) => widget.bridge.tr(key: key);
    final (MadarTone tone, String label) = switch (s.status) {
      'open' => (MadarTone.success, t('shifts.open_now')),
      'force_closed' => (MadarTone.danger, t('shifts.force_closed')),
      _ => (MadarTone.neutral, t('shifts.closed')),
    };
    final opened = widget.bridge.formatTime(
      rfc3339: s.openedAt,
      style: s.isOpen ? TimeStyle.time : TimeStyle.dateTime,
    );
    final declared = s.closingDeclaredMinor;
    final busy = widget.loading || _printing;
    final result = _result;
    final statusChip = busy
        ? SizedBox.square(
            dimension: _rowSpinnerSize,
            child: CircularProgressIndicator(
              color: colors.accent,
              strokeWidth: _rowSpinnerStroke,
            ),
          )
        : switch (result) {
            PrintOutcome.printed => MadarTag(
              label: t('receipt.printed'),
              tone: MadarTone.success,
            ),
            PrintOutcome.noPrinter => MadarTag(
              label: t('receipt.no_printer'),
              tone: MadarTone.warning,
            ),
            PrintOutcome.failed => MadarTag(
              label: t('receipt.print_failed'),
              tone: MadarTone.danger,
            ),
            null => MadarTag(label: label, tone: tone),
          };
    return GestureDetector(
      // LONG PRESS opens the preview — TactileScale below owns the tap so
      // its press-scale + haptic still fire on the print, exactly like the
      // sell screen's item tiles (long-press outer, tap inner).
      onLongPress: busy ? null : widget.onPreview,
      child: TactileScale(
        onTap: busy ? null : () => unawaited(_handlePrintNow()),
        child: MadarRow(
          title: s.tellerName ?? '—',
          subtitle: '${t('shift.opened_at')} $opened',
          bar: tone.color(colors),
          value: declared == null
              ? null
              : MoneyText(
                  declared,
                  currency: widget.currency,
                  color: colors.textPrimary,
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              statusChip,
              // Discoverability: long-press has no visible affordance of
              // its own, and a manager who never discovers it would never
              // find the preview at all — this glyph-only button is the
              // same action, always in reach, from the control kit rather
              // than a bespoke tap target.
              MadarButton(
                label: '',
                glyph: MadarGlyph.receipt,
                variant: MadarButtonVariant.ghost,
                size: MadarButtonSize.compact,
                tooltip: t('chrome.view'),
                enabled: !busy,
                onTap: widget.onPreview,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
