/// The schedule's week grid (`dawam/schedule-page.tsx` table + `DayCell`,
/// `WarningChip`, `ScheduleLegend`; TEAM-SCH-016…025): a row per person and
/// the open shifts, Saturday → Friday, the name column pinned while the
/// days scroll sideways (a phone sees about three days at once).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ElsewhereShift, LabourWarning, OpenShift, RosterPerson, RosterShift, RosterView, WorkShiftBrief;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/team_format.dart';
import '../shared/week.dart';
import 'schedule_data.dart';
import 'schedule_providers.dart';

abstract final class ScheduleMetrics {
  /// The name column (`max-w-[12rem]`); narrower on a phone.
  static const double name = 192;
  static const double namePhone = 168;

  /// A day column at its narrowest (`min-w-[56rem]` less the names, / 7).
  static const double day = 100;
  static const double dayPhone = 108;

  /// A day cell's least height (`min-h-9`).
  static const double cell = 36;

  /// The roster skeleton (`h-72`).
  static const double skeleton = Space.xxl * 9;

  /// The tiny marks in a cell (`text-[10px]`, `text-[11px]`).
  static const double tiny = 10;
  static const double mini = 11;
}

/// A shift's times "HH:MM–HH:MM" (LTR), with the "+1" moon when it ends the
/// next day (`ShiftTimes`).
class ShiftTimes extends StatelessWidget {
  const ShiftTimes({
    required this.start,
    required this.end,
    required this.crossesMidnight,
    this.compact = false,
    super.key,
  });

  final String start;
  final String end;
  final bool crossesMidnight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.xs,
      children: [
        Text(
          ltr('${hhmm(start)}–${hhmm(end)}'),
          maxLines: 1,
          softWrap: false,
          style: DashType.mono.copyWith(
            fontSize: ScheduleMetrics.mini,
            color: c.textSecondary,
          ),
        ),
        if (crossesMidnight) NextDayMark(compact: compact),
      ],
    );
  }
}

/// "+1 day": the shift ends the next day, visible and read out, never a bare
/// "+1" (`NextDayMark`); `compact` in a grid cell, where the legend says it.
class NextDayMark extends ConsumerWidget {
  const NextDayMark({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final style = DashType.smallStrong.copyWith(
      fontSize: ScheduleMetrics.tiny,
      color: c.textPrimary,
    );
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DashMetrics.hair,
      children: [
        DashIcon('moon', size: ScheduleMetrics.tiny, color: c.textPrimary),
        Text(compact ? '+1' : t('dawamOps.plusOneDay'), style: style),
      ],
    );
    return Tooltip(
      message: t('staff.endsNextDay'),
      child: Semantics(
        label: t('staff.endsNextDay'),
        excludeSemantics: true,
        child: compact
            ? mark
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(Radii.xs / 2),
                ),
                child: mark,
              ),
      ),
    );
  }
}

/// The dot a shift changed after publishing carries (`role="img"`).
class ChangedDot extends ConsumerWidget {
  const ChangedDot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(tProvider)('dawam.changedAfterPublish');
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        image: true,
        child: Container(
          width: Space.xs + DashMetrics.hair,
          height: Space.xs + DashMetrics.hair,
          decoration: BoxDecoration(
            color: context.madarColors.textPrimary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// The label of a labour limit (`dawam.warn_<kind>`, else the kind).
String warningLabel(Translator t, String kind) =>
    t.exists('dawam.warn_$kind') ? t('dawam.warn_$kind') : kind;

/// One labour-limit warning as a chip: which limit, and by how much
/// (`WarningChip`).
class WarningChip extends ConsumerWidget {
  const WarningChip(this.warning, {super.key});

  final LabourWarning warning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = t.lang;
    final c = context.madarColors;
    final label = warningLabel(t, warning.kind);
    final detail =
        '${fmtHours(lang, warning.minutes)} / '
        '${fmtHours(lang, warning.limitMinutes)}';
    final fg = DashTone.warning.foreground(c);
    return Tooltip(
      message: '$label: $detail',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs + 2),
        decoration: BoxDecoration(
          color: DashTone.warning.wash(c),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: DashMetrics.hair,
          children: [
            DashIcon('triangle-alert', size: Space.md, color: fg),
            Flexible(
              child: Text(
                label,
                style: DashType.smallMedium.copyWith(
                  fontSize: ScheduleMetrics.tiny,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The grid: a row per person, then the open shifts, then the legend.
class ScheduleGrid extends ConsumerStatefulWidget {
  const ScheduleGrid({
    required this.view,
    required this.index,
    required this.days,
    required this.today,
    required this.branchId,
    required this.branchNames,
    required this.canEdit,
    required this.busy,
    required this.onOpenDay,
    required this.onPrefs,
    required this.onCancelOpen,
    required this.onPostOpen,
    super.key,
  });

  final RosterView view;
  final RosterIndex index;
  final List<String> days;
  final String today;
  final String branchId;
  final Map<String, String> branchNames;
  final bool canEdit;

  /// The page's action in flight (`open|<id>` disables that take-back).
  final String? busy;
  final void Function(RosterPerson person, String date) onOpenDay;
  final void Function(RosterPerson person) onPrefs;
  final void Function(OpenShift open) onCancelOpen;
  final void Function(String date, WorkShiftBrief block) onPostOpen;

  @override
  ConsumerState<ScheduleGrid> createState() => _ScheduleGridState();
}

class _ScheduleGridState extends ConsumerState<ScheduleGrid> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final w = widget;

    return LayoutBuilder(
      builder: (context, box) {
        final nameW = phone ? ScheduleMetrics.namePhone : ScheduleMetrics.name;
        final minDay = phone ? ScheduleMetrics.dayPhone : ScheduleMetrics.day;
        final fit = (box.maxWidth - nameW) / 7;
        final dayW = fit > minDay ? fit : minDay;
        final width = nameW + dayW * 7;
        final edge = BorderSide(color: c.hairline);

        // The name cell stays put while the days scroll: it is laid out
        // first but painted (and hit) last, moved back by the scroll.
        Widget pinned(Widget child) => AnimatedBuilder(
          animation: _scroll,
          builder: (context, child) {
            final dx = _scroll.hasClients ? _scroll.offset : 0.0;
            return Transform.translate(
              offset: Offset(rtl ? -dx : dx, 0),
              child: child,
            );
          },
          child: child,
        );

        // One table: a row is as tall as its tallest day; the name cell
        // fills it. Laid out in the opposite direction with the children
        // reversed, so the name still sits at the start and is painted (and
        // hit) over the days it is pinned above.
        TableRow row(Widget name, List<Widget> cells, {bool header = false}) =>
            TableRow(
              decoration: BoxDecoration(
                border: Border(
                  top: header ? BorderSide.none : edge,
                  bottom: header ? edge : BorderSide.none,
                ),
              ),
              children: [
                ...cells.reversed,
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.fill,
                  child: pinned(name),
                ),
              ],
            );

        Widget nameBox(Widget child, {bool header = false}) => Container(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: phone ? Space.sm : Space.lg,
            vertical: header ? Space.sm + 2 : Space.xs + 2,
          ),
          decoration: BoxDecoration(
            color: c.card,
            border: BorderDirectional(end: edge),
          ),
          alignment: AlignmentDirectional.centerStart,
          child: child,
        );

        final header = row(
          nameBox(
            Text(
              t('staff.employee'),
              style: DashType.smallStrong.copyWith(color: c.textSecondary),
            ),
            header: true,
          ),
          [
            for (final d in w.days)
              _HeaderCell(
                weekday: weekdayName(weekdayOf(d), t.lang),
                date: f.fmtDate(d),
                today: d == w.today,
                todayLabel: t('dawamOps.today'),
              ),
          ],
          header: true,
        );

        final people = [
          for (final p in w.view.staff)
            row(
              nameBox(_NameCell(person: p, onPrefs: () => w.onPrefs(p))),
              [
                for (final d in w.days)
                  _DayCell(
                    person: p,
                    date: d,
                    minHeight: _NameCell.heightOf(p),
                    branchId: w.branchId,
                    branchNames: w.branchNames,
                    shifts: w.index.shiftsOf(p.employeeId, d),
                    elsewhere: w.index.elsewhereOf(p.employeeId, d),
                    warnings: w.index.warningsOf(p.employeeId, d),
                    dayOff: w.index.dateSets[cellKey(p.employeeId, d)] == true,
                    editable: w.canEdit,
                    onOpen: () => w.onOpenDay(p, d),
                  ),
              ],
            ),
        ];

        final open = row(
          nameBox(
            Text(
              t('dawam.openShifts'),
              style: DashType.smallStrong.copyWith(color: c.textSecondary),
            ),
          ),
          [
            for (final d in w.days)
              _OpenShiftsCell(
                date: d,
                open: [
                  for (final o in w.view.openShifts)
                    if (o.onDate == d) o,
                ],
                blocks: blocksOn(w.index.templates, weekdayOf(d)),
                canEdit: w.canEdit,
                busy: w.busy,
                onCancel: w.onCancelOpen,
                onPost: (b) => w.onPostOpen(d, b),
              ),
          ],
        );

        final todayAt = w.days.indexOf(w.today);
        final table = SizedBox(
          width: width,
          child: Stack(
            children: [
              // Today's column, under the cells (`bg-primary/[0.04]`).
              if (todayAt >= 0)
                PositionedDirectional(
                  top: 0,
                  bottom: 0,
                  start: nameW + todayAt * dayW,
                  width: dayW,
                  child: ColoredBox(color: c.accent.withValues(alpha: 0.04)),
                ),
              Table(
                textDirection: rtl ? TextDirection.ltr : TextDirection.rtl,
                columnWidths: {
                  for (var i = 0; i < 7; i++) i: FixedColumnWidth(dayW),
                  7: FixedColumnWidth(nameW),
                },
                children: [header, ...people, open],
              ),
            ],
          ),
        );

        return Container(
          key: const Key('schedule-grid'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: c.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: table,
                ),
              ),
              const ScheduleLegend(),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.weekday,
    required this.date,
    required this.today,
    required this.todayLabel,
  });

  final String weekday;
  final String date;
  final bool today;
  final String todayLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = today ? c.textPrimary : c.textSecondary;
    return Semantics(
      container: true,
      selected: today,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.xs,
          vertical: Space.sm + 2,
        ),
        decoration: BoxDecoration(
          color: today ? c.accent.withValues(alpha: 0.02) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(weekday, style: DashType.smallStrong.copyWith(color: fg)),
            Text(
              date,
              maxLines: 1,
              softWrap: false,
              style: DashType.small.copyWith(color: fg),
            ),
            if (today)
              Text(
                todayLabel,
                style: DashType.smallStrong.copyWith(
                  fontSize: ScheduleMetrics.mini,
                  color: c.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NameCell extends ConsumerWidget {
  const _NameCell({required this.person, required this.onPrefs});

  /// The row's least height: the padding, the name beside its 44 pt
  /// preferences button, and the preferences line when there is one.
  static double heightOf(RosterPerson p) =>
      (Space.xs + 2) * 2 +
      DashMetrics.target +
      (_hasPrefs(p) ? Space.lg + 2 : 0);

  /// The web shows the line only with a preferred time or days off; "set by
  /// a manager" rides on it.
  static bool _hasPrefs(RosterPerson p) =>
      p.prefTime != null || p.cantWorkDays.isNotEmpty;

  final RosterPerson person;
  final VoidCallback onPrefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final p = person;
    final days = p.cantWorkDays
        .map((d) => d >= 0 && d < 7 ? t(weekdayKeys[d]) : '')
        .join(', ');
    final prefs = [
      if (p.prefTime == 'morning' || p.prefTime == 'evening')
        t('dawam.prefers_${p.prefTime}'),
      if (p.cantWorkDays.isNotEmpty) t('dawam.cantWork', args: {'days': days}),
      if (p.prefsSetBy == 'manager') t('dawam.setByManager'),
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: Space.xs,
          children: [
            Flexible(
              child: MadarClippedText(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ),
            DashIconButton(
              icon: 'sliders-horizontal',
              iconSize: IconSize.xs,
              semanticLabel: t('dawam.prefsOf', args: {'name': p.name}),
              onIntent: () =>
                  ref.warm(schedulePreferenceLogProvider(p.employeeId)),
              onPressed: onPrefs,
            ),
          ],
        ),
        if (_hasPrefs(p))
          MadarClippedText(
            prefs,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.person,
    required this.date,
    required this.minHeight,
    required this.branchId,
    required this.branchNames,
    required this.shifts,
    required this.elsewhere,
    required this.warnings,
    required this.dayOff,
    required this.editable,
    required this.onOpen,
  });

  final RosterPerson person;
  final String date;

  /// At least the name cell's height (the row's least height).
  final double minHeight;

  /// The board's branch: a shift elsewhere says where.
  final String branchId;
  final Map<String, String> branchNames;
  final List<RosterShift> shifts;

  /// Their shifts at other branches that date: shown, never edited here.
  final List<ElsewhereShift> elsewhere;
  final List<LabourWarning> warnings;

  /// A day off set by a date change (not a rest day in the pattern).
  final bool dayOff;
  final bool editable;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final tiny = DashType.smallMedium.copyWith(
      fontSize: ScheduleMetrics.tiny,
      color: c.textSecondary,
    );

    Widget at(String branch) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DashMetrics.hair,
      children: [
        DashIcon('map-pin', size: Space.md, color: c.textSecondary),
        Flexible(
          child: Text(
            t('dawamOps.atBranch', args: {'branch': branch}),
            textAlign: TextAlign.center,
            style: tiny,
          ),
        ),
      ],
    );
    String branchOf(String id, [String? name]) => name != null && name.isNotEmpty
        ? name
        : branchNames[id] ?? t('dawamOps.otherBranch');

    final body = <Widget>[
      if (shifts.isEmpty)
        if (dayOff)
          Text(
            t('dawam.dayOffSet'),
            style: DashType.smallMedium.copyWith(color: c.textPrimary),
          )
        else if (elsewhere.isEmpty)
          Text(t('dawam.off'), style: DashType.small.copyWith(color: c.textSecondary)),
      for (final s in shifts)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                Flexible(
                  child: Text(
                    s.shiftName,
                    textAlign: TextAlign.center,
                    style: s.onLeave
                        ? DashType.small.copyWith(
                            color: c.textSecondary,
                            decoration: TextDecoration.lineThrough,
                          )
                        : DashType.smallMedium.copyWith(color: c.textPrimary),
                  ),
                ),
                if (s.changed) const ChangedDot(),
              ],
            ),
            if (s.onLeave) Text(t('dawamOps.onLeave'), style: tiny),
            if (s.branchId != branchId) at(branchOf(s.branchId)),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Space.xs,
              children: [
                ShiftTimes(
                  start: s.startTime,
                  end: s.endTime,
                  crossesMidnight: s.crossesMidnight,
                  compact: true,
                ),
                if (s.timesEdited)
                  Text(
                    t('dawam.edited'),
                    style: tiny.copyWith(color: c.accent),
                  ),
              ],
            ),
          ],
        ),
      for (final s in elsewhere)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.shiftName,
              textAlign: TextAlign.center,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
            at(branchOf(s.branchId, s.branchName)),
            ShiftTimes(
              start: s.startTime,
              end: s.endTime,
              crossesMidnight: s.crossesMidnight,
              compact: true,
            ),
          ],
        ),
      for (final w in warnings) WarningChip(w),
    ];

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight - Space.xs * 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: DashMetrics.hair,
        children: body,
      ),
    );

    final cell = Padding(
      padding: const EdgeInsets.all(Space.xs),
      child: editable
          ? DashPressable(
              onTap: onOpen,
              semanticLabel: t(
                'dawam.editDay',
                args: {'name': person.name, 'date': f.fmtDate(date)},
              ),
              excludeChildSemantics: true,
              pressScale: false,
              builder: (context, s) => Container(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                decoration: BoxDecoration(
                  color: s.highlighted ? c.hover : null,
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(
                    color: s.highlighted ? c.hairline : Colors.transparent,
                  ),
                ),
                foregroundDecoration: dashFocusRing(
                  context,
                  s,
                  BorderRadius.circular(Radii.xs),
                ),
                child: content,
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: content,
            ),
    );
    return cell;
  }
}

class _OpenShiftsCell extends ConsumerWidget {
  const _OpenShiftsCell({
    required this.date,
    required this.open,
    required this.blocks,
    required this.canEdit,
    required this.busy,
    required this.onCancel,
    required this.onPost,
  });

  final String date;
  final List<OpenShift> open;

  /// The blocks that run that weekday.
  final List<WorkShiftBrief> blocks;
  final bool canEdit;
  final String? busy;
  final ValueChanged<OpenShift> onCancel;
  final ValueChanged<WorkShiftBrief> onPost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final weekday = weekdayOf(date);
    return Padding(
      padding: const EdgeInsets.all(Space.xs),
      child: Column(
        spacing: Space.xs,
        children: [
          for (final o in open)
            Container(
              padding: EdgeInsetsDirectional.only(
                start: Space.sm,
                end: canEdit ? 0 : Space.sm,
              ),
              decoration: BoxDecoration(
                color: o.status == 'claimed' ? c.muted : null,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: o.status == 'claimed' ? Colors.transparent : c.hairline,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      o.claimedByName == null
                          ? o.shiftName
                          : '${o.shiftName} · ${o.claimedByName}',
                      style: DashType.smallMedium.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  if (canEdit)
                    DashIconButton(
                      icon: 'x',
                      iconSize: IconSize.xs,
                      semanticLabel: t(
                        'dawam.cancelOpenOf',
                        args: {'shift': o.shiftName, 'date': f.fmtDate(o.onDate)},
                      ),
                      onPressed: busy == 'open|${o.id}'
                          ? null
                          : () => onCancel(o),
                    ),
                ],
              ),
            ),
          if (canEdit)
            DashMenu(
              align: DashPopoverAlign.start,
              items: [
                DashMenuItem(label: t('dawam.postOpen'), enabled: false),
                if (blocks.isEmpty)
                  DashMenuItem(label: t('dawam.noShiftThatDay'), enabled: false),
                for (final b in blocks)
                  () {
                    final at = blockTimesOn(b, weekday);
                    return DashMenuItem(
                      label: b.name,
                      hint: ltr('${at.start}–${at.end}'),
                      onSelected: () => onPost(b),
                    );
                  }(),
              ],
              builder: (context, menu) => DashIconButton(
                icon: 'calendar-plus',
                semanticLabel: t(
                  'dawam.postOpenOn',
                  args: {'date': f.fmtDate(date)},
                ),
                onPressed: menu.toggle,
              ),
            ),
        ],
      ),
    );
  }
}

/// What the marks in a day cell mean, said once under the grid
/// (`ScheduleLegend`, TEAM-SCH-022).
class ScheduleLegend extends ConsumerWidget {
  const ScheduleLegend({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final small = DashType.small.copyWith(color: c.textSecondary);
    Widget item(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + 2,
      children: [mark, Text(text, style: small)],
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm + 2,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: Wrap(
        spacing: Space.xl - Space.xs,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          item(
            DashIcon('info', size: IconSize.xs, color: c.textPrimary),
            t('dawamOps.legend'),
          ),
          item(Text(t('dawam.off'), style: small), t('dawamOps.legendOff')),
          item(
            Text(
              t('dawam.dayOffSet'),
              style: DashType.smallMedium.copyWith(color: c.textPrimary),
            ),
            t('dawamOps.legendDayOff'),
          ),
          item(const NextDayMark(compact: true), t('staff.endsNextDay')),
          item(
            Text(
              t('dawam.edited'),
              style: DashType.smallMedium.copyWith(color: c.accent),
            ),
            t('dawamOps.legendEdited'),
          ),
          item(
            ExcludeSemantics(
              child: Container(
                width: Space.xs + DashMetrics.hair,
                height: Space.xs + DashMetrics.hair,
                decoration: BoxDecoration(
                  color: c.textPrimary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            t('dawam.changedAfterPublish'),
          ),
          item(
            DashIcon(
              'triangle-alert',
              size: IconSize.xs,
              color: DashTone.warning.foreground(c),
            ),
            t('dawamOps.legendWarning'),
          ),
        ],
      ),
    );
  }
}
