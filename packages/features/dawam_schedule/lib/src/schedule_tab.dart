import 'dart:async';
import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:feature_dawam_schedule/src/coverage_sheet.dart';
import 'package:feature_dawam_schedule/src/roster_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// The manager's roster as a week board: people down the side, Saturday to
/// Friday across. Tap a shift to change or reassign it, tap an empty day to
/// add one, long-press a shift to drag it to another day or person (SC-5,
/// SC-7); publish the week (SC-3); accept or reject suggestions (SC-13);
/// set up holidays (RU-10). Limits warn, never block (RU-13).
class ScheduleTab extends ConsumerStatefulWidget {
  const ScheduleTab({super.key});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<ScheduleTab> {
  String? _pickedBranch;
  late DateTime _week = weekStart(ref.read(dawamProvider).today);

  /// A phone's one-day list, and the day it shows (0 = Saturday).
  bool _dayView = false;
  int? _day;

  DawamStore get _store => ref.read(dawamProvider);

  /// The branch on show: the one picked, while the manager still has it.
  String _branch(DawamStore store) {
    final picked = _pickedBranch;
    if (picked != null && store.myBranches.contains(picked)) return picked;
    return store.myBranches.firstOrNull ?? '';
  }

  List<Emp> _staff(DawamStore store, String branch) =>
      store.emps.values
          .where((e) => e.branches.contains(branch) && e.role != Role.owner)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  String _branchName(DawamStore store, String id) {
    final b = store.branches[id];
    return b == null ? id : loc(b);
  }

  String _who(DawamStore store, String? emp) {
    final e = emp == null ? null : store.emps[emp];
    return e == null ? tr('staff.open_shift') : name(e);
  }

  List<DateTime> _days(DateTime ws) => [
    for (var i = 0; i < 7; i++) DateTime(ws.year, ws.month, ws.day + i),
  ];

  /// "8 AM", "8:30 PM", or "20:30" on a 24-hour phone: short enough for a
  /// phone's column.
  String _clock(int minute) {
    final m = minute % 1440;
    final h = m ~/ 60;
    final mm = (m % 60).toString().padLeft(2, '0');
    if (use24h) return '${h.toString().padLeft(2, '0')}:$mm';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12${mm == '00' ? '' : ':$mm'} '
        '${h < 12 ? tr('staff.am') : tr('staff.pm')}';
  }

  /// A shift's own hours as the server resolved them (the assignment's,
  /// else the block's for that weekday); "+1" when it ends the next day.
  /// Tighter on a phone's narrow column (Arabic's ص and م are short
  /// enough to keep the spaces).
  String _hours(Shift s, {bool tight = false}) {
    final t = s.template;
    final a = s.start ?? t.start;
    final z = s.end ?? t.end;
    return '${_clock(a)}${tight ? '–' : ' – '}${_clock(z)}'
        '${s.nextDay ? ' +1' : ''}';
  }

  /// A block's hours on [d]: that weekday's own, else its default.
  String _blockHours(Tpl t, DateTime d) {
    final (a, z) = t.timesOn(d);
    return '${hmMin(a)} – ${hmMin(z)}${z <= a ? ' +1' : ''}';
  }

  /// The most people the coverage grid asks for at once on [d]'s weekday;
  /// null when the branch has no grid (typed or derived) for it.
  int? _need(DawamStore store, String branch, DateTime d) {
    final view = store.coverage[branch];
    if (view == null) return null;
    List<J> rows(String k) => [
      for (final x in (view[k] as List<dynamic>?) ?? const <dynamic>[])
        if (x is J) x,
    ];
    final typed = rows('needs');
    var peak = 0;
    for (final n in typed.isNotEmpty ? typed : rows('derived')) {
      if (n['day_of_week'] == d.weekday % 7) {
        peak = math.max(peak, (n['staff'] as num?)?.round() ?? 0);
      }
    }
    return peak > 0 ? peak : null;
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final branch = _branch(store);
    final ws = _week;
    final days = _days(ws);
    final end = days.last;
    final thisWeek = sameDay(ws, weekStart(store.today));
    // The week on show is on the phone, or why not (H2-01): past what the
    // phone holds it is fetched, and nothing there is edited blind.
    final away = store.notHeld(ws, end);
    final held = away == null;
    final pub = store.published.contains('$branch|$ws');
    final sugg = store.suggestions.where((g) => g.branch == branch).toList();
    final hols = store.holidays
        .where(
          (h) =>
              h.decision == null &&
              h.date.isAfter(store.today) &&
              h.date.difference(store.today).inDays < 30,
        )
        .toList();
    final phone = MadarLayout.of(context).isPhone;

    // ── the week's picture ──
    final tpls = store.tpls.values.where((t) => t.branch == branch).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    Color tplColor(String id) {
      final i = tpls.indexWhere((t) => t.id == id);
      return c.series[math.max(i, 0) % c.series.length];
    }

    final week = store.shifts.where(
      (s) =>
          store.tpls[s.tpl]?.branch == branch &&
          !s.date.isBefore(ws) &&
          !s.date.isAfter(end),
    );
    final byCell = <String, List<Shift>>{};
    for (final s in week) {
      (byCell['${s.emp}|${dateOnly(s.date)}'] ??= []).add(s);
    }
    for (final l in byCell.values) {
      l.sort((a, b) => a.startAt.compareTo(b.startAt));
    }
    final swaps = {
      for (final r in store.reqs)
        if (r.kind == ReqKind.swap &&
            (r.status == ReqStatus.awaitingPeer ||
                r.status == ReqStatus.pending))
          ...[r.shift, r.shift2].nonNulls,
    };
    final claims = {
      for (final r in store.reqs)
        if (r.kind == ReqKind.openShift && r.status == ReqStatus.pending)
          ?r.shift,
    };
    List<RosterCard> cardsAt(String? emp, DateTime d) => [
      for (final s in byCell['$emp|${dateOnly(d)}'] ?? const <Shift>[])
        RosterCard(
          shift: s,
          title: switch (store.tpls[s.tpl]) {
            final t? => tplName(t),
            null => '',
          },
          window: _hours(s, tight: phone && !isAr),
          color: s.emp == null ? c.warning : tplColor(s.tpl),
          leave: s.leave,
          half: s.halfLeave,
          changed: s.changed,
          swap: swaps.contains(s.id),
          claimed: claims.contains(s.id),
          edited: s.edited,
          nextDay: s.nextDay,
        ),
    ];

    // People: the branch's staff, then anyone else rostered here this week;
    // the open shifts ride on top.
    final staff = _staff(store, branch);
    final extra = {
      for (final s in week)
        if (s.emp case final id? when !staff.any((e) => e.id == id)) id,
    };
    int minutesOf(String emp) {
      var m = 0;
      for (final s in week) {
        if (s.emp != emp || store.tpls[s.tpl] == null) continue;
        final length = s.endAt.difference(s.startAt).inMinutes;
        if (s.leave == null) {
          m += length;
        } else if (s.halfLeave) {
          m += length ~/ 2;
        }
      }
      return m;
    }

    final ids = [...staff.map((e) => e.id), ...extra];
    final rows = [
      RosterRow(emp: null, name: tr('staff.open_shifts'), color: c.warning),
      for (final (i, id) in ids.indexed)
        RosterRow(
          emp: id,
          name: switch (store.emps[id]) {
            final e? => phone ? firstName(e) : name(e),
            null => '—',
          },
          color: c.series[i % c.series.length],
          minutes: minutesOf(id),
        ),
    ];
    final heads = [
      for (final d in days)
        RosterDay(
          d,
          today: sameDay(d, store.today),
          holiday: switch (store.holidays.where(
            (h) => h.decision == 'holiday' && sameDay(h.date, d),
          )) {
            final hs when hs.isNotEmpty => loc(hs.first),
            _ => null,
          },
          staffed: {
            for (final s in byCell.entries)
              if (s.key.endsWith('|$d'))
                for (final x in s.value)
                  if (x.emp != null && x.leave == null) x.emp,
          }.length,
          need: _need(store, branch, d),
        ),
    ];
    final focus = thisWeek ? store.today.difference(ws).inDays.clamp(0, 6) : 0;
    final day = _day ?? focus;

    // ── the bar ──
    final nav = Row(
      spacing: Space.sm,
      children: [
        MadarGlyphTile(
          glyph: MadarGlyph.chevronBack,
          semanticLabel: tr('staff.previous'),
          onTap: () => _goWeek(-7),
        ),
        MadarGlyphTile(
          glyph: MadarGlyph.chevronForward,
          semanticLabel: tr('staff.next'),
          onTap: () => _goWeek(7),
        ),
        Expanded(
          child: Text(
            '${dayMonth(ws)} – ${dayMonth(end)}',
            style: MadarType.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    // Draft only when the server says the week isn't published (H2-03);
    // nothing said about a week the phone doesn't hold.
    final status = held
        ? MadarStatusPill.of(
            pub ? tr('staff.published') : tr('staff.draft'),
            tone: pub ? MadarTone.success : MadarTone.warning,
            glyph: pub ? MadarGlyph.check : MadarGlyph.edit,
          )
        : null;
    final review = sugg.length + hols.length;
    final actions = <Widget>[
      if (!thisWeek)
        MadarChip(
          label: tr('staff.this_week'),
          onTap: () => setState(() {
            _week = weekStart(store.today);
            _day = null;
          }),
        ),
      if (held && !pub)
        MadarButton(
          label: tr('staff.publish_week'),
          glyph: MadarGlyph.check,
          size: MadarButtonSize.compact,
          onTap: () => _publish(branch, ws),
        ),
      MadarButton(
        label: tr('staff.coverage_needs'),
        glyph: MadarGlyph.users,
        size: MadarButtonSize.compact,
        variant: MadarButtonVariant.secondary,
        onTap: () => showDawamSheet<void>(
          context,
          title: tr('staff.coverage_needs'),
          builder: (ctx, ref, store) => CoverageSheet(branch: branch),
        ),
      ),
      // What needs a decision (holidays, suggestions) waits one tap away,
      // so the board keeps the room.
      MadarButton(
        label: review > 0
            ? '${tr('staff.suggestions')} · $review'
            : tr('staff.suggestions'),
        glyph: MadarGlyph.sparkle,
        size: MadarButtonSize.compact,
        variant: MadarButtonVariant.secondary,
        onTap: () => showDawamSheet<void>(
          context,
          title: tr('staff.to_review'),
          builder: (ctx, ref, store) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [
              for (final h in hols) _HolidayPrompt(h),
              _Suggestions(branch: branch),
              Text(
                tr('staff.limits_48_h_a_week_12'),
                style: MadarType.bodySm.copyWith(
                  color: ctx.madarColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
    final branches = [
      if (store.myBranches.length > 1)
        for (final b in store.myBranches)
          MadarChip(
            label: _branchName(store, b),
            selected: b == branch,
            onTap: () => setState(() => _pickedBranch = b),
          ),
    ];

    final bar = phone
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Row(
                spacing: Space.sm,
                children: [
                  Expanded(child: nav),
                  ?status,
                ],
              ),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [...branches, ...actions],
              ),
              MadarSegmented<bool>(
                items: [
                  MadarSegmentItem(false, tr('staff.view_week')),
                  MadarSegmentItem(true, tr('staff.view_day')),
                ],
                value: _dayView,
                onChanged: (v) => setState(() => _dayView = v),
              ),
            ],
          )
        : LayoutBuilder(
            // One row when it all fits; else the week's range keeps its
            // room and the actions wrap below it (E2E roster: on an iPad in
            // portrait the range was squeezed to nothing and overflowed).
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [
                if (box.maxWidth >= 1100)
                  Row(
                    spacing: Space.sm,
                    children: [
                      Expanded(child: nav),
                      ?status,
                      ...actions,
                    ],
                  )
                else ...[
                  Row(
                    spacing: Space.sm,
                    children: [
                      Expanded(child: nav),
                      ?status,
                    ],
                  ),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: actions,
                  ),
                ],
                if (branches.isNotEmpty) _Strip(branches),
              ],
            ),
          );

    final Widget body;
    if (phone && _dayView) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          _Strip([
            for (final (i, d) in heads.indexed)
              MadarChip(
                label: '${weekday(d.date.weekday)} ${d.date.day}',
                glyph: d.holiday != null ? MadarGlyph.flame : null,
                selected: i == day,
                onTap: () => setState(() => _day = i),
              ),
          ]),
          Expanded(
            child: RosterDayList(
              rows: rows,
              day: heads[day],
              cardsAt: cardsAt,
              onTapCard: _edit,
              onTapEmpty: _add,
            ),
          ),
        ],
      );
    } else {
      body = RosterBoard(
        rows: rows,
        days: heads,
        cardsAt: cardsAt,
        focus: focus,
        onTapCard: _edit,
        onTapEmpty: _add,
        onDrop: _drop,
      );
    }

    // The board takes the rest of the height, so the tab does not scroll
    // by itself: pullable, for the shell's pull to refresh.
    return MadarPullable(
      child: MadarContentFrame(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            top: Space.lg,
            bottom: Space.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              bar,
              if (away != null) NoticeBanner(text: away, tone: ChipTone.info),
              Expanded(child: body),
              if (!phone)
                Text(
                  tr('staff.roster_drag_hint'),
                  style: MadarType.bodySm.copyWith(color: c.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _goWeek(int days) {
    setState(() {
      _week = DateTime(_week.year, _week.month, _week.day + days);
      _day = null;
    });
    // A week past what the phone holds is fetched (H2-01).
    final ws = _week;
    unawaited(_store.viewRange(ws, DateTime(ws.year, ws.month, ws.day + 6)));
  }

  /// One board edit, waited for (H2-04): the server's words on a refusal
  /// (the sheet that asked stays open), [ok] once it is taken, then [done].
  Future<void> _save(
    Future<void> Function() call, {
    required String ok,
    VoidCallback? done,
  }) async {
    if (await attempt(ref, call, ok: ok)) done?.call();
  }

  Future<void> _publish(String branch, DateTime ws) async {
    final ok = await showMadarConfirm(
      context,
      title: tr('staff.publish_this_week'),
      body: tr('staff.staff_see_it_and_are_notified'),
      confirmLabel: tr('staff.publish'),
      cancelLabel: tr('staff.not_yet'),
    );
    if (ok) {
      await attempt(
        ref,
        () => _store.publish(branch, ws),
        ok: tr('staff.published'),
      );
    }
  }

  /// A drop: another day of the same row moves the shift, keeping its
  /// template; another row the same day gives it to that person (or opens
  /// it). Shifts follow templates (SC-1).
  void _drop(Shift s, String? emp, DateTime day) {
    if (s.emp == emp) {
      unawaited(
        attempt(
          ref,
          () => _store.moveShift(s, dateOnly(day), s.tpl),
          ok: tr('staff.moved_to', {'date': dayLabel(day)}),
        ),
      );
    } else {
      final to = emp == null ? null : _store.emps[emp];
      unawaited(
        _save(
          () => _store.assign(s, emp),
          ok: to == null
              ? tr('staff.open_shift_posted')
              : tr('staff.given_to', {'name': name(to)}),
        ),
      );
    }
  }

  /// One shift tapped: change THIS block (the rest of a split day stays),
  /// its own times, give it away, take it off, or put the date back on the
  /// usual pattern (SC-5, SC-11). An open shift can be taken back (SC-9).
  Future<void> _edit(Shift s) => showDawamSheet<void>(
    context,
    title: _who(_store, s.emp),
    builder: (ctx, ref, store) {
      final branch = _branch(store);
      final e = s.emp == null ? null : store.emps[s.emp];
      final warnings = e == null
          ? const <(String, Map<String, Object>)>[]
          : store.warnings(e.id, weekStart(s.date));
      final tpl = store.tpls[s.tpl];
      // Only the blocks worked on this weekday, at this day's times.
      final tpls = store.tpls.values
          .where((t) => t.branch == branch && t.validOn(s.date))
          .toList();
      void close() => Navigator.of(ctx).maybePop();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          MadarCard.column(
            spacing: 0,
            children: [
              MadarSummaryLine(label: tr('staff.day'), value: dayLabel(s.date)),
              if (tpl != null)
                MadarSummaryLine(label: tplName(tpl), value: _hours(s)),
            ],
          ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              if (s.edited)
                MadarTag(label: tr('staff.edited'), tone: MadarTone.accent),
              if (s.nextDay) MadarTag(label: tr('staff.ends_next_day')),
              if (s.changed)
                MadarTag(label: tr('staff.changed'), tone: MadarTone.warning),
            ],
          ),
          if (e != null && e.cantWork.contains(s.date.weekday))
            NoticeBanner(
              text: tr('staff.said_they_can_t_work_s', {
                'name': name(e),
                'day': weekday(s.date.weekday),
              }),
            ),
          for (final (key, args) in warnings) NoticeBanner(text: tr(key, args)),
          Text(
            tr('staff.changes_this_date_only_the_standing'),
            style: MadarType.bodySm.copyWith(color: ctx.madarColors.textMuted),
          ),
          if (e == null)
            MadarListRow.nav(
              glyph: MadarGlyph.close,
              title: tr('staff.cancel_open_shift'),
              onTap: () => _save(
                () => store.cancelOpen(s),
                ok: tr('staff.day_saved'),
                done: close,
              ),
            ),
          if (e != null)
            DawamSection(
              tr('staff.shift'),
              children: [
                for (final t in tpls)
                  MadarListRow.pick(
                    title: tplName(t),
                    meta: _blockHours(t, s.date),
                    selected: t.id == s.tpl,
                    onTap: () => t.id == s.tpl
                        ? close()
                        : _save(
                            () => store.moveShift(s, dateOnly(s.date), t.id),
                            ok: tr('staff.day_saved'),
                            done: close,
                          ),
                  ),
                MadarListRow.nav(
                  glyph: MadarGlyph.clock,
                  title: tr('staff.change_times'),
                  onTap: () async {
                    final a = await pickTime(ctx, s.start ?? s.template.start);
                    if (a == null || !ctx.mounted) return;
                    final z = await pickTime(ctx, s.end ?? s.template.end);
                    if (z == null || !ctx.mounted) return;
                    final ok = await attempt(
                      ref,
                      () => store.setTimes(s, a, z),
                      ok: tr('staff.times_saved'),
                    );
                    if (ok && ctx.mounted) close();
                  },
                ),
                if (s.edited)
                  MadarListRow.nav(
                    glyph: MadarGlyph.refresh,
                    title: tr('staff.block_times'),
                    onTap: () => _save(
                      () => store.setTimes(s, null, null),
                      ok: tr('staff.times_saved'),
                      done: close,
                    ),
                  ),
                MadarListRow.nav(
                  glyph: MadarGlyph.minus,
                  title: tr('staff.remove_this_shift'),
                  onTap: () => _save(
                    () => store.removeBlock(s),
                    ok: tr('staff.day_saved'),
                    done: close,
                  ),
                ),
                MadarListRow.nav(
                  glyph: MadarGlyph.close,
                  title: tr('staff.day_off'),
                  onTap: () => _save(
                    () => store.setDay(e.id, s.date, null, branch),
                    ok: tr('staff.day_saved'),
                    done: close,
                  ),
                ),
                if (s.ownDay || store.isOwnDay(e.id, s.date))
                  MadarListRow.nav(
                    glyph: MadarGlyph.calendar,
                    title: tr('staff.back_to_pattern'),
                    onTap: () => _save(
                      () => store.resetDay(e.id, s.date),
                      ok: tr('staff.day_saved'),
                      done: close,
                    ),
                  ),
              ],
            ),
          if (e != null)
            DawamSection(
              tr('staff.give_to'),
              children: [
                for (final p in _staff(
                  store,
                  branch,
                ).where((p) => p.id != s.emp))
                  MadarListRow.nav(
                    title: name(p),
                    meta: p.cantWork.contains(s.date.weekday)
                        ? tr('staff.said_they_can_t_work_s', {
                            'name': firstName(p),
                            'day': weekday(s.date.weekday),
                          })
                        : null,
                    onTap: () => _save(
                      () => store.giveShift(s, p.id),
                      ok: tr('staff.given_to', {'name': name(p)}),
                      done: close,
                    ),
                  ),
                MadarListRow.nav(
                  glyph: MadarGlyph.plus,
                  title: tr('staff.open_shift_anyone_claims'),
                  onTap: () => _save(
                    () => store.assign(s, null),
                    ok: tr('staff.open_shift_posted'),
                    done: close,
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );

  /// An empty day tapped: add a shift for that row's person, or post an
  /// open one from the open-shifts row.
  Future<void> _add(String? emp, DateTime at) async {
    final d = dateOnly(at);
    final branch = _branch(_store);
    // Never a day built from dates the phone doesn't hold (H2-01).
    final away = _store.notHeld(d, d);
    if (away != null) {
      ref.read(toastProvider.notifier).show(away, tone: ChipTone.danger);
      return;
    }
    // Only the blocks worked on this weekday, at this day's times.
    final tpls =
        _store.tpls.values
            .where((t) => t.branch == branch && t.validOn(d))
            .toList()
          ..sort((a, b) => a.timesOn(d).$1.compareTo(b.timesOn(d).$1));
    final first = tpls.firstOrNull;
    if (first == null) {
      ref
          .read(toastProvider.notifier)
          .show(tr('staff.no_shift_starts_then'), tone: ChipTone.danger);
      return;
    }
    var who = emp;
    var tpl = first.id;
    await showDawamSheet<void>(
      context,
      title: tr('staff.add_to', {'date': dayLabel(d)}),
      builder: (ctx, ref, store) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            // A day off by a date change: say so, and offer the pattern back.
            if (emp != null && store.isDayOff(emp, d)) ...[
              Wrap(
                children: [
                  MadarTag(
                    label: '${tr('staff.day_off')} · ${tr('staff.changed')}',
                    tone: MadarTone.warning,
                  ),
                ],
              ),
              MadarListRow.nav(
                glyph: MadarGlyph.calendar,
                title: tr('staff.back_to_pattern'),
                onTap: () => _save(
                  () => store.resetDay(emp, d),
                  ok: tr('staff.day_saved'),
                  done: () => Navigator.of(ctx).maybePop(),
                ),
              ),
            ],
            DawamSection(
              tr('staff.shift'),
              children: [
                for (final t in tpls)
                  MadarListRow.pick(
                    title: tplName(t),
                    meta: _blockHours(t, d),
                    selected: t.id == tpl,
                    onTap: () => setS(() => tpl = t.id),
                  ),
              ],
            ),
            DawamSection(
              tr('staff.who'),
              children: [
                MadarListRow.pick(
                  title: tr('staff.open_shift_anyone_claims'),
                  selected: who == null,
                  onTap: () => setS(() => who = null),
                ),
                for (final p in _staff(store, branch))
                  MadarListRow.pick(
                    title: name(p),
                    meta: p.cantWork.contains(d.weekday)
                        ? tr('staff.said_they_can_t_work_s', {
                            'name': firstName(p),
                            'day': weekday(d.weekday),
                          })
                        : null,
                    selected: who == p.id,
                    onTap: () => setS(() => who = p.id),
                  ),
              ],
            ),
            MadarButton(
              label: who == null
                  ? tr('staff.post_open_shift')
                  : tr('staff.add'),
              glyph: MadarGlyph.plus,
              // Waited for (H2-04, owner bug 1: the sheet closed at once and
              // a refusal, or nothing at all, followed).
              onTap: () {
                final id = who;
                unawaited(
                  _save(
                    () => id == null
                        ? store.postOpen(branch, d, tpl)
                        // Beside whatever else they work that day (a split day).
                        : store.addBlock(id, d, tpl),
                    ok: id == null
                        ? tr('staff.open_shift_posted')
                        : tr('staff.added'),
                    done: () => Navigator.of(ctx).maybePop(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of controls that scrolls sideways rather than wrap or overflow.
class _Strip extends StatelessWidget {
  const _Strip(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(spacing: Space.sm, children: children),
  );
}

/// Roster suggestions: each with its one-line reason and confidence; a
/// default-decided one says so (SC-13).
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.branch});

  final String branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final list = store.suggestions.where((g) => g.branch == branch).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        MadarSectionHeader(
          text: tr('staff.suggestions'),
          glyph: MadarGlyph.sparkle,
        ),
        if (list.isEmpty)
          MadarCard(
            child: Text(
              tr('staff.no_suggestions'),
              style: MadarType.bodySm.copyWith(color: c.textMuted),
            ),
          ),
        for (final g in list)
          MadarCard.column(
            spacing: Space.sm,
            children: [
              Row(
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: Text(dayLabel(g.date), style: MadarType.label),
                  ),
                  MadarStatusPill.of('${g.confidence}%'),
                ],
              ),
              Text(loc(g), style: MadarType.body),
              if (g.byDefault)
                MadarTag(
                  label: tr('staff.decided_by_the_default'),
                  tone: MadarTone.warning,
                ),
              Row(
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: MadarButton(
                      label: tr('staff.reject'),
                      size: MadarButtonSize.compact,
                      variant: MadarButtonVariant.secondary,
                      onTap: () =>
                          attempt(ref, () => store.rejectSuggestion(g)),
                    ),
                  ),
                  Expanded(
                    child: MadarButton(
                      label: tr('staff.accept'),
                      size: MadarButtonSize.compact,
                      glyph: MadarGlyph.check,
                      onTap: () =>
                          attempt(ref, () => store.acceptSuggestion(g)),
                    ),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _HolidayPrompt extends ConsumerWidget {
  const _HolidayPrompt(this.h);

  final Holiday h;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    return MadarCard.column(
      spacing: Space.sm,
      children: [
        Row(
          spacing: Space.sm,
          children: [
            MadarGlyphIcon(MadarGlyph.flame, color: c.warning),
            Expanded(
              child: Text(
                '${loc(h)} · ${dayLabel(h.date)}',
                style: MadarType.title,
              ),
            ),
          ],
        ),
        Text(
          tr('staff.make_it_a_holiday_nobody_is', {
            'holiday_mult': store.holidayMult,
          }),
          style: MadarType.bodySm.copyWith(color: c.textSecondary),
        ),
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: MadarButton(
                label: tr('staff.not_now'),
                size: MadarButtonSize.compact,
                variant: MadarButtonVariant.secondary,
                onTap: () =>
                    attempt(ref, () => store.decideHoliday(h, 'dismissed')),
              ),
            ),
            Expanded(
              child: MadarButton(
                label: tr('staff.set_as_holiday'),
                size: MadarButtonSize.compact,
                onTap: () =>
                    attempt(ref, () => store.decideHoliday(h, 'holiday')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
