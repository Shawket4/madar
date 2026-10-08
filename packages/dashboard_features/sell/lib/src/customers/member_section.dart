/// A customer's loyalty card inside the customer sheet (the web's
/// `features/loyalty/admin/members/member-section.tsx`, SELL-CUS-041 …
/// 043): what they hold, the actions (adjust, wallet, leave) and the ledger —
/// every movement with its branch, its order and its reason, a row a later
/// reversal undoes struck through.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'adjust_dialog.dart';
import 'customers_data.dart';
import 'google_object_dialog.dart';
import 'leave_dialog.dart';
import 'people_widgets.dart';
import 'person_surface.dart';

class MemberSection extends ConsumerWidget {
  const MemberSection({
    required this.detail,
    required this.onOpenOrder,
    required this.onForgotten,
    this.branchId,
    this.readOnly = false,
    super.key,
  });

  final MemberDetail detail;

  /// The branch an adjustment defaults to (the scope the sheet was opened
  /// under).
  final String? branchId;

  /// Opened from somewhere that only looks: no actions at all.
  final bool readOnly;
  final ValueChanged<String> onOpenOrder;

  /// They left the programme.
  final VoidCallback onForgotten;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final access = ref.watch(peopleAccessProvider);
    final member = detail.member;
    final canAdjust = access.canAdjust && !readOnly;
    final canForget = access.canForget && !readOnly;
    final canInspect = access.canInspectWallet && !readOnly;
    final branches = canAdjust
        ? ref.watch(branchesProvider).value ?? const <Branch>[]
        : const <Branch>[];
    final active = [
      for (final b in branches)
        if (b.isActive) b,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        _MemberSummary(member: member),
        if (canAdjust || canForget || canInspect)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              if (canAdjust)
                DashButton(
                  label: t('loyalty.adjustTitle'),
                  icon: 'sliders-horizontal',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => showAdjustDialog(
                    context,
                    member: member,
                    branches: active,
                    defaultBranchId: branchId,
                  ),
                ),
              if (canInspect)
                DashButton(
                  label: t('loyalty.googleObject'),
                  icon: 'wallet',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => showGoogleObjectDialog(
                    context,
                    memberId: member.id,
                    memberName: member.name,
                  ),
                ),
              if (canForget)
                DashButton(
                  label: t('loyalty.leave.action'),
                  icon: 'user-minus',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () async {
                    final left = await showLeaveProgrammeDialog(
                      context,
                      member: member,
                    );
                    if (left) onForgotten();
                  },
                ),
            ],
          ),
        LedgerList(entries: detail.ledger, onOpenOrder: onOpenOrder),
        if (detail.ledger.length >= ledgerShownMax)
          Text(
            t('loyalty.ledgerTruncated'),
            style: DashType.small.copyWith(
              color: context.madarColors.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _MemberSummary extends ConsumerWidget {
  const _MemberSummary({required this.member});

  final MemberView member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final visits = member.mode == 'visits';
    final other = visits ? 'points' : 'visits';
    final otherBalance = visits ? member.pointsBalance : member.visitsBalance;
    final joined = t(
      'loyalty.joinedOn',
      args: {'date': fmt.fmtDate(member.enrolledAt)},
    );
    final also = otherBalance != 0
        ? ' · ${t('loyalty.otherBalance', args: {'amount': '$otherBalance ${loyaltyUnit(t, other, otherBalance)}'})}'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        StatGrid(
          children: [
            StatBox(
              label: t('loyalty.balance'),
              value:
                  '${member.balance} ${loyaltyUnit(t, member.mode, member.balance)}',
            ),
            StatBox(
              label: t('loyalty.lifetime'),
              value:
                  '${visits ? member.lifetimeVisits : member.lifetimePoints}',
            ),
            StatBox(
              label: t('loyalty.rewardsReady'),
              value: '${member.rewardsReady}',
            ),
            StatBox(
              label: t('loyalty.progress'),
              value:
                  '${member.pointsToNextReward} ${loyaltyUnit(t, member.mode, member.pointsToNextReward)}',
            ),
          ],
        ),
        Text(
          '$joined$also',
          style: DashType.small.copyWith(
            color: context.madarColors.textSecondary,
          ),
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

/// The ledger (`LedgerTable`): a table on a wide screen, stacked rows on a
/// phone.
class LedgerList extends ConsumerWidget {
  const LedgerList({
    required this.entries,
    required this.onOpenOrder,
    super.key,
  });

  final List<LedgerEntry> entries;
  final ValueChanged<String> onOpenOrder;

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
    final undone = reversedIds(entries);
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
          Text('“$n”', textDirection: autoDirection(n), style: muted),
      ],
    );

    Widget amount(LedgerEntry e) {
      final isUndone = undone.contains(e.id);
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: signedAmount(e.points),
              style: DashType.mono.copyWith(
                fontSize: 14,
                color: isUndone ? c.textSecondary : c.textPrimary,
                decoration: isUndone ? TextDecoration.lineThrough : null,
              ),
            ),
            const TextSpan(text: ' '),
            TextSpan(
              text: loyaltyUnit(t, e.currency, e.points.abs()),
              style: muted.copyWith(
                decoration: isUndone ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
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
        if (e.orderId case final id?)
          LinkText(
            label: t('loyalty.viewOrder'),
            icon: 'receipt',
            small: true,
            onTap: () => onOpenOrder(id),
          ),
      ],
    );

    if (phone) {
      return RuledBox(
        children: [
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
        ],
      );
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
    return RuledBox(
      children: [
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
      ],
    );
  }
}
