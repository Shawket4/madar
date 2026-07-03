/// Close-shift — count the closing drawer and end the shift. A
/// pixel-and-behavior port of the Kotlin CloseShiftScreen.kt: a summary
/// card (teller / opening float / opened-at + the shift's sales figures),
/// the counted-cash card (expected drawer in a tinted teal hero block, the
/// autofocused count, a live over/short banner, and the discrepancy
/// reason), the full Z-report breakdown, the report preview entry, and one
/// loud danger CTA. On a successful close the core marks the shift closed;
/// the screen pops the overlay first, then hands off to the shell (route
/// flips back to open-shift). State lives in [closeShiftProvider].
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/material.dart' show Scaffold, Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (CloseShiftScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Content column cap (natives: widthIn(max = 640.dp)).
const double _contentMaxWidth = 640;

/// Card-header tone tile (natives: 34.dp square, Radii.sm).
const double _headerTileSize = 34;

/// Expected-cash block insets (natives: h 16.dp / v 14.dp) and money size
/// (natives: 20.sp Black tabular).
const double _expectedVPad = 14;
const double _expectedMoneySize = 20;

/// Discrepancy banner insets/gap (natives: 14/12/10.dp).
const double _bannerHPad = 14;
const double _bannerVPad = 12;
const double _bannerGap = 10;

/// The end-of-day drawer count, shown over the order screen; the header's
/// back pops it via `Navigator.maybePop`.
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
    // (shift closed → open-shift).
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
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    // Narrow slices — the count keystrokes repaint only the cash card below.
    final shift = ref.watch(closeShiftProvider.select((s) => s.shift));
    final report = ref.watch(closeShiftProvider.select((s) => s.report));
    final busy = ref.watch(closeShiftProvider.select((s) => s.busy));
    final error = ref.watch(closeShiftProvider.select((s) => s.error));
    // Scaffold: screens own their own Material ancestor in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          MadarHeader(
            title: t('shift.close_title'),
            subtitle: t('shift.closing_desc'),
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(Space.xl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.lg,
                      children: [
                        if (shift != null)
                          _SummaryCard(
                            shift: shift,
                            report: report,
                            currency: currency,
                            bridge: bridge,
                          ),
                        _CashCard(note: _note, currency: currency, tr: t),
                        if (report != null)
                          _Card(
                            children: [
                              _CardHeader(
                                icon: 'list.bullet.rectangle',
                                title: t('shift.report_title'),
                              ),
                              ShiftReportBreakdown(
                                report: report,
                                currency: currency,
                                tr: t,
                              ),
                            ],
                          ),
                        if (report != null)
                          ShiftButton(
                            label: t('shift.print_report'),
                            icon: 'printer',
                            variant: ShiftButtonVariant.outline,
                            onTap: () => unawaited(_openReportPreview(report)),
                          ),
                        if (error != null)
                          NoticeBanner(
                            text: error,
                            tone: ChipTone.danger,
                            icon: 'exclamationmark.circle',
                          ),
                        ShiftButton(
                          label: t('order.close_shift'),
                          icon: 'lock',
                          variant: ShiftButtonVariant.danger,
                          loading: busy,
                          onTap: () => unawaited(_close()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shift-summary card: teller, opening float (hero money), opened-at —
/// plus the shift's headline figures (sales / cash / card / voided) once
/// the Z-report lands.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.shift,
    required this.report,
    required this.currency,
    required this.bridge,
  });

  final ShiftView shift;
  final ShiftReportView? report;
  final String currency;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) {
    String t(String key) => bridge.tr(key: key);
    String money(int minor) => Money.format(minor, currency: currency);
    final report = this.report;
    return _Card(
      children: [
        _CardHeader(icon: 'doc.text', title: t('shift.summary')),
        _InfoRow(label: t('shift.teller'), value: shift.tellerName),
        // Opening cash is money — the hero treatment (bold teal, tabular).
        _InfoRow(
          label: t('shift.opening_cash'),
          value: money(shift.openingCashMinor),
          money: true,
        ),
        _InfoRow(
          label: t('shift.opened_at'),
          value: bridge.formatTime(
            rfc3339: shift.openedAt,
            style: TimeStyle.dateTime,
          ),
        ),
        // Headline figures once the Z-report lands (sales + voids up top;
        // the per-method cash/card split lives in the report card below).
        if (report != null) ...[
          _InfoRow(
            label: t('shift.payments'),
            value: money(report.totalPaymentsMinor),
            money: true,
          ),
          if (report.voidedAmountMinor > 0)
            _InfoRow(
              label: t('history.voided'),
              value: '−${money(report.voidedAmountMinor)}',
              money: true,
            ),
        ],
      ],
    );
  }
}

/// The counted-cash card: expected drawer (hero teal block), the count
/// itself, the live over/short banner, and the note — which becomes the
/// REQUIRED discrepancy reason when the count deviates (the open screen's
/// pattern). Watches its own narrow slices so count keystrokes repaint only
/// this card.
class _CashCard extends ConsumerWidget {
  const _CashCard({
    required this.note,
    required this.currency,
    required this.tr,
  });

  final TextEditingController note;
  final String currency;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countedMinor = ref.watch(
      closeShiftProvider.select((s) => s.countedMinor),
    );
    final needsReason = ref.watch(
      closeShiftProvider.select((s) => s.needsReason),
    );
    final report = ref.watch(closeShiftProvider.select((s) => s.report));
    return _Card(
      children: [
        _CardHeader(icon: 'banknote', title: tr('shift.counted_cash')),
        // System (expected) cash — the figure the count is measured
        // against, so it gets the hero money treatment in a tinted teal
        // block (mirrors the order screen's grand-total block).
        if (report != null)
          _ExpectedCashBlock(
            expectedMinor: report.expectedCashMinor,
            currency: currency,
            tr: tr,
          ),
        AmountField(
          amountMinor: countedMinor,
          onAmountMinor: (v) =>
              ref.read(closeShiftProvider.notifier).setCounted(v),
          currencyCode: currency,
          autofocus: true,
        ),
        if (report != null)
          _DiscrepancyBanner(
            declaredMinor: countedMinor,
            expectedMinor: report.expectedCashMinor,
            currency: currency,
            tr: tr,
          ),
        ShiftTextField(
          controller: note,
          placeholder: needsReason
              ? tr('shift.opening_reason_label')
              : tr('shift.cash_note'),
          icon: needsReason ? 'exclamationmark.bubble' : 'note.text',
        ),
      ],
    );
  }
}

/// The system-expected cash — bold teal money in a tinted teal block, the
/// figure the declared count is reconciled against.
class _ExpectedCashBlock extends StatelessWidget {
  const _ExpectedCashBlock({
    required this.expectedMinor,
    required this.currency,
    required this.tr,
  });

  final int expectedMinor;
  final String currency;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accentBg,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.lg,
          vertical: _expectedVPad,
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    tr('shift.system_cash'),
                    style: MadarType.label.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.accent,
                    ),
                  ),
                  Text(
                    tr('shift.system_cash_explain'),
                    style: MadarType.labelSm.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            MoneyText(
              expectedMinor,
              currency: currency,
              style: MadarType.moneyLg.copyWith(
                fontSize: _expectedMoneySize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live drawer variance: matched (success), over (warning), short (danger).
class _DiscrepancyBanner extends StatelessWidget {
  const _DiscrepancyBanner({
    required this.declaredMinor,
    required this.expectedMinor,
    required this.currency,
    required this.tr,
  });

  final int declaredMinor;
  final int expectedMinor;
  final String currency;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final diff = declaredMinor - expectedMinor;
    final (Color fg, Color bg, String icon, String label) = switch (diff) {
      0 => (
        colors.success,
        colors.successBg,
        'checkmark.circle',
        tr('shift.drawer_matches'),
      ),
      > 0 => (
        colors.warning,
        colors.warningBg,
        'arrow.up.circle',
        '${tr('shift.drawer_over')} '
            '${Money.format(diff, currency: currency)}',
      ),
      _ => (
        colors.danger,
        colors.dangerBg,
        'arrow.down.circle',
        '${tr('shift.drawer_short')} '
            '${Money.format(-diff, currency: currency)}',
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: fg.withValues(alpha: Opacities.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: _bannerHPad,
          vertical: _bannerVPad,
        ),
        child: Row(
          spacing: _bannerGap,
          children: [
            MadarIcon(icon, tint: fg),
            Expanded(
              child: Text(
                label,
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The close screen's card primitive (natives: Radii.md, CARD elevation,
/// borderLight hairline, Space.lg inset, Space.md rhythm).
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
        boxShadow: MadarElevation.card.shadows(colors, dark: dark),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: children,
        ),
      ),
    );
  }
}

/// Leading teal tone-tile behind the glyph + a bold card title — matches
/// the confident Kitchen/Order/Sync header (accentBg + accent icon).
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.icon, required this.title});

  final String icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.sm,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accentBg,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: SizedBox.square(
            dimension: _headerTileSize,
            child: Center(
              child: MadarIcon(icon, tint: colors.accent, size: IconSize.lg),
            ),
          ),
        ),
        Expanded(
          child: Text(
            title,
            style: MadarType.h3.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Quiet label/value row; money values are the hero — bold teal, tabular.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.money = false,
  });

  final String label;
  final String value;
  final bool money;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
        ),
        if (money)
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: MadarType.money.copyWith(color: colors.accent),
          )
        else
          Text(
            value,
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
      ],
    );
  }
}
