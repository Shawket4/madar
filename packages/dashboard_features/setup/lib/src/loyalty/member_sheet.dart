/// One member's card, opened from a Members row (SET-LOY-062 … 073, 084):
/// what they hold, the actions (adjust, wallet, leave) and the ledger, as
/// the web's `members/{member-section,adjust-dialog,leave-programme-dialog}`.
///
/// The web opens the whole customer sheet here (the sell area's), and so does
/// the app, through dashboard_core's [areaOpenersProvider]. This area cannot
/// depend on that package, so when the seam is not wired (this package's own
/// tests) this panel stands in with the loyalty half — the rows this unit
/// owns — under the person's name and phone.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'google_object_dialog.dart';
import 'loyalty_data.dart';

/// Opens [id]'s card from the end side (full screen on a phone), read under
/// [branchId]'s programme; resolves when it closes.
Future<void> showMemberSheet(
  BuildContext context, {
  required String id,
  required String name,
  String? branchId,
}) => showDashSidePanel<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (_) => MemberSheet(id: id, name: name, branchId: branchId),
);

class MemberSheet extends ConsumerWidget {
  const MemberSheet({
    required this.id,
    required this.name,
    this.branchId,
    super.key,
  });

  final String id;

  /// The row's name, shown while the card loads.
  final String name;
  final String? branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final key = (id: id, branchId: branchId);
    final q = ref.watch(loyaltyMemberProvider(key));
    final detail = q.value;
    final Widget body;
    if (q.awaitingFirst) {
      body = const DashSkeleton(height: Space.xxl * 8);
    } else if (detail == null) {
      body = DashEmptyState(
        title: t('loyalty.memberLoadFailed'),
        description: q.hasError ? errorMessage(q.error, t) : null,
        action: DashButton(
          label: t('common.retry'),
          variant: DashButtonVariant.outline,
          loading: q.isLoading,
          onPressed: () => ref.invalidate(loyaltyMemberProvider(key)),
        ),
      );
    } else {
      body = MemberSection(
        detail: detail,
        branchId: branchId,
        onLeft: () => Navigator.of(context).maybePop(),
      );
    }
    final phone = detail?.member.phone ?? '';
    return _PersonSurface(
      title: detail?.member.name ?? name,
      description: phone.isEmpty
          ? null
          : Text(
              formatPhoneDisplay(phone),
              textDirection: TextDirection.ltr,
              style: DashType.mono.copyWith(
                fontSize: 14,
                color: c.textSecondary,
              ),
            ),
      body: body,
    );
  }
}

/// The sheet's frame: the kit's surface header with a name in its own
/// direction and the phone, left to right, under it.
class _PersonSurface extends StatelessWidget {
  const _PersonSurface({
    required this.title,
    required this.body,
    this.description,
  });

  final String title;
  final Widget? description;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final mode = DashSurfaceScope.maybeOf(context) ?? DashSurfaceMode.panel;
    final full = mode == DashSurfaceMode.fullScreen;
    final pad = full ? Space.lg : Space.card;
    final close = DashIconButton(
      icon: 'x',
      semanticLabel: context.dashStrings.close,
      onPressed: () => Navigator.of(context).maybePop(),
      iconSize: full ? IconSize.md : IconSize.sm,
      color: full ? null : c.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            full ? Space.xs : pad,
            full ? Space.sm : pad - Space.xs,
            Space.sm,
            Space.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (full)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: Space.xs),
                  child: close,
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.xs,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          textDirection: dashTextDirectionOf(title),
                          style: DashType.sectionTitle.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      ?description,
                    ],
                  ),
                ),
              ),
              if (!full) close,
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(pad, Space.sm, pad, pad),
            child: body,
          ),
        ),
      ],
    );
  }
}

/// A bordered stat (`rounded-lg border p-3`): a small label over a figure.
class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: DashMetrics.hair,
        children: [
          MadarClippedText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: DashType.statFigure(18).copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card: four stats (two columns, four from 640), the joined line, the
/// actions, the ledger.
class MemberSection extends ConsumerWidget {
  const MemberSection({
    required this.detail,
    required this.onLeft,
    this.branchId,
    super.key,
  });

  final MemberDetail detail;

  /// The branch an adjustment defaults to (the scope).
  final String? branchId;

  /// They left the programme.
  final VoidCallback onLeft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final access = ref.watch(loyaltyAccessProvider);
    final c = context.madarColors;
    final m = detail.member;
    final visits = m.mode == 'visits';
    final other = visits ? 'points' : 'visits';
    final otherBalance = visits ? m.pointsBalance : m.visitsBalance;
    final stats = [
      _StatBox(
        label: t('loyalty.balance'),
        value: loyaltyCost(t, m.mode, m.balance),
      ),
      _StatBox(
        label: t('loyalty.lifetime'),
        value: '${visits ? m.lifetimeVisits : m.lifetimePoints}',
      ),
      _StatBox(label: t('loyalty.rewardsReady'), value: '${m.rewardsReady}'),
      _StatBox(
        label: t('loyalty.progress'),
        value: loyaltyCost(t, m.mode, m.pointsToNextReward),
      ),
    ];
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm ? 4 : 2;
    final branches = access.canAdjust
        ? [
            for (final b
                in ref.watch(branchesProvider).value ?? const <Branch>[])
              if (b.isActive && isSelling(b)) b,
          ]
        : const <Branch>[];
    final joined = t(
      'loyalty.joinedOn',
      args: {'date': fmt.fmtDate(m.enrolledAt)},
    );
    final also = otherBalance != 0
        ? ' · ${t('loyalty.otherBalance', args: {'amount': loyaltyCost(t, other, otherBalance)})}'
        : '';
    return Column(
      key: const ValueKey('loyalty-member-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            for (var i = 0; i < stats.length; i += cols)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Space.sm,
                  children: [
                    for (var j = i; j < i + cols; j++)
                      Expanded(child: stats[j]),
                  ],
                ),
              ),
            Text(
              '$joined$also',
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
        if (access.canAdjust || access.canForget || access.canInspectWallet)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              if (access.canAdjust)
                DashButton(
                  key: const ValueKey('member-adjust'),
                  label: t('loyalty.adjustTitle'),
                  icon: 'sliders-horizontal',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => showDashDialog<void>(
                    context,
                    builder: (_) => AdjustDialog(
                      member: m,
                      branches: branches,
                      defaultBranchId: branchId,
                    ),
                  ),
                ),
              if (access.canInspectWallet)
                DashButton(
                  key: const ValueKey('member-google'),
                  label: t('loyalty.googleObject'),
                  icon: 'wallet',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => showGoogleObjectDialog(
                    context,
                    memberId: m.id,
                    memberName: m.name,
                  ),
                ),
              if (access.canForget)
                DashButton(
                  key: const ValueKey('member-leave'),
                  label: t('loyalty.leave.action'),
                  icon: 'user-minus',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () async {
                    final left = await showDashDialog<bool>(
                      context,
                      phoneFullScreen: false,
                      barrierDismissible: false,
                      builder: (_) => LeaveProgrammeDialog(member: m),
                    );
                    if (left == true) onLeft();
                  },
                ),
            ],
          ),
        LedgerList(entries: detail.ledger),
        if (detail.ledger.length >= ledgerShownMax)
          Text(
            t('loyalty.ledgerTruncated'),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

DashTone _toneOf(LedgerTone t) => switch (t) {
  LedgerTone.earn => DashTone.success,
  LedgerTone.spend => DashTone.accent,
  LedgerTone.reversal => DashTone.danger,
  LedgerTone.gift => DashTone.warning,
  LedgerTone.manual => DashTone.neutral,
};

/// The ledger: a table on a wide screen, stacked rows on a phone.
class LedgerList extends ConsumerWidget {
  const LedgerList({required this.entries, super.key});

  final List<LedgerEntry> entries;

  /// "View order": the order's own deep link (`/orders?order=<id>`).
  static String orderLink(String orderId) =>
      Uri(path: '/orders', queryParameters: {'order': orderId}).toString();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    if (entries.isEmpty) {
      return DashEmptyState(
        title: t('loyalty.noLedger'),
        description: t('loyalty.noLedgerHint'),
      );
    }
    final undone = ledgerReversedIds(entries);
    final phone = DashBreakpoints.isPhone(context);
    final muted = DashType.small.copyWith(color: c.textSecondary);

    Widget what(LedgerEntry e) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        Wrap(
          spacing: Space.xs + DashMetrics.hair,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DashStatusPill(
              label: ledgerLabel(e, t),
              tone: _toneOf(ledgerTone(e)),
              small: true,
            ),
            if (undone.contains(e.id))
              Text(t('loyalty.ledgerUndone'), style: muted),
          ],
        ),
        Text(ledgerActor(e, t), style: muted),
        if (e.rewardName case final r? when r.isNotEmpty)
          Text(r, style: DashType.small.copyWith(color: c.textPrimary)),
        if (e.note case final n? when n.isNotEmpty)
          Text('“$n”', textDirection: dashTextDirectionOf(n), style: muted),
      ],
    );

    Widget amount(LedgerEntry e) {
      final isUndone = undone.contains(e.id);
      final strike = isUndone ? TextDecoration.lineThrough : null;
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: MadarFormat.ltr(ledgerSigned(e.points)),
              style: DashType.mono.copyWith(
                fontSize: 14,
                color: isUndone ? c.textSecondary : c.textPrimary,
                decoration: strike,
              ),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: loyaltyUnit(t, e.currency, e.points.abs()),
              style: muted.copyWith(decoration: strike),
            ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
      );
    }

    Widget where(LedgerEntry e) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          e.branchName ?? '—',
          style: DashType.small.copyWith(color: c.textPrimary),
        ),
        if (e.orderId case final id?) _ViewOrder(orderId: id),
      ],
    );

    Widget ruled(List<Widget> children) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
            children[i],
          ],
        ],
      ),
    );

    if (phone) {
      return ruled([
        for (final e in entries)
          Padding(
            key: ValueKey('ledger-row-${e.id}'),
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.sm,
                  children: [
                    Expanded(child: what(e)),
                    amount(e),
                  ],
                ),
                Text(fmt.fmtDateTime(e.createdAt), style: muted),
                where(e),
              ],
            ),
          ),
      ]);
    }

    const whenW = Space.xxl * 4;
    const amountW = Space.xxl * 3 + Space.lg;
    const whereW = Space.xxl * 4 + Space.lg;
    Widget head(String s, {bool end = false}) => Text(
      s.toUpperCase(),
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: DashType.tableHeader.copyWith(color: c.textSecondary),
    );
    Widget row(List<Widget> cells, {Key? key, bool header = false}) => Padding(
      key: key,
      padding: EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: header ? Space.sm + DashMetrics.hair : Space.md,
      ),
      child: Row(
        crossAxisAlignment: header
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          SizedBox(width: whenW, child: cells[0]),
          Expanded(child: cells[1]),
          SizedBox(
            width: amountW,
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: cells[2],
            ),
          ),
          SizedBox(width: whereW, child: cells[3]),
        ],
      ),
    );
    return ruled([
      row(header: true, [
        head(t('loyalty.ledgerWhen')),
        head(t('loyalty.ledgerWhat')),
        head(t('loyalty.ledgerAmount'), end: true),
        head(t('loyalty.ledgerWhere')),
      ]),
      for (final e in entries)
        row(key: ValueKey('ledger-row-${e.id}'), [
          Text(fmt.fmtDateTime(e.createdAt), style: muted),
          what(e),
          amount(e),
          where(e),
        ]),
    ]);
  }
}

/// "View order": the orders area's sheet over the card when the app wires it
/// (the web's `onOpenOrder`); otherwise the card closes and the order's deep
/// link opens. Warms what it opens on intent.
class _ViewOrder extends ConsumerWidget {
  const _ViewOrder({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(tProvider)('loyalty.viewOrder');
    final seam = ref.watch(areaOpenersProvider).orderSheet;
    return DashPressable(
      onTap: () {
        if (seam != null) {
          seam.open(context, orderId);
          return;
        }
        final router = GoRouter.of(context);
        Navigator.of(context).maybePop();
        router.go(LedgerList.orderLink(orderId));
      },
      onIntent: () =>
          seam != null ? seam.warm(ref, orderId) : ref.prefetchRoute('/orders'),
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) {
        final fg = dashButtonColors(
          context,
          DashButtonVariant.link,
          s,
          enabled: true,
        ).fg;
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: DashMetrics.target),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                DashIcon('receipt', size: IconSize.xs, color: fg),
                Text(
                  label,
                  style: DashType.small.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    decorationColor: fg,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Add or take away points by hand; the reason stays on their history.
class AdjustDialog extends ConsumerStatefulWidget {
  const AdjustDialog({
    required this.member,
    required this.branches,
    this.defaultBranchId,
    super.key,
  });

  final MemberView member;

  /// The org's active selling branches (warehouses never hold points).
  final List<Branch> branches;
  final String? defaultBranchId;

  @override
  ConsumerState<AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<AdjustDialog> {
  final _form = GlobalKey<FormState>();
  final _reasonFocus = FocusNode();
  late String _branchId =
      widget.defaultBranchId ??
      (widget.branches.length == 1 ? widget.branches.first.id : '');

  /// Shown when there is a choice, or nothing chosen (decided once).
  late final bool _showBranch = widget.branches.length > 1 || _branchId.isEmpty;
  String _direction = 'add';
  String _amount = '';
  String _reason = '';
  String? _reasonServerError;
  bool _pending = false;

  MemberView get _m => widget.member;

  @override
  void dispose() {
    _reasonFocus.dispose();
    super.dispose();
  }

  Map<String, Object?> _vars(Translator t) => {
    'balance': _m.balance,
    'unit': loyaltyUnit(t, _m.mode, _m.balance),
  };

  String? _amountError(String v, Translator t) {
    final n = num.tryParse(v.trim());
    if (n == null || n != n.truncateToDouble() || n <= 0 || n > adjustLimit) {
      return t('loyalty.errors.adjustAmount', args: _vars(t));
    }
    if (_direction == 'deduct' && n > _m.balance) {
      return t('loyalty.errors.adjustOverdraw', args: _vars(t));
    }
    return null;
  }

  String? _reasonError(String v, Translator t) {
    final r = v.trim();
    if (r.length < adjustReasonMin) {
      return t('loyalty.errors.adjustReason', args: _vars(t));
    }
    if (r.length > adjustReasonMax) {
      return t('loyalty.errors.adjustReasonLong', args: _vars(t));
    }
    return null;
  }

  Future<void> _submit() async {
    final t = ref.read(tProvider);
    setState(() => _reasonServerError = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    final amount = num.parse(_amount.trim()).toInt();
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _pending = true);
    try {
      await api.loyalty.loyaltyAdjust(
        body: AdjustRequest(
          branchId: _branchId,
          customerId: _m.id,
          points: _direction == 'deduct' ? -amount : amount,
          note: _reason.trim(),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      final refused = loyaltyServerError(e, t);
      if (refused.kind == LoyaltyRefusal.noteRequired) {
        setState(() => _reasonServerError = refused.message);
        _reasonFocus.requestFocus();
      }
      DashToast.error(context, refused.message);
      setState(() => _pending = false);
      return;
    }
    // Every person read, whatever became of the dialog.
    bus.invalidate(LoyaltyPaths.people);
    if (!mounted) return;
    DashToast.success(context, t('loyalty.adjusted'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    return DashSurface(
      title: t('loyalty.adjustTitle'),
      description: t(
        'loyalty.adjustBody',
        args: {'name': _m.name, ..._vars(t)},
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('adjust-confirm'),
          label: t('loyalty.adjustConfirm'),
          loading: _pending,
          onPressed: _submit,
        ),
      ],
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: DashSegmentedControl<String>(
                options: [
                  DashOption(value: 'add', label: t('loyalty.adjustAdd')),
                  DashOption(value: 'deduct', label: t('loyalty.adjustDeduct')),
                ],
                value: _direction,
                onChanged: (v) => setState(() => _direction = v),
              ),
            ),
            DashFormField<String>(
              key: const ValueKey('adjust-amount'),
              label:
                  '${t('loyalty.adjustAmount')} (${loyaltyUnit(t, _m.mode)})',
              value: _amount,
              validator: (v) => _amountError(v, t),
              builder: (context, invalid) => DashTextInput(
                value: _amount,
                semanticLabel: t('loyalty.adjustAmount'),
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                mono: true,
                invalid: invalid,
                onChanged: (v) => setState(() => _amount = v),
              ),
            ),
            if (_showBranch)
              DashSelectField<String>(
                key: const ValueKey('adjust-branch'),
                label: t('loyalty.adjustBranch'),
                placeholder: t('loyalty.adjustPickBranch'),
                options: [
                  for (final b in widget.branches)
                    DashOption(value: b.id, label: b.name),
                ],
                value: _branchId.isEmpty ? null : _branchId,
                validator: (v) => v == null || v.isEmpty
                    ? t('loyalty.errors.adjustBranch', args: _vars(t))
                    : null,
                onChanged: (v) => setState(() => _branchId = v),
              ),
            DashFormField<String>(
              key: const ValueKey('adjust-reason'),
              label: t('loyalty.adjustReason'),
              value: _reason,
              errorText: _reasonServerError,
              validator: (v) => _reasonError(v, t),
              builder: (context, invalid) => DashTextInput(
                value: _reason,
                focusNode: _reasonFocus,
                semanticLabel: t('loyalty.adjustReason'),
                placeholder: t('loyalty.adjustReasonPlaceholder'),
                minLines: 2,
                maxLines: 4,
                maxLength: adjustReasonMax,
                invalid: invalid,
                onChanged: (v) => setState(() {
                  _reason = v;
                  _reasonServerError = null;
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Take someone out of the programme: the card stops, the customer stays,
/// rejoining restores the balance. Cannot be dismissed mid-request; pops
/// true once they have left.
class LeaveProgrammeDialog extends ConsumerStatefulWidget {
  const LeaveProgrammeDialog({required this.member, super.key});

  final MemberView member;

  @override
  ConsumerState<LeaveProgrammeDialog> createState() =>
      _LeaveProgrammeDialogState();
}

class _LeaveProgrammeDialogState extends ConsumerState<LeaveProgrammeDialog> {
  bool _pending = false;

  Future<void> _confirm() async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _pending = true);
    try {
      await api.loyalty.deleteLoyaltyMember(id: widget.member.id);
    } on Object catch (e) {
      if (!mounted) return;
      DashToast.error(context, loyaltyServerError(e, t).message);
      setState(() => _pending = false);
      return;
    }
    bus.invalidate(LoyaltyPaths.people);
    if (!mounted) return;
    DashToast.success(context, t('loyalty.leave.done'));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    Widget line(String key) =>
        Text(t(key), style: DashType.body.copyWith(color: c.textSecondary));
    return PopScope(
      canPop: !_pending,
      child: DashSurface(
        title: t('loyalty.leave.title', args: {'name': widget.member.name}),
        showClose: false,
        actions: [
          DashButton(
            label: t('common.cancel'),
            variant: DashButtonVariant.outline,
            onPressed: _pending ? null : () => Navigator.of(context).pop(false),
          ),
          DashButton(
            key: const ValueKey('leave-confirm'),
            label: t('loyalty.leave.confirm'),
            loading: _pending,
            onPressed: () => unawaited(_confirm()),
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            line('loyalty.leave.stops'),
            line('loyalty.leave.stays'),
            line('loyalty.leave.rejoin'),
          ],
        ),
      ),
    );
  }
}
