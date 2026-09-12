/// Close shift — count the drawer and end the shift. The expected cash with
/// its arithmetic beside the counted figure; the difference named plainly
/// (Short by / Over by / Drawer matches) with a reason required when the
/// count is off; the Z report preview a row away; and the one red button in
/// the till. iPad: two cards side by side. Phone: the same two, stacked.
///
/// On a successful close the core marks the shift closed; the screen pops
/// first, then hands off to the shell (the route flips). State lives in
/// [closeShiftProvider].
///
/// Not here, on purpose: "− refunds" (no refunds on the report) and
/// "Suggested safe drop" (no standard float anywhere on the wire).
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The counted-cash card's width beside the expected card (canvas: 520).
const double _countedColumnWidth = 520;

/// Arithmetic row height and the expected figure's size (canvas: 32 / 30).
const double _arithmeticRowHeight = 32;
const double _expectedFigureSize = 30;

/// The difference banner (canvas: 40 tall, 14 inset, 10 gap).
const double _bannerHeight = 40;
const double _bannerHPad = 14;
const double _bannerGap = 10;

/// The end-of-day drawer count, pushed over the shell; the header's back
/// pops it via `Navigator.maybePop`.
class CloseShiftScreen extends ConsumerStatefulWidget {
  /// Creates the close-shift screen.
  const CloseShiftScreen({super.key});

  @override
  ConsumerState<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends ConsumerState<CloseShiftScreen> {
  /// Closing note / discrepancy-reason text — widget-local ephemera; visible
  /// state flows from [closeShiftProvider].
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    // Capture the shell hand-off up front: a successful close pops this
    // route, which disposes this widget's ref.
    final shell = ref.read(shellProvider.notifier);
    final ok = await ref
        .read(closeShiftProvider.notifier)
        .close(note: _note.text);
    if (!ok || !mounted) return;
    // Dismiss the overlay first, then let the shell re-read `app_route()`
    // (shift closed → open-shift / the Till tab's open card).
    await Navigator.of(context).maybePop();
    shell.refresh();
  }

  /// Preview the Z-report (paper layout) before printing — works with no
  /// printer, and the Print lives inside the preview.
  Future<void> _openReportPreview(ShiftReportView report) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ShiftReportSheet(report: report),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final layout = context.madarLayout;
    // Narrow slices — the count keystrokes repaint only the counted card.
    final shift = ref.watch(closeShiftProvider.select((s) => s.shift));
    final report = ref.watch(closeShiftProvider.select((s) => s.report));
    final tillName = ref.watch(closeShiftProvider.select((s) => s.tillName));
    final orderCount = ref.watch(
      closeShiftProvider.select((s) => s.orderCount),
    );

    final subtitle = [
      ?tillName,
      if (shift != null) shift.tellerName,
      if (shift != null)
        '${t('till.open_since')} ${bridge.formatTime(rfc3339: shift.openedAt, style: TimeStyle.time)}',
      if (orderCount != null) '$orderCount ${t('shift.orders')}',
    ].join(' · ');

    final expected = _ExpectedCard(
      report: report,
      currency: currency,
      tr: t,
      onPreview: report == null
          ? null
          : () => unawaited(_openReportPreview(report)),
    );
    final counted = _CountedCard(
      note: _note,
      currency: currency,
      tr: t,
      onClose: () => unawaited(_close()),
    );

    // Scaffold: screens own their own Material ancestor in this app.
    return MadarPageScaffold(
      body: Column(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: layout.gutter),
            child: MadarHeader(
              title: t('shift.close_title'),
              subtitle: subtitle.isEmpty ? null : subtitle,
              onBack: () => Navigator.maybePop(context),
              safeTop: true,
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: layout.isTablet
                  ? Padding(
                      padding: EdgeInsetsDirectional.all(layout.gutter),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.lg,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(child: expected),
                          ),
                          SizedBox(
                            width: _countedColumnWidth,
                            child: SingleChildScrollView(child: counted),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: EdgeInsetsDirectional.all(layout.gutter),
                      children: [
                        expected,
                        const SizedBox(height: Space.lg),
                        counted,
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Expected cash and how it was reached: opening float + cash sales + paid
/// in − paid out. Cash sales is the report's own remainder, so the rows
/// always sum to the figure above them — offline too, when "cash sales" is
/// the queued cash the core added to the float. Then the Z report preview.
class _ExpectedCard extends StatelessWidget {
  const _ExpectedCard({
    required this.report,
    required this.currency,
    required this.tr,
    required this.onPreview,
  });

  final ShiftReportView? report;
  final String currency;
  final String Function(String key) tr;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final r = report;
    String money(int minor) => Money.format(minor, currency: currency);
    String plus(int minor) => '+${money(minor)}';
    String minus(int minor) => '−${money(minor)}';
    final cashSales = r == null
        ? 0
        : r.expectedCashMinor -
              r.openingCashMinor -
              r.cashInMinor +
              r.cashOutMinor;
    return MadarCard.column(
      spacing: _statGap,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('shift.expected_cash'),
                style: MadarType.h3.copyWith(color: colors.textPrimary),
              ),
            ),
            if (r == null)
              const SkeletonBlock(height: _expectedFigureSize, width: 140)
            else
              MoneyText(
                r.expectedCashMinor,
                currency: currency,
                style: MadarType.moneyDisplay.copyWith(
                  fontSize: _expectedFigureSize,
                ),
              ),
            if (r != null && !r.fromServer) ...[
              const SizedBox(width: Space.sm),
              MadarTag(label: tr('chrome.offline'), tone: MadarTone.warning),
            ],
          ],
        ),
        const MadarHairline(),
        if (r != null) ...[
          _ArithmeticRow(
            label: tr('shift.opening_float'),
            value: money(r.openingCashMinor),
          ),
          _ArithmeticRow(label: tr('shift.cash_sales'), value: plus(cashSales)),
          _ArithmeticRow(
            label: tr('shift.paid_in'),
            value: plus(r.cashInMinor),
          ),
          _ArithmeticRow(
            label: tr('shift.paid_out'),
            value: minus(r.cashOutMinor),
          ),
          if (r.voidedAmountMinor > 0)
            _ArithmeticRow(
              label: tr('history.voided'),
              value: minus(r.voidedAmountMinor),
              muted: true,
            ),
          const MadarHairline(),
          MadarRow(
            title: tr('shift.z_preview'),
            glyph: MadarGlyph.receipt,
            dense: true,
            onTap: onPreview,
          ),
        ] else
          const SkeletonList(count: 4),
      ],
    );
  }
}

/// A stat card's row rhythm, shared with the Till figures.
const double _statGap = 6;

/// One line of the drawer's arithmetic: quiet label, mono figure.
class _ArithmeticRow extends StatelessWidget {
  const _ArithmeticRow({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;

  /// A line that is shown for the record but is not part of the sum.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return SizedBox(
      height: _arithmeticRowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.body.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: MadarType.money.copyWith(
              color: muted ? colors.textMuted : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The counted-cash card: the autofocused count, the live difference in
/// words, the reason (required when off, an optional note when matched),
/// what closing does, the error next to the action, and the danger button.
/// Watches its own narrow slices so count keystrokes repaint only this card.
class _CountedCard extends ConsumerWidget {
  const _CountedCard({
    required this.note,
    required this.currency,
    required this.tr,
    required this.onClose,
  });

  final TextEditingController note;
  final String currency;
  final String Function(String key) tr;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final countedMinor = ref.watch(
      closeShiftProvider.select((s) => s.countedMinor),
    );
    final expectedMinor = ref.watch(
      closeShiftProvider.select((s) => s.report?.expectedCashMinor),
    );
    final busy = ref.watch(closeShiftProvider.select((s) => s.busy));
    final error = ref.watch(closeShiftProvider.select((s) => s.error));
    final diff = expectedMinor == null ? null : countedMinor - expectedMinor;
    final needsReason = diff != null && diff != 0;
    return MadarCard.column(
      children: [
        MadarSectionHeader(text: tr('shift.counted_cash')),
        MadarAmountField(
          amountMinor: countedMinor,
          onAmountMinor: (v) =>
              ref.read(closeShiftProvider.notifier).setCounted(v),
          currencyCode: currency,
          autofocus: true,
        ),
        if (diff != null)
          _DifferenceBanner(diff: diff, currency: currency, tr: tr),
        MadarField(
          controller: note,
          placeholder: switch (diff) {
            null || 0 => tr('shift.cash_note'),
            < 0 => tr('shift.why_short'),
            _ => tr('shift.why_over'),
          },
          glyph: needsReason ? MadarGlyph.alertCircle : MadarGlyph.note,
        ),
        Text(
          tr('shift.close_hint'),
          style: MadarType.bodySm.copyWith(color: colors.textSecondary),
        ),
        if (error != null)
          NoticeBanner(
            text: error,
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          ),
        MadarButton(
          label: tr('shift.close_title'),
          glyph: MadarGlyph.lock,
          variant: MadarButtonVariant.danger,
          loading: busy,
          enabled: expectedMinor != null,
          tooltip: expectedMinor == null ? tr('chrome.syncing') : null,
          onTap: onClose,
        ),
      ],
    );
  }
}

/// The difference, named: Drawer matches (success), Over by (warning),
/// Short by (danger) — with "reason required" on the end when it is off.
class _DifferenceBanner extends StatelessWidget {
  const _DifferenceBanner({
    required this.diff,
    required this.currency,
    required this.tr,
  });

  final int diff;
  final String currency;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final (Color fg, Color bg, MadarGlyph glyph, String label) = switch (diff) {
      0 => (
        colors.success,
        colors.successBg,
        MadarGlyph.checkCircle,
        tr('shift.drawer_matches'),
      ),
      > 0 => (
        colors.warning,
        colors.warningBg,
        MadarGlyph.alertTriangle,
        tr('shift.drawer_over'),
      ),
      _ => (
        colors.danger,
        colors.dangerBg,
        MadarGlyph.xCircle,
        tr('shift.drawer_short'),
      ),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: _bannerHeight),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: _bannerHPad,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        spacing: _bannerGap,
        children: [
          MadarGlyphIcon(glyph, color: fg),
          // Wraps rather than overflows: on a phone "Short by · figure ·
          // reason required" is wider than the card.
          Expanded(
            child: Wrap(
              spacing: _bannerGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  label,
                  style: MadarType.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (diff != 0)
                  Text(
                    Money.format(diff.abs(), currency: currency),
                    textDirection: TextDirection.ltr,
                    style: MadarType.numLg.copyWith(color: fg),
                  ),
              ],
            ),
          ),
          if (diff != 0)
            Text(
              tr('shift.reason_required'),
              style: MadarType.bodySm.copyWith(color: fg),
            ),
        ],
      ),
    );
  }
}
