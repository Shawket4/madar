/// Cash spot — the live drawer view and a recorded count (owner design
/// 2026-09-16 item 5). It replaces the old X and Z previews.
///
/// With `till.cash_spot_check` the page opens straight away. Without it the
/// button is still there: someone holding the grant types their PIN
/// ([askCashSpotPin]) and that unlocks this one check; the signed-in person
/// does not change. The core decides everything — who may look, the expected
/// figures, the differences — this page only renders and sequences.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart' show askCashSpotPin;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Ask the core whether the person may open Cash spot; take the one-time PIN
/// when they may not; then push the page. Returns when the page pops.
Future<void> openCashSpot(BuildContext context, WidgetRef ref) async {
  final bridge = ref.read(bridgeProvider);
  ApprovalView? approval;
  if (bridge.cashSpotAccess().outcome != 'allow') {
    approval = await askCashSpotPin(
      context,
      reason: bridge.tr(key: 'spot.needs_pin'),
    );
    if (approval == null || !context.mounted) return;
  }
  await MadarPages.push<void>(
    context,
    (_) => CashSpotScreen(approval: approval),
  );
}

/// The one-time PIN for the close screen's expected figures, when needed.
/// Returns the figures, or null when dismissed or refused.
Future<CloseTillPreviewView?> unlockCloseFigures(
  BuildContext context,
  WidgetRef ref,
) async {
  final bridge = ref.read(bridgeProvider);
  ApprovalView? approval;
  if (bridge.cashSpotAccess().outcome != 'allow') {
    approval = await askCashSpotPin(
      context,
      reason: bridge.tr(key: 'spot.needs_pin'),
    );
    if (approval == null) return null;
  }
  try {
    return await bridge.closeFigures(approval: approval);
  } on MadarError catch (_) {
    return null;
  }
}

/// The live drawer view with the count form.
class CashSpotScreen extends ConsumerStatefulWidget {
  /// Creates the page; [approval] is the one-time unlock, if one was needed.
  const CashSpotScreen({super.key, this.approval});

  /// The approval that unlocked this one check (null when the grant is held).
  final ApprovalView? approval;

  @override
  ConsumerState<CashSpotScreen> createState() => _CashSpotScreenState();
}

class _CashSpotScreenState extends ConsumerState<CashSpotScreen> {
  final TextEditingController _note = TextEditingController();
  CashSpotView? _view;
  UiText? _loadError;
  int? _cash;
  final Map<String, int?> _counts = {};
  bool _busy = false;
  UiText? _error;
  SpotCheckResultView? _result;

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

  Future<void> _load() async {
    try {
      final v = await ref
          .read(bridgeProvider)
          .cashSpotView(approval: widget.approval);
      if (mounted) {
        setState(() {
          _view = v;
          _loadError = null;
        });
      }
    } on MadarError catch (e) {
      if (mounted) setState(() => _loadError = UiText.error(e));
    }
  }

  Future<void> _record() async {
    if (_busy || _cash == null || _result != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(bridgeProvider)
          .recordCashSpotCheck(
            countedCashMinor: _cash!,
            counts: [
              for (final e in _counts.entries)
                SpotCountInput(method: e.key, countedMinor: e.value),
            ],
            note: _note.text,
            approval: widget.approval,
          );
      ref.read(drawerTickProvider.notifier).bump();
      if (mounted) {
        setState(() {
          _busy = false;
          _result = r;
        });
      }
    } on MadarError catch (e) {
      MadarHaptics.warning();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = UiText.error(e);
        });
      }
    }
  }

  MadarStatus _verdict(String verdict, String Function(String) t) =>
      switch (verdict) {
        'matches' => MadarStatus(t('spot.matches'), tone: MadarTone.success),
        'over' => MadarStatus(t('spot.over'), tone: MadarTone.warning),
        _ => MadarStatus(t('spot.short'), tone: MadarTone.danger),
      };

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final view = _view;

    final Widget body;
    if (view == null && _loadError != null) {
      body = ErrorState(
        message: _loadError!.of(bridge),
        retryLabel: t('history.retry'),
        onRetry: () => unawaited(_load()),
      );
    } else if (view == null) {
      body = const SkeletonScope(child: SkeletonList(count: 5));
    } else {
      body = ListView(
        padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
        children: [
          MadarSectionHeader(text: t('spot.tenders')),
          const SizedBox(height: Space.md),
          MadarCard.column(
            flush: true,
            children: [
              for (final (i, m) in view.methods.indexed) ...[
                if (i > 0) const MadarHairline.row(),
                MadarListRow.ledger(
                  title: m.isCash ? t('till.expected_cash') : m.label,
                  minor: m.systemTotalMinor,
                  currency: currency,
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.xl),
          MadarSectionHeader(text: t('spot.counted_cash')),
          const SizedBox(height: Space.md),
          MadarCard.column(
            children: [
              MadarAmountField(
                key: const ValueKey('spot-cash'),
                amountMinor: _cash,
                onAmount: (v) => setState(() => _cash = v),
                currencyCode: currency,
                autofocus: true,
              ),
              for (final m in view.methods.where((m) => !m.isCash)) ...[
                Text(m.label, style: MadarType.title),
                MadarAmountField(
                  key: ValueKey('spot-${m.method}'),
                  amountMinor: _counts[m.method],
                  onAmount: (v) => setState(() => _counts[m.method] = v),
                  currencyCode: currency,
                ),
              ],
              MadarField(
                controller: _note,
                placeholder: t('till.cash_note'),
                glyph: MadarGlyph.note,
              ),
              if (_error != null)
                NoticeBanner(
                  text: _error!.of(bridge),
                  tone: ChipTone.danger,
                  icon: 'exclamationmark.circle',
                ),
              if (_result case final r?) ...[
                Row(
                  spacing: Space.md,
                  children: [
                    MadarStatusPill(_verdict(r.verdict, t)),
                    MoneyText(
                      r.check.discrepancyMinor.abs(),
                      currency: currency,
                      style: MadarType.numMd,
                    ),
                  ],
                ),
                for (final l in r.methods.where((l) => !l.isCash))
                  MadarSummaryLine(
                    label: '${l.label} · ${t('spot.discrepancy')}',
                    minor: l.discrepancyMinor ?? 0,
                    currency: currency,
                    muted: l.countedMinor == null,
                  ),
              ] else
                MadarButton(
                  label: t('spot.record'),
                  glyph: MadarGlyph.wallet,
                  loading: _busy,
                  enabled: _cash != null,
                  onTap: () => unawaited(_record()),
                ),
            ],
          ),
          if (view.checks.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            MadarSectionHeader(text: t('spot.checks')),
            const SizedBox(height: Space.md),
            MadarCard.column(
              flush: true,
              children: [
                for (final (i, c) in view.checks.indexed) ...[
                  if (i > 0) const MadarHairline.row(),
                  MadarListRow.ledger(
                    title: [
                      MadarFormat.isolate(
                        bridge.formatStamp(rfc3339: c.checkedAt),
                      ),
                      c.checkedByName,
                      if (c.approvedByName case final a?)
                        '${t('spot.approved_by')} $a',
                    ].join(' · '),
                    minor: c.discrepancyMinor,
                    currency: currency,
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    }

    return MadarPageScaffold(
      title: t('spot.title'),
      width: MadarContentWidth.form,
      body: body,
    );
  }
}
