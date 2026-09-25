import 'package:design_system/design_system.dart';
import 'package:feature_dawam_requests/src/requests_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

enum _Filter { all, time, shifts, money }

_Filter _filterOf(ReqKind k) => switch (k) {
  ReqKind.leave ||
  ReqKind.lateArrival ||
  ReqKind.earlyDeparture ||
  ReqKind.excuse ||
  ReqKind.mission ||
  ReqKind.correction => _Filter.time,
  ReqKind.cover ||
  ReqKind.swap ||
  ReqKind.openShift ||
  ReqKind.overtime => _Filter.shifts,
  ReqKind.salaryAdvance => _Filter.money,
};

/// Approvals: one queue for requests, corrections, advances, covers, swaps,
/// open-shift claims, overtime, and — for the owner — adjustments over a
/// manager's limit. Needs a connection and says so (APP-8).
class ApprovalsTab extends ConsumerStatefulWidget {
  const ApprovalsTab({super.key});

  @override
  ConsumerState<ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends ConsumerState<ApprovalsTab> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dawamProvider);
    final reqs = store.inbox;
    final adjs = store.adjInbox;
    int count(_Filter f) => f == _Filter.all
        ? reqs.length + adjs.length
        : reqs.where((r) => _filterOf(r.kind) == f).length +
              (f == _Filter.money ? adjs.length : 0);
    final cards = <Widget>[
      for (final r in reqs)
        if (_filter == _Filter.all || _filterOf(r.kind) == _filter)
          _ReqCard(r, key: ValueKey(r.id)),
      if (_filter == _Filter.all || _filter == _Filter.money)
        for (final a in adjs) _AdjCard(a, key: ValueKey(a.id)),
    ];
    return DawamPage(
      width: MadarContentWidth.full,
      children: [
        const OfflineNotice(),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: Space.sm,
            children: [
              for (final (f, label) in [
                (_Filter.all, tr('staff.filter_all')),
                (_Filter.time, tr('staff.filter_time_off')),
                (_Filter.shifts, tr('staff.filter_shifts')),
                (_Filter.money, tr('staff.filter_money')),
              ])
                MadarChip(
                  label: label,
                  count: count(f),
                  selected: _filter == f,
                  onTap: () => setState(() => _filter = f),
                ),
            ],
          ),
        ),
        if (cards.isEmpty)
          MadarCard(
            child: EmptyState(
              icon: 'checkmark.circle',
              title: tr('staff.all_caught_up'),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final cols = box.maxWidth >= 840 ? 2 : 1;
              final w = (box.maxWidth - Space.lg * (cols - 1)) / cols;
              return Wrap(
                spacing: Space.lg,
                runSpacing: Space.lg,
                children: [for (final c in cards) SizedBox(width: w, child: c)],
              );
            },
          ),
      ],
    );
  }
}

/// A swap waiting for the manager: each side names the person whose shift
/// it is (E2E S-229: the requester was named on both sides).
String swapWords({
  required String requester,
  required String requesterDay,
  required String peer,
  required String peerDay,
}) => tr('staff.s_s_both_agreed', {
  'name': requester,
  'date': requesterDay,
  'name2': peer,
  'date2': peerDay,
});

class _Who extends StatelessWidget {
  const _Who(this.e, this.what, this.at, {this.flag});

  final Emp e;
  final String what;
  final DateTime at;
  final MadarStatus? flag;

  @override
  Widget build(BuildContext context) => Row(
    spacing: Space.md,
    children: [
      personAvatar(e),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name(e), style: MadarType.title),
            Text(
              '$what · ${dayMonth(at)} ${hm(at)}',
              style: MadarType.bodySm.copyWith(
                color: context.madarColors.textSecondary,
              ),
            ),
            if (flag != null) ...[
              const SizedBox(height: Space.xs),
              MadarStatusPill(flag!),
            ],
          ],
        ),
      ),
    ],
  );
}

class _Decide extends ConsumerWidget {
  const _Decide({
    required this.yes,
    required this.no,
    this.yesLabel,
    this.askWhy = false,
    this.warnAfterYes = false,
  });

  final Future<void> Function() yes;

  /// Declines; `why` is the reason typed when [askWhy].
  final Future<void> Function(String? why) no;
  final String? yesLabel;

  /// Declining asks why first (a pay line or an advance, decision #8): the
  /// server refuses a rejection without a reason.
  final bool askWhy;

  /// An approval can come back with labour limits it breaks (an open-shift
  /// claim, minor #26): said as a warning, never a block.
  final bool warnAfterYes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(dawamProvider.select((d) => d.offline));
    return Row(
      spacing: Space.sm,
      children: [
        Expanded(
          child: MadarButton(
            label: tr('staff.decline'),
            size: MadarButtonSize.compact,
            variant: MadarButtonVariant.secondary,
            enabled: !offline,
            tooltip: tr('staff.needs_a_connection'),
            onTap: () => askWhy
                ? declineWithReason(context, no)
                : attempt(ref, () => no(null), ok: tr('staff.declined')),
          ),
        ),
        Expanded(
          child: MadarButton(
            label: yesLabel ?? tr('staff.approve'),
            size: MadarButtonSize.compact,
            glyph: MadarGlyph.check,
            enabled: !offline,
            tooltip: tr('staff.needs_a_connection'),
            onTap: () async {
              if (!warnAfterYes) {
                await attempt(ref, yes, ok: tr('staff.approved'));
                return;
              }
              if (!await attempt(ref, yes)) return;
              final broken = ref.read(dawamProvider).lastWarnings;
              ref
                  .read(toastProvider.notifier)
                  .show(
                    approvedWithWarnings(broken),
                    tone: broken.isEmpty ? ChipTone.success : ChipTone.warning,
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _AdjCard extends ConsumerWidget {
  const _AdjCard(this.a, {super.key});

  final Adj a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final e = store.emp(a.emp);
    return MadarCard.column(
      children: [
        _Who(
          e,
          a.bonus
              ? tr('staff.bonus_over_the_limit')
              : tr('staff.deduction_over_the_limit'),
          a.at,
        ),
        MadarSummaryLine(
          label: a.reason,
          minor: a.bonus ? a.value(e) : -a.value(e),
          currency: 'EGP',
          signed: true,
          tone: a.bonus ? null : MadarTone.danger,
          emphasis: true,
        ),
        Text(
          tr('staff.by_name', {'name': name(store.emp(a.by))}),
          style: MadarType.bodySm.copyWith(
            color: context.madarColors.textMuted,
          ),
        ),
        _Decide(
          yes: () => store.decideAdj(a, yes: true),
          no: (why) => store.decideAdj(a, yes: false, reason: why),
          askWhy: true,
        ),
      ],
    );
  }
}

class _ReqCard extends ConsumerStatefulWidget {
  const _ReqCard(this.r, {super.key});

  final Req r;

  @override
  ConsumerState<_ReqCard> createState() => _ReqCardState();
}

class _ReqCardState extends ConsumerState<_ReqCard> {
  // Leave starts paid; an excuse or early departure from the rule the
  // server sends (branch, else business: RQ-7).
  late bool _paid =
      widget.r.kind == ReqKind.leave || (widget.r.paidDefault ?? false);
  late int _inst = widget.r.installments;
  // To the piastre, so approving it unchanged changes nothing (§3).
  late final String _asked = (widget.r.amount / 100).toStringAsFixed(2);
  late final _amount = TextEditingController(text: _asked);

  /// Pay is asked of leave, an excuse and an early departure only.
  bool get _asksPay => switch (widget.r.kind) {
    ReqKind.leave || ReqKind.excuse || ReqKind.earlyDeparture => true,
    _ => false,
  };

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dawamProvider);
    final r = widget.r;
    final e = store.emp(r.emp);
    final c = context.madarColors;
    // The shift a request names may sit outside the weeks the snapshot holds;
    // then the card falls back to the request's own dates.
    Shift? sh(String? id) =>
        id == null ? null : store.shifts.where((s) => s.id == id).firstOrNull;
    final (s1, s2) = (sh(r.shift), sh(r.shift2));
    // A cover's row is the coverer's; the card names whose shift it was.
    final s1Emp = s1?.coverOf ?? s1?.emp;
    final s1In = s1?.inAt;
    final from = r.from;
    final detail = switch (r.kind) {
      ReqKind.swap when s1 != null && s2 != null && s1Emp != null => swapWords(
        requester: name(store.emp(s1Emp)),
        requesterDay: dayLabel(s1.date),
        peer: name(store.emp(s2.emp ?? r.peer ?? r.emp)),
        peerDay: dayLabel(s2.date),
      ),
      ReqKind.openShift when s1 != null =>
        '${dayLabel(s1.date)} · ${tplName(s1.template)}'
            ' · ${shiftWindow(s1)}',
      ReqKind.cover when s1 != null && s1Emp != null && s1In != null =>
        tr('staff.covered_s_from_paid_at_s', {
          'name': name(store.emp(s1Emp)),
          'shift': tplName(s1.template),
          'time': hm(s1In),
          'name2': name(e),
        }),
      ReqKind.overtime when from != null => tr('staff.past_the_shift_end', {
        'date': dayLabel(from),
        'duration': mins(r.minutes),
      }),
      ReqKind.salaryAdvance => advanceCapLine(
        store,
        r.emp,
        within: r.withinCap,
      ),
      _ => reqWhen(r),
    };
    return MadarCard.column(
      children: [
        _Who(
          e,
          kindLabel(r.kind),
          r.created,
          flag: r.toOwner
              ? MadarStatus(
                  tr('staff.a_manager_s_own_request'),
                  tone: MadarTone.accent,
                )
              : null,
        ),
        Text(detail, style: MadarType.body),
        if (r.note.isNotEmpty)
          Text(
            '“${r.note}”',
            style: MadarType.bodySm.copyWith(color: c.textSecondary),
          ),
        if (_asksPay)
          MadarSegmented<bool>(
            items: [
              MadarSegmentItem(true, tr('staff.approve_paid')),
              MadarSegmentItem(false, tr('staff.unpaid')),
            ],
            value: _paid,
            onChanged: (v) => setState(() => _paid = v),
          ),
        if (r.kind == ReqKind.salaryAdvance) ...[
          MadarField(
            controller: _amount,
            placeholder: tr('staff.amount_egp'),
            kind: MadarFieldKind.decimal,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _inst == 1
                      ? tr('staff.in_full_next_payslip')
                      : tr('staff.installments_count', {'inst': _inst}),
                  style: MadarType.body,
                ),
              ),
              MadarStepper(
                value: _inst,
                min: 1,
                max: 6,
                onChanged: (v) => setState(() => _inst = v),
              ),
            ],
          ),
        ],
        _Decide(
          yes: () => store.decide(
            r,
            approve: true,
            paid: _asksPay ? _paid : null,
            // Sent only when the approver changed it: the asked amount
            // stands as the server has it.
            amount:
                r.kind == ReqKind.salaryAdvance && _amount.text.trim() != _asked
                ? readMoney(_amount)
                : null,
            installments: _inst,
          ),
          no: (why) => store.decide(r, approve: false, note: why),
          askWhy: r.kind == ReqKind.salaryAdvance,
          warnAfterYes: r.kind == ReqKind.openShift,
          yesLabel: r.kind == ReqKind.cover ? tr('staff.confirm_cover') : null,
        ),
        if (r.kind == ReqKind.cover)
          Text(
            tr('staff.declining_pays_nothing_the_absent_owner'),
            style: MadarType.bodySm.copyWith(color: c.textMuted),
          ),
      ],
    );
  }
}

/// "Approved", or "Approved. Mind: …" with the labour limits the approved
/// day breaks (RU-13, minor #26).
String approvedWithWarnings(List<(String, Map<String, Object>)> broken) =>
    broken.isEmpty
    ? tr('staff.approved')
    : tr('staff.approved_mind', {
        'warnings': [
          for (final (key, args) in broken) tr(key, args),
        ].join(isAr ? '، ' : '; '),
      });
