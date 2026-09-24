import 'package:design_system/design_system.dart';
import 'package:feature_dawam_pay/src/money_sheets.dart';
import 'package:feature_dawam_pay/src/slip_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

enum _View { preview, adjustments, advances, payout }

/// The payroll run: one for the whole business (PAY-3), a live preview that
/// is the same calculation approval freezes (PAY-2), bonuses and deductions,
/// advances, approve and reopen (PAY-5, PAY-6), paid per person with a
/// method (PAY-7) and the bank and wallet lists (PAY-8).
class PayrollTab extends ConsumerStatefulWidget {
  const PayrollTab({super.key});

  @override
  ConsumerState<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends ConsumerState<PayrollTab> {
  _View _view = _View.preview;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final p = store.period;
    // The server's run, not everyone visible (PAY-3): someone not on
    // payroll has no slip and no row (owner decision 2).
    final slips = store.runSlips(
      p,
    )..sort((a, b) => name(store.emp(a.emp)).compareTo(name(store.emp(b.emp))));
    final total = slips.fold(0, (a, s) => a + s.net);
    final status = switch (p.status) {
      PeriodStatus.open => MadarStatus(
        tr('staff.open_live_preview'),
        tone: MadarTone.warning,
      ),
      PeriodStatus.approved => MadarStatus(
        tr('staff.approved_payslips_frozen'),
        tone: MadarTone.accent,
      ),
      PeriodStatus.paid => MadarStatus(
        tr('staff.paid'),
        tone: MadarTone.success,
        glyph: MadarGlyph.check,
      ),
    };
    return DawamPage(
      width: MadarContentWidth.full,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${dayMonth(p.start)} – ${dayMonth(p.end)}',
                style: MadarType.h2,
              ),
            ),
            MadarStatusPill(status),
          ],
        ),
        LayoutBuilder(
          builder: (context, box) {
            final cards = [
              MadarStatCard(
                label: tr('staff.net_total'),
                minor: total,
                currency: 'EGP',
                glyph: MadarGlyph.banknote,
                compact: true,
              ),
              MadarStatCard(
                label: tr('staff.people'),
                value: '${slips.length}',
                glyph: MadarGlyph.users,
                compact: true,
              ),
              MadarStatCard(
                label: tr('staff.paid'),
                value: '${p.paidBy.length + p.settled.length}/${slips.length}',
                glyph: MadarGlyph.check,
                compact: true,
              ),
            ];
            if (box.maxWidth < 560) {
              return Column(
                spacing: Space.md,
                children: [
                  cards.first,
                  Row(
                    spacing: Space.md,
                    children: [
                      for (final c in cards.skip(1)) Expanded(child: c),
                    ],
                  ),
                ],
              );
            }
            return Row(
              spacing: Space.md,
              children: [for (final c in cards) Expanded(child: c)],
            );
          },
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: Space.sm,
            children: [
              for (final (v, label, g) in [
                (_View.preview, tr('staff.preview'), MadarGlyph.receipt),
                (_View.adjustments, tr('staff.adjustments'), MadarGlyph.edit),
                (_View.advances, tr('staff.advances'), MadarGlyph.wallet),
                (_View.payout, tr('staff.pay_out'), MadarGlyph.banknote),
              ])
                MadarChip(
                  label: label,
                  glyph: g,
                  selected: _view == v,
                  onTap: () => setState(() => _view = v),
                ),
            ],
          ),
        ),
        ...switch (_view) {
          _View.preview => _preview(store, slips),
          _View.adjustments => _adjustments(store),
          _View.advances => _advances(store),
          _View.payout => _payout(store, slips),
        },
        if (p.status == PeriodStatus.open)
          Text(
            tr('staff.one_run_for_the_whole_business'),
            style: MadarType.bodySm.copyWith(color: c.textMuted),
          ),
      ],
    );
  }

  List<Widget> _preview(DawamStore store, List<Slip> slips) => [
    DawamSection(
      tr('staff.payroll_payslips'),
      children: [
        for (final s in slips)
          MadarListRow.bill(
            title: name(store.emp(s.emp)),
            meta: [
              store
                  .emp(s.emp)
                  .branches
                  .map((b) => branchName(store, b))
                  .join(' · '),
              if (s.carryOut > 0)
                tr('staff.carries', {'amount': egp(s.carryOut)}),
              if (s.carryIn > 0)
                tr('staff.carried_in', {'amount': egp(s.carryIn)}),
            ].join(' · '),
            minor: s.net,
            currency: 'EGP',
            rail: s.carryOut > 0 ? MadarTone.danger : null,
            onTap: () => _slip(s.emp),
          ),
      ],
    ),
  ];

  Future<void> _slip(String emp) => showDawamSheet<void>(
    context,
    title: name(ref.read(dawamProvider).emp(emp)),
    refreshable: true,
    builder: (ctx, ref, store) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        SlipLines(store.slip(emp, store.period), manage: true),
        if (store.period.status == PeriodStatus.open) ...[
          Text(
            tr('staff.tap_a_rule_line_to_waive'),
            style: MadarType.bodySm.copyWith(color: ctx.madarColors.textMuted),
          ),
          MadarButton(
            label: tr('staff.add_bonus_or_deduction'),
            glyph: MadarGlyph.plus,
            variant: MadarButtonVariant.secondary,
            onTap: () => adjustmentSheet(ctx, emp: emp),
          ),
        ],
      ],
    ),
  );

  List<Widget> _adjustments(DawamStore store) {
    final list = store.adjs.where((a) => a.status != 'deleted').toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return [
      MadarButton(
        label: tr('staff.add_bonus_or_deduction'),
        glyph: MadarGlyph.plus,
        enabled: store.period.status == PeriodStatus.open,
        tooltip: tr('staff.payroll_is_approved'),
        onTap: () => adjustmentSheet(context),
      ),
      DawamSection(
        tr('staff.this_period'),
        children: [
          for (final a in list)
            MadarListRow.bill(
              title: '${name(store.emp(a.emp))} · ${a.reason}',
              meta: [
                if (a.recurring)
                  tr('staff.every_month')
                else
                  tr('staff.one_off'),
                tr('staff.by_name', {'name': name(store.emp(a.by))}),
                dayMonth(a.at),
              ].join(' · '),
              minor: a.bonus
                  ? a.value(store.emp(a.emp))
                  : -a.value(store.emp(a.emp)),
              currency: 'EGP',
              rail: a.bonus ? MadarTone.success : MadarTone.danger,
              status: switch (a.status) {
                'pendingOwner' => MadarStatus(
                  tr('staff.waits_for_owner'),
                  tone: MadarTone.warning,
                ),
                'rejected' => MadarStatus(
                  tr('staff.declined'),
                  tone: MadarTone.danger,
                ),
                'stopped' => MadarStatus(tr('staff.stopped')),
                _ => null,
              },
              onTap: a.recurring && a.status == 'active'
                  ? () => _stop(a)
                  : null,
            ),
        ],
      ),
    ];
  }

  List<Widget> _advances(DawamStore store) => [
    DawamSection(
      tr('staff.salary_advances'),
      children: [
        for (final a in store.advances)
          MadarListRow.bill(
            title: name(store.emp(a.emp)),
            meta: tr('staff.installment_s', {
              'amount': egp(a.amount),
              'installments': a.installments,
              'date': a.date,
            }),
            minor: a.outstanding,
            currency: 'EGP',
            rail: a.outstanding == 0 ? MadarTone.success : MadarTone.warning,
          ),
      ],
    ),
    DawamSection(
      tr('staff.expense_advances_log_only'),
      trailing: MadarButton(
        label: tr('staff.log_an_expense_advance'),
        size: MadarButtonSize.compact,
        variant: MadarButtonVariant.secondary,
        glyph: MadarGlyph.plus,
        onTap: () => expenseSheet(context),
      ),
      children: [
        for (final x in store.expenses.reversed)
          MadarListRow.bill(
            title: '${name(store.emp(x.emp))} · ${x.purpose}',
            meta: [
              dayMonth(x.date),
              branchName(store, x.branch),
              tr('staff.by_name', {'name': name(store.emp(x.by))}),
              switch (x.via) {
                'till' => tr('staff.till_pay_out_inline'),
                'bank' => tr('staff.bank_transfer_inline'),
                _ => tr('staff.safe'),
              },
            ].join(' · '),
            minor: x.amount,
            currency: 'EGP',
          ),
      ],
    ),
  ];

  List<Widget> _payout(DawamStore store, List<Slip> slips) {
    final p = store.period;
    if (p.status == PeriodStatus.open) {
      final carries = slips.where((s) => s.carryOut > 0).toList();
      return [
        if (carries.isNotEmpty)
          NoticeBanner(
            text: tr('staff.shortfall_list', {
              'count': carries.length,
              'names': carries
                  .map((s) => name(store.emp(s.emp)))
                  .join(isAr ? '، ' : ', '),
            }),
          ),
        MadarMoneyBar(
          label: tr('staff.approve_payroll'),
          amountMinor: slips.fold(0, (a, s) => a + s.net),
          currency: 'EGP',
          onTap: () async {
            final ok = await showMadarConfirm(
              context,
              title: tr('staff.approve_and_freeze_every_payslip'),
              body: tr('staff.employees_see_their_payslips_the_month'),
              confirmLabel: tr('staff.approve_payroll_confirm'),
              cancelLabel: tr('staff.not_yet'),
            );
            if (ok) await store.approvePayroll();
          },
        ),
      ];
    }
    return [
      Row(
        spacing: Space.sm,
        children: [
          Expanded(
            child: MadarButton(
              label: tr('staff.bank_file'),
              glyph: MadarGlyph.card,
              size: MadarButtonSize.compact,
              variant: MadarButtonVariant.secondary,
              onTap: () => _list(tr('staff.bank_file'), PayMethod.bank),
            ),
          ),
          Expanded(
            child: MadarButton(
              label: tr('staff.wallet_list'),
              glyph: MadarGlyph.phone,
              size: MadarButtonSize.compact,
              variant: MadarButtonVariant.secondary,
              onTap: () => _list(tr('staff.wallet_list'), PayMethod.wallet),
            ),
          ),
        ],
      ),
      DawamSection(
        tr('staff.mark_each_person_paid'),
        children: [
          for (final s in slips)
            MadarListRow.bill(
              title: name(store.emp(s.emp)),
              meta: payMethod(store.emp(s.emp).pay),
              minor: s.net,
              currency: 'EGP',
              status: p.settled.contains(s.emp)
                  ? MadarStatus(tr('staff.nothing_to_pay'))
                  : p.paidBy[s.emp] == null
                  ? null
                  : MadarStatus(
                      tr('staff.paid_with_method', {
                        'method': payMethod(p.paidBy[s.emp]!),
                      }),
                      tone: MadarTone.success,
                    ),
              ctaLabel: p.paidBy[s.emp] == null && !p.settled.contains(s.emp)
                  ? tr('staff.paid')
                  : null,
              onCta: p.paidBy[s.emp] == null && !p.settled.contains(s.emp)
                  ? () => _markPaid(s.emp)
                  : null,
            ),
        ],
      ),
      if (p.paidBy.isEmpty)
        MadarButton(
          label: tr('staff.reopen_payroll'),
          variant: MadarButtonVariant.ghost,
          onTap: _reopen,
        ),
      if (p.status == PeriodStatus.paid)
        NoticeBanner(
          text: tr('staff.everyone_is_paid_this_month_is'),
          tone: ChipTone.success,
        ),
    ];
  }

  /// Stopping an every-month line is logged with why (AD-3, AD-9): the
  /// server refuses a stop without a reason, and its refusal is shown.
  Future<void> _stop(Adj a) {
    final reason = TextEditingController();
    return showDawamSheet<void>(
      context,
      title: tr('staff.stop_this_every_month_line'),
      builder: (ctx, ref, store) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            '${name(store.emp(a.emp))} · ${a.reason}',
            style: MadarType.body,
          ),
          MadarField(
            controller: reason,
            placeholder: tr('staff.reason_required'),
            kind: MadarFieldKind.note,
            autofocus: true,
          ),
          MadarButton(
            label: tr('staff.stop'),
            variant: MadarButtonVariant.danger,
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
                () => store.stopAdj(a, reason.text.trim()),
                ok: tr('staff.stopped'),
              );
              if (done && ctx.mounted) Navigator.of(ctx).maybePop();
            },
          ),
        ],
      ),
    );
  }

  /// Reopening is logged with why (AD-9, PAY-6): ask before sending.
  Future<void> _reopen() {
    final reason = TextEditingController();
    return showDawamSheet<void>(
      context,
      title: tr('staff.reopen_payroll'),
      builder: (ctx, ref, store) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(tr('staff.reopen_reason'), style: MadarType.body),
          MadarField(
            controller: reason,
            placeholder: tr('staff.reason_required'),
            kind: MadarFieldKind.note,
            autofocus: true,
          ),
          MadarButton(
            label: tr('staff.reopen_payroll'),
            variant: MadarButtonVariant.danger,
            onTap: () async {
              if (reason.text.trim().isEmpty) {
                ref
                    .read(toastProvider.notifier)
                    .show(
                      tr('staff.a_reason_is_required_to_reopen'),
                      tone: ChipTone.danger,
                    );
                return;
              }
              final done = await attempt(
                ref,
                () => store.reopenPayroll(reason.text.trim()),
                ok: tr('staff.reopened_advances_were_not_collected_twice'),
              );
              if (done && ctx.mounted) Navigator.of(ctx).maybePop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _markPaid(String emp) {
    var m = ref.read(dawamProvider).emp(emp).pay;
    return showDawamSheet<void>(
      context,
      title: tr('staff.paid_how'),
      builder: (ctx, ref, store) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Text(name(store.emp(emp)), style: MadarType.title),
            MadarSegmented<PayMethod>(
              items: [
                for (final x in PayMethod.values)
                  MadarSegmentItem(x, payMethod(x)),
              ],
              value: m,
              onChanged: (v) => setS(() => m = v),
            ),
            MadarButton(
              label: tr('staff.mark_paid'),
              onTap: () async {
                final done = await attempt(ref, () => store.markPaid(emp, m));
                if (done && ctx.mounted) Navigator.of(ctx).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The bank file or the wallet list: this period's payslips of everyone
  /// paid that way, read from the store while open, so a pull shows the
  /// fresh figures.
  Future<void> _list(String title, PayMethod method) => showDawamSheet<void>(
    context,
    title: title,
    refreshable: true,
    builder: (ctx, ref, store) {
      final rows = [
        for (final e in store.emps.values)
          if (e.pay == method) store.slip(e.id, store.period),
      ];
      return MadarCard.column(
        spacing: 0,
        children: [
          for (final s in rows)
            MadarSummaryLine(
              label: '${store.emp(s.emp).en} · ${store.emp(s.emp).account}',
              minor: s.net,
              currency: 'EGP',
            ),
          const MadarHairline(),
          MadarSummaryLine(
            label: '${rows.length}',
            minor: rows.fold<int>(0, (a, s) => a + s.net),
            currency: 'EGP',
            emphasis: true,
          ),
        ],
      );
    },
  );
}
