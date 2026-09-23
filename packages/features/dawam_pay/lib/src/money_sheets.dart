import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:staff_core/staff_core.dart';

/// A bonus or deduction — one-off (AD-1, AD-2) or every month (AD-3), an
/// amount or a % of salary. Over the manager's limit it waits for the owner
/// (AD-5). [emp] fixes the person; otherwise one is picked here.
Future<void> adjustmentSheet(BuildContext context, {String? emp}) {
  var who = emp;
  var bonus = true;
  var recurring = false;
  var pct = false;
  final amount = TextEditingController();
  final reason = TextEditingController();
  return showDawamSheet<void>(
    context,
    title: tr('staff.bonus_or_deduction'),
    builder: (ctx, ref, store) => StatefulBuilder(
      builder: (ctx, setS) {
        final people = store.visibleEmps.where((e) => e.id != store.me);
        who ??= people.firstOrNull?.id;
        // Nobody I can add this for (06 B6): say so, never crash.
        if (who == null) return const _NoOneHere();
        final limit = bonus
            ? store.managerBonusLimit
            : store.managerDeductLimit;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            const OfflineNotice(),
            if (emp == null)
              _PersonPicker(
                people: people.toList(),
                value: who!,
                onChanged: (v) => setS(() => who = v),
              )
            else
              Row(
                spacing: Space.md,
                children: [
                  personAvatar(store.emp(emp), size: 36),
                  Text(name(store.emp(emp)), style: MadarType.title),
                ],
              ),
            MadarSegmented<bool>(
              items: [
                MadarSegmentItem(true, tr('staff.bonus')),
                MadarSegmentItem(false, tr('staff.deduction')),
              ],
              value: bonus,
              onChanged: (v) => setS(() {
                bonus = v;
                if (!v) pct = false;
              }),
            ),
            MadarSegmented<bool>(
              items: [
                MadarSegmentItem(false, tr('staff.one_off')),
                MadarSegmentItem(true, tr('staff.every_month')),
              ],
              value: recurring,
              onChanged: (v) => setS(() => recurring = v),
            ),
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: MadarField(
                    controller: amount,
                    placeholder: pct
                        ? tr('staff.of_salary')
                        : tr('staff.amount_egp'),
                    kind: MadarFieldKind.decimal,
                  ),
                ),
                if (bonus)
                  MadarChip(
                    label: '%',
                    selected: pct,
                    onTap: () => setS(() => pct = !pct),
                  ),
              ],
            ),
            MadarField(
              controller: reason,
              placeholder: tr('staff.reason_the_employee_sees_it'),
              kind: MadarFieldKind.note,
            ),
            if (store.user.role != Role.owner)
              Text(
                tr('staff.over_waits_for_the_owner_before', {
                  'amount': egp(limit),
                }),
                style: MadarType.bodySm.copyWith(
                  color: ctx.madarColors.textMuted,
                ),
              ),
            MadarButton(
              label: tr('staff.add'),
              glyph: MadarGlyph.plus,
              onTap: () async {
                final v = readNumber(amount.text);
                if (v == null || v <= 0 || reason.text.trim().isEmpty) {
                  ref
                      .read(toastProvider.notifier)
                      .show(
                        tr('staff.amount_and_reason_are_required'),
                        tone: ChipTone.danger,
                      );
                  return;
                }
                final added = await attempt(
                  ref,
                  () => store.addAdjustment(
                    who!,
                    bonus: bonus,
                    amount: pct ? 0 : (v * 100).round(),
                    pct: pct ? v : null,
                    reason: reason.text.trim(),
                    recurring: recurring,
                  ),
                  ok: tr('staff.added'),
                );
                if (added && ctx.mounted) Navigator.of(ctx).maybePop();
              },
            ),
          ],
        );
      },
    ),
  );
}

/// A salary advance recorded by a manager: in full from the next payslip,
/// or monthly installments (AV-3), within the owner's cap (AV-5).
Future<void> recordAdvanceSheet(BuildContext context, String emp) {
  final amount = TextEditingController();
  var inst = 1;
  return showDawamSheet<void>(
    context,
    title: tr('staff.record_a_salary_advance'),
    builder: (ctx, ref, store) => StatefulBuilder(
      builder: (ctx, setS) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(name(store.emp(emp)), style: MadarType.title),
          MadarField(
            controller: amount,
            placeholder: tr('staff.amount_egp'),
            kind: MadarFieldKind.decimal,
          ),
          Text(
            tr('staff.outstanding_cap', {
              'amount': egp(store.outstandingAdvances(emp)),
              'amount2': egp(store.advanceCap(emp)),
            }),
            style: MadarType.bodySm.copyWith(
              color: ctx.madarColors.textSecondary,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  inst == 1
                      ? tr('staff.in_full_from_the_next_payslip')
                      : tr('staff.installments_monthly'),
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
          MadarButton(
            label: tr('staff.record'),
            onTap: () async {
              final v = readMoney(amount);
              if (v == null) {
                ref
                    .read(toastProvider.notifier)
                    .show(tr('staff.enter_an_amount'), tone: ChipTone.danger);
                return;
              }
              final done = await attempt(
                ref,
                () => store.recordAdvance(emp, v, inst),
                ok: tr('staff.recorded'),
              );
              if (done && ctx.mounted) Navigator.of(ctx).maybePop();
            },
          ),
        ],
      ),
    ),
  );
}

/// Cash handed over for shop purchases: logged only — never deducted,
/// never settled (AV-7, AV-8).
Future<void> expenseSheet(BuildContext context, {String? emp}) {
  var who = emp;
  var via = 'safe';
  final amount = TextEditingController();
  final purpose = TextEditingController();
  return showDawamSheet<void>(
    context,
    title: tr('staff.log_an_expense_advance'),
    builder: (ctx, ref, store) => StatefulBuilder(
      builder: (ctx, setS) {
        final people = store.visibleEmps.toList();
        who ??= people.firstOrNull?.id;
        if (who == null) return const _NoOneHere();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            if (emp == null)
              _PersonPicker(
                people: people,
                value: who!,
                onChanged: (v) => setS(() => who = v),
              )
            else
              Text(name(store.emp(emp)), style: MadarType.title),
            MadarField(
              controller: amount,
              placeholder: tr('staff.amount_egp'),
              kind: MadarFieldKind.decimal,
            ),
            MadarField(
              controller: purpose,
              placeholder: tr('staff.what_it_s_for'),
              kind: MadarFieldKind.note,
            ),
            MadarSegmented<String>(
              items: [
                MadarSegmentItem('safe', tr('staff.from_the_safe')),
                MadarSegmentItem('bank', tr('staff.bank_transfer')),
                MadarSegmentItem('till', tr('staff.till_pay_out')),
              ],
              value: via,
              onChanged: (v) => setS(() => via = v),
            ),
            Text(
              tr('staff.a_log_only_never_deducted_never'),
              style: MadarType.bodySm.copyWith(
                color: ctx.madarColors.textMuted,
              ),
            ),
            MadarButton(
              label: tr('staff.log_it'),
              onTap: () async {
                final v = readMoney(amount);
                if (v == null || purpose.text.trim().isEmpty) {
                  ref
                      .read(toastProvider.notifier)
                      .show(
                        tr('staff.amount_and_purpose_are_required'),
                        tone: ChipTone.danger,
                      );
                  return;
                }
                final done = await attempt(
                  ref,
                  () => store.logExpense(who!, v, purpose.text.trim(), via),
                  ok: tr('staff.logged'),
                );
                if (done && ctx.mounted) Navigator.of(ctx).maybePop();
              },
            ),
          ],
        );
      },
    ),
  );
}

/// Who a form is for: avatar chips that scroll sideways on a phone.
class _PersonPicker extends StatelessWidget {
  const _PersonPicker({
    required this.people,
    required this.value,
    required this.onChanged,
  });

  final List<Emp> people;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      spacing: Space.sm,
      children: [
        for (final e in people)
          MadarChip(
            label: firstName(e),
            selected: e.id == value,
            onTap: () => onChanged(e.id),
          ),
      ],
    ),
  );
}

/// A money sheet opened with nobody visible to pick (a manager whose
/// branches have no one else yet).
class _NoOneHere extends StatelessWidget {
  const _NoOneHere();

  @override
  Widget build(BuildContext context) => Text(
    tr('staff.no_one_to_pick'),
    style: MadarType.body.copyWith(color: context.madarColors.textMuted),
  );
}
