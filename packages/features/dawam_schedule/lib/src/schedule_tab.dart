import 'package:design_system/design_system.dart';
import 'package:feature_dawam_schedule/src/shift_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// The manager's roster on a calendar: drag a shift to another day or
/// start, tap it to change or reassign, tap an empty slot to add (SC-5,
/// SC-7); publish the week (SC-3); accept or reject suggestions (SC-13);
/// set up holidays (RU-10). Limits warn, never block (RU-13).
class ScheduleTab extends ConsumerStatefulWidget {
  const ScheduleTab({super.key});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<ScheduleTab> {
  late String _branch = ref.read(dawamProvider).myBranches.first;
  late DateTime _visible = ref.read(dawamProvider).today;
  String? _person;

  DawamStore get _store => ref.read(dawamProvider);

  List<Emp> _staff(DawamStore store) =>
      store.emps.values
          .where((e) => e.branches.contains(_branch) && e.role != Role.owner)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  Color _colorOf(DawamStore store, Shift s, MadarColors c) {
    if (s.emp == null) return c.warning;
    final i = _staff(store).indexWhere((e) => e.id == s.emp);
    return c.series[(i < 0 ? 0 : i) % c.series.length];
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final ws = weekStart(_visible);
    final pub = store.published.contains('$_branch|$ws');
    final sugg = store.suggestions.where((g) => g.branch == _branch).toList();
    final hols = store.holidays
        .where(
          (h) =>
              h.decision == null &&
              h.date.isAfter(store.today) &&
              h.date.difference(store.today).inDays < 30,
        )
        .toList();
    final shifts = store.shifts
        .where(
          (s) =>
              s.template.branch == _branch &&
              (_person == null || s.emp == _person || s.emp == null),
        )
        .toList();
    final phone = MadarLayout.of(context).isPhone;

    final bar = Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (store.myBranches.length > 1)
          for (final b in store.myBranches)
            MadarChip(
              label: branchName(store, b),
              selected: b == _branch,
              onTap: () => setState(() {
                _branch = b;
                _person = null;
              }),
            ),
        MadarStatusPill.of(
          '${pub ? tr('staff.published') : tr('staff.draft')} · '
          '${dayMonth(ws)} – ${dayMonth(ws.add(const Duration(days: 6)))}',
          tone: pub ? MadarTone.success : MadarTone.warning,
          glyph: pub ? MadarGlyph.check : MadarGlyph.edit,
        ),
        if (!pub)
          MadarButton(
            label: tr('staff.publish_week'),
            glyph: MadarGlyph.check,
            size: MadarButtonSize.compact,
            onTap: () => _publish(ws),
          ),
        // On a phone the calendar keeps the height; what needs a decision
        // (holidays, suggestions) waits one tap away.
        if (phone && sugg.length + hols.length > 0)
          MadarButton(
            label: '${tr('staff.to_review')} · ${sugg.length + hols.length}',
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
                  _Suggestions(branch: _branch),
                ],
              ),
            ),
          ),
      ],
    );

    final calendar = ShiftCalendar(
      shifts: shifts,
      now: () => _store.now,
      editable: true,
      phoneView: CalendarView.day,
      tabletView: CalendarView.threeDays,
      colorOf: (s) => _colorOf(store, s, c),
      titleOf: (s) =>
          s.emp == null ? tr('staff.open_shift') : firstName(store.emp(s.emp!)),
      onTapShift: _edit,
      onMove: _move,
      onTapSlot: _add,
      onRangeChanged: (d) => setState(() => _visible = d),
      trailing: _PersonFilter(
        people: _staff(store),
        value: _person,
        colorOf: (e) => c.series[_staff(store).indexOf(e) % c.series.length],
        onChanged: (v) => setState(() => _person = v),
      ),
    );

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        bar,
        Expanded(child: calendar),
      ],
    );

    return MadarContentFrame(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          top: Space.lg,
          bottom: Space.lg,
        ),
        child: phone
            ? main
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xl,
                children: [
                  Expanded(child: main),
                  SizedBox(
                    width: 320,
                    child: ListView(
                      children: [
                        for (final h in hols) ...[
                          _HolidayPrompt(h),
                          const SizedBox(height: Space.lg),
                        ],
                        _Suggestions(branch: _branch),
                        const SizedBox(height: Space.xl),
                        Text(
                          tr('staff.limits_48_h_a_week_12'),
                          style: MadarType.bodySm.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _publish(DateTime ws) async {
    final ok = await showMadarConfirm(
      context,
      title: tr('staff.publish_this_week'),
      body: tr('staff.staff_see_it_and_are_notified'),
      confirmLabel: tr('staff.publish'),
      cancelLabel: tr('staff.not_yet'),
    );
    if (ok) {
      _store.publish(_branch, ws);
      ref
          .read(toastProvider.notifier)
          .show(tr('staff.published'), tone: ChipTone.success);
    }
  }

  /// A drop: another day keeps the template; another start picks the
  /// branch template that begins then. Shifts follow templates (SC-1).
  void _move(Shift s, DateTime start) {
    final minute = start.hour * 60 + start.minute;
    final tpl = minute == s.template.start
        ? s.template
        : _store.tpls.values
              .where((t) => t.branch == _branch && t.start == minute)
              .firstOrNull;
    if (tpl == null) {
      ref
          .read(toastProvider.notifier)
          .show(tr('staff.no_shift_starts_then'), tone: ChipTone.danger);
      return;
    }
    _store.moveShift(s, dateOnly(start), tpl.id);
    ref
        .read(toastProvider.notifier)
        .show(
          tr('staff.moved_to', {'date': dayLabel(start)}),
          tone: ChipTone.success,
        );
  }

  Future<void> _edit(Shift s) => showDawamSheet<void>(
    context,
    title: s.emp == null ? tr('staff.open_shift') : name(_store.emp(s.emp!)),
    builder: (ctx, ref, store) {
      final e = s.emp == null ? null : store.emp(s.emp!);
      final warnings = e == null
          ? const <(String, Map<String, Object>)>[]
          : store.warnings(e.id, weekStart(s.date));
      final tpls = store.tpls.values.where((t) => t.branch == _branch);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          MadarCard.column(
            spacing: 0,
            children: [
              MadarSummaryLine(label: tr('staff.day'), value: dayLabel(s.date)),
              MadarSummaryLine(
                label: tplName(s.template),
                value: shiftWindow(s),
              ),
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
          if (e != null)
            DawamSection(
              tr('staff.shift'),
              children: [
                for (final t in tpls)
                  MadarListRow.pick(
                    title: tplName(t),
                    meta: '${hmMin(t.start)} – ${hmMin(t.end)}',
                    selected: t.id == s.tpl,
                    onTap: () {
                      store.setDay(e.id, s.date, t.id, _branch);
                      Navigator.of(ctx).maybePop();
                    },
                  ),
                MadarListRow.nav(
                  glyph: MadarGlyph.close,
                  title: tr('staff.day_off'),
                  onTap: () {
                    store.setDay(e.id, s.date, null, _branch);
                    Navigator.of(ctx).maybePop();
                  },
                ),
              ],
            ),
          DawamSection(
            tr('staff.give_to'),
            children: [
              for (final p in _staff(store).where((p) => p.id != s.emp))
                MadarListRow.nav(
                  title: name(p),
                  meta: p.cantWork.contains(s.date.weekday)
                      ? tr('staff.said_they_can_t_work_s', {
                          'name': firstName(p),
                          'day': weekday(s.date.weekday),
                        })
                      : null,
                  onTap: () {
                    store.assign(s, p.id);
                    Navigator.of(ctx).maybePop();
                  },
                ),
              if (s.emp != null)
                MadarListRow.nav(
                  glyph: MadarGlyph.plus,
                  title: tr('staff.open_shift_anyone_claims'),
                  onTap: () {
                    store.assign(s, null);
                    Navigator.of(ctx).maybePop();
                  },
                ),
            ],
          ),
        ],
      );
    },
  );

  Future<void> _add(DateTime at) {
    final d = dateOnly(at);
    final minute = at.hour * 60 + at.minute;
    final tpls = _store.tpls.values.where((t) => t.branch == _branch).toList()
      ..sort(
        (a, b) => (a.start - minute).abs().compareTo((b.start - minute).abs()),
      );
    String? who;
    var tpl = tpls.first.id;
    return showDawamSheet<void>(
      context,
      title: tr('staff.add_to', {'date': dayLabel(d)}),
      builder: (ctx, ref, store) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            DawamSection(
              tr('staff.shift'),
              children: [
                for (final t in tpls)
                  MadarListRow.pick(
                    title: tplName(t),
                    meta: '${hmMin(t.start)} – ${hmMin(t.end)}',
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
                for (final p in _staff(store))
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
              onTap: () {
                if (who == null) {
                  store.postOpen(_branch, d, tpl);
                } else {
                  store.setDay(who!, d, tpl, _branch);
                }
                Navigator.of(ctx).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Filter the calendar to one person (open shifts stay visible).
class _PersonFilter extends StatelessWidget {
  const _PersonFilter({
    required this.people,
    required this.value,
    required this.colorOf,
    required this.onChanged,
  });

  final List<Emp> people;
  final String? value;
  final Color Function(Emp) colorOf;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tr('staff.filter_people'),
    onSelected: (v) => onChanged(v.isEmpty ? null : v),
    itemBuilder: (_) => [
      PopupMenuItem(value: '', child: Text(tr('staff.everyone'))),
      for (final e in people)
        PopupMenuItem(
          value: e.id,
          child: Row(
            spacing: Space.sm,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colorOf(e),
                  shape: BoxShape.circle,
                ),
              ),
              Text(name(e)),
            ],
          ),
        ),
    ],
    child: IgnorePointer(
      child: MadarChip(
        label: value == null
            ? tr('staff.everyone')
            : firstName(people.firstWhere((e) => e.id == value)),
        glyph: MadarGlyph.users,
        selected: value != null,
        onTap: () {},
      ),
    ),
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
                      onTap: () => store.rejectSuggestion(g),
                    ),
                  ),
                  Expanded(
                    child: MadarButton(
                      label: tr('staff.accept'),
                      size: MadarButtonSize.compact,
                      glyph: MadarGlyph.check,
                      onTap: () => store.acceptSuggestion(g),
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
                onTap: () => store.decideHoliday(h, 'dismissed'),
              ),
            ),
            Expanded(
              child: MadarButton(
                label: tr('staff.set_as_holiday'),
                size: MadarButtonSize.compact,
                onTap: () => store.decideHoliday(h, 'holiday'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
