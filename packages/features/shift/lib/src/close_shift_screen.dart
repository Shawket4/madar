/// Close-shift — count the closing drawer and end the shift. A
/// pixel-and-behavior port of the Kotlin CloseShiftScreen.kt: a summary
/// card (teller / opening float / opened-at + the shift's sales figures),
/// the counted-cash card (expected drawer in a tinted teal hero block, the
/// autofocused count, a live over/short banner, and the discrepancy
/// reason), the full Z-report breakdown, the report preview entry, and one
/// loud danger CTA. On a successful close the core marks the shift closed
/// and the shell's route flips back to open-shift via `onStateChanged`.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/material.dart' show Scaffold, Theme;
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (CloseShiftScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Content column cap (natives: widthIn(max = 640.dp)).
const double _contentMaxWidth = 640;

/// Header back chevron (natives: 17.dp) and title size (natives: 17.sp
/// Black; Cairo tops out at ExtraBold so w800 stands in).
const double _headerIconSize = 17;
const double _headerTitleSize = 17;

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

/// The end-of-day drawer count. Takes the shared screen contract: [core]
/// for every bridge call and [onStateChanged] after the close succeeds
/// (the core's `app_route()` flips back to open-shift). Shown over the
/// order screen; the header's back pops it via `Navigator.maybePop`.
class CloseShiftScreen extends StatefulWidget {
  /// Creates the close-shift screen.
  const CloseShiftScreen({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// Invoked after any call that can move `app_route()` (the close).
  final void Function() onStateChanged;

  @override
  State<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends State<CloseShiftScreen> {
  MadarBridge get _bridge => widget.core.bridge;

  int _countedMinor = 0;
  final TextEditingController _note = TextEditingController();
  bool _busy = false;
  String? _error;
  ShiftView? _shift;
  ShiftReportView? _report;

  String _t(String key) => _bridge.tr(key: key);

  /// The count deviates from the system's expected drawer → a closing
  /// reason is required (the open screen's discrepancy pattern).
  bool get _needsReason =>
      _report != null && _countedMinor != _report!.expectedCashMinor;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Prime the screen: the open shift for the summary card (server-fresh
  /// when online, cache otherwise — never let a transient refresh nuke a
  /// good local shift), then the Z-report for the expected drawer figures.
  Future<void> _load() async {
    ShiftView? shift;
    if (_bridge.currentSession()?.online ?? false) {
      try {
        shift = await _bridge.refreshShift();
      } on Exception catch (_) {
        shift = await _currentShiftOrNull();
      }
    } else {
      shift = await _currentShiftOrNull();
    }
    if (!mounted) return;
    setState(() => _shift = shift);
    try {
      final report = await _bridge.shiftReport();
      if (mounted) setState(() => _report = report);
    } on Exception catch (_) {}
  }

  Future<ShiftView?> _currentShiftOrNull() async {
    try {
      return await _bridge.currentShift();
    } on Exception catch (_) {
      return null;
    }
  }

  Future<void> _close() async {
    if (_needsReason && _note.text.trim().isEmpty) {
      // Guidance next to the action that triggers it — the natives'
      // flagError, mirroring the open screen's required reason.
      setState(() => _error = _t('shift.opening_reason_required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = _note.text.trim();
      await _bridge.closeShift(
        closingCashMinor: _countedMinor,
        cashNote: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      // Dismiss the overlay first, then let the shell re-read `app_route()`
      // (shift closed → open-shift).
      await Navigator.of(context).maybePop();
      widget.onStateChanged();
    } on MadarError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _bridge.humanMessage(e);
      });
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _t('err.generic');
      });
    }
  }

  /// Preview the Z-report (paper layout) before printing — works with no
  /// printer, and the Print lives inside the preview.
  Future<void> _openReportPreview() async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ShiftReportSheet(core: widget.core, report: _report),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final currency = _bridge.currentSession()?.currencyCode ?? '';
    // Scaffold: screens own their own Material ancestor in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          _Header(
            title: _t('shift.close_title'),
            subtitle: _t('shift.closing_desc'),
            onBack: () => unawaited(Navigator.of(context).maybePop()),
          ),
          Expanded(
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
                      if (_shift != null)
                        _SummaryCard(
                          shift: _shift!,
                          report: _report,
                          currency: currency,
                          bridge: _bridge,
                        ),
                      _CashCard(
                        countedMinor: _countedMinor,
                        onCountedMinor: (v) =>
                            setState(() => _countedMinor = v),
                        note: _note,
                        needsReason: _needsReason,
                        currency: currency,
                        report: _report,
                        tr: _t,
                      ),
                      if (_report != null)
                        _Card(
                          children: [
                            _CardHeader(
                              icon: 'list.bullet.rectangle',
                              title: _t('shift.report_title'),
                            ),
                            ShiftReportBreakdown(
                              report: _report!,
                              currency: currency,
                              tr: _t,
                            ),
                          ],
                        ),
                      if (_report != null)
                        ShiftButton(
                          label: _t('shift.print_report'),
                          icon: 'printer',
                          variant: ShiftButtonVariant.outline,
                          onTap: () => unawaited(_openReportPreview()),
                        ),
                      if (_error != null)
                        NoticeBanner(
                          text: _error!,
                          tone: ChipTone.danger,
                          icon: 'exclamationmark.circle',
                        ),
                      ShiftButton(
                        label: _t('order.close_shift'),
                        icon: 'lock',
                        variant: ShiftButtonVariant.danger,
                        loading: _busy,
                        onTap: () => unawaited(_close()),
                      ),
                    ],
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

/// Surface top bar: back chevron + title/description, over a hairline.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            child: Row(
              spacing: Space.md,
              children: [
                Semantics(
                  button: true,
                  child: TactileScale(
                    onTap: onBack,
                    child: MadarIcon(
                      'chevron.backward',
                      tint: colors.textPrimary,
                      size: _headerIconSize,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 1,
                    children: [
                      Text(
                        title,
                        style: MadarType.h3.copyWith(
                          fontSize: _headerTitleSize,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: MadarType.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 1, child: ColoredBox(color: colors.border)),
      ],
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
/// pattern).
class _CashCard extends StatelessWidget {
  const _CashCard({
    required this.countedMinor,
    required this.onCountedMinor,
    required this.note,
    required this.needsReason,
    required this.currency,
    required this.report,
    required this.tr,
  });

  final int countedMinor;
  final ValueChanged<int> onCountedMinor;
  final TextEditingController note;
  final bool needsReason;
  final String currency;
  final ShiftReportView? report;
  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
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
          onAmountMinor: onCountedMinor,
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
          Text(value, style: MadarType.money.copyWith(color: colors.accent))
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
