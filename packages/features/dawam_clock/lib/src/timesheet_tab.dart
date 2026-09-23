import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// Timesheet: each shift this period with its punches, lateness, overtime
/// and flags; fix a shift, auto-closed ones included (CL-15, RQ-9).
class TimesheetTab extends ConsumerWidget {
  const TimesheetTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final p = store.period;
    final list =
        store.shifts
            .where(
              (s) =>
                  s.emp == store.me &&
                  store.isPublished(s) &&
                  !s.date.isBefore(p.start) &&
                  !s.startAt.isAfter(store.now),
            )
            .toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt));
    final worked = list.where((s) => s.inAt != null && !s.covered).length;
    final late = list.fold(0, (a, s) => a + store.lateMinutes(s));
    final absent = list.where(store.isAbsent).length;
    return DawamPage(
      children: [
        Text(
          tr('staff.this_period_dates', {'date': p.start, 'date2': p.end}),
          style: MadarType.h2,
        ),
        Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: MadarStatCard(
                label: tr('staff.shifts'),
                value: '$worked',
                glyph: MadarGlyph.check,
                compact: true,
              ),
            ),
            Expanded(
              child: MadarStatCard(
                label: tr('staff.late_total'),
                value: mins(late),
                tone: late > 0 ? MadarTone.warning : null,
                glyph: MadarGlyph.clock,
                compact: true,
              ),
            ),
            Expanded(
              child: MadarStatCard(
                label: tr('staff.absent_total'),
                value: '$absent',
                tone: absent > 0 ? MadarTone.danger : null,
                glyph: MadarGlyph.close,
                compact: true,
              ),
            ),
          ],
        ),
        DawamSection(
          tr('staff.days'),
          children: [for (final s in list) _DayRow(s)],
        ),
      ],
    );
  }
}

class _DayRow extends ConsumerWidget {
  const _DayRow(this.s);

  final Shift s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final late = store.lateMinutes(s);
    final absent = store.isAbsent(s);
    final ot = store.reqs
        .where((r) => r.kind == ReqKind.overtime && r.shift == s.id)
        .firstOrNull;
    final flag = store.flags
        .where((f) => f.shift == s.id && f.kind != FlagKind.cover)
        .firstOrNull;
    final status = absent
        ? MadarStatus(tr('staff.absent_total'), tone: MadarTone.danger)
        : s.leave != null
        ? MadarStatus(
            s.leave == 'paid'
                ? tr('staff.paid_leave')
                : tr('staff.unpaid_leave'),
          )
        : s.mission
        ? MadarStatus(tr('staff.mission'))
        : late > 0
        ? MadarStatus(
            tr('staff.late_m', {'late': late}),
            tone: MadarTone.warning,
          )
        : s.outMethod == Method.auto
        ? MadarStatus(tr('staff.auto_closed'), tone: MadarTone.warning)
        : ot != null
        ? MadarStatus(
            tr('staff.ot_m', {'minutes': ot.minutes}),
            tone: ot.status == ReqStatus.approved
                ? MadarTone.success
                : MadarTone.warning,
          )
        : flag != null
        ? MadarStatus(flagInfo(flag.kind).label, tone: flagInfo(flag.kind).tone)
        : null;
    return MadarListRow.bill(
      title: '${dayLabel(s.date)} · ${tplName(s.template)}',
      meta: s.inAt == null
          ? shiftWindow(s)
          : '${hm(s.inAt!)} – ${s.outAt == null ? '…' : hm(s.outAt!)}'
                '${switch (s.inMethod) {
                  final m? => ' · ${methodLabel(m)}',
                  null => '',
                }}',
      status: status,
      rail: absent
          ? MadarTone.danger
          : late > 0
          ? MadarTone.warning
          : MadarTone.success,
      onTap: () => _detail(context),
    );
  }

  Future<void> _detail(BuildContext context) => showDawamSheet<void>(
    context,
    title: '${dayLabel(s.date)} · ${tplName(s.template)}',
    builder: (ctx, ref, store) {
      final live = store.reqs.any(
        (r) =>
            r.kind == ReqKind.correction &&
            r.shift == s.id &&
            r.status == ReqStatus.pending,
      );
      final late = store.lateMinutes(s);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          MadarCard.column(
            spacing: 0,
            children: [
              MadarSummaryLine(
                label: tr('staff.rostered'),
                value: shiftWindow(s),
              ),
              MadarSummaryLine(
                label: [
                  tr('staff.in_label'),
                  if (s.inMethod != null) methodLabel(s.inMethod!),
                ].join(' · '),
                value: s.inAt == null ? '—' : hm(s.inAt!),
              ),
              MadarSummaryLine(
                label: [
                  tr('staff.out'),
                  if (s.outMethod != null) methodLabel(s.outMethod!),
                ].join(' · '),
                value: s.outAt == null ? '—' : hm(s.outAt!),
              ),
              if (late > 0)
                MadarSummaryLine(
                  label: tr('staff.late_past_grace'),
                  value: mins(late),
                  tone: MadarTone.warning,
                ),
            ],
          ),
          if (live)
            NoticeBanner(
              text: tr('staff.a_correction_for_this_shift_is'),
              tone: ChipTone.info,
            ),
          MadarButton(
            label: tr('staff.fix_this_shift'),
            glyph: MadarGlyph.edit,
            variant: MadarButtonVariant.secondary,
            enabled: !live && s.monthOpen,
            tooltip: tr('staff.one_live_correction_per_shift'),
            onTap: () => correctionSheet(ctx, s),
          ),
        ],
      );
    },
  );
}

/// One live correction per shift (RQ-9); its lateness still counts (RQ-10).
/// Only what is proposed goes: a missing punch, or a time that was changed.
/// An untouched punch stays as recorded (§3).
Future<void> correctionSheet(BuildContext context, Shift s) {
  final inAt = s.inAt;
  final outAt = s.outAt;
  // A missing punch is proposed at THIS shift's times: its own from/to when
  // the rota set them, else its block's (E2E S10: it took the template's).
  final in0 = inAt == null
      ? (s.start ?? s.template.start)
      : inAt.hour * 60 + inAt.minute;
  final out0 = outAt == null
      ? (s.end ?? s.template.end)
      : outAt.hour * 60 + outAt.minute;
  var inT = in0;
  var outT = out0;
  final note = TextEditingController();
  return showDawamSheet<void>(
    context,
    title: tr('staff.fix', {'date': dayLabel(s.date)}),
    builder: (ctx, ref, store) => StatefulBuilder(
      builder: (ctx, setS) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          const OfflineNotice(),
          DawamPickField(
            label: tr('staff.punch_in_label'),
            value: hmMin(inT),
            glyph: MadarGlyph.clock,
            onTap: () async {
              final v = await pickTime(ctx, inT);
              if (v != null) setS(() => inT = v);
            },
          ),
          DawamPickField(
            label: tr('staff.punch_out_label'),
            value: hmMin(outT),
            glyph: MadarGlyph.clock,
            onTap: () async {
              final v = await pickTime(ctx, outT);
              if (v != null) setS(() => outT = v);
            },
          ),
          MadarField(
            controller: note,
            placeholder: tr('staff.what_happened'),
            kind: MadarFieldKind.note,
          ),
          Text(
            tr('staff.lateness_still_counts_fixing_a_missing'),
            style: MadarType.bodySm.copyWith(color: ctx.madarColors.textMuted),
          ),
          MadarButton(
            label: tr('staff.send_to_manager'),
            onTap: () async {
              final sent = await attempt(
                ref,
                () => store.file(
                  ReqKind.correction,
                  from: s.date,
                  shift: s.id,
                  time: inAt == null || inT != in0 ? inT : null,
                  time2: outAt == null || outT != out0 ? outT : null,
                  note: note.text,
                ),
                ok: tr('staff.sent'),
              );
              if (sent && ctx.mounted) {
                Navigator.of(ctx).popUntil((r) => r.isFirst);
              }
            },
          ),
        ],
      ),
    ),
  );
}
