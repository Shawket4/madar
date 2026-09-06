import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../ui/kit.dart';

/// The money a manager adds to or takes off a payslip, outside the rules.
///
/// Three lists, one screen, because they answer one question — "why is this
/// month's pay what it is?" — and a manager reaching for one usually wants to
/// see the others.
///
/// The important distinction is between HAND-ENTERED and RULE-GENERATED rows.
/// A manual bonus or deduction can be deleted outright. A late penalty or an
/// absence charge cannot: it is evidence of what the rules decided, so it is
/// WAIVED (kept, skipped by payroll) or OVERRIDDEN (charged at a different
/// figure, original retained) — never erased. The server enforces that; this
/// screen just doesn't offer the wrong verb.
class AdjustmentsScreen extends ConsumerStatefulWidget {
  const AdjustmentsScreen({super.key});

  @override
  ConsumerState<AdjustmentsScreen> createState() => _AdjustmentsScreenState();
}

enum _Tab { deductions, bonuses, advances }

class _AdjustmentsScreenState extends ConsumerState<AdjustmentsScreen> {
  _Tab _tab = _Tab.deductions;
  final _busy = <String>{};

  /// The current month — the window a payroll run covers.
  ({bool deductions, String from, String to}) get _query {
    final now = DateTime.now();
    return (
      deductions: _tab == _Tab.deductions,
      from: isoDate(DateTime(now.year, now.month)),
      to: isoDate(DateTime(now.year, now.month + 1, 0)),
    );
  }

  void _invalidate() {
    ref
      ..invalidate(adjustmentsProvider)
      ..invalidate(advancesProvider);
    // The run's figures move with these, so its preview must not stay stale.
    ref.invalidate(payrollPreviewProvider);
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    final core = ref.read(coreProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(id));
    try {
      await action();
      _invalidate();
    } on MadarError catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(core.bridge.humanMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final query = _query;

    return StaffPage(
      title: t('adj.title'),
      onRefresh: () async => _invalidate(),
      floating: _tab == _Tab.advances
          ? null
          : PrimaryButton(
              label: _tab == _Tab.deductions
                  ? t('adj.addDeduction')
                  : t('adj.addBonus'),
              icon: 'plus',
              onPressed: () => _openAddSheet(deductions: query.deductions),
            ),
      children: [
        Segmented<_Tab>(
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
          segments: [
            (value: _Tab.deductions, label: t('adj.deductions')),
            (value: _Tab.bonuses, label: t('adj.bonuses')),
            (value: _Tab.advances, label: t('adj.advances')),
          ],
        ),
        const SizedBox(height: Space.md),
        if (_tab == _Tab.advances)
          _Advances(busy: _busy, onDecide: _decideAdvance)
        else
          _Adjustments(
            query: query,
            busy: _busy,
            onOverride: _openOverrideSheet,
            onWaive: _openWaiveSheet,
            onDelete: _confirmDelete,
          ),
      ],
    );
  }

  // ── Actions ─────────────────────────────────────────────────

  Future<void> _decideAdvance(SalaryAdvanceView advance, bool approve) => _run(
    advance.id,
    () => ref
        .read(coreProvider)
        .bridge
        .managerDecideAdvance(advanceId: advance.id, approve: approve),
  );

  Future<void> _openAddSheet({required bool deductions}) async {
    final t = ref.read(tProvider);
    final result =
        await showMadarSheet<({String userId, int minor, String reason})>(
          context,
          builder: (sheetContext) => _AddSheet(deductions: deductions),
        );
    if (result == null) return;
    final now = DateTime.now();
    await _run(
      'new',
      () => ref
          .read(coreProvider)
          .bridge
          .managerCreateAdjustment(
            deductions: deductions,
            userId: result.userId,
            amountMinor: result.minor,
            reason: result.reason,
            // Dated TODAY so it lands in the period being run. Backdating is a
            // dashboard job; from a phone, "now" is the honest default.
            effectiveDate: isoDate(now),
          ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('adj.added'))));
    }
  }

  Future<void> _openOverrideSheet(AdjustmentView row) async {
    final result = await showMadarSheet<({int minor, String reason})>(
      context,
      builder: (_) => _ReasonSheet(
        titleKey: 'adj.overrideTitle',
        hintKey: 'adj.overrideHint',
        withAmount: true,
        initialMinor: row.amountMinor,
      ),
    );
    if (result == null) return;
    await _run(
      row.id,
      () => ref
          .read(coreProvider)
          .bridge
          .managerOverrideDeduction(
            id: row.id,
            amountMinor: result.minor,
            reason: result.reason,
          ),
    );
  }

  Future<void> _openWaiveSheet(AdjustmentView row) async {
    final result = await showMadarSheet<({int minor, String reason})>(
      context,
      builder: (_) => const _ReasonSheet(
        titleKey: 'adj.waiveTitle',
        hintKey: 'adj.waiveHint',
        withAmount: false,
      ),
    );
    if (result == null) return;
    await _run(
      row.id,
      () => ref
          .read(coreProvider)
          .bridge
          .managerWaiveDeduction(id: row.id, reason: result.reason),
    );
  }

  Future<void> _confirmDelete(AdjustmentView row, bool deductions) async {
    final t = ref.read(tProvider);
    final ok = await showMadarSheet<bool>(
      context,
      builder: (sheetContext) {
        final colors = sheetContext.madarColors;
        return Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('adj.deleteTitle'),
                style: MadarType.h3.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: Space.xs),
              Text(
                row.reason,
                style: MadarType.bodySm.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.lg),
              SecondaryButton(
                label: t('common.delete'),
                icon: 'trash',
                tone: colors.danger,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true) return;
    await _run(
      row.id,
      () => ref
          .read(coreProvider)
          .bridge
          .managerDeleteAdjustment(deductions: deductions, id: row.id),
    );
  }
}

// ── Bonuses & deductions ──────────────────────────────────────

class _Adjustments extends ConsumerWidget {
  const _Adjustments({
    required this.query,
    required this.busy,
    required this.onOverride,
    required this.onWaive,
    required this.onDelete,
  });

  final ({bool deductions, String from, String to}) query;
  final Set<String> busy;
  final void Function(AdjustmentView) onOverride;
  final void Function(AdjustmentView) onWaive;
  final void Function(AdjustmentView, bool) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final rows = ref.watch(adjustmentsProvider(query));

    return rows.when(
      loading: () => const SkeletonList(count: 4),
      error: (e, _) => ErrorState(
        message: '$e',
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(adjustmentsProvider(query)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: query.deductions ? 'minus' : 'plus',
            title: t(query.deductions ? 'adj.noDeductions' : 'adj.noBonuses'),
            message: t('adj.emptyHint'),
          );
        }
        return Column(
          children: [
            for (final row in list)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _AdjustmentCard(
                  row: row,
                  deductions: query.deductions,
                  busy: busy.contains(row.id),
                  onOverride: () => onOverride(row),
                  onWaive: () => onWaive(row),
                  onDelete: () => onDelete(row, query.deductions),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AdjustmentCard extends ConsumerWidget {
  const _AdjustmentCard({
    required this.row,
    required this.deductions,
    required this.busy,
    required this.onOverride,
    required this.onWaive,
    required this.onDelete,
  });

  final AdjustmentView row;
  final bool deductions;
  final bool busy;
  final VoidCallback onOverride;
  final VoidCallback onWaive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final manual = row.source == 'manual';
    // Only a rule-generated row has an "original" to strike through.
    final wasOverridden = row.overridden && row.originalAmountMinor > 0;

    return MadarCard(
      padding: const EdgeInsets.fromLTRB(
        Space.md,
        Space.sm + 2,
        Space.md,
        Space.sm + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: switch (row.source) {
                  'late_penalty' => 'clock',
                  'absence' => 'exclamationmark.triangle',
                  _ => deductions ? 'minus' : 'plus',
                },
                background: deductions ? colors.dangerBg : colors.successBg,
                tint: deductions ? colors.danger : colors.success,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      row.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.labelSm.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (wasOverridden)
                    Text(
                      formatAmount(row.originalAmountMinor),
                      style: MadarType.num.copyWith(
                        color: colors.textMuted,
                        decoration: TextDecoration.lineThrough,
                        fontSize: 11,
                      ),
                    ),
                  Num(
                    formatAmount(row.amountMinor),
                    style: MadarType.num.copyWith(fontWeight: FontWeight.w700),
                    // A waived row is struck from payroll, so its figure reads
                    // as inert rather than as money.
                    color: row.waived
                        ? colors.textMuted
                        : deductions
                        ? colors.danger
                        : colors.success,
                  ),
                  Num(
                    row.effectiveDate,
                    style: MadarType.num.copyWith(fontSize: 10),
                    color: colors.textMuted,
                  ),
                ],
              ),
            ],
          ),
          if (row.waived || row.overridden) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusChip(
                label: row.waived
                    ? t('adj.waivedBy', {'reason': row.waiveReason})
                    : t('adj.overriddenBy', {'reason': row.overrideReason}),
                tone: row.waived ? ChipTone.neutral : ChipTone.warning,
              ),
            ),
          ],
          // A rule-generated deduction is waived or overridden; a hand-entered
          // one is simply removed. Never both sets of verbs on one row.
          if (deductions && !row.waived) ...[
            const SizedBox(height: Space.sm + 2),
            Row(
              children: [
                if (manual)
                  Expanded(
                    child: SecondaryButton(
                      label: t('common.delete'),
                      height: 34,
                      tone: colors.danger,
                      onPressed: busy ? null : onDelete,
                    ),
                  )
                else ...[
                  Expanded(
                    child: SecondaryButton(
                      label: t('adj.override'),
                      height: 34,
                      onPressed: busy ? null : onOverride,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: SecondaryButton(
                      label: t('adj.waive'),
                      height: 34,
                      tone: colors.warning,
                      onPressed: busy ? null : onWaive,
                    ),
                  ),
                ],
              ],
            ),
          ] else if (!deductions && manual) ...[
            const SizedBox(height: Space.sm + 2),
            SecondaryButton(
              label: t('common.delete'),
              height: 34,
              tone: colors.danger,
              onPressed: busy ? null : onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Advances ──────────────────────────────────────────────────

class _Advances extends ConsumerWidget {
  const _Advances({required this.busy, required this.onDecide});

  final Set<String> busy;
  final Future<void> Function(SalaryAdvanceView, bool) onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final rows = ref.watch(advancesProvider);

    return rows.when(
      loading: () => const SkeletonList(count: 3),
      error: (e, _) => ErrorState(
        message: '$e',
        retryLabel: t('common.retry'),
        onRetry: () => ref.invalidate(advancesProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: 'banknote',
            title: t('adj.noAdvances'),
            message: t('adj.noAdvancesHint'),
          );
        }
        return Column(
          children: [
            for (final advance in list)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: MadarCard(
                  padding: const EdgeInsets.fromLTRB(
                    Space.md,
                    Space.sm + 2,
                    Space.md,
                    Space.sm + 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconTile(
                            icon: 'banknote',
                            background: colors.accentBg,
                            tint: colors.accent,
                          ),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Num(
                                  formatAmount(advance.amountMinor),
                                  style: MadarType.num.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  t('adj.installments', {
                                    'count': '${advance.installments}',
                                    'each': formatAmount(
                                      advance.monthlyInstallmentMinor,
                                    ),
                                  }),
                                  style: MadarType.labelSm.copyWith(
                                    color: colors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusChip(
                            label: t('advance.${advance.status}'),
                            tone: switch (advance.status) {
                              'approved' => ChipTone.success,
                              'rejected' => ChipTone.danger,
                              'pending' => ChipTone.warning,
                              'settled' => ChipTone.info,
                              _ => ChipTone.neutral,
                            },
                          ),
                        ],
                      ),
                      if (advance.reason.isNotEmpty) ...[
                        const SizedBox(height: Space.xs),
                        Text(
                          advance.reason,
                          style: MadarType.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                      // Still owed, for an advance already being collected.
                      if (advance.status == 'approved' &&
                          advance.remainingMinor > 0) ...[
                        const SizedBox(height: Space.xs),
                        Row(
                          children: [
                            Expanded(child: FieldLabel(t('adj.remaining'))),
                            Num(
                              formatAmount(advance.remainingMinor),
                              color: colors.textSecondary,
                            ),
                          ],
                        ),
                      ],
                      if (advance.status == 'pending') ...[
                        const SizedBox(height: Space.sm + 2),
                        Row(
                          children: [
                            Expanded(
                              child: PrimaryButton(
                                label: t('ap.approve'),
                                icon: 'checkmark',
                                height: 38,
                                busy: busy.contains(advance.id),
                                onPressed: busy.contains(advance.id)
                                    ? null
                                    : () => onDecide(advance, true),
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: SecondaryButton(
                                label: t('ap.reject'),
                                icon: 'xmark',
                                height: 38,
                                tone: colors.danger,
                                onPressed: busy.contains(advance.id)
                                    ? null
                                    : () => onDecide(advance, false),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Sheets ────────────────────────────────────────────────────

/// Pick an employee, an amount, and a reason.
class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({required this.deductions});

  final bool deductions;

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  String? _userId;
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final roster = ref.watch(rosterProvider(''));
    final currency = ref.watch(sessionProvider)?.currencyCode ?? '';

    final major = double.tryParse(_amount.text.trim()) ?? 0;
    final valid =
        _userId != null && major > 0 && _reason.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        top: Space.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(widget.deductions ? 'adj.addDeduction' : 'adj.addBonus'),
              style: MadarType.h3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: Space.md),
            FieldLabel(t('adj.employee')),
            const SizedBox(height: Space.xs),
            roster.maybeWhen(
              data: (list) => Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final e in list)
                    TactileScale(
                      onTap: () => setState(() => _userId = e.userId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                          vertical: Space.sm,
                        ),
                        decoration: BoxDecoration(
                          color: _userId == e.userId
                              ? colors.accent
                              : colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                        child: Text(
                          e.name,
                          style: MadarType.labelSm.copyWith(
                            color: _userId == e.userId
                                ? colors.textOnAccent
                                : colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              orElse: () => const SkeletonRow(),
            ),
            const SizedBox(height: Space.md),
            FieldLabel('${t('adj.amount')} · $currency'),
            const SizedBox(height: Space.xs),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              style: MadarType.numMd.copyWith(color: colors.textPrimary),
              decoration: _decoration(colors, '0.00'),
            ),
            const SizedBox(height: Space.md),
            FieldLabel(t('adj.reason')),
            const SizedBox(height: Space.xs),
            TextField(
              controller: _reason,
              onChanged: (_) => setState(() {}),
              style: MadarType.body.copyWith(color: colors.textPrimary),
              decoration: _decoration(colors, t('adj.reasonHint')),
            ),
            const SizedBox(height: Space.lg),
            PrimaryButton(
              label: t('common.save'),
              onPressed: valid
                  ? () => Navigator.of(context).pop((
                      userId: _userId!,
                      // Major units in, piastres out — the wire is integer
                      // minor units everywhere, so this is the one place the
                      // conversion happens.
                      minor: (major * 100).round(),
                      reason: _reason.text.trim(),
                    ))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A reason, and optionally a replacement amount.
class _ReasonSheet extends ConsumerStatefulWidget {
  const _ReasonSheet({
    required this.titleKey,
    required this.hintKey,
    required this.withAmount,
    this.initialMinor = 0,
  });

  final String titleKey;
  final String hintKey;
  final bool withAmount;
  final int initialMinor;

  @override
  ConsumerState<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends ConsumerState<_ReasonSheet> {
  late final _amount = TextEditingController(
    text: widget.withAmount
        ? (widget.initialMinor / 100).toStringAsFixed(2)
        : '',
  );
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    // Zero IS allowed on an override — it means "charge nothing" while keeping
    // the row and its history, which is different from deleting it.
    final major = double.tryParse(_amount.text.trim());
    final amountOk = !widget.withAmount || (major != null && major >= 0);
    final valid = amountOk && _reason.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        top: Space.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(widget.titleKey),
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.xs),
          Text(
            t(widget.hintKey),
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.md),
          if (widget.withAmount) ...[
            FieldLabel(t('adj.newAmount')),
            const SizedBox(height: Space.xs),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              style: MadarType.numMd.copyWith(color: colors.textPrimary),
              decoration: _decoration(colors, '0.00'),
            ),
            const SizedBox(height: Space.md),
          ],
          FieldLabel(t('adj.reason')),
          const SizedBox(height: Space.xs),
          TextField(
            controller: _reason,
            onChanged: (_) => setState(() {}),
            style: MadarType.body.copyWith(color: colors.textPrimary),
            decoration: _decoration(colors, t('adj.reasonHint')),
          ),
          const SizedBox(height: Space.lg),
          PrimaryButton(
            label: t('common.save'),
            onPressed: valid
                ? () => Navigator.of(context).pop((
                    minor: ((major ?? 0) * 100).round(),
                    reason: _reason.text.trim(),
                  ))
                : null,
          ),
        ],
      ),
    );
  }
}

InputDecoration _decoration(MadarColors colors, String hint) => InputDecoration(
  hintText: hint,
  hintStyle: MadarType.body.copyWith(color: colors.textMuted),
  filled: true,
  fillColor: colors.surface,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: Space.md,
    vertical: Space.md,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.sm),
    borderSide: BorderSide(color: colors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.sm),
    borderSide: BorderSide(color: colors.accent),
  ),
);
