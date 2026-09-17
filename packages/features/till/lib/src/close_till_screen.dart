/// Close till — count the drawer and end the till.
///
/// On the spec (docs/design/SPEC.md §15): pushed, full width. The expected
/// cash as a ledger — the float, what came in, what went out — adding up to
/// the figure the count is checked against; the count as a form (blank until
/// something is typed — a blank count is not a drawer short by the whole
/// float); the difference named in the core's words with a reason required
/// when it is off; and, once closed, the Z report offered before the page
/// goes. Wide pages lay the two side by side; narrower ones stack them.
///
/// State lives in [closeTillProvider].
///
/// Not here, on purpose: "Suggested safe drop" (no standard float on the
/// wire).
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/src/held_orders_close_step.dart';
import 'package:feature_till/src/till_providers.dart';
import 'package:feature_till/src/till_report_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The count column beside the ledger (SPEC §3's form width).
const double _countWidth = 560;

/// The ledger keeps at least this much beside the count; below it they stack.
const double _ledgerMinWidth = 360;

/// The end-of-day drawer count, pushed over the shell; the header's back
/// pops it via `Navigator.maybePop`.
class CloseTillScreen extends ConsumerStatefulWidget {
  /// Creates the close-till screen.
  const CloseTillScreen({super.key});

  @override
  ConsumerState<CloseTillScreen> createState() => _CloseTillScreenState();
}

class _CloseTillScreenState extends ConsumerState<CloseTillScreen> {
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
    final notifier = ref.read(closeTillProvider.notifier);
    final bridge = ref.bridge;
    // Held orders still parked on this device: say which, before anything else.
    if (!await confirmHeldOrdersBeforeClose(context, ref) || !mounted) return;
    // The branch's last open till: say what stays open behind it. It never
    // blocks — bills belong to the branch, and the next till settles them.
    final warning = ref.read(closeTillProvider).preview?.lastTillWarning;
    if (warning != null && ref.read(closeTillProvider).canClose) {
      final currency = bridge.currentSession()?.currencyCode ?? '';
      final amount = bridge.formatMoney(
        minor: warning.openBillsAmountMinor,
        currency: currency,
        signed: false,
      );
      final go = await showMadarConfirm(
        context,
        title: bridge.tr(key: 'till.last_till_title'),
        body: bridge
            .tr(key: 'till.last_till_body')
            .replaceAll('{bills}', MadarFormat.ltr('${warning.openBillsCount}'))
            .replaceAll('{amount}', amount)
            .replaceAll(
              '{tables}',
              MadarFormat.ltr('${warning.seatedTablesCount}'),
            ),
        confirmLabel: bridge.tr(key: 'till.close_anyway'),
        cancelLabel: bridge.tr(key: 'common.cancel'),
      );
      if (!go || !mounted) return;
    }
    final ok = await notifier.close(note: _note.text, leaveHeldOpen: true);
    if (!ok || !mounted) return;
    // The Z report is the close's paper trail: offer it — print or read —
    // before the page goes, from the CLOSED till's own report.
    final closedId = ref.read(closeTillProvider).closedTillId;
    if (closedId != null) {
      await showMadarSheet<void>(
        context,
        size: SheetSize.large,
        builder: (_) => TillReportSheet(tillId: closedId, closed: true),
      );
      if (!mounted) return;
    }
    // Dismiss the page first, then let the shell re-read `app_route()`.
    await Navigator.of(context).maybePop();
    shell.refresh();
  }

  Future<void> _preview(TillReportView report) async {
    await showMadarSheet<void>(
      context,
      size: SheetSize.large,
      builder: (_) => TillReportSheet(report: report),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final till = ref.watch(closeTillProvider.select((s) => s.till));
    final report = ref.watch(closeTillProvider.select((s) => s.report));
    final orderCount = ref.watch(closeTillProvider.select((s) => s.orderCount));

    final subtitle = [
      if (till?.deviceCode case final code?) MadarFormat.ltr(code),
      if (till != null) till.tellerName,
      if (till != null)
        '${t('till.open_since')} ${MadarFormat.isolate(bridge.formatStamp(rfc3339: till.openedAt))}',
      if (orderCount != null)
        '${MadarFormat.ltr('$orderCount')} ${t('till.orders')}',
    ].join(' · ');

    final expected = _Expected(
      onPreview: report == null ? null : () => unawaited(_preview(report)),
    );
    final count = _Count(note: _note, onClose: () => unawaited(_close()));

    return MadarPageScaffold(
      title: t('till.close_title'),
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
    final r = ref.watch(closeTillProvider.select((s) => s.report));
    final loadError = ref.watch(closeTillProvider.select((s) => s.loadError));
    final notifier = ref.read(closeTillProvider.notifier);

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
      final cashSales = bridge.tillCashSalesMinor(report: r);
      card = MadarCard.column(
        flush: true,
        children: [
          MadarListRow.ledger(
            title: t('till.opening_float'),
            minor: r.openingCashMinor,
            currency: currency,
          ),
          const MadarHairline.row(),
          MadarListRow.ledger(
            title: t('till.cash_sales'),
            minor: cashSales,
            currency: currency,
          ),
          if (r.cashInMinor > 0) ...[
            const MadarHairline.row(),
            MadarListRow.ledger(
              title: t('till.paid_in'),
              minor: r.cashInMinor,
              currency: currency,
            ),
          ],
          if (r.cashOutMinor > 0) ...[
            const MadarHairline.row(),
            MadarListRow.ledger(
              title: t('till.paid_out'),
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
                  label: t('till.expected_cash'),
                  minor: r.expectedCashMinor,
                  currency: currency,
                  emphasis: true,
                ),
              ],
            ),
          ),
          const MadarHairline.row(),
          MadarListRow.nav(
            title: t('till.z_preview'),
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
          text: t('till.expected_cash'),
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
      closeTillProvider.select((s) => s.countedMinor),
    );
    final expectedMinor = ref.watch(
      closeTillProvider.select((s) => s.report?.expectedCashMinor),
    );
    final busy = ref.watch(closeTillProvider.select((s) => s.busy));
    final error = ref.watch(closeTillProvider.select((s) => s.error));
    final canClose = ref.watch(closeTillProvider.select((s) => s.canClose));
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
      0 => MadarStatus(t('till.drawer_matches'), tone: MadarTone.success),
      > 0 => MadarStatus(t('till.drawer_over'), tone: MadarTone.warning),
      _ => MadarStatus(t('till.drawer_short'), tone: MadarTone.danger),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(text: t('till.counted_cash')),
        MadarCard.column(
          children: [
            MadarAmountField(
              key: const ValueKey('close-count'),
              amountMinor: countedMinor,
              onAmount: (v) =>
                  ref.read(closeTillProvider.notifier).setCounted(v),
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
                        t('till.reason_required'),
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
                null || 0 => t('till.cash_note'),
                < 0 => t('till.why_short'),
                _ => t('till.why_over'),
              },
              glyph: needsReason ? MadarGlyph.alertCircle : MadarGlyph.note,
            ),
          ],
        ),
        const _MethodChecks(),
        MadarCard.column(
          children: [
            Text(
              t('till.close_hint'),
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
            if (error != null)
              NoticeBanner(
                text: error.of(bridge),
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            MadarButton(
              label: t('till.close_title'),
              glyph: MadarGlyph.lock,
              variant: MadarButtonVariant.danger,
              loading: busy,
              enabled: canClose || busy,
              tooltip: expectedMinor == null
                  ? t('chrome.syncing')
                  : countedMinor == null
                  ? t('till.count_required')
                  : null,
              onTap: onClose,
            ),
          ],
        ),
      ],
    );
  }
}

/// Every non-cash method used on this till, each ticked Checked or given
/// the amount the teller sees and a note. The cash row is the count above.
class _MethodChecks extends ConsumerWidget {
  const _MethodChecks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final methods = ref.watch(
      closeTillProvider.select((s) => s.methodsToCheck),
    );
    if (methods.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        const SizedBox(height: Space.sm),
        MadarSectionHeader(text: t('till.reconcile_title')),
        MadarCard.column(
          flush: true,
          children: [
            for (final (i, m) in methods.indexed) ...[
              if (i > 0) const MadarHairline.row(),
              _MethodCheckForm(method: m),
            ],
          ],
        ),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}

class _MethodCheckForm extends ConsumerStatefulWidget {
  const _MethodCheckForm({required this.method});

  final CloseTillMethodView method;

  @override
  ConsumerState<_MethodCheckForm> createState() => _MethodCheckFormState();
}

class _MethodCheckFormState extends ConsumerState<_MethodCheckForm> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final m = widget.method;
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final check = ref.watch(
      closeTillProvider.select((s) => s.checkFor(m.method)),
    );
    final attempted = ref.watch(closeTillProvider.select((s) => s.attempted));
    final notifier = ref.read(closeTillProvider.notifier);
    final needsNote = attempted && (check.missingNote || check.missingAmount);

    return Semantics(
      container: true,
      label: m.label,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Row(
              spacing: Space.md,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.title.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        '${t('till.reconcile_system')} · '
                        '${MadarFormat.ltr('${m.orderCount}')} '
                        '${t('till.orders')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.bodySm.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                MoneyText(
                  m.systemTotalMinor,
                  currency: currency,
                  style: MadarType.numMd,
                ),
              ],
            ),
            MadarSegmented<String>(
              value: check.status ?? '',
              items: [
                MadarSegmentItem('checked', t('till.reconcile_checked')),
                MadarSegmentItem('disagreed', t('till.reconcile_disagree')),
              ],
              onChanged: (v) => v == 'checked'
                  ? notifier.markChecked(m.method)
                  : notifier.markDisagreed(m.method),
            ),
            if (check.disagrees) ...[
              MadarAmountField(
                key: ValueKey('declared-${m.method}'),
                amountMinor: check.amountMinor,
                onAmount: (v) => notifier.setDeclared(m.method, v),
                currencyCode: currency,
              ),
              MadarField(
                key: ValueKey('note-${m.method}'),
                controller: _note,
                placeholder: t('till.reconcile_note'),
                glyph: needsNote ? MadarGlyph.alertCircle : MadarGlyph.note,
                onChanged: (v) => notifier.setMethodNote(m.method, v),
              ),
            ],
            if (needsNote)
              Text(
                t('till.reconcile_note_required'),
                style: MadarType.bodySm.copyWith(color: colors.danger),
              ),
          ],
        ),
      ),
    );
  }
}
