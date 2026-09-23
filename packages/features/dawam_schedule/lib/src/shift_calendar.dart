import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:kalender/kalender.dart';
import 'package:staff_core/staff_core.dart';

/// A roster shift on the calendar. The fields the tile shows are copied in,
/// so a reassignment or template change reads as a new event (the calendar
/// rebuilds a tile only when its event changes).
/// Shifts are the branch's wall-clock times (AT-1): the core writes every
/// time in the branch's zone and the app keeps its wall fields as they are.
/// The calendar hands them back as the same wall fields, so they are copied
/// field by field — never converted through the phone's zone.
DateTime _wall(DateTime d) =>
    DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second);

class ShiftEvent extends KalenderEvent {
  ShiftEvent({
    required this.shift,
    required super.start,
    required super.end,
    super.interaction,
  }) : emp = shift.emp,
       tpl = shift.tpl,
       changed = shift.changed,
       super(id: shift.id);

  ShiftEvent.of(Shift s, {EventInteraction? interaction})
    : this(shift: s, start: s.startAt, end: s.endAt, interaction: interaction);

  final Shift shift;
  final String? emp;
  final String tpl;
  final bool changed;

  @override
  ShiftEvent copyWithData({required DateTime start, required DateTime end}) =>
      carryOver(ShiftEvent(shift: shift, start: start, end: end));

  @override
  // kalender compares events by value to decide which tiles to rebuild and
  // asks subclasses to extend it; KalenderEvent itself is not @immutable.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      other is ShiftEvent &&
      super == other &&
      other.emp == emp &&
      other.tpl == tpl &&
      other.changed == changed;

  @override
  // Pairs with == above.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(super.hashCode, emp, tpl, changed);
}

/// The calendar's views, named in the core's words.
enum CalendarView { day, threeDays, week, month, list }

/// Dawam's calendar: kalender in Madar's clothes. Day, 3-day, week, month
/// and list views; the week starts on Saturday; figures are Latin in both
/// languages (APP-4); each person keeps one colour from the kit's series.
/// With [editable], shifts drag to another day or time (SC-7).
class ShiftCalendar extends StatefulWidget {
  const ShiftCalendar({
    required this.shifts,
    required this.now,
    required this.colorOf,
    required this.titleOf,
    this.onTapShift,
    this.onMove,
    this.onTapSlot,
    this.onRangeChanged,
    this.editable = false,
    this.phoneView = CalendarView.threeDays,
    this.tabletView = CalendarView.week,
    this.trailing,
    super.key,
  });

  final List<Shift> shifts;
  final DateTime Function() now;
  final Color Function(Shift) colorOf;
  final String Function(Shift) titleOf;
  final void Function(Shift)? onTapShift;
  final void Function(Shift, DateTime start)? onMove;
  final void Function(DateTime)? onTapSlot;
  final void Function(DateTime start)? onRangeChanged;
  final bool editable;
  final CalendarView phoneView;
  final CalendarView tabletView;

  /// Extra controls at the toolbar's end (a filter, a legend button).
  final Widget? trailing;

  @override
  State<ShiftCalendar> createState() => _ShiftCalendarState();
}

class _ShiftCalendarState extends State<ShiftCalendar> {
  final _events = DefaultEventsController();
  final _controller = KalenderController();
  late final Map<CalendarView, ViewConfiguration> _views;
  CalendarView? _view;
  String _signature = '';
  KalenderDateTimeRange? _range;

  // A tear-off is stable across builds; the calendar compares its
  // configurations by value.
  DateTime _now() => widget.now();

  @override
  void initState() {
    super.initState();
    final start = widget.now();
    final hours = KalenderTimeRange.allDay();
    const at = KalenderTime(hour: 7, minute: 0);
    _views = {
      CalendarView.day: MultiDayViewConfiguration.singleDay(
        initialDateTime: start,
        nowCallback: _now,
        timeOfDayRange: hours,
        initialTimeOfDay: at,
        firstDayOfWeek: DateTime.saturday,
      ),
      CalendarView.threeDays: MultiDayViewConfiguration.custom(
        name: '3',
        numberOfDays: 3,
        initialDateTime: start,
        nowCallback: _now,
        timeOfDayRange: hours,
        initialTimeOfDay: at,
        firstDayOfWeek: DateTime.saturday,
      ),
      CalendarView.week: MultiDayViewConfiguration.week(
        initialDateTime: start,
        nowCallback: _now,
        timeOfDayRange: hours,
        initialTimeOfDay: at,
        firstDayOfWeek: DateTime.saturday,
      ),
      CalendarView.month: MonthViewConfiguration.singleMonth(
        initialDateTime: start,
        nowCallback: _now,
        firstDayOfWeek: DateTime.saturday,
      ),
      CalendarView.list: ScheduleViewConfiguration.continuous(
        initialDateTime: start,
        nowCallback: _now,
      ),
    };
    _sync();
    // The calendar sets its visible range while it builds; take it after
    // the frame so the toolbar never rebuilds mid-build.
    _controller.visibleDateTimeRange.addListener(() {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _range = _controller.visibleDateTimeRange.value);
        }
      });
    });
  }

  @override
  void didUpdateWidget(ShiftCalendar old) {
    super.didUpdateWidget(old);
    // Replace the events after this frame: the calendar listens to its
    // controller and must not be told to rebuild mid-build.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    final sig = widget.shifts
        .map(
          (s) =>
              '${s.id}${s.emp}${s.tpl}${s.date}${s.changed}${s.start}${s.end}',
        )
        .join();
    if (sig == _signature) return;
    _signature = sig;
    final interaction = widget.editable ? null : EventInteraction.allowNone();
    _events.replaceEvents([
      for (final s in widget.shifts) ShiftEvent.of(s, interaction: interaction),
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    _events.dispose();
    super.dispose();
  }

  String _viewLabel(CalendarView v) => switch (v) {
    CalendarView.day => tr('staff.view_day'),
    CalendarView.threeDays => tr('staff.view_three_days'),
    CalendarView.week => tr('staff.view_week'),
    CalendarView.month => tr('staff.view_month'),
    CalendarView.list => tr('staff.view_list'),
  };

  String _rangeLabel(KalenderDateTimeRange? r, CalendarView v) {
    if (r == null) return '';
    final start = _wall(r.start);
    final end = _wall(r.end).subtract(const Duration(minutes: 1));
    if (v == CalendarView.month) {
      final mid = start.add(const Duration(days: 15));
      return '${tr('staff.month_${mid.month}')} ${mid.year}';
    }
    if (v == CalendarView.list || sameDay(start, end)) return dayLabel(start);
    return '${dayMonth(start)} – ${dayMonth(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final phone = MadarLayout.of(context).isPhone;
    final view = _view ?? (phone ? widget.phoneView : widget.tabletView);
    final views = [
      if (!phone) CalendarView.day,
      CalendarView.threeDays,
      if (!phone) CalendarView.week,
      if (phone) CalendarView.day,
      CalendarView.month,
      CalendarView.list,
    ];

    final arrows = <Widget>[
      MadarGlyphTile(
        glyph: MadarGlyph.chevronBack,
        semanticLabel: tr('staff.previous'),
        onTap: _controller.animateToPreviousPage,
      ),
      MadarChip(
        label: tr('staff.today_short'),
        onTap: () => _controller.animateToDate(widget.now()),
      ),
      MadarGlyphTile(
        glyph: MadarGlyph.chevronForward,
        semanticLabel: tr('staff.next'),
        onTap: _controller.animateToNextPage,
      ),
    ];
    final label = Text(
      _rangeLabel(_range, view),
      style: MadarType.h3,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final switcher = <Widget>[
      for (final v in views)
        MadarChip(
          label: _viewLabel(v),
          selected: v == view,
          onTap: () => setState(() => _view = v),
        ),
      ?widget.trailing,
    ];
    final toolbar = LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 960) {
          return Row(
            spacing: Space.sm,
            children: [
              ...arrows,
              Expanded(child: label),
              ...switcher,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            Row(
              spacing: Space.sm,
              children: [
                ...arrows,
                Expanded(child: label),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(spacing: Space.sm, children: switcher),
            ),
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        toolbar,
        Expanded(
          child: MadarCard(
            flush: true,
            clip: true,
            padding: EdgeInsets.zero,
            child: KalenderTheme(
              data: KalenderThemeData(
                timeIndicatorStyle: TimeIndicatorStyle(
                  lineColor: c.danger,
                  circleColor: c.danger,
                ),
              ),
              child: KalenderView(
                eventsController: _events,
                kalenderController: _controller,
                viewConfiguration: _views[view]!,
                locale: Locale(currentLang),
                callbacks: KalenderCallbacks(
                  onEventTapped: (e) =>
                      widget.onTapShift?.call((e as ShiftEvent).shift),
                  onEventChanged: (old, updated) => widget.onMove?.call(
                    (old as ShiftEvent).shift,
                    _wall(updated.start),
                  ),
                  onTapped: (d) => widget.onTapSlot?.call(_wall(d)),
                  onPageChanged: (r) =>
                      widget.onRangeChanged?.call(_wall(r.start)),
                ),
                components: _components,
                header: KalenderHeader(
                  multiDayTileComponents: TileComponents(tileBuilder: _tile),
                ),
                body: KalenderBody(
                  interaction: KalenderInteraction(
                    allowResizing: false,
                    allowRescheduling: widget.editable,
                    allowEventCreation: false,
                  ),
                  snapping: const KalenderSnapping(snapIntervalMinutes: 30),
                  multiDayTileComponents: TileComponents(tileBuilder: _tile),
                  monthTileComponents: TileComponents(tileBuilder: _monthTile),
                  scheduleTileComponents: ScheduleTileComponents(
                    tileBuilder: _listTile,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Latin figures and the core's day and month names in every view.
  late final KalenderComponents _components = KalenderComponents(
    multiDayComponents: MultiDayComponents(
      headerComponents: MultiDayHeaderComponents(
        dayHeaderStringBuilder: (_, d) => weekday(d.weekday),
        dayHeaderNumberStringBuilder: (_, d) => '${d.day}',
      ),
      bodyComponents: MultiDayBodyComponents(
        timelineStringBuilder: (_, t) => hmMin(t.hour * 60 + t.minute),
      ),
    ),
    monthComponents: MonthComponents(
      bodyComponents: MonthBodyComponents(
        monthDayHeaderStringBuilder: (_, d) => '${d.day}',
      ),
      headerComponents: MonthHeaderComponents(
        weekDayHeaderStringBuilder: (_, d) => weekday(d.weekday),
      ),
    ),
    scheduleComponents: ScheduleComponents(
      leadingDateStringBuilder: (_, d) => weekday(d.weekday),
    ),
  );

  Widget _tile(BuildContext context, KalenderEvent e, KalenderDateTimeRange r) {
    final s = (e as ShiftEvent).shift;
    final c = context.madarColors;
    final hue = widget.colorOf(s);
    return Padding(
      padding: const EdgeInsets.all(1.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(hue.withValues(alpha: 0.16), c.surface),
          borderRadius: BorderRadius.circular(Radii.xs),
          border: BorderDirectional(start: BorderSide(color: hue, width: 3)),
        ),
        child: LayoutBuilder(
          builder: (context, box) => box.maxWidth < 44
              // Too narrow for words (a busy week): the person's initial.
              ? Center(
                  child: Text(
                    initialOf(widget.titleOf(s)),
                    style: MadarType.label.copyWith(color: hue),
                  ),
                )
              : Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.titleOf(s),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MadarType.labelSm.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          if (s.changed)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: c.warning,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (box.maxHeight > 34)
                        Text(
                          '${hm(s.startAt)} – ${hm(s.endAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MadarType.labelSm.copyWith(
                            color: c.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _monthTile(
    BuildContext context,
    KalenderEvent e,
    KalenderDateTimeRange r,
  ) {
    final s = (e as ShiftEvent).shift;
    final hue = widget.colorOf(s);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: hue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        widget.titleOf(s),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: MadarType.labelSm.copyWith(
          color: context.madarColors.textPrimary,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _listTile(
    BuildContext context,
    KalenderEvent e,
    KalenderDateTimeRange r,
  ) {
    final s = (e as ShiftEvent).shift;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: MadarListRow.bill(
        title: widget.titleOf(s),
        meta: '${hm(s.startAt)} – ${hm(s.endAt)} · ${tplName(s.template)}',
        railColor: widget.colorOf(s),
        status: s.changed
            ? MadarStatus(tr('staff.changed'), tone: MadarTone.warning)
            : null,
        onTap: widget.onTapShift == null ? null : () => widget.onTapShift!(s),
      ),
    );
  }
}
