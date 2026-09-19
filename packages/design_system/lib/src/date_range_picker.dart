/// The date-range picker: ONE control for "which days am I looking at".
///
/// It is the POS's half of the dashboard's period filter
/// (`MadarDashboard/src/components/app/date-range-picker.tsx`) and behaves the
/// same way on purpose — the owner reads the two side by side and a window
/// that means "this week" must mean the same week in both. Quick presets as
/// pills, a calendar for a hand-picked range, two taps with a live preview
/// between them, no future days, and an explicit Apply; the trigger shows the
/// active preset, or the literal range once a window is hand-picked.
///
/// It is deliberately DUMB about time: it never asks the device what day it
/// is, never decides where a week starts, and never names a month itself.
/// All three arrive in [MadarCalendarChrome], which the core fills from the
/// BRANCH's clock (`timefmt::DatePickerChromeView`) — a till in a different
/// zone from its branch must still grey out the branch's tomorrow. Inside
/// this file a `DateTime` is a UTC-tagged CIVIL DATE and nothing else: a
/// label on a square, never an instant.
library;

import 'package:design_system/src/controls.dart';
import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/sheet.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/widgets.dart';

/// What the calendar needs to know that it must not work out for itself:
/// today IN THE BRANCH, which weekday a week starts on, and the words.
@immutable
class MadarCalendarChrome {
  /// Creates the chrome. See [MadarDateRangePicker] for where it comes from.
  const MadarCalendarChrome({
    required this.today,
    required this.weekStart,
    required this.weekdays,
    required this.months,
    required this.monthsShort,
  });

  /// Today in the branch timezone, `YYYY-MM-DD`. Days after it are refused.
  final String today;

  /// The weekday a week starts on, 0 = Sunday … 6 = Saturday. The owner's
  /// rule is Saturday; the core carries it, this widget only obeys it.
  final int weekStart;

  /// Seven column headings, already rotated so index 0 is [weekStart].
  final List<String> weekdays;

  /// Twelve month names in full, January first — the calendar's header.
  final List<String> months;

  /// Twelve month names as a DATE shows them (`Sep`) — day labels.
  final List<String> monthsShort;
}

/// One quick preset pill: its key, and its label in the till's language.
@immutable
class MadarDatePreset {
  /// Creates a preset pill.
  const MadarDatePreset(this.key, this.label);

  /// The key the caller's core knows the window by (`today`, `this_week`, …).
  final String key;

  /// Already-localized label.
  final String label;
}

/// The window in effect: a preset key, or `custom` with two branch-local days.
@immutable
class MadarDateWindow {
  /// A named preset.
  const MadarDateWindow.preset(this.preset) : from = null, to = null;

  /// A hand-picked window, two inclusive `YYYY-MM-DD` days.
  const MadarDateWindow.custom(String this.from, String this.to)
    : preset = 'custom';

  /// The preset key, or `custom`.
  final String preset;

  /// The first day, `YYYY-MM-DD`; null unless [preset] is `custom`.
  final String? from;

  /// The last day, inclusive; null unless [preset] is `custom`.
  final String? to;
}

/// The picker's words. Already localized by the caller — this package holds no
/// strings of its own (the app's words live in the core's `i18n.rs`).
@immutable
class MadarDateRangeLabels {
  /// Creates the label bundle.
  const MadarDateRangeLabels({
    required this.title,
    required this.from,
    required this.to,
    required this.apply,
    required this.custom,
    required this.pickStart,
    required this.pickEnd,
    required this.rangePicked,
    required this.previousMonth,
    required this.nextMonth,
  });

  /// The sheet's title ("Period").
  final String title;

  /// "From" / "To", over the two chosen days.
  final String from;
  final String to;

  /// The commit button ("Apply").
  final String apply;

  /// What the trigger says for a custom window with no days yet.
  final String custom;

  /// The footer hint, by how far the two taps have got.
  final String pickStart;
  final String pickEnd;
  final String rangePicked;

  /// Month-arrow labels, for a screen reader.
  final String previousMonth;
  final String nextMonth;
}

// ── Civil dates ──────────────────────────────────────────────────────────────
//
// A `DateTime` here is UTC-tagged and carries a calendar day, nothing more.
// Tagging it UTC keeps arithmetic free of the DEVICE's zone and of DST, which
// would otherwise make "the 26th plus one day" occasionally the 26th again.

/// `YYYY-MM-DD` → a civil date, or null when it is not one.
DateTime? madarParseDay(String? day) {
  if (day == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final out = DateTime.utc(y, mo, d);
  // Rejects the 31st of a 30-day month instead of rolling into the next one.
  return (out.month == mo && out.day == d) ? out : null;
}

/// A civil date → `YYYY-MM-DD`.
String madarFormatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// A day as a date READS — `Sep 17`, Arabic `سبتمبر 17` — from the core's own
/// short months, so a square agrees with the range label beside it.
String madarDayLabel(MadarCalendarChrome chrome, DateTime day) =>
    '${chrome.monthsShort[day.month - 1]} ${day.day}';

/// `Sep 17` for one day, `Sep 17 – Sep 21` for a window.
String madarRangeLabel(
  MadarCalendarChrome chrome,
  DateTime from,
  DateTime to,
) => from == to
    ? madarDayLabel(chrome, from)
    : '${madarDayLabel(chrome, from)} – ${madarDayLabel(chrome, to)}';

// ── The trigger ──────────────────────────────────────────────────────────────

/// THE period control: a compact trigger that opens the picker sheet.
///
/// ```dart
/// MadarDateRangePicker(
///   chrome: chrome,            // from `bridge.datePickerChrome()`
///   presets: presets,          // from `bridge.posMetricsPresets()`
///   value: window,
///   labels: labels,
///   onChanged: (w) => load(w),
/// )
/// ```
///
/// [onChanged] fires once, with a preset the moment its pill is tapped, or
/// with a custom window when Apply is pressed — never while the two taps are
/// still being made.
class MadarDateRangePicker extends StatelessWidget {
  /// Creates the period trigger.
  const MadarDateRangePicker({
    required this.chrome,
    required this.presets,
    required this.value,
    required this.labels,
    required this.onChanged,
    super.key,
  });

  /// Today, the week start and the words — see [MadarCalendarChrome].
  final MadarCalendarChrome chrome;

  /// The quick presets, in the order they are shown.
  final List<MadarDatePreset> presets;

  /// The window in effect.
  final MadarDateWindow value;

  /// The picker's already-localized words.
  final MadarDateRangeLabels labels;

  /// Called with the window a person settled on.
  final ValueChanged<MadarDateWindow> onChanged;

  /// What the trigger says: the active preset's label, or the literal range.
  String _triggerLabel() {
    if (value.preset != 'custom') {
      for (final p in presets) {
        if (p.key == value.preset) return p.label;
      }
      return labels.custom;
    }
    final from = madarParseDay(value.from);
    final to = madarParseDay(value.to);
    if (from == null || to == null) return labels.custom;
    return madarRangeLabel(chrome, from, to);
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showMadarSheet<MadarDateWindow>(
      context,
      // Hug: a calendar is a fixed shape, and `auto` would float it at the top
      // of a card stretched to 88% of a tall tablet.
      size: SheetSize.hug,
      builder: (context) => _DateRangeSheet(
        chrome: chrome,
        presets: presets,
        value: value,
        labels: labels,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: MadarButton(
        label: _triggerLabel(),
        glyph: MadarGlyph.calendar,
        variant: MadarButtonVariant.secondary,
        size: MadarButtonSize.compact,
        onTap: () => _open(context),
      ),
    );
  }
}

// ── The sheet ────────────────────────────────────────────────────────────────

class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({
    required this.chrome,
    required this.presets,
    required this.value,
    required this.labels,
  });

  final MadarCalendarChrome chrome;
  final List<MadarDatePreset> presets;
  final MadarDateWindow value;
  final MadarDateRangeLabels labels;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  /// The two taps. [_to] is null between them; [_preview] is the day under the
  /// pointer while the second tap has not landed.
  DateTime? _from;
  DateTime? _to;
  DateTime? _preview;

  /// The visible month, as its first day.
  late DateTime _month;

  DateTime get _today =>
      madarParseDay(widget.chrome.today) ?? DateTime.utc(2000);

  @override
  void initState() {
    super.initState();
    _from = madarParseDay(widget.value.from);
    _to = madarParseDay(widget.value.to);
    final anchor = _from ?? _today;
    _month = DateTime.utc(anchor.year, anchor.month);
  }

  /// A tap: the first opens a window, the second closes it (either way round —
  /// tapping before the start day reverses the pair rather than refusing it),
  /// and a third starts over.
  void _tap(DateTime day) {
    setState(() {
      final from = _from;
      if (from == null || _to != null) {
        _from = day;
        _to = null;
      } else if (day.isBefore(from)) {
        _from = day;
        _to = from;
      } else {
        _to = day;
      }
      _preview = null;
    });
  }

  void _showPreview(DateTime? day) {
    if (_from == null || _to != null) return;
    if (_preview == day) return;
    setState(() => _preview = day);
  }

  void _step(int months) =>
      setState(() => _month = DateTime.utc(_month.year, _month.month + months));

  /// Nothing after the branch's today, so a month past it is unreachable.
  bool get _canStepForward =>
      _month.isBefore(DateTime.utc(_today.year, _today.month));

  void _apply() {
    final from = _from;
    if (from == null) return;
    // One tap means one day — the commonest window there is.
    final to = _to ?? from;
    MadarSheet.close(
      context,
      MadarDateWindow.custom(madarFormatDay(from), madarFormatDay(to)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final labels = widget.labels;
    final from = _from;
    final end = _to ?? _preview;

    return Padding(
      padding: const EdgeInsets.all(Space.card),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            labels.title,
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.lg),

          // Quick presets — a tap here is the whole answer.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final p in widget.presets)
                if (p.key != 'custom')
                  MadarChip(
                    label: p.label,
                    selected: widget.value.preset == p.key,
                    onTap: () => MadarSheet.close(
                      context,
                      MadarDateWindow.preset(p.key),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: Space.lg),
          const MadarHairline(),
          const SizedBox(height: Space.lg),

          _Summary(chrome: widget.chrome, labels: labels, from: from, to: end),
          const SizedBox(height: Space.lg),

          _MonthBar(
            title: '${widget.chrome.months[_month.month - 1]} ${_month.year}',
            previousLabel: labels.previousMonth,
            nextLabel: labels.nextMonth,
            onPrevious: () => _step(-1),
            onNext: _canStepForward ? () => _step(1) : null,
          ),
          const SizedBox(height: Space.md),

          _MonthGrid(
            chrome: widget.chrome,
            month: _month,
            today: _today,
            from: from,
            to: end,
            onTap: _tap,
            onPreview: _showPreview,
          ),
          const SizedBox(height: Space.lg),

          Row(
            children: [
              Expanded(
                child: Text(
                  from == null
                      ? labels.pickStart
                      : _to == null
                      ? labels.pickEnd
                      : labels.rangePicked,
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: Space.md),
              MadarButton(
                label: labels.apply,
                size: MadarButtonSize.compact,
                enabled: from != null,
                onTap: _apply,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The two chosen days, spelled out — the second one following the pointer
/// while the window is still being drawn.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.chrome,
    required this.labels,
    required this.from,
    required this.to,
  });

  final MadarCalendarChrome chrome;
  final MadarDateRangeLabels labels;
  final DateTime? from;
  final DateTime? to;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    Widget half(String label, DateTime? day) => Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: MadarType.label.copyWith(
              color: colors.textMuted,
              letterSpacing: MadarType.tracking,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            day == null ? '—' : madarDayLabel(chrome, day),
            style: MadarType.numMd.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Row(
        children: [
          half(labels.from, from),
          Container(width: 1, height: 28, color: colors.borderLight),
          half(labels.to, to),
        ],
      ),
    );
  }
}

/// `‹  September 2026  ›` — the arrows mirror themselves under RTL, and
/// forward is absent once the visible month holds today.
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.title,
    required this.previousLabel,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final String previousLabel;
  final String nextLabel;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    Widget arrow(MadarGlyph glyph, String label, VoidCallback? onTap) {
      final enabled = onTap != null;
      return Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: TactileScale(
          onTap: onTap,
          child: SizedBox(
            // 44 — the touch floor, on a screen with no keyboard.
            width: Metrics.glyphTile,
            height: Metrics.glyphTile,
            child: Center(
              child: MadarGlyphIcon(
                glyph,
                size: IconSize.sm,
                color: enabled ? colors.textPrimary : colors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        arrow(MadarGlyph.chevronBack, previousLabel, onPrevious),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: MadarType.title.copyWith(color: colors.textPrimary),
          ),
        ),
        arrow(MadarGlyph.chevronForward, nextLabel, onNext),
      ],
    );
  }
}

/// One month as seven columns. Laid out with plain [Row]s, so Arabic mirrors
/// the whole grid and the week still starts in the reading-first column.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.chrome,
    required this.month,
    required this.today,
    required this.from,
    required this.to,
    required this.onTap,
    required this.onPreview,
  });

  final MadarCalendarChrome chrome;
  final DateTime month;
  final DateTime today;
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime> onTap;
  final ValueChanged<DateTime?> onPreview;

  /// How many blank squares stand before the 1st, given the week start.
  int get _lead {
    // `weekday` is 1 = Monday … 7 = Sunday; `% 7` puts Sunday at 0, which is
    // the numbering `weekStart` uses.
    final firstColumn = DateTime.utc(month.year, month.month).weekday % 7;
    return (firstColumn - chrome.weekStart + 7) % 7;
  }

  int get _daysInMonth =>
      DateTime.utc(month.year, month.month + 1).difference(month).inDays;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(_lead, null),
      for (var d = 1; d <= _daysInMonth; d++)
        DateTime.utc(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    final lo = from != null && to != null
        ? (from!.isBefore(to!) ? from! : to!)
        : null;
    final hi = from != null && to != null
        ? (from!.isBefore(to!) ? to! : from!)
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final name in chrome.weekdays)
              Expanded(
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  style: MadarType.labelSm.copyWith(color: colors.textMuted),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.xs),
        for (var row = 0; row < cells.length ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _DayCell(
                    day: cells[row * 7 + col],
                    today: today,
                    start: from,
                    end: to,
                    low: lo,
                    high: hi,
                    onTap: onTap,
                    onPreview: onPreview,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.start,
    required this.end,
    required this.low,
    required this.high,
    required this.onTap,
    required this.onPreview,
  });

  final DateTime? day;
  final DateTime today;
  final DateTime? start;
  final DateTime? end;
  final DateTime? low;
  final DateTime? high;
  final ValueChanged<DateTime> onTap;
  final ValueChanged<DateTime?> onPreview;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final day = this.day;
    if (day == null) return const SizedBox(height: Metrics.glyphTile);

    // The guard: the branch's today is the last selectable day.
    final future = day.isAfter(today);
    final isToday = day == today;
    final isLow = low != null && day == low;
    final isHigh = high != null && day == high;
    final isEdge = day == start || (end != null && day == end);
    final inside =
        low != null && high != null && day.isAfter(low!) && day.isBefore(high!);

    final band = isLow || isHigh || inside;
    final bandRadius = BorderRadiusDirectional.horizontal(
      start: Radius.circular(isLow || low == high ? Radii.pill : 0),
      end: Radius.circular(isHigh || low == high ? Radii.pill : 0),
    );

    final label = Text(
      '${day.day}',
      style: MadarType.numMd.copyWith(
        color: future
            ? colors.textMuted
            : isEdge
            ? colors.textOnAccent
            : colors.textPrimary,
      ),
    );

    final cell = Container(
      height: Metrics.glyphTile,
      alignment: Alignment.center,
      decoration: band
          ? BoxDecoration(color: colors.accentBg, borderRadius: bandRadius)
          : null,
      child: Container(
        width: Metrics.glyphTile - Space.xs,
        height: Metrics.glyphTile - Space.xs,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isEdge ? colors.accent : null,
          border: isToday && !isEdge ? Border.all(color: colors.accent) : null,
        ),
        child: label,
      ),
    );

    if (future) {
      return Semantics(
        label: madarFormatDay(day),
        enabled: false,
        child: ExcludeSemantics(child: cell),
      );
    }

    return Semantics(
      button: true,
      selected: isEdge || inside,
      label: madarFormatDay(day),
      child: ExcludeSemantics(
        child: MouseRegion(
          onEnter: (_) => onPreview(day),
          onExit: (_) => onPreview(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Press previews the window before the finger lifts; the tap
            // commits it. On a tablet this is the hover the dashboard has.
            onTapDown: (_) => onPreview(day),
            onTapCancel: () => onPreview(null),
            onTap: () {
              MadarHaptics.selection();
              onTap(day);
            },
            child: cell,
          ),
        ),
      ),
    );
  }
}
