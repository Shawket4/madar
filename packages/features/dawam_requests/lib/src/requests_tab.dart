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

/// A request's "when", in the words of its kind.
String reqWhen(Req r) {
  final d = r.from == null ? '' : dayLabel(r.from!);
  return switch (r.kind) {
    ReqKind.leave || ReqKind.mission =>
      r.to != null && !sameDay(r.to!, r.from!)
          ? '$d → ${dayLabel(r.to!)}'
          : '$d${r.half ? tr('staff.half_day_suffix') : ''}',
    ReqKind.lateArrival => '$d · ${tr('staff.until')} ${hmMin(r.time!)}',
    ReqKind.earlyDeparture =>
      '$d · ${tr('staff.from_inline')} ${hmMin(r.time!)}',
    ReqKind.excuse ||
    ReqKind.correction => '$d · ${hmMin(r.time!)} – ${hmMin(r.time2!)}',
    ReqKind.salaryAdvance =>
      '${egp(r.amount)} · '
          '${r.installments == 1 ? tr('staff.next_payslip') : tr('staff.months', {'installments': r.installments})}',
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
    final cancellable =
        r.status == ReqStatus.pending ||
        r.status == ReqStatus.awaitingPeer ||
        (r.status == ReqStatus.approved &&
            r.kind == ReqKind.leave &&
            store.monthOpen(r.from!));
    return MadarListRow.bill(
      title: kindLabel(r.kind),
      meta: [reqWhen(r), if (r.note.isNotEmpty) r.note].join(' · '),
      status: statusOf(r.status),
      onTap: cancellable
          ? () async {
              final ok = await showMadarConfirm(
                context,
                title: tr('staff.cancel_this_request'),
                body: r.status == ReqStatus.approved
                    ? tr('staff.those_days_are_repriced')
                    : null,
                confirmLabel: tr('staff.cancel_request'),
                cancelLabel: tr('staff.keep'),
              );
              if (ok) {
                attempt(ref, () => store.cancel(r), ok: tr('staff.cancelled'));
              }
            }
          : null,
    );
  }
}

/// The form for one kind. Leave takes a range and full/half day; the
/// timed kinds take their times; the manager decides paid or unpaid.
Future<void> requestSheet(BuildContext context, ReqKind k) {
  DateTime? from;
  DateTime? to;
  var half = false;
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
                if (v != null) setS(() => from = v);
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
                value: hmMin(time2),
                glyph: MadarGlyph.clock,
                onTap: () async {
                  final v = await pickTime(ctx, time2);
                  if (v != null) setS(() => time2 = v);
                },
              ),
            MadarField(
              controller: note,
              placeholder: tr('staff.note_for_your_manager'),
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
              onTap: () {
                if (k == ReqKind.excuse && time2 <= time) {
                  ref
                      .read(toastProvider.notifier)
                      .show(
                        tr('staff.the_end_must_be_after_the'),
                        tone: ChipTone.danger,
                      );
                  return;
                }
                final sent = attempt(
                  ref,
                  () => store.file(
                    k,
                    from: day,
                    to: to,
                    half: half,
                    time: multi ? null : time,
                    time2: k == ReqKind.excuse ? time2 : null,
                    note: note.text,
                  ),
                  ok: store.user.role == Role.owner
                      ? tr('staff.approved')
                      : tr('staff.sent_to_your_manager'),
                );
                if (sent) Navigator.of(ctx).maybePop();
              },
            ),
          ],
        );
      },
    ),
  );
}
