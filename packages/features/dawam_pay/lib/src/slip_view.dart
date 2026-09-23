import 'package:design_system/design_system.dart';
import 'package:feature_dawam_pay/src/payslip_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// A payslip's lines, each with its reason (PAY-9, AD-6), as the kit's
/// summary lines. With [manage], a rule-made line can be waived with a
/// reason — never deleted — and a manual one-off deleted (AD-7).
class SlipLines extends ConsumerWidget {
  const SlipLines(this.slip, {this.manage = false, super.key});

  final Slip slip;
  final bool manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final open =
        manage &&
        store.period.status == PeriodStatus.open &&
        !store.period.frozen.containsKey(slip.emp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (slip.carryIn > 0)
          NoticeBanner(
            text: tr('staff.carried_in_from_the_last_payslip', {
              'amount': egp(slip.carryIn),
            }),
          ),
        if (slip.carryOut > 0)
          NoticeBanner(
            text: tr('staff.deductions_exceed_pay_this_payslip_stops', {
              'amount': egp(slip.carryOut),
            }),
            tone: ChipTone.danger,
          ),
        MadarCard.column(
          spacing: 0,
          children: [
            for (final l in slip.lines)
              _Line(
                l,
                onTap: open && (l.rule || l.manual != null)
                    ? () => _actions(context, ref, l)
                    : null,
              ),
            const MadarHairline(),
            MadarSummaryLine(
              label: tr('staff.net'),
              minor: slip.net,
              currency: 'EGP',
              emphasis: true,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref, Line l) async {
    final store = ref.read(dawamProvider);
    if (l.manual != null) {
      final ok = await showMadarConfirm(
        context,
        title: tr('staff.delete_this_line'),
        body: loc(l),
        confirmLabel: tr('staff.delete'),
        cancelLabel: tr('staff.keep'),
      );
      if (ok) await store.deleteAdj(l.manual!);
      return;
    }
    if (l.waived) {
      await store.unwaive(l.key);
      return;
    }
    if (!context.mounted) return;
    final reason = TextEditingController();
    await showDawamSheet<void>(
      context,
      title: tr('staff.waive_this_deduction'),
      builder: (ctx, ref, store) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          MadarSummaryLine(
            label: loc(l),
            minor: l.amount,
            currency: 'EGP',
            signed: true,
            tone: MadarTone.danger,
          ),
          Text(
            tr('staff.rule_made_lines_are_never_deleted'),
            style: MadarType.bodySm.copyWith(color: ctx.madarColors.textMuted),
          ),
          MadarField(
            controller: reason,
            placeholder: tr('staff.reason_required'),
            kind: MadarFieldKind.note,
            autofocus: true,
          ),
          MadarButton(
            label: tr('staff.waive'),
            onTap: () async {
              if (reason.text.trim().isEmpty) {
                ref
                    .read(toastProvider.notifier)
                    .show(
                      tr('staff.a_reason_is_required'),
                      tone: ChipTone.danger,
                    );
                return;
              }
              final done = await attempt(
                ref,
                () => store.waive(l.key, reason.text.trim()),
              );
              if (done && ctx.mounted) Navigator.of(ctx).maybePop();
            },
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.l, {this.onTap});

  final Line l;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MadarSummaryLine(
          label: loc(l),
          minor: l.amount == 0 && l.waived ? null : l.amount,
          value: l.waived ? tr('staff.waived_short') : null,
          currency: 'EGP',
          signed: true,
          strike: l.waived,
          muted: l.waived,
          tone: l.amount < 0 ? MadarTone.danger : null,
        ),
        if (l.waived && l.note != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
            child: Text(
              tr('staff.waived', {'note': l.note!}),
              style: MadarType.bodySm.copyWith(
                color: context.madarColors.textMuted,
              ),
            ),
          ),
      ],
    );
    if (onTap == null) return line;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: line,
    );
  }
}

/// A frozen payslip; PDF in Arabic or English after approval (PAY-10).
Future<void> payslipSheet(BuildContext context, Slip s) => showDawamSheet<void>(
  context,
  title: tr('staff.payslip', {'date': s.start, 'date2': s.end}),
  builder: (ctx, ref, store) {
    final paid = [
      store.period,
      ...store.history,
    ].where((p) => sameDay(p.start, s.start)).firstOrNull?.paidBy[s.emp];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        Row(
          spacing: Space.md,
          children: [
            personAvatar(store.emp(s.emp)),
            Expanded(
              child: Text(name(store.emp(s.emp)), style: MadarType.title),
            ),
            MadarStatusPill.of(
              paid == null
                  ? tr('staff.payslip_approved')
                  : tr('staff.paid_with_method', {'method': payMethod(paid)}),
              tone: paid == null ? MadarTone.accent : MadarTone.success,
            ),
          ],
        ),
        SlipLines(s),
        Row(
          spacing: Space.sm,
          children: [
            for (final (l, ar) in [('العربية', true), ('English', false)])
              Expanded(
                child: MadarButton(
                  label: 'PDF · $l',
                  glyph: MadarGlyph.printer,
                  size: MadarButtonSize.compact,
                  variant: MadarButtonVariant.secondary,
                  onTap: () => sharePayslipPdf(
                    slip: s,
                    person: name(store.emp(s.emp)),
                    business: store.orgName,
                    arabic: ar,
                    paidWith: paid == null ? null : payMethod(paid),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  },
);
