import 'package:design_system/design_system.dart';
import 'package:feature_dawam_pay/src/slip_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// Pay: this period so far, marked estimate, with every line (PAY-9); the
/// payslips (PAY-10); salary advances (AV-2) and the expense-advance log,
/// which never touches pay (AV-9).
class PayTab extends ConsumerWidget {
  const PayTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final me = store.me!;
    final p = store.period;
    final est = store.slip(me, p);
    final slips = store.payslipsOf(me);
    final advs = store.advances.where((a) => a.emp == me).toList();
    final asked = store.reqs.where(
      (r) =>
          r.emp == me &&
          r.kind == ReqKind.salaryAdvance &&
          r.status == ReqStatus.pending,
    );
    final exps = store.expenses.where((x) => x.emp == me).toList();

    final now = <Widget>[
      if (p.status == PeriodStatus.open) ...[
        MadarStatCard(
          label: tr('staff.this_period_so_far'),
          minor: est.net,
          currency: 'EGP',
          glyph: MadarGlyph.wallet,
          meta: '${dayMonth(p.start)} – ${dayMonth(p.end)}',
          status: MadarStatus(tr('staff.estimate'), tone: MadarTone.warning),
        ),
        SlipLines(est),
      ],
    ];
    final history = <Widget>[
      DawamSection(
        tr('staff.payslips'),
        children: [
          for (final s in slips)
            MadarListRow.bill(
              title: '${dayMonth(s.start)} – ${dayMonth(s.end)}',
              meta: s.carryOut > 0
                  ? tr('staff.shortfall_carried', {'amount': egp(s.carryOut)})
                  : null,
              minor: s.net,
              currency: 'EGP',
              rail: s.carryOut > 0 ? MadarTone.danger : MadarTone.success,
              onTap: () => payslipSheet(context, s),
            ),
        ],
      ),
      DawamSection(
        tr('staff.salary_advances'),
        trailing: MadarButton(
          label: tr('staff.request'),
          size: MadarButtonSize.compact,
          variant: MadarButtonVariant.secondary,
          glyph: MadarGlyph.plus,
          onTap: () => _advanceRequest(context),
        ),
        children: [
          for (final r in asked)
            MadarListRow.bill(
              title: egp(r.amount),
              meta: tr('staff.requested'),
              status: statusOf(r.status),
            ),
          for (final a in advs)
            MadarListRow.bill(
              title: egp(a.amount),
              meta: tr('staff.installment_s_left', {
                'date': a.date,
                'installments': a.installments,
                'amount': egp(a.outstanding),
              }),
              status: MadarStatus(
                a.outstanding == 0 ? tr('staff.repaid') : tr('staff.repaying'),
                tone: a.outstanding == 0
                    ? MadarTone.success
                    : MadarTone.neutral,
              ),
            ),
        ],
      ),
      DawamSection(
        tr('staff.expense_advances'),
        children: [
          for (final x in exps)
            MadarListRow.bill(
              title: x.purpose,
              meta:
                  '${dayMonth(x.date)} · ${tr('staff.from_inline')} '
                  '${name(store.emp(x.by))}',
              minor: x.amount,
              currency: 'EGP',
            ),
        ],
      ),
      Text(
        tr('staff.expense_advances_are_a_log_of'),
        style: MadarType.bodySm.copyWith(color: c.textMuted),
      ),
    ];

    return MadarLayoutSwitch(
      phone: (_) => DawamPage(children: [...now, ...history]),
      tablet: (_) => MadarContentFrame(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xl,
          children: [
            if (now.isNotEmpty)
              Expanded(
                child: DawamPage(width: MadarContentWidth.full, children: now),
              ),
            Expanded(
              child: DawamPage(
                width: MadarContentWidth.full,
                children: history,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _advanceRequest(BuildContext context) {
    final amount = TextEditingController();
    final note = TextEditingController();
    var inst = 1;
    return showDawamSheet<void>(
      context,
      title: tr('staff.request_a_salary_advance'),
      builder: (ctx, ref, store) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            const OfflineNotice(),
            MadarField(
              controller: amount,
              placeholder: tr('staff.amount_egp'),
              kind: MadarFieldKind.decimal,
            ),
            Text(
              tr('staff.outstanding_cap_of_salary', {
                'amount': egp(store.outstandingAdvances(store.me!)),
                'amount2': egp(store.advanceCap(store.me!)),
                'advance_cap_pct': store.advanceCapPct,
              }),
              style: MadarType.bodySm.copyWith(
                color: ctx.madarColors.textSecondary,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    tr('staff.pay_back_over_months'),
                    style: MadarType.body,
                  ),
                ),
                MadarStepper(
                  value: inst,
                  min: 1,
                  max: 6,
                  onChanged: (v) => setS(() => inst = v),
                ),
              ],
            ),
            MadarField(
              controller: note,
              placeholder: tr('staff.what_for_optional'),
              kind: MadarFieldKind.note,
            ),
            MadarButton(
              label: tr('staff.send'),
              onTap: () async {
                final v = readMoney(amount);
                if (v == null) {
                  ref
                      .read(toastProvider.notifier)
                      .show(tr('staff.enter_an_amount'), tone: ChipTone.danger);
                  return;
                }
                final sent = await attempt(
                  ref,
                  () => store.file(
                    ReqKind.salaryAdvance,
                    amount: v,
                    installments: inst,
                    note: note.text,
                  ),
                  ok: tr('staff.sent_to_your_manager'),
                );
                if (sent && ctx.mounted) Navigator.of(ctx).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
