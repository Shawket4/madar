/// Close shift — count the drawer and end the shift.
///
/// On the spec (docs/design/SPEC.md §15): pushed, full width. The expected
/// cash as a ledger — the float, what came in, what went out — adding up to
/// the figure the count is checked against; the count as a form (blank until
/// something is typed — a blank count is not a drawer short by the whole
/// float); the difference named in the core's words with a reason required
/// when it is off; and, once closed, the Z report offered before the page
/// goes. Wide pages lay the two side by side; narrower ones stack them.
///
/// State lives in [closeShiftProvider].
///
/// Not here, on purpose: "Suggested safe drop" (no standard float on the
/// wire).
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/shift_providers.dart';
import 'package:feature_shift/src/shift_report_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The count column beside the ledger (SPEC §3's form width).
const double _countWidth = 560;

/// The ledger keeps at least this much beside the count; below it they stack.
const double _ledgerMinWidth = 360;

/// The end-of-day drawer count, pushed over the shell; the header's back
/// pops it via `Navigator.maybePop`.
class CloseShiftScreen extends ConsumerStatefulWidget {
  /// Creates the close-shift screen.
  const CloseShiftScreen({super.key});

  @override
  ConsumerState<CloseShiftScreen> createState() => _CloseShiftScreenState();
}

class _CloseShiftScreenState extends ConsumerState<CloseShiftScreen> {
  /// Closing note / discrepancy-reason text — widget-local ephemera.
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
    final notifier = ref.read(closeShiftProvider.notifier);
    final ok = await notifier.close(note: _note.text);
    if (!ok || !mounted) return;
    // The Z report is the close's paper trail: offer it — print or read —
    // before the page goes, from the CLOSED shift's own report.
    final closedId = ref.read(closeShiftProvider).closedShiftId;
    if (closedId != null) {
      await showMadarSheet<void>(
        context,
        size: SheetSize.large,
        builder: (_) => ShiftReportSheet(shiftId: closedId, closed: true),
      );
      if (!mounted) return;
    }
    // Dismiss the page first, then let the shell re-read `app_route()`.
    await Navigator.of(context).maybePop();
    shell.refresh();
  }

  Future<void> _preview(ShiftReportView report) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => ShiftReportSheet(report: report),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
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
        '${t('till.open_since')} ${MadarFormat.ltr(bridge.formatStamp(rfc3339: shift.openedAt))}',
      if (orderCount != null)
        '${MadarFormat.ltr('$orderCount')} ${t('shift.orders')}',
    ].join(' · ');

    final expected = _Expected(
      onPreview: report == null ? null : () => unawaited(_preview(report)),
    );
    final count = _Count(note: _note, onClose: () => unawaited(_close()));

    return MadarPageScaffold(
      title: t('shift.close_title'),
      subtitle: subtitle.isEmpty ? null : subtitle,
      width: MadarContentWidth.full,
      body: LayoutBuilder(
        builder: (context, c) {
          final side =
              context.madarLayout.isTablet &&
              c.maxWidth - _countWidth - Space.lg >= _ledgerMinWidth;
          if (!side) {
            return ListView(
              padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
              children: [
                expected,
                const SizedBox(height: Space.xl),
                count,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.lg,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
                  child: expected,
                ),
              ),
              SizedBox(
                width: _countWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
                  child: count,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The expected cash and how it was reached: the float and what came in
/// (+), what went out (−), adding up to the expected figure. Cash sales is
/// the core's remainder, so the lines always sum — offline too.
class _Expected extends ConsumerWidget {
  const _Expected({required this.onPreview});

  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final r = ref.watch(closeShiftProvider.select((s) => s.report));
    final loadError = ref.watch(closeShiftProvider.select((s) => s.loadError));
    final notifier = ref.read(closeShiftProvider.notifier);

    final Widget card;
    if (r == null && loadError != null) {
      card = MadarCard(
        child: SizedBox(
          height: MadarTableMetrics.stateHeight,
          child: ErrorState(
            message: loadError.of(bridge),
            retryLabel: t('history.retry'),
            onRetry: () => unawaited(notifier.retry()),
          ),
        ),
      );
    } else if (r == null) {
      card = const MadarCard(
        flush: true,
        child: SkeletonScope(child: SkeletonList(count: 4)),
      );
    } else {
      final cashSales = bridge.shiftCashSalesMinor(report: r);
      card = MadarCard.column(
        flush: true,
        children: [
          MadarListRow.ledger(
            title: t('shift.opening_float'),
            minor: r.openingCashMinor,
            currency: currency,
          ),
          const MadarHairline.row(),
          MadarListRow.ledger(
            title: t('shift.cash_sales'),
            minor: cashSales,
            currency: currency,
          ),
          if (r.cashInMinor > 0) ...[
            const MadarHairline.row(),
            MadarListRow.ledger(
              title: t('shift.paid_in'),
              minor: r.cashInMinor,
              currency: currency,
            ),
          ],
          if (r.cashOutMinor > 0) ...[
            const MadarHairline.row(),
            MadarListRow.ledger(
              title: t('shift.paid_out'),
              minor: -r.cashOutMinor,
              currency: currency,
            ),
          ],
          const MadarHairline.row(),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.card,
              vertical: Space.sm,
            ),
            child: Column(
              children: [
                if (r.voidedAmountMinor > 0)
                  MadarSummaryLine(
                    label: t('history.voided'),
                    minor: -r.voidedAmountMinor,
                    currency: currency,
                    muted: true,
                  ),
                MadarSummaryLine(
                  label: t('shift.expected_cash'),
                  minor: r.expectedCashMinor,
                  currency: currency,
                  emphasis: true,
                ),
              ],
            ),
          ),
          const MadarHairline.row(),
          MadarListRow.nav(
            title: t('shift.z_preview'),
            glyph: MadarGlyph.receipt,
            onTap: onPreview,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(
          text: t('shift.expected_cash'),
          trailing: r != null && !r.fromServer
              ? MadarStatusPill(
                  MadarStatus(t('chrome.offline'), tone: MadarTone.warning),
                )
              : null,
        ),
        card,
      ],
    );
  }
}

/// The count: the amount (blank until typed), the difference in words, the
/// reason (required when off), what closing does, the error beside the
/// action, and the one red button.
class _Count extends ConsumerWidget {
  const _Count({required this.note, required this.onClose});

  final TextEditingController note;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final countedMinor = ref.watch(
      closeShiftProvider.select((s) => s.countedMinor),
    );
    final expectedMinor = ref.watch(
      closeShiftProvider.select((s) => s.report?.expectedCashMinor),
    );
    final busy = ref.watch(closeShiftProvider.select((s) => s.busy));
    final error = ref.watch(closeShiftProvider.select((s) => s.error));
    final canClose = ref.watch(closeShiftProvider.select((s) => s.canClose));
    // What the count means is the core's: `pending` until a count is entered.
    final check = expectedMinor == null
        ? null
        : bridge.closeCountCheck(
            expectedMinor: expectedMinor,
            countedMinor: countedMinor,
          );
    final diff = check == null || !check.entered ? null : check.varianceMinor;
    final needsReason = check?.needsReason ?? false;

    final verdict = switch (diff) {
      null => null,
      0 => MadarStatus(t('shift.drawer_matches'), tone: MadarTone.success),
      > 0 => MadarStatus(t('shift.drawer_over'), tone: MadarTone.warning),
      _ => MadarStatus(t('shift.drawer_short'), tone: MadarTone.danger),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(text: t('shift.counted_cash')),
        MadarCard.column(
          children: [
            MadarAmountField(
              amountMinor: countedMinor,
              onAmount: (v) =>
                  ref.read(closeShiftProvider.notifier).setCounted(v),
              currencyCode: currency,
              autofocus: true,
            ),
            if (verdict != null)
              Row(
                spacing: Space.md,
                children: [
                  MadarStatusPill(verdict),
                  if (diff != 0)
                    MoneyText(
                      diff!.abs(),
                      currency: currency,
                      style: MadarType.numMd,
                      color: verdict.tone.color(colors),
                    ),
                  const Spacer(),
                  if (needsReason)
                    Flexible(
                      flex: 4,
                      child: Text(
                        t('shift.reason_required'),
                        textAlign: TextAlign.end,
                        style: MadarType.bodySm.copyWith(
                          color: verdict.tone.color(colors),
                        ),
                      ),
                    ),
                ],
              ),
            MadarField(
              controller: note,
              placeholder: switch (diff) {
                null || 0 => t('shift.cash_note'),
                < 0 => t('shift.why_short'),
                _ => t('shift.why_over'),
              },
              glyph: needsReason ? MadarGlyph.alertCircle : MadarGlyph.note,
            ),
            Text(
              t('shift.close_hint'),
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
            if (error != null)
              NoticeBanner(
                text: error.of(bridge),
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            MadarButton(
              label: t('shift.close_title'),
              glyph: MadarGlyph.lock,
              variant: MadarButtonVariant.danger,
              loading: busy,
              enabled: canClose || busy,
              tooltip: expectedMinor == null
                  ? t('chrome.syncing')
                  : countedMinor == null
                  ? t('shift.count_required')
                  : null,
              onTap: onClose,
            ),
          ],
        ),
      ],
    );
  }
}
