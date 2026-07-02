/// Z-report preview — the pixel-and-behavior port of ShiftReportPreview.kt:
/// the shared `ShiftReportBreakdown` (per-method sales with proportional
/// bars, drawer pay-in/out + itemised movements, voids, totals and the
/// close reconciliation), presented as a sheet on a white "thermal paper"
/// card (ReceiptPaper.kt's visual language — always white paper with dark
/// ink, in BOTH themes) with a Print footer that renders the report in the
/// core and streams the bytes to the configured network printer.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

// ── Native metrics (ShiftReportPreview.kt / ReceiptPaper.kt) that fall
// between the 4-pt Space steps — kept verbatim so the Flutter paper
// measures identically to the Kotlin/Swift natives. ─────────────────────────

/// Paper card cap / corner / inset (natives: 360.dp / 10.dp / 18.dp).
const double _paperMaxWidth = 360;
const double _paperRadius = 10;
const double _paperPad = 18;

/// Paper row rhythm (natives: spacedBy(6.dp)).
const double _paperGap = 6;

/// Header title size (natives: 18.sp Black; Cairo tops out at ExtraBold so
/// w800 stands in for the natives' Black).
const double _headerTitleSize = 18;

/// Store-name line on the paper (natives: 15.sp Bold).
const double _storeNameSize = 15;

/// Proportional method bar height (natives: 5.dp) and its floor fraction.
const double _barHeight = 5;
const double _barMinFraction = 0.02;

/// Movement-list rhythm (natives: spacedBy(3.dp)).
const double _movementGap = 3;

/// Emphasized total-row sizes (natives: label 15.sp / value 16.sp).
const double _totalLabelSize = 15;
const double _totalValueSize = 16;

/// Quiet row sizes (natives: label/value 13.sp, meta 11.sp).
const double _rowSize = 13;
const double _metaSize = 11;

/// ESC/POS character columns (natives: renderShiftReport(..., 32u, ...)).
const int _printWidth = 32;

/// Default JetDirect printer port (natives: parsePrinter's 9100).
const int _printerPort = 9100;

// ── Theme-invariant "thermal paper" ink (ReceiptPaper.kt): a receipt is
// always white paper with dark ink, so these are fixed, not tokens. ─────────
const Color _paper = Color(0xFFFFFFFF);
const Color _ink = Color(0xFF1A1A1A);
const Color _faint = Color(0xFF6B6B6B);
const Color _rule = Color(0xFFCCCCCC);
const Color _inkTrack = Color(0xFFEEEEEE);
const Color _inkSuccess = Color(0xFF2E7D32);
const Color _inkDanger = Color(0xFFB71C1C);
const Color _inkWarning = Color(0xFFB26A00);

/// The natives' `PrintState` — the terminal print feedback the teller needs
/// (sent / no printer bound / unreachable).
enum _PrintState { idle, printing, printed, noPrinter, failed }

/// Tone set `ShiftReportBreakdown` renders with: the theme palette inside
/// the close-shift report card (Kotlin ShiftReportBreakdown), or fixed
/// ink-on-paper inside the Z-report preview sheet.
class ShiftReportPalette {
  /// Creates an explicit tone set.
  const ShiftReportPalette({
    required this.strong,
    required this.soft,
    required this.muted,
    required this.rule,
    required this.positive,
    required this.negative,
    required this.caution,
    required this.barTrack,
    required this.barCash,
    required this.barOther,
  });

  /// The theme-driven palette (the Kotlin breakdown's madarColors mapping).
  factory ShiftReportPalette.of(MadarColors colors) => ShiftReportPalette(
    strong: colors.textPrimary,
    soft: colors.textSecondary,
    muted: colors.textMuted,
    rule: colors.border,
    positive: colors.success,
    negative: colors.danger,
    caution: colors.warning,
    barTrack: colors.surfaceAlt,
    barCash: colors.success,
    barOther: colors.accent,
  );

  /// Fixed ink-on-white for the paper preview (theme-invariant).
  static const ShiftReportPalette paper = ShiftReportPalette(
    strong: _ink,
    soft: _ink,
    muted: _faint,
    rule: _rule,
    positive: _inkSuccess,
    negative: _inkDanger,
    caution: _inkWarning,
    barTrack: _inkTrack,
    barCash: _inkSuccess,
    barOther: _ink,
  );

  /// Primary row text.
  final Color strong;

  /// Quiet row labels.
  final Color soft;

  /// Meta text (order counts, movement notes).
  final Color muted;

  /// Hairline dividers.
  final Color rule;

  /// Cash-in / matched tones.
  final Color positive;

  /// Cash-out / short / void tones.
  final Color negative;

  /// Over / mismatch tones.
  final Color caution;

  /// Proportional bar track.
  final Color barTrack;

  /// Bar fill for cash methods.
  final Color barCash;

  /// Bar fill for non-cash methods.
  final Color barOther;
}

/// The Z-report breakdown — per-method sales rows with proportional bars,
/// drawer pay-in/out (with each itemised movement), the voided total,
/// payments + opening cash (and the opening mismatch with its reason), the
/// expected cash, and — once the shift is closed — the counted drawer and
/// the over/short difference. Port of Kotlin's `ShiftReportBreakdown`,
/// reused by the close-shift report card and this preview sheet.
class ShiftReportBreakdown extends StatelessWidget {
  /// Creates the breakdown for [report], formatting money in [currency] and
  /// resolving strings through [tr].
  const ShiftReportBreakdown({
    required this.report,
    required this.currency,
    required this.tr,
    this.palette,
    super.key,
  });

  /// The rendered report.
  final ShiftReportView report;

  /// ISO currency code for the money rows.
  final String currency;

  /// Core-localized string lookup (`bridge.tr`).
  final String Function(String key) tr;

  /// Tone override — defaults to the theme palette.
  final ShiftReportPalette? palette;

  String _money(int minor) => Money.format(minor, currency: currency);

  @override
  Widget build(BuildContext context) {
    final p = palette ?? ShiftReportPalette.of(context.madarColors);
    var maxLine = 0;
    for (final line in report.paymentLines) {
      if (line.totalMinor > maxLine) maxLine = line.totalMinor;
    }
    if (maxLine < 1) maxLine = 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (report.paymentLines.isEmpty)
          Text(
            tr('history.empty'),
            style: MadarType.label.copyWith(
              fontWeight: FontWeight.w400,
              color: p.muted,
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              for (final line in report.paymentLines)
                _MethodRow(
                  line: line,
                  maxLine: maxLine,
                  currency: currency,
                  palette: p,
                ),
            ],
          ),
        _Rule(color: p.rule),
        if (report.cashInMinor > 0)
          _TotalRow(
            label: tr('shift.cash_in'),
            value: _money(report.cashInMinor),
            tone: p.positive,
            palette: p,
          ),
        if (report.cashOutMinor > 0)
          _TotalRow(
            label: tr('shift.cash_out'),
            value: '−${_money(report.cashOutMinor)}',
            tone: p.negative,
            palette: p,
          ),
        if (report.cashMovements.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _movementGap,
              children: [
                for (final m in report.cashMovements)
                  _MovementRow(movement: m, currency: currency, palette: p),
              ],
            ),
          ),
        if (report.voidedAmountMinor > 0)
          _TotalRow(
            label: tr('history.voided'),
            value: '−${_money(report.voidedAmountMinor)}',
            tone: p.negative,
            palette: p,
          ),
        _Rule(color: p.rule),
        _TotalRow(
          label: tr('shift.payments'),
          value: _money(report.totalPaymentsMinor),
          tone: p.strong,
          palette: p,
        ),
        // Opening float (drawer carry-over) — the base Expected cash builds on.
        _TotalRow(
          label: tr('shift.opening_cash'),
          value: _money(report.openingCashMinor),
          tone: p.strong,
          palette: p,
        ),
        // Opening mismatch — the counted opening float differed from the
        // suggested (last close); the signed difference + the teller's reason.
        if (report.openingCashWasEdited) ...[
          if (report.openingCashOriginalMinor != null)
            _TotalRow(
              label: tr('shift.opening_mismatch'),
              value: _signed(
                report.openingCashMinor - report.openingCashOriginalMinor!,
              ),
              tone: report.openingCashMinor == report.openingCashOriginalMinor
                  ? p.soft
                  : p.caution,
              palette: p,
            ),
          if ((report.openingCashEditReason ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.sm),
              child: Text(
                '${tr('shift.opening_reason_label')}: '
                '${report.openingCashEditReason}',
                style: MadarType.labelSm.copyWith(
                  fontWeight: FontWeight.w400,
                  color: p.muted,
                ),
              ),
            ),
        ],
        _TotalRow(
          label: tr('shift.expected_cash'),
          value: _money(report.expectedCashMinor),
          tone: p.strong,
          palette: p,
          emphasized: true,
        ),
        // Reconciliation — the counted drawer + over/short, present once the
        // shift is closed (declared cash set). Mirrors the printed Z-report.
        if (report.closingCashDeclaredMinor != null) ...[
          _TotalRow(
            label: tr('shift.counted_cash'),
            value: _money(report.closingCashDeclaredMinor!),
            tone: p.strong,
            palette: p,
            emphasized: true,
          ),
          _differenceRow(
            report.expectedCashMinor - report.closingCashDeclaredMinor!,
            p,
          ),
        ],
      ],
    );
  }

  Widget _differenceRow(int diff, ShiftReportPalette p) {
    if (diff == 0) {
      return _TotalRow(
        label: tr('shift.difference'),
        value: _money(0),
        tone: p.positive,
        palette: p,
      );
    }
    if (diff > 0) {
      return _TotalRow(
        label: tr('shift.drawer_short'),
        value: _money(diff),
        tone: p.negative,
        palette: p,
      );
    }
    return _TotalRow(
      label: tr('shift.drawer_over'),
      value: _money(-diff),
      tone: p.caution,
      palette: p,
    );
  }

  String _signed(int diff) =>
      (diff < 0 ? '−' : '+') + Money.format(diff.abs(), currency: currency);
}

/// One payment-method line: name · order count · total, over a proportional
/// bar (cash tinted success, everything else accent/ink).
class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.line,
    required this.maxLine,
    required this.currency,
    required this.palette,
  });

  final ShiftReportPaymentLine line;
  final int maxLine;
  final String currency;
  final ShiftReportPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final fraction = (line.totalMinor / maxLine).clamp(_barMinFraction, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xs,
      children: [
        Row(
          children: [
            Text(
              line.method,
              style: MadarType.money.copyWith(
                fontSize: _rowSize,
                fontWeight: FontWeight.w600,
                color: p.strong,
              ),
            ),
            Text(
              ' · ${line.orderCount}',
              style: MadarType.labelSm.copyWith(
                fontWeight: FontWeight.w400,
                color: p.muted,
              ),
            ),
            const Spacer(),
            MoneyText(
              line.totalMinor,
              currency: currency,
              style: MadarType.money.copyWith(fontSize: _rowSize),
              color: p.strong,
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.pill),
          child: SizedBox(
            height: _barHeight,
            child: ColoredBox(
              color: p.barTrack,
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: fraction,
                child: ColoredBox(color: line.isCash ? p.barCash : p.barOther),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One itemised drawer movement: note (or who moved it) + the signed amount.
class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.movement,
    required this.currency,
    required this.palette,
  });

  final ShiftReportCashLine movement;
  final String currency;
  final ShiftReportPalette palette;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final out = m.amountMinor < 0;
    return Row(
      children: [
        Expanded(
          child: Text(
            m.note.trim().isEmpty ? m.movedByName : m.note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.labelSm.copyWith(
              fontWeight: FontWeight.w400,
              color: palette.muted,
            ),
          ),
        ),
        Text(
          (out ? '−' : '+') +
              Money.format(m.amountMinor.abs(), currency: currency),
          style: MadarType.money.copyWith(
            fontSize: _metaSize,
            fontWeight: FontWeight.w600,
            color: out ? palette.negative : palette.positive,
          ),
        ),
      ],
    );
  }
}

/// A quiet (or emphasized) label/value totals row — tabular money values.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    required this.tone,
    required this.palette,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color tone;
  final ShiftReportPalette palette;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasized
                ? MadarType.title.copyWith(
                    fontSize: _totalLabelSize,
                    fontWeight: FontWeight.w700,
                    color: palette.strong,
                  )
                : MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w500,
                    color: palette.soft,
                  ),
          ),
        ),
        Text(
          value,
          style: MadarType.money.copyWith(
            fontSize: emphasized ? _totalValueSize : _rowSize,
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            color: tone,
          ),
        ),
      ],
    );
  }
}

/// 1-px hairline divider.
class _Rule extends StatelessWidget {
  const _Rule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 1, child: ColoredBox(color: color));
  }
}

/// The Z-report preview sheet — Print WITHOUT closing the shift. Shows the
/// CURRENT shift's report by default, or a specific past-shift [report]
/// (from Past Shifts). Fully on-screen, so it works with no printer; the
/// footer carries the natives' terminal print feedback (sent / no printer /
/// failed). Present with [showMadarSheet] — the sheet gets its Material
/// ancestor from MadarSheet; dismiss returns via `Navigator.maybePop`.
class ShiftReportSheet extends StatefulWidget {
  /// Creates the preview; a null [report] loads the current shift's.
  const ShiftReportSheet({required this.core, this.report, super.key});

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// A pre-fetched report (close-shift / past shifts), or null to load the
  /// current shift's on entry.
  final ShiftReportView? report;

  @override
  State<ShiftReportSheet> createState() => _ShiftReportSheetState();
}

class _ShiftReportSheetState extends State<ShiftReportSheet> {
  MadarBridge get _bridge => widget.core.bridge;

  ShiftReportView? _report;
  _PrintState _print = _PrintState.idle;

  String _t(String key) => _bridge.tr(key: key);

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    if (_report == null) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final report = await _bridge.shiftReport();
      if (mounted) setState(() => _report = report);
    } on Exception catch (_) {}
  }

  /// Render the Z-report in the core and stream the bytes to the device's
  /// configured network printer — the natives' printReportView: no printer
  /// bound is a distinct state (not a failure), and the send is best-effort.
  Future<void> _printReport() async {
    final report = _report;
    if (report == null || _print == _PrintState.printing) return;
    final config = _bridge.deviceConfig();
    final host = config.printerHost?.trim() ?? '';
    if (host.isEmpty) {
      setState(() => _print = _PrintState.noPrinter);
      return;
    }
    setState(() => _print = _PrintState.printing);
    try {
      final bytes = await _bridge.renderShiftReport(
        report: report,
        storeName: config.branchName ?? '',
        currency: _bridge.currentSession()?.currencyCode ?? '',
        width: _printWidth,
        brand: config.printerBrand == 'star'
            ? PrinterBrand.star
            : PrinterBrand.epson,
      );
      await _bridge.sendToPrinter(
        host: host,
        port: config.printerPort ?? _printerPort,
        bytes: bytes,
      );
      if (mounted) setState(() => _print = _PrintState.printed);
    } on Exception catch (_) {
      if (mounted) setState(() => _print = _PrintState.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header: title + teller, and the report's data source ──────────
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          child: Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('shift.report_title'),
                      style: MadarType.h2.copyWith(
                        fontSize: _headerTitleSize,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (report != null)
                      Text(
                        report.tellerName,
                        style: MadarType.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (report != null)
                StatusChip(
                  label: _t(
                    report.fromServer ? 'chrome.online' : 'chrome.offline',
                  ),
                  tone: report.fromServer ? ChipTone.success : ChipTone.warning,
                ),
            ],
          ),
        ),
        SizedBox(height: 1, child: ColoredBox(color: colors.border)),
        // ── Body: the report on thermal paper ─────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.only(
              start: Space.lg,
              end: Space.lg,
              top: Space.lg,
              bottom: Space.xl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _paperMaxWidth),
                child: report == null
                    ? const _PaperSkeleton()
                    : _ReportPaper(report: report, bridge: _bridge),
              ),
            ),
          ),
        ),
        // ── Footer: print feedback + actions ──────────────────────────────
        Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              if (_printChip case final Widget chip) Center(child: chip),
              ShiftButton(
                label: _print == _PrintState.printing
                    ? _t('receipt.printing')
                    : _t('shift.print_report'),
                icon: 'printer',
                loading: _print == _PrintState.printing,
                enabled: report != null,
                onTap: () => unawaited(_printReport()),
              ),
              ShiftButton(
                label: _t('common.done'),
                variant: ShiftButtonVariant.ghost,
                onTap: () => unawaited(Navigator.of(context).maybePop()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Terminal print feedback — the teller must know whether the Z-report
  /// actually printed, hit no configured printer, or failed.
  Widget? get _printChip => switch (_print) {
    _PrintState.printed => StatusChip(
      label: _t('receipt.printed'),
      tone: ChipTone.success,
      icon: 'checkmark.circle',
    ),
    _PrintState.noPrinter => StatusChip(
      label: _t('receipt.no_printer'),
      tone: ChipTone.warning,
      icon: 'exclamationmark.triangle',
    ),
    _PrintState.failed => StatusChip(
      label: _t('receipt.print_failed'),
      tone: ChipTone.danger,
      icon: 'exclamationmark.triangle',
    ),
    _PrintState.idle || _PrintState.printing => null,
  };
}

/// The report on "thermal paper": store-name masthead, the teller/opened
/// stamp, then the shared breakdown in fixed ink. Theme-invariant by design
/// (ReceiptPaper.kt) — white paper with dark ink in both themes.
class _ReportPaper extends StatelessWidget {
  const _ReportPaper({required this.report, required this.bridge});

  final ShiftReportView report;
  final MadarBridge bridge;

  @override
  Widget build(BuildContext context) {
    String t(String key) => bridge.tr(key: key);
    final storeName = bridge.deviceConfig().branchName?.trim() ?? '';
    final currency = bridge.currentSession()?.currencyCode ?? '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(_paperRadius),
        border: Border.all(color: _rule),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(_paperPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: _paperGap,
          children: [
            Text(
              (storeName.isEmpty ? 'MADAR' : storeName).toUpperCase(),
              textAlign: TextAlign.center,
              style: MadarType.title.copyWith(
                fontSize: _storeNameSize,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            Text(
              t('shift.report_title').toUpperCase(),
              textAlign: TextAlign.center,
              style: MadarType.labelSm.copyWith(
                color: _faint,
                letterSpacing: MadarType.tracking,
              ),
            ),
            const _Rule(color: _rule),
            _paperStamp(t('shift.teller'), report.tellerName),
            _paperStamp(
              t('shift.opened_at'),
              bridge.formatTime(
                rfc3339: report.openedAt,
                style: TimeStyle.dateTime,
              ),
            ),
            const _Rule(color: _rule),
            ShiftReportBreakdown(
              report: report,
              currency: currency,
              tr: t,
              palette: ShiftReportPalette.paper,
            ),
          ],
        ),
      ),
    );
  }

  Widget _paperStamp(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: MadarType.labelSm.copyWith(
              fontWeight: FontWeight.w400,
              color: _faint,
            ),
          ),
        ),
        Text(
          value,
          style: MadarType.labelSm.copyWith(color: _ink),
        ),
      ],
    );
  }
}

/// Loading placeholder while the current shift's report is fetched.
class _PaperSkeleton extends StatelessWidget {
  const _PaperSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        SkeletonBlock(height: Space.xl),
        SkeletonBlock(height: Space.xl),
        SkeletonBlock(height: Space.xxl * 3),
      ],
    );
  }
}
