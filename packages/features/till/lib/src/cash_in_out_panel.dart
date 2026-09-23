/// Cash in / out — the record form and this till's movements.
///
/// On the spec (docs/design/SPEC.md §7, §15): the kind as segments (Pay out ·
/// Pay in), the amount as the hero field, the note (required), a button that
/// names what it will record — then the till's movements as `.ledger` rows,
/// each named by what it IS (a safe drop and a pay-out both take cash out;
/// only one is spend). [CashLedger] is the same ledger on its own, for the
/// Till's recent movements.
///
/// State lives in [cashMovementsProvider]. Movements are OFFLINE-FIRST
/// (queued through the durable outbox, idempotent on a client_ref), so a
/// recorded row appears at once.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/src/till_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The record form over the full ledger. [autofocusAmount] is for the
/// pushed page, where the amount is the one thing to do.
class CashInOutPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const CashInOutPanel({super.key, this.autofocusAmount = false});

  /// Focus the amount once the route's entrance settles.
  final bool autofocusAmount;

  @override
  ConsumerState<CashInOutPanel> createState() => _CashInOutPanelState();
}

class _CashInOutPanelState extends ConsumerState<CashInOutPanel> {
  /// Note text — mirrored into the provider through `setNote` so the Record
  /// button's enablement is state-derived.
  final TextEditingController _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    // The provider outlives this panel, so a half-typed note comes back.
    _note.text = ref.read(cashMovementsProvider).note;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final state = ref.read(cashMovementsProvider);
    if (!state.canRecord) return;
    // Money leaving the drawer is asked once, with the figure: a pay-out
    // mistyped by a zero is a real shortage at the close.
    if (!state.isIn) {
      final bridge = ref.read(bridgeProvider);
      final currency = bridge.currentSession()?.currencyCode ?? '';
      final ok = await showMadarConfirm(
        context,
        title: bridge
            .tr(key: 'cash.confirm_pay_out')
            .replaceAll(
              '{amount}',
              bridge.formatMoney(
                minor: state.amountMinor,
                currency: currency,
                signed: false,
              ),
            ),
        body: state.note.trim(),
        confirmLabel: bridge.tr(key: 'cash.record_pay_out'),
        cancelLabel: bridge.tr(key: 'common.cancel'),
      );
      if (!ok || !mounted) return;
    }
    final ok = await ref.read(cashMovementsProvider.notifier).record();
    if (ok && mounted) _note.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    // Narrow slices — amount keystrokes repaint the form, not the ledger.
    final isIn = ref.watch(cashMovementsProvider.select((s) => s.isIn));
    final amountMinor = ref.watch(
      cashMovementsProvider.select((s) => s.amountMinor),
    );
    final busy = ref.watch(cashMovementsProvider.select((s) => s.busy));
    final canRecord = ref.watch(
      cashMovementsProvider.select((s) => s.canRecord),
    );
    final error = ref.watch(cashMovementsProvider.select((s) => s.error));
    final notifier = ref.read(cashMovementsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        MadarCard.column(
          children: [
            // Pay out leads: it is the movement a till actually makes.
            MadarSegmented<bool>(
              items: [
                MadarSegmentItem(
                  false,
                  t('cash.pay_out'),
                  glyph: MadarGlyph.arrowUpEnd,
                ),
                MadarSegmentItem(
                  true,
                  t('cash.pay_in'),
                  glyph: MadarGlyph.arrowDownStart,
                ),
              ],
              value: isIn,
              onChanged: (v) => notifier.setDirection(isIn: v),
            ),
            MadarAmountField(
              amountMinor: amountMinor,
              onAmountMinor: notifier.setAmount,
              currencyCode: currency,
              autofocus: widget.autofocusAmount,
            ),
            MadarField(
              controller: _note,
              placeholder: t('cash.note_hint'),
              kind: MadarFieldKind.note,
              glyph: MadarGlyph.note,
              onChanged: notifier.setNote,
              onSubmitted: (_) => unawaited(_record()),
              trailing: Text(
                t('cash.note_required'),
                style: MadarType.labelSm.copyWith(color: colors.textMuted),
              ),
            ),
            if (!isIn) const _AdvanceToRow(),
            if (error != null)
              NoticeBanner(
                text: error.of(bridge),
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            MadarButton(
              label: t(isIn ? 'cash.record_pay_in' : 'cash.record_pay_out'),
              loading: busy,
              enabled: canRecord,
              tooltip: canRecord ? null : t('cash.note_hint'),
              onTap: () => unawaited(_record()),
            ),
          ],
        ),
        const CashLedger(),
      ],
    );
  }
}

/// Optional: the pay-out is cash handed to an employee for shop purchases,
/// logged for them in Dawam as an expense advance (AV-8).
class _AdvanceToRow extends ConsumerWidget {
  const _AdvanceToRow();

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final bridge = ref.read(bridgeProvider);
    final notifier = ref.read(cashMovementsProvider.notifier);
    List<BranchPersonView> people;
    try {
      people = await bridge.branchPeople();
    } on MadarError catch (e) {
      notifier.fail(UiText.error(e));
      return;
    }
    if (!context.mounted) return;
    final picked = await showMadarSheet<BranchPersonView?>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MadarRow(
            title: bridge.tr(key: 'cash.expense_advance_none'),
            onTap: () => Navigator.of(context).pop(),
            chevron: false,
          ),
          for (final p in people)
            MadarRow(
              title: p.name,
              glyph: MadarGlyph.user,
              onTap: () => Navigator.of(context).pop(p),
              chevron: false,
            ),
        ],
      ),
    );
    notifier.setAdvanceTo(picked?.employeeId, picked?.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final name = ref.watch(
      cashMovementsProvider.select((s) => s.advanceToName),
    );
    return MadarRow(
      title: bridge.tr(key: 'cash.expense_advance'),
      subtitle: bridge.tr(key: 'cash.expense_advance_hint'),
      glyph: MadarGlyph.user,
      value: Text(name ?? bridge.tr(key: 'cash.expense_advance_none')),
      onTap: () => unawaited(_pick(context, ref)),
    );
  }
}

/// A movement's name: what it is, then what it was for.
String cashMovementTitle(MadarBridge bridge, CashMovementView m) {
  final kind = bridge.tr(
    key: switch (m.kind) {
      'safe_drop' => 'cash.kind.safe_drop',
      'correction' => 'cash.kind.correction',
      'pay_in' => 'cash.pay_in',
      'pay_out' => 'cash.pay_out',
      _ => m.amountMinor >= 0 ? 'cash.pay_in' : 'cash.pay_out',
    },
  );
  final note = m.note.trim();
  return note.isEmpty ? kind : '$kind · $note';
}

/// This till's movements as ledger rows under a section header that
/// carries the count and the net. [maxRows] caps it (the Till's recent
/// movements) with [onSeeAll] as the header's way to the rest.
class CashLedger extends ConsumerWidget {
  /// Creates the ledger.
  const CashLedger({super.key, this.title, this.maxRows, this.onSeeAll});

  /// The section's name; this till by default.
  final String? title;

  final int? maxRows;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';
    final movements = ref.watch(
      cashMovementsProvider.select((s) => s.movements),
    );
    final loading = ref.watch(cashMovementsProvider.select((s) => s.loading));
    final loadError = ref.watch(
      cashMovementsProvider.select((s) => s.loadError),
    );
    // The net is a sum for the header line, not a business figure — the
    // report's cash in / out are the ones that count. It is still a drawer
    // aggregate, so it goes with the rest without `till.cash_spot_check`.
    final showNet = bridge.tillFiguresVisible();
    var net = 0;
    for (final m in movements) {
      net += m.amountMinor;
    }
    final cap = maxRows;
    final shown = cap == null || movements.length <= cap
        ? movements
        : movements.sublist(0, cap);

    final Widget body;
    if (loadError != null && movements.isEmpty && !loading) {
      body = MadarCard(
        child: SizedBox(
          height: MadarTableMetrics.stateHeight,
          child: ErrorState(
            message: loadError.of(bridge),
            retryLabel: t('history.retry'),
            onRetry: () =>
                unawaited(ref.read(cashMovementsProvider.notifier).load()),
          ),
        ),
      );
    } else if (loading && movements.isEmpty) {
      body = const MadarCard(
        flush: true,
        child: SkeletonScope(child: SkeletonList(count: 2)),
      );
    } else if (movements.isEmpty) {
      body = MadarCard(
        child: EmptyState(
          icon: 'banknote',
          title: t('cash.empty'),
          message: t('cash.empty_message'),
        ),
      );
    } else {
      body = MadarCard.column(
        flush: true,
        children: [
          for (final (i, m) in shown.indexed) ...[
            if (i > 0) const MadarHairline.row(),
            MadarListRow.ledger(
              title: cashMovementTitle(bridge, m),
              meta: [
                m.movedByName,
                MadarFormat.isolate(bridge.formatStamp(rfc3339: m.createdAt)),
              ].join(' · '),
              minor: m.amountMinor,
              currency: currency,
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarSectionHeader(
          text: title ?? t('till.this_shift'),
          trailing: movements.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    Text(
                      showNet
                          ? '${MadarFormat.ltr('${movements.length}')} · '
                                '${t('cash.net')}'
                          : MadarFormat.ltr('${movements.length}'),
                      style: MadarType.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (showNet)
                      MoneyText(
                        net,
                        currency: currency,
                        signed: true,
                        style: MadarType.num,
                        color: net < 0 ? colors.danger : colors.success,
                      ),
                    if (onSeeAll != null && movements.length > shown.length)
                      MadarButton(
                        label: t('chrome.see_all'),
                        variant: MadarButtonVariant.ghost,
                        size: MadarButtonSize.compact,
                        onTap: onSeeAll!,
                      ),
                  ],
                ),
        ),
        body,
      ],
    );
  }
}
