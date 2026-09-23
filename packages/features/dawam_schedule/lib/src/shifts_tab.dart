import 'package:design_system/design_system.dart';
import 'package:feature_dawam_schedule/src/shift_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// My shifts on a calendar: published weeks only (SC-3), changes marked
/// (SC-4), open shifts to claim (SC-9), swaps (SC-8), and my preferences
/// (SC-12).
class ShiftsTab extends ConsumerWidget {
  const ShiftsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final me = store.me!;
    final asks = store.reqs
        .where((r) => r.peer == me && r.status == ReqStatus.awaitingPeer)
        .toList();
    // Swaps I asked for that nobody decided yet: I can take them back.
    final mine = store.reqs
        .where(
          (r) =>
              r.kind == ReqKind.swap &&
              r.emp == me &&
              (r.status == ReqStatus.awaitingPeer ||
                  r.status == ReqStatus.pending),
        )
        .toList();
    final next = weekStart(store.today).add(const Duration(days: 7));
    final nextPublished = store.user.branches.every(
      (b) => store.published.contains('$b|$next'),
    );
    final shifts = store.shifts
        .where(
          (s) =>
              store.isPublished(s) &&
              (s.emp == me ||
                  (s.emp == null &&
                      store.user.branches.contains(s.template.branch))),
        )
        .toList();
    return MadarContentFrame(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          top: Space.lg,
          bottom: Space.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            for (final r in asks) _SwapAsk(r),
            for (final r in mine) _MySwap(r),
            if (!nextPublished)
              NoticeBanner(
                text: tr('staff.not_published_yet_you_ll_get'),
                tone: ChipTone.info,
              ),
            Expanded(
              child: ShiftCalendar(
                shifts: shifts,
                now: () => ref.read(dawamProvider).now,
                phoneView: CalendarView.list,
                tabletView: CalendarView.month,
                colorOf: (s) => s.emp == null ? c.warning : c.brand,
                titleOf: (s) => s.emp == null
                    ? tr('staff.open_shift')
                    : '${tplName(s.template)} · '
                          '${branchName(store, s.template.branch)}',
                onTapShift: (s) => _tap(context, ref, s),
                trailing: MadarChip(
                  label: tr('staff.my_preferences'),
                  glyph: MadarGlyph.star,
                  onTap: () => _prefs(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _tap(BuildContext context, WidgetRef ref, Shift s) async {
    final store = ref.read(dawamProvider);
    if (!s.startAt.isAfter(store.now)) return;
    if (s.emp == null) {
      final claimed = store.reqs.any(
        (r) =>
            r.shift == s.id &&
            r.emp == store.me &&
            r.status == ReqStatus.pending,
      );
      if (claimed) {
        ref.read(toastProvider.notifier).show(tr('staff.claimed'));
        return;
      }
      final ok = await showMadarConfirm(
        context,
        title: tr('staff.claim_this_shift'),
        body:
            '${dayLabel(s.date)} · ${tplName(s.template)} · ${shiftWindow(s)}',
        confirmLabel: tr('staff.claim'),
        cancelLabel: tr('staff.not_now'),
      );
      if (ok) {
        await attempt(
          ref,
          () => store.claim(s),
          ok: tr('staff.claimed_waiting_for_the_manager'),
        );
      }
      return;
    }
    if (context.mounted) await _swap(context, s);
  }

  Future<void> _swap(BuildContext context, Shift mine) => showDawamSheet<void>(
    context,
    title: tr('staff.swap_this_shift'),
    builder: (ctx, ref, store) {
      final options =
          store.shifts
              .where(
                (s) =>
                    s.emp != null &&
                    s.emp != store.me &&
                    s.template.branch == mine.template.branch &&
                    store.isPublished(s) &&
                    s.startAt.isAfter(store.now),
              )
              .toList()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          MadarCard.column(
            spacing: 0,
            children: [
              MadarSummaryLine(
                label: tr('staff.day'),
                value: dayLabel(mine.date),
              ),
              MadarSummaryLine(
                label: tplName(mine.template),
                value: shiftWindow(mine),
              ),
            ],
          ),
          const OfflineNotice(),
          DawamSection(
            tr('staff.swap_with'),
            children: [
              for (final s in options.take(12))
                MadarListRow.nav(
                  title: name(store.emp(s.emp!)),
                  meta: '${dayLabel(s.date)} · ${tplName(s.template)}',
                  onTap: () async {
                    // MY shift first, the colleague's second (06 B2).
                    final sent = await attempt(
                      ref,
                      () => store.askSwap(mine, s),
                      ok: tr('staff.asked', {'name': name(store.emp(s.emp!))}),
                    );
                    if (sent && ctx.mounted) Navigator.of(ctx).maybePop();
                  },
                ),
            ],
          ),
          Text(
            tr('staff.your_colleague_agrees_first_then_your'),
            style: MadarType.bodySm.copyWith(color: ctx.madarColors.textMuted),
          ),
        ],
      );
    },
  );

  Future<void> _prefs(BuildContext context) => showDawamSheet<void>(
    context,
    title: tr('staff.my_preferences'),
    builder: (ctx, ref, store) {
      final u = store.user;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          MadarSectionHeader(text: tr('staff.preferred_time')),
          MadarSegmented<String>(
            items: [
              MadarSegmentItem('morning', tr('staff.mornings')),
              MadarSegmentItem('evening', tr('staff.evenings')),
              MadarSegmentItem('any', tr('staff.any')),
            ],
            value: u.prefTime ?? 'any',
            onChanged: (v) =>
                store.setPrefs(u.id, v == 'any' ? null : v, u.cantWork),
          ),
          MadarSectionHeader(text: tr('staff.days_i_can_t_work')),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final d in [6, 7, 1, 2, 3, 4, 5])
                MadarChip(
                  label: weekday(d),
                  selected: u.cantWork.contains(d),
                  onTap: () => store.setPrefs(
                    u.id,
                    u.prefTime,
                    u.cantWork.contains(d)
                        ? ({...u.cantWork}..remove(d))
                        : {...u.cantWork, d},
                  ),
                ),
            ],
          ),
          Text(
            tr('staff.your_manager_sees_these_when_building'),
            style: MadarType.bodySm.copyWith(color: ctx.madarColors.textMuted),
          ),
        ],
      );
    },
  );
}

/// A colleague asked to swap: agree first, then the manager decides.
class _SwapAsk extends ConsumerWidget {
  const _SwapAsk(this.r);

  final Req r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final a = store.shifts.firstWhere((s) => s.id == r.shift);
    final b = store.shifts.firstWhere((s) => s.id == r.shift2);
    return MadarCard.column(
      children: [
        Row(
          spacing: Space.md,
          children: [
            personAvatar(store.emp(r.emp), size: 36),
            Expanded(
              child: Text(
                tr('staff.wants_to_swap', {'name': name(store.emp(r.emp))}),
                style: MadarType.title,
              ),
            ),
          ],
        ),
        Text(
          tr('staff.their_your', {
            'date': dayLabel(a.date),
            'shift': tplName(a.template),
            'date2': dayLabel(b.date),
            'shift2': tplName(b.template),
          }),
          style: MadarType.body,
        ),
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: MadarButton(
                label: tr('staff.decline_swap'),
                variant: MadarButtonVariant.secondary,
                size: MadarButtonSize.compact,
                onTap: () =>
                    attempt(ref, () => store.peerAnswer(r, yes: false)),
              ),
            ),
            Expanded(
              child: MadarButton(
                label: tr('staff.agree'),
                size: MadarButtonSize.compact,
                glyph: MadarGlyph.check,
                onTap: () => attempt(
                  ref,
                  () => store.peerAnswer(r, yes: true),
                  ok: tr('staff.sent_to_the_manager'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One side of a swap: its day and shift, from the shift when I have it,
/// else from its id (`emp|yyyy-mm-dd|template`).
String _side(Shift? s, String? id) {
  if (s != null) return '${dayLabel(s.date)} · ${tplName(s.template)}';
  final p = (id ?? '').split('|');
  final day = p.length > 1 ? DateTime.tryParse(p[1]) : null;
  final tpl = p.length > 2 ? tplIndex[p[2]] : null;
  return [
    if (day != null) dayLabel(day),
    if (tpl != null) tplName(tpl),
  ].join(' · ');
}

/// A swap I asked for, still undecided: I can take it back (SC-8).
class _MySwap extends ConsumerWidget {
  const _MySwap(this.r);

  final Req r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final a = store.shifts.where((s) => s.id == r.shift).firstOrNull;
    final b = store.shifts.where((s) => s.id == r.shift2).firstOrNull;
    final peer = r.peer == null ? null : store.emps[r.peer];
    return MadarCard.column(
      children: [
        Text(tr('staff.swap_this_shift'), style: MadarType.title),
        // Which swap, even when its week isn't published to me yet and its
        // shifts aren't in my picture: the ids carry the day and the shift
        // (E2E S5 — the card said only "Swap this shift").
        Text(
          '${_side(a, r.shift)} ⇄ '
          '${peer == null ? '' : '${name(peer)} · '}'
          '${_side(b, r.shift2)}',
          style: MadarType.body,
        ),
        MadarButton(
          label: tr('staff.cancel_swap'),
          variant: MadarButtonVariant.secondary,
          size: MadarButtonSize.compact,
          glyph: MadarGlyph.close,
          onTap: () => attempt(ref, () => store.cancel(r)),
        ),
      ],
    );
  }
}
