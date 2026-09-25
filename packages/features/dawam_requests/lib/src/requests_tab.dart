import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

const List<(ReqKind, MadarGlyph)> _kinds = [
  (ReqKind.leave, MadarGlyph.calendar),
  (ReqKind.lateArrival, MadarGlyph.clock),
  (ReqKind.earlyDeparture, MadarGlyph.signOut),
  (ReqKind.excuse, MadarGlyph.note),
  (ReqKind.mission, MadarGlyph.bag),
];

/// Requests: leave (full or half day), late arrival, early departure,
/// excuse, mission — and the status of each (RQ-1…RQ-12).
class RequestsTab extends ConsumerWidget {
  const RequestsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final mine =
        store.reqs
            .where(
              (r) =>
                  r.emp == store.me &&
                  r.kind != ReqKind.overtime &&
                  r.kind != ReqKind.cover,
            )
            .toList()
          ..sort((a, b) => b.created.compareTo(a.created));
    final open = mine
        .where(
          (r) =>
              r.status == ReqStatus.pending ||
              r.status == ReqStatus.awaitingPeer,
        )
        .toList();
    final done = mine.where((r) => !open.contains(r)).toList();
    return DawamPage(
      children: [
        const OfflineNotice(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            MadarSectionHeader(text: tr('staff.new_request')),
            LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 600 ? 5 : 2;
                final w = (box.maxWidth - Space.sm * (cols - 1)) / cols;
                return Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final (k, g) in _kinds)
                      SizedBox(
                        width: w,
                        child: MadarCard(
                          onTap: () => requestSheet(context, k),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: Space.md,
                            children: [
                              MadarGlyphIcon(g, color: c.brand, size: 26),
                              Text(kindLabel(k), style: MadarType.title),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            Text(
              tr('staff.fix_a_punch_from_timesheet_ask'),
              style: MadarType.bodySm.copyWith(color: c.textMuted),
            ),
          ],
        ),
        if (open.isNotEmpty)
          DawamSection(
            tr('staff.pending'),
            children: [for (final r in open) _ReqRow(r)],
          ),
        DawamSection(
          tr('staff.my_requests'),
          children: [for (final r in done) _ReqRow(r)],
        ),
      ],
    );
  }
}

/// Who cancelled a request of mine, and why, when it wasn't me (RQ-F6):
/// read from the cancel's own fields — decided_by stays the approver's. A
/// canceller the phone doesn't list (the owner, outside the branch) goes by
/// the name the server sent, else "a manager".
String? cancelledWords(Req r, String? me, String? Function(String id) nameOf) {
  final by = r.cancelledBy;
  if (r.status != ReqStatus.cancelled || by == null || by == me) return null;
  final who = nameOf(by) ?? r.cancelledByName;
  final note = r.cancelNote?.trim() ?? '';
  return [
    if (who == null)
      tr('staff.cancelled_by_manager')
    else
      tr('staff.cancelled_by_name', {'name': who}),
    if (note.isNotEmpty) note,
  ].join(' · ');
}

/// A request row's one line: when, then — if someone else cancelled it —
/// who and why before my own note, so the line's cut never hides it.
String reqMeta(Req r, String? me, String? Function(String id) nameOf) {
  final cancelled = cancelledWords(r, me, nameOf);
  return [
    reqWhen(r),
    ?cancelled,
    ?declineReason(r),
    if (r.note.isNotEmpty) r.note,
  ].join(' · ');
}

/// The lines a request row's meta may take: a row that carries words — my
/// note, why it was declined, who cancelled it and why — is read in full
/// (on a phone one line cut them: "until 9:30 AM …", "… · R…"; an Arabic
/// excuse with its note and times takes five beside its pill), up to eight
/// for a note that runs on; a row that says only when keeps one line.
int reqMetaLines(Req r) =>
    r.note.trim().isNotEmpty ||
        declineReason(r) != null ||
        (r.status == ReqStatus.cancelled && r.cancelledBy != null)
    ? 8
    : 1;

/// Why a request of mine was declined (decision #8: a decline needs a
/// reason, and the person who asked sees it): the server's decision note.
String? declineReason(Req r) {
  final note = r.decisionNote?.trim() ?? '';
  if (r.status != ReqStatus.rejected || note.isEmpty) return null;
  return tr('staff.decline_reason', {'note': note});
}

/// What taking back a request of mine says: a claim on an open shift is
/// withdrawn, as its row then reads (B-H1-5: the server keeps a withdrawn
/// claim apart from a cancel), anything else cancelled.
String takenBackWords(Req r) => r.kind == ReqKind.openShift
    ? tr('staff.claim_withdrawn')
    : tr('staff.cancelled');

/// " · half day", with its half when the server says which (RQ-8).
String halfSuffix(String? half) => switch (half) {
  'first' => tr('staff.half_day_first_suffix'),
  'second' => tr('staff.half_day_second_suffix'),
  _ => tr('staff.half_day_suffix'),
};

/// A request's "when", in the words of its kind.
String reqWhen(Req r) {
  final from = r.from;
  final to = r.to;
  final time = r.time;
  final time2 = r.time2;
  final d = from == null ? '' : dayLabel(from);
  // Times come from the server as it stored them: a correction may fix only
  // the in or only the out, so print what is there and nothing for the rest.
  final window = [
    if (time != null) hmMin(time),
    if (time2 != null) hmMin(time2),
  ].join(' – ');
  // Isolated left-to-right, so an Arabic row reads "23:30 – 00:30" in time
  // order like every other time on the screen (E2E, QUESTIONS #27).
  final ltrWindow = window.isEmpty ? '' : '\u2066$window\u2069';
  return switch (r.kind) {
    ReqKind.leave || ReqKind.mission =>
      to != null && from != null && !sameDay(to, from)
          ? '$d → ${dayLabel(to)}'
          : '$d${r.half ? halfSuffix(r.leaveHalf) : ''}',
    ReqKind.lateArrival when time != null =>
      '$d · ${tr('staff.until')} ${hmMin(time)}',
    ReqKind.earlyDeparture when time != null =>
      '$d · ${tr('staff.from_inline')} ${hmMin(time)}',
    ReqKind.excuse ||
    ReqKind.correction when window.isNotEmpty => '$d · $ltrWindow',
    ReqKind.salaryAdvance =>
      '${egp(r.amount)} · '
          '${r.installments == 1 ? tr('staff.next_payslip') : trCount('staff.months', r.installments, {'installments': r.installments})}',
    ReqKind.overtime => '$d · ${mins(r.minutes)}',
    _ => d,
  };
}

class _ReqRow extends ConsumerWidget {
  const _ReqRow(this.r);

  final Req r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    // Whether its days can still change is the core's answer (RQ-4, B13).
    final cancellable =
        r.status == ReqStatus.pending ||
        r.status == ReqStatus.awaitingPeer ||
        (r.status == ReqStatus.approved &&
            r.kind == ReqKind.leave &&
            r.monthOpen);
    return MadarListRow.bill(
      title: kindLabel(r.kind),
      meta: reqMeta(r, store.me, (id) {
        final e = store.emps[id];
        return e == null ? null : name(e);
      }),
      metaLines: reqMetaLines(r),
      status: reqStatus(r, store.me),
      onTap: !cancellable
          ? null
          : r.status == ReqStatus.approved
          ? () => _cancelApproved(context)
          : () async {
              final ok = await showMadarConfirm(
                context,
                title: tr('staff.cancel_this_request'),
                confirmLabel: tr('staff.cancel_request'),
                cancelLabel: tr('staff.keep'),
              );
              if (ok) {
                await attempt(
                  ref,
                  () => store.cancel(r),
                  ok: takenBackWords(r),
                );
              }
            },
    );
  }

  /// Undoing an approved request says why (AT-7). The sheet waits for the
  /// server and closes only when it agreed.
  Future<void> _cancelApproved(BuildContext context) {
    final why = TextEditingController();
    return showDawamSheet<void>(
      context,
      title: tr('staff.cancel_this_request'),
      builder: (ctx, ref, store) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          const OfflineNotice(),
          Text(
            tr('staff.those_days_are_repriced'),
            style: MadarType.body.copyWith(
              color: ctx.madarColors.textSecondary,
            ),
          ),
          MadarField(
            controller: why,
            placeholder: tr('staff.why_cancel'),
            kind: MadarFieldKind.note,
          ),
          MadarButton(
            label: tr('staff.cancel_request'),
            variant: MadarButtonVariant.danger,
            onTap: () async {
              final done = await attempt(
                ref,
                () => store.cancel(r, note: why.text),
                ok: tr('staff.cancelled'),
              );
              if (done && ctx.mounted) Navigator.of(ctx).maybePop();
            },
          ),
        ],
      ),
    );
  }
}

/// The form for one kind. Leave takes a range and full/half day; the
/// timed kinds take their times; the manager decides paid or unpaid.
Future<void> requestSheet(BuildContext context, ReqKind k) {
  DateTime? from;
  DateTime? to;
  var half = false;
  var leaveHalf = 'first';
  // Paid or unpaid — asked only when my leave is approved as I file it
  // (QUESTIONS #19, RQ-2); null until chosen.
  bool? paid;
  String? shift;
  var time = switch (k) {
    ReqKind.lateArrival => 10 * 60,
    ReqKind.earlyDeparture => 15 * 60,
    _ => 12 * 60,
  };
  var time2 = 13 * 60;
  final note = TextEditingController();
  final multi = k == ReqKind.leave || k == ReqKind.mission;
  return showDawamSheet<void>(
    context,
    title: kindLabel(k),
    builder: (ctx, ref, store) => StatefulBuilder(
      builder: (ctx, setS) {
        final day = from ?? store.today.add(const Duration(days: 1));
        // A timed request names its shift on a split day (B4).
        final timed =
            k == ReqKind.lateArrival ||
            k == ReqKind.earlyDeparture ||
            k == ReqKind.excuse;
        final dayShifts = timed
            ? store.rostered(store.user.id, day)
            : <Shift>[];
        final picked = dayShifts.where((s) => s.id == shift).firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            const OfflineNotice(),
            DawamPickField(
              label: multi ? tr('staff.from') : tr('staff.day'),
              value: dayLabel(day),
              onTap: () async {
                final v = await pickDate(ctx, store, initial: day);
                if (v != null) {
                  setS(() {
                    from = v;
                    shift = null;
                  });
                }
              },
            ),
            if (multi)
              DawamPickField(
                label: tr('staff.to'),
                value: to == null ? tr('staff.same_day') : dayLabel(to!),
                onTap: () async {
                  final v = await pickDate(
                    ctx,
                    store,
                    initial: to ?? day,
                    first: day,
                  );
                  if (v != null) setS(() => to = sameDay(v, day) ? null : v);
                },
              ),
            if (k == ReqKind.leave && to == null)
              MadarSegmented<bool>(
                items: [
                  MadarSegmentItem(false, tr('staff.full_day')),
                  MadarSegmentItem(true, tr('staff.half_day')),
                ],
                value: half,
                onChanged: (v) => setS(() => half = v),
              ),
            if (k == ReqKind.leave && to == null && half)
              MadarSegmented<String>(
                items: [
                  MadarSegmentItem('first', tr('staff.first_half')),
                  MadarSegmentItem('second', tr('staff.second_half')),
                ],
                value: leaveHalf,
                onChanged: (v) => setS(() => leaveHalf = v),
              ),
            if (k == ReqKind.leave && store.selfApproves) ...[
              Text(tr('staff.leave_pay_question'), style: MadarType.bodySm),
              MadarSegmented<bool?>(
                items: [
                  MadarSegmentItem(true, tr('staff.leave_paid')),
                  MadarSegmentItem(false, tr('staff.leave_unpaid')),
                ],
                value: paid,
                onChanged: (v) => setS(() => paid = v),
              ),
            ],
            if (dayShifts.length > 1) ...[
              Text(tr('staff.for_the_shift'), style: MadarType.bodySm),
              MadarSegmented<String>(
                items: [
                  for (final s in dayShifts)
                    MadarSegmentItem(s.id, tplName(s.template)),
                ],
                value: (picked ?? dayShifts.first).id,
                onChanged: (v) => setS(() => shift = v),
              ),
            ],
            if (!multi)
              DawamPickField(
                label: switch (k) {
                  ReqKind.lateArrival => tr('staff.arrive_by'),
                  ReqKind.earlyDeparture => tr('staff.leave_at'),
                  _ => tr('staff.from'),
                },
                value: hmMin(time),
                glyph: MadarGlyph.clock,
                onTap: () async {
                  final v = await pickTime(ctx, time);
                  if (v != null) setS(() => time = v);
                },
              ),
            if (k == ReqKind.excuse)
              DawamPickField(
                label: tr('staff.to'),
                // Ending earlier on the clock runs past midnight (B5).
                value: time2 < time
                    ? '${hmMin(time2)} · ${tr('staff.ends_the_next_day')}'
                    : hmMin(time2),
                glyph: MadarGlyph.clock,
                onTap: () async {
                  final v = await pickTime(ctx, time2);
                  if (v != null) setS(() => time2 = v);
                },
              ),
            MadarField(
              controller: note,
              placeholder: k == ReqKind.mission
                  ? tr('staff.where_you_ll_be')
                  : tr('staff.note_for_your_manager'),
              kind: MadarFieldKind.note,
            ),
            if (k == ReqKind.leave)
              Text(
                tr('staff.your_manager_decides_if_it_s'),
                style: MadarType.bodySm.copyWith(
                  color: ctx.madarColors.textMuted,
                ),
              ),
            MadarButton(
              label: tr('staff.send'),
              onTap: () async {
                // What a request needs (a mission's note, a window that
                // isn't empty) is checked by the core, in its words.
                if (k == ReqKind.leave && store.selfApproves && paid == null) {
                  ref
                      .read(toastProvider.notifier)
                      .show(
                        tr('staff.err_leave_pay_required'),
                        tone: ChipTone.danger,
                      );
                  return;
                }
                Filed? filed;
                final sent = await attempt(
                  ref,
                  () async => filed = await store.file(
                    k,
                    from: day,
                    to: to,
                    half: half && to == null,
                    leaveHalf: leaveHalf,
                    paid: k == ReqKind.leave ? paid : null,
                    time: multi ? null : time,
                    time2: k == ReqKind.excuse ? time2 : null,
                    note: note.text,
                    shift: dayShifts.length > 1
                        ? (picked ?? dayShifts.first).id
                        : null,
                  ),
                );
                if (!sent) return;
                // The server's answer, never the filer's role (RQ-5).
                ref
                    .read(toastProvider.notifier)
                    .show(filedWords(filed), tone: ChipTone.success);
                if (ctx.mounted) Navigator.of(ctx).maybePop();
              },
            ),
          ],
        );
      },
    ),
  );
}

/// A request's status in my list: my own pending one that the owner decides
/// says so (RQ-5, addendum 2), never a plain "Pending".
MadarStatus reqStatus(Req r, String? me) =>
    r.emp == me && r.status == ReqStatus.pending && r.toOwner
    ? MadarStatus(tr('staff.waiting_for_the_owner'), tone: MadarTone.warning)
    : statusOf(r.status);

/// What to tell the filer, from what the server did with it (RQ-5).
String filedWords(Filed? f) => switch (f) {
  (status: ReqStatus.approved, id: _, toOwner: _) => tr('staff.approved'),
  (status: _, id: _, toOwner: true) => tr('staff.sent_to_the_owner'),
  _ => tr('staff.sent_to_your_manager'),
};
