import 'package:design_system/design_system.dart';
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

enum _P { inNow, late, absent, notYet, leave, done, off }

/// Team: who's in, late, absent or on leave now for my branches (RO-6); the
/// flags to handle (CL-6…CL-9, CV-3, RO-4); punch for someone (CL-13).
class TeamTab extends ConsumerStatefulWidget {
  const TeamTab({super.key});

  @override
  ConsumerState<TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends ConsumerState<TeamTab> {
  String? _branch;

  /// Where someone is right now: the SERVER's call (AT-3, team presence),
  /// never worked out here from grace minutes and the phone's clock. The
  /// roster only supplies the words (which shift, when it starts).
  (_P, String) _presence(DawamStore store, Emp e) {
    final p = store.presence[e.id];
    final since = p?.since;
    final today = store
        .rostered(e.id, store.today)
        .where((s) => !s.covered)
        .toList();
    final next = today.where((s) => s.inAt == null).firstOrNull;
    return switch (p?.state) {
      PresenceState.in_ => (
        _P.inNow,
        since == null
            ? tr('staff.in_now')
            : tr('staff.in_since', {'time': hm(since)}),
      ),
      PresenceState.late => (
        _P.late,
        tr('staff.in_since_m_late', {
          'time': since == null ? '—' : hm(since),
          'l': p!.lateMinutes,
        }),
      ),
      PresenceState.absent => (_P.absent, tr('staff.absent_now')),
      PresenceState.onLeave => (_P.leave, tr('staff.on_leave_now')),
      PresenceState.done => (_P.done, tr('staff.done_for_today')),
      // Off now: a shift still to come today, or nothing today.
      _ when next != null => (
        _P.notYet,
        tr('staff.starts', {'time': hm(next.startAt)}),
      ),
      _ => (_P.off, tr('staff.off_today')),
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dawamProvider);
    final people = store.visibleEmps
        .where(
          (e) =>
              e.id != store.me &&
              (_branch == null || e.branches.contains(_branch)),
        )
        .toList();
    final ps = {for (final e in people) e.id: _presence(store, e)};
    int n(Set<_P> k) => ps.values.where((p) => k.contains(p.$1)).length;
    const order = [
      _P.absent,
      _P.late,
      _P.inNow,
      _P.notYet,
      _P.leave,
      _P.done,
      _P.off,
    ];
    people.sort(
      (a, b) =>
          order.indexOf(ps[a.id]!.$1).compareTo(order.indexOf(ps[b.id]!.$1)),
    );
    final flags = store.openFlags
        .where(
          (f) => _branch == null || store.emp(f.emp).branches.contains(_branch),
        )
        .toList();

    final head = <Widget>[
      if (store.myBranches.length > 1)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: Space.sm,
            children: [
              MadarChip(
                label: tr('staff.all_branches'),
                selected: _branch == null,
                onTap: () => setState(() => _branch = null),
              ),
              for (final b in store.myBranches)
                MadarChip(
                  label: branchName(store, b),
                  selected: _branch == b,
                  onTap: () => setState(() => _branch = b),
                ),
            ],
          ),
        ),
      Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: MadarStatCard(
              label: tr('staff.in_now'),
              value: '${n({_P.inNow, _P.late})}',
              tone: MadarTone.success,
              glyph: MadarGlyph.check,
              compact: true,
            ),
          ),
          Expanded(
            child: MadarStatCard(
              label: tr('staff.late_now'),
              value: '${n({_P.late})}',
              tone: MadarTone.warning,
              glyph: MadarGlyph.clock,
              compact: true,
            ),
          ),
          Expanded(
            child: MadarStatCard(
              label: tr('staff.not_in'),
              value: '${n({_P.absent})}',
              tone: MadarTone.danger,
              glyph: MadarGlyph.close,
              compact: true,
            ),
          ),
        ],
      ),
    ];
    final flagSection = DawamSection(
      tr('staff.flags'),
      empty: tr('staff.no_flags'),
      children: [
        for (final f in flags)
          MadarListRow.bill(
            title: '${name(store.emp(f.emp))} · ${flagInfo(f.kind).label}',
            meta:
                '${dayLabel(f.at)} · ${hm(f.at)}'
                '${f.minutesAway > 0 ? tr('staff.min_away', {'minutes_away': f.minutesAway}) : ''}',
            rail: flagInfo(f.kind).tone,
            onTap: () => _flag(f),
          ),
      ],
    );
    final peopleSection = DawamSection(
      tr('staff.now'),
      children: [
        for (final e in people)
          MadarListRow.bill(
            title: name(e),
            meta: ps[e.id]!.$2,
            rail: switch (ps[e.id]!.$1) {
              _P.inNow => MadarTone.success,
              _P.late => MadarTone.warning,
              _P.absent => MadarTone.danger,
              _ => MadarTone.neutral,
            },
            onTap: () => _person(e),
          ),
      ],
    );
    return MadarLayoutSwitch(
      phone: (_) => DawamPage(children: [...head, flagSection, peopleSection]),
      tablet: (_) => DawamPage(
        width: MadarContentWidth.full,
        children: [
          ...head,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xl,
            children: [
              Expanded(child: flagSection),
              Expanded(child: peopleSection),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _flag(Flag f) => showDawamSheet<void>(
    context,
    title: flagInfo(f.kind).label,
    builder: (ctx, ref, store) {
      final e = store.emp(f.emp);
      final suggest = store.suggestedAway(f);
      final amount = TextEditingController(
        text: (suggest / 100).toStringAsFixed(0),
      );
      Future<void> done(String how, {int deduct = 0}) async {
        final ok = await attempt(
          ref,
          () => store.resolve(f, how, deduct: deduct),
        );
        if (ok && ctx.mounted) Navigator.of(ctx).maybePop();
      }

      final explain = switch (f.kind) {
        FlagKind.leftMidShift => tr('staff.two_pings_in_a_row_were', {
          'minutes_away': f.minutesAway,
        }),
        FlagKind.suspicious => tr('staff.pings_had_identical_coordinates_or_a'),
        FlagKind.trackingOff => tr('staff.always_location_was_refused_so_no'),
        FlagKind.newPhone => tr('staff.signed_in_on_the_old_phone', {
          'name': name(e),
          'device': e.device,
        }),
        FlagKind.cover => tr('staff.a_cover_is_paid_only_after'),
        FlagKind.timeUnverified => tr(
          'staff.the_phone_rebooted_offline_the_time',
        ),
        FlagKind.phoneDied => tr('staff.phone_died_explain'),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Row(
            spacing: Space.md,
            children: [
              personAvatar(e),
              Expanded(child: Text(name(e), style: MadarType.title)),
              MadarStatusPill.of(
                flagInfo(f.kind).label,
                tone: flagInfo(f.kind).tone,
                glyph: flagInfo(f.kind).glyph,
              ),
            ],
          ),
          Text(explain, style: MadarType.body),
          if (f.kind == FlagKind.leftMidShift) ...[
            Row(
              spacing: Space.sm,
              children: [
                Expanded(
                  child: MadarButton(
                    label: tr('staff.excuse_paid'),
                    size: MadarButtonSize.compact,
                    variant: MadarButtonVariant.secondary,
                    onTap: () => done('excuse_paid'),
                  ),
                ),
                Expanded(
                  child: MadarButton(
                    label: tr('staff.excuse_unpaid'),
                    size: MadarButtonSize.compact,
                    variant: MadarButtonVariant.secondary,
                    onTap: () =>
                        done('excuse_unpaid', deduct: store.suggestedAway(f)),
                  ),
                ),
              ],
            ),
            MadarField(
              controller: amount,
              placeholder: tr('staff.deduction_egp'),
              kind: MadarFieldKind.decimal,
            ),
            Text(
              tr('staff.suggested_min_minute_rate', {
                'minutes_away': f.minutesAway,
                'amount': egp(suggest),
              }),
              style: MadarType.bodySm.copyWith(
                color: ctx.madarColors.textMuted,
              ),
            ),
            MadarButton(
              label: tr('staff.deduct'),
              variant: MadarButtonVariant.danger,
              onTap: () async {
                final v = readMoney(amount);
                if (v == null) {
                  ref
                      .read(toastProvider.notifier)
                      .show(tr('staff.type_an_amount'), tone: ChipTone.danger);
                  return;
                }
                await done('deduct', deduct: v);
              },
            ),
          ],
          if (f.kind == FlagKind.newPhone)
            MadarButton(
              label: tr('staff.revoke_this_phone'),
              variant: MadarButtonVariant.danger,
              onTap: () => done('revoke'),
            ),
          MadarButton(
            label: tr('staff.ignore'),
            variant: MadarButtonVariant.ghost,
            onTap: () => done('ignore'),
          ),
        ],
      );
    },
  );

  Future<void> _person(Emp e) => showDawamSheet<void>(
    context,
    title: name(e),
    builder: (ctx, ref, store) {
      final today = store.rostered(e.id, store.today);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DawamSection(
            tr('staff.today'),
            empty: tr('staff.off_today'),
            children: [
              for (final s in today)
                MadarListRow.bill(
                  title: '${tplName(s.template)} · ${shiftWindow(s)}',
                  meta: s.covered
                      ? tr('staff.covered_by', {
                          'name': name(store.emp(s.coverBy!)),
                        })
                      : s.inAt == null
                      ? tr('staff.no_punch')
                      : '${hm(s.inAt!)} – '
                            '${s.outAt == null ? '…' : hm(s.outAt!)}'
                            '${switch (s.inMethod) {
                              final m? => ' · ${methodLabel(m)}',
                              null => '',
                            }}',
                  ctaLabel: s.covered || s.outAt != null || s.leave != null
                      ? null
                      : s.inAt == null
                      ? tr('staff.punch_in')
                      : tr('staff.punch_out'),
                  onCta: () => _punch(ctx, s),
                ),
            ],
          ),
          DawamSection(
            tr('staff.profile'),
            children: [
              MadarListRow.nav(
                glyph: MadarGlyph.phone,
                title: e.phone,
                meta: tr('staff.whatsapp'),
              ),
              MadarListRow.nav(
                glyph: MadarGlyph.lock,
                title: e.device,
                meta: tr('staff.phone_since', {'date': e.deviceSince ?? ''}),
              ),
              MadarListRow.nav(
                glyph: MadarGlyph.star,
                title: switch (e.prefTime) {
                  'morning' => tr('staff.prefers_mornings'),
                  'evening' => tr('staff.prefers_evenings'),
                  _ => tr('staff.no_time_preference'),
                },
                meta: e.cantWork.isEmpty
                    ? null
                    : tr('staff.can_t_work') +
                          e.cantWork.map(weekday).join(isAr ? '، ' : ', '),
              ),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              MadarButton(
                label: tr('staff.bonus_deduction'),
                size: MadarButtonSize.compact,
                variant: MadarButtonVariant.secondary,
                glyph: MadarGlyph.plus,
                onTap: () => adjustmentSheet(ctx, emp: e.id),
              ),
              MadarButton(
                label: tr('staff.salary_advance'),
                size: MadarButtonSize.compact,
                variant: MadarButtonVariant.secondary,
                glyph: MadarGlyph.banknote,
                onTap: () => recordAdvanceSheet(ctx, e.id),
              ),
              MadarButton(
                label: tr('staff.log_expense_advance'),
                size: MadarButtonSize.compact,
                variant: MadarButtonVariant.secondary,
                glyph: MadarGlyph.bag,
                onTap: () => expenseSheet(ctx, emp: e.id),
              ),
            ],
          ),
        ],
      );
    },
  );

  Future<void> _punch(BuildContext context, Shift s) {
    final reason = TextEditingController();
    return showDawamSheet<void>(
      context,
      title: s.inAt == null
          ? tr('staff.punch_in_for_them')
          : tr('staff.punch_out_for_them'),
      builder: (ctx, ref, store) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            '${name(store.emp(s.emp ?? ''))} · ${hm(store.now)}',
            style: MadarType.title,
          ),
          MadarField(
            controller: reason,
            placeholder: tr('staff.reason_required_e_g_phone_died'),
            kind: MadarFieldKind.note,
            autofocus: true,
          ),
          MadarButton(
            label: tr('staff.punch'),
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
              final ok = await attempt(
                ref,
                () => store.punchFor(s, reason.text.trim()),
              );
              if (ok && ctx.mounted) Navigator.of(ctx).maybePop();
            },
          ),
        ],
      ),
    );
  }
}
