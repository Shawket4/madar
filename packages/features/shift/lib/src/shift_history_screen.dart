/// Past shifts — the branch's closed-shift history, a pixel-and-behavior
/// port of the Kotlin ShiftHistoryScreen (in CashAndShiftsScreen.kt).
/// Responsive: a fixed-column table at container width ≥
/// [Responsive.wideTable], per-row cards below it. The locally-open shift
/// is pinned on top (the natives' `shiftsWithLocalOpen`); tapping a row
/// opens the shared [ShiftReportSheet] with that shift's Z-report via
/// `shiftReportFor`. All data + rules live in the core; this screen
/// renders. Full-screen over the order screen.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/controls.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/material.dart'
    show CircularProgressIndicator, Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (CashAndShiftsScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Content cap (natives: widthIn(max = 880.dp)).
const double _contentMaxWidth = 880;

/// Fixed table columns (natives: ShiftStatusW / ShiftDeclaredW / ShiftChevW
/// = 26 / 110 / 44.dp).
const double _statusColWidth = 26;
const double _declaredColWidth = 110;
const double _chevronColWidth = 44;

/// Shift status dot (natives: 8.dp circle).
const double _statusDotSize = 8;

/// Row report-fetch spinner (natives: 14.dp / 2.dp stroke).
const double _rowSpinnerSize = 14;
const double _rowSpinnerStroke = 2;

/// The branch's shift history (full-screen over the order screen). Takes
/// the shared screen contract: [core] for every bridge call and
/// [onStateChanged] kept for the contract (history is read-only — nothing
/// here moves shared state). The header's back pops it via
/// `Navigator.maybePop`.
class ShiftHistoryScreen extends StatefulWidget {
  /// Creates the shift-history screen.
  const ShiftHistoryScreen({
    required this.core,
    required this.onStateChanged,
    this.onBack,
    super.key,
  });

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// Kept for the shared screen contract; shift history is read-only.
  final void Function() onStateChanged;

  /// Back affordance — defaults to popping this route (the natives set
  /// `showShiftHistory` = false).
  final VoidCallback? onBack;

  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  MadarBridge get _bridge => widget.core.bridge;

  List<ShiftSummaryView> _shifts = const [];
  ShiftView? _live;
  bool _loading = false;
  String? _reportLoadingId;
  ToastData? _toast;
  int _toastSeq = 0;

  String _t(String key) => _bridge.tr(key: key);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _back() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  /// Past shifts (newest first) + the live shift for pinning. Load failures
  /// degrade to empty (the natives' `getOrDefault(emptyList())`).
  Future<void> _load() async {
    setState(() => _loading = true);
    List<ShiftSummaryView> shifts;
    try {
      shifts = await _bridge.listShifts();
    } on Exception catch (_) {
      shifts = const [];
    }
    ShiftView? live;
    try {
      live = await _bridge.currentShift();
    } on Exception catch (_) {
      live = null;
    }
    if (!mounted) return;
    setState(() {
      _shifts = shifts;
      _live = live;
      _loading = false;
    });
  }

  /// The natives' `shiftsWithLocalOpen`: prepend the locally-opened-but-
  /// unsynced shift to the top of the page if it isn't already present, so
  /// the live shift always shows.
  List<ShiftSummaryView> get _rows {
    final live = _live;
    if (live == null || !live.isOpen || _shifts.any((s) => s.id == live.id)) {
      return _shifts;
    }
    final pinned = ShiftSummaryView(
      id: live.id,
      tellerName: live.tellerName,
      openedAt: live.openedAt,
      openingCashMinor: live.openingCashMinor,
      status: live.status,
      isOpen: live.isOpen,
    );
    return [pinned, ..._shifts];
  }

  /// Open a shift's Z-report in the shared preview sheet — the live shift
  /// loads the current report in-sheet; a past shift is fetched via
  /// `shiftReportFor` first (spinner in the row's chevron slot, danger
  /// toast on failure — the natives' `openShiftReportPreviewFor`).
  Future<void> _openReport(ShiftSummaryView s) async {
    if (_reportLoadingId != null) return;
    MadarHaptics.selection();
    if (s.isOpen && s.id == _live?.id) {
      await showMadarSheet<void>(
        context,
        size: SheetSize.large,
        builder: (_) => ShiftReportSheet(core: widget.core),
      );
      return;
    }
    setState(() => _reportLoadingId = s.id);
    try {
      final report = await _bridge.shiftReportFor(shiftId: s.id);
      if (!mounted) return;
      setState(() => _reportLoadingId = null);
      await showMadarSheet<void>(
        context,
        size: SheetSize.large,
        builder: (_) =>
            ShiftReportSheet(core: widget.core, report: report, shiftId: s.id),
      );
    } on Exception catch (_) {
      if (!mounted) return;
      setState(() {
        _reportLoadingId = null;
        _toastSeq += 1;
        _toast = ToastData(
          id: _toastSeq,
          text: _t('receipt.print_failed'),
          tone: ChipTone.danger,
          icon: 'xmark.circle',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // Scaffold: every screen root owns its own Scaffold in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                ShiftHeaderBar(title: _t('shifts.title'), onBack: _back),
                Expanded(child: _buildBody()),
              ],
            ),
            // Toasts float above everything on this screen.
            ToastHost(
              _toast,
              onDismiss: (id) {
                if (_toast?.id == id) setState(() => _toast = null);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _shifts.isEmpty && _live == null) {
      return const Align(alignment: Alignment.topCenter, child: SkeletonList());
    }
    final rows = _rows;
    if (rows.isEmpty) {
      return EmptyState(
        icon: 'clock.arrow.circlepath',
        title: _t('shifts.empty'),
      );
    }
    final currency = _bridge.currentSession()?.currencyCode ?? '';
    // Width-driven, matching the natives' `wide = maxWidth >= 680`.
    return ResponsiveBuilder(
      builder: (context, info) {
        final wide = info.isWideTable;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: ListView(
              padding: const EdgeInsetsDirectional.all(Space.lg),
              children: [
                // Wide: header + rows live in one card; narrow keeps
                // per-row cards.
                if (wide)
                  ShiftFlushCard(
                    children: [
                      _ColumnHeader(tr: _t),
                      for (final (index, s) in rows.indexed) ...[
                        _WideShiftRow(
                          shift: s,
                          currency: currency,
                          odd: index.isOdd,
                          loadingReport: _reportLoadingId == s.id,
                          bridge: _bridge,
                          onTap: () => unawaited(_openReport(s)),
                        ),
                        const ShiftHairline(),
                      ],
                    ],
                  )
                else
                  for (final (index, s) in rows.indexed) ...[
                    if (index > 0) const SizedBox(height: Space.sm),
                    _NarrowShiftCard(
                      shift: s,
                      currency: currency,
                      loadingReport: _reportLoadingId == s.id,
                      bridge: _bridge,
                      onTap: () => unawaited(_openReport(s)),
                    ),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Status-dot color (the natives' `_statusColor`): open→success,
/// force_closed→danger, closed/other→muted.
Color _statusColor(String status, MadarColors colors) => switch (status) {
  'open' => colors.success,
  'force_closed' => colors.danger,
  _ => colors.textMuted,
};

/// Wide-table column header — 42-tall, surfaceAlt fill, bottom hairline:
/// `[status dot 26][Teller][Opened][Closed][Declared 110][chevron 44]`.
/// The status-dot label is blank; Declared end-aligns.
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.tr});

  final String Function(String key) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: Metrics.tableHeaderHeight,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
            ),
            child: Row(
              spacing: Space.md,
              children: [
                const SizedBox(width: _statusColWidth),
                Expanded(child: _HeaderCell(label: tr('shift.teller'))),
                Expanded(child: _HeaderCell(label: tr('shift.opened_at'))),
                Expanded(child: _HeaderCell(label: tr('shifts.closed'))),
                SizedBox(
                  width: _declaredColWidth,
                  child: _HeaderCell(
                    label: tr('shifts.declared'),
                    alignEnd: true,
                  ),
                ),
                const SizedBox(width: _chevronColWidth),
              ],
            ),
          ),
          const ShiftHairline(),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Align(
      alignment: alignEnd
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: MadarType.labelSm.copyWith(color: colors.textMuted),
      ),
    );
  }
}

/// A single table row, 56-tall, zebra fill on odd rows —
/// `[status dot][Teller][Opened][Closed][Declared][chevron]`.
class _WideShiftRow extends StatelessWidget {
  const _WideShiftRow({
    required this.shift,
    required this.currency,
    required this.odd,
    required this.loadingReport,
    required this.bridge,
    required this.onTap,
  });

  final ShiftSummaryView shift;
  final String currency;
  final bool odd;
  final bool loadingReport;
  final MadarBridge bridge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = shift;
    return ColoredBox(
      color: odd ? colors.surfaceAlt : Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: Metrics.tableRowHeight,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
          ),
          child: Row(
            spacing: Space.md,
            children: [
              SizedBox(
                width: _statusColWidth,
                child: Center(
                  child: Container(
                    width: _statusDotSize,
                    height: _statusDotSize,
                    decoration: BoxDecoration(
                      color: _statusColor(s.status, colors),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  s.tellerName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.title.copyWith(color: colors.textPrimary),
                ),
              ),
              Expanded(
                child: Text(
                  bridge.formatTime(
                    rfc3339: s.openedAt,
                    style: TimeStyle.dateTime,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  s.closedAt == null
                      ? '—'
                      : bridge.formatTime(
                          rfc3339: s.closedAt!,
                          style: TimeStyle.dateTime,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    color: s.closedAt == null
                        ? colors.textMuted
                        : colors.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: _declaredColWidth,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    s.closingDeclaredMinor == null
                        ? '—'
                        : Money.format(
                            s.closingDeclaredMinor!,
                            currency: currency,
                          ),
                    maxLines: 1,
                    textDirection: TextDirection.ltr,
                    style: MadarType.money.copyWith(
                      color: s.closingDeclaredMinor == null
                          ? colors.textMuted
                          : colors.textPrimary,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: _chevronColWidth,
                child: Center(
                  child: _RowDisclosure(loading: loadingReport),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Narrow row card: opened date + status chip up top, then the opening /
/// declared / discrepancy metric rows.
class _NarrowShiftCard extends StatelessWidget {
  const _NarrowShiftCard({
    required this.shift,
    required this.currency,
    required this.loadingReport,
    required this.bridge,
    required this.onTap,
  });

  final ShiftSummaryView shift;
  final String currency;
  final bool loadingReport;
  final MadarBridge bridge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final s = shift;
    String t(String key) => bridge.tr(key: key);
    final discrepancy = s.discrepancyMinor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.borderLight),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bridge.formatTime(
                        rfc3339: s.openedAt,
                        style: TimeStyle.dateShort,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  StatusChip(
                    label: t(s.isOpen ? 'shifts.open_now' : 'shifts.closed'),
                    tone: s.isOpen ? ChipTone.success : ChipTone.neutral,
                  ),
                  _RowDisclosure(loading: loadingReport),
                ],
              ),
              _MetricRow(
                label: t('shifts.opening'),
                value: Money.format(s.openingCashMinor, currency: currency),
              ),
              if (s.closingDeclaredMinor case final declared?)
                _MetricRow(
                  label: t('shifts.declared'),
                  value: Money.format(declared, currency: currency),
                ),
              if (discrepancy != null && discrepancy != 0)
                _MetricRow(
                  label: t('shifts.discrepancy'),
                  value:
                      '${discrepancy > 0 ? '+' : '−'}'
                      '${Money.format(discrepancy.abs(), currency: currency)}',
                  tone: ChipTone.danger,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The row's trailing affordance: a forward chevron, or a small spinner
/// while that row's Z-report is being fetched.
class _RowDisclosure extends StatelessWidget {
  const _RowDisclosure({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    if (loading) {
      return SizedBox.square(
        dimension: _rowSpinnerSize,
        child: CircularProgressIndicator(
          color: colors.accent,
          strokeWidth: _rowSpinnerStroke,
        ),
      );
    }
    return MadarIcon('chevron.forward', tint: colors.textMuted);
  }
}

/// The natives' `MetricRow`: label ↔ tabular money value, optional tone.
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final ChipTone? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        Text(
          label,
          style: MadarType.bodySm.copyWith(
            color: tone?.resolve(colors) ?? colors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: MadarType.money.copyWith(
            color: tone?.resolve(colors) ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
