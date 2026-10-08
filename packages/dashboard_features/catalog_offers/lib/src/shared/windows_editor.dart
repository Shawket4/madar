/// When a combo or a deal is on sale (the web's `windows-editor.tsx`, shared
/// by the combo editor and the deal dialog): an optional list of windows,
/// each with its weekdays, hours and dates, for one branch or all of them.
/// No window means always available, and the empty state says so.
///
/// Controlled: [value] in, [onChanged] out, the errors from
/// [validateWindow] passed back in by the form that owns it.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'offers_format.dart';
import 'sale_window_form.dart';

/// A branch a window can be limited to.
typedef OffersBranch = ({String id, String name});

class WindowsEditor extends ConsumerWidget {
  const WindowsEditor({
    required this.value,
    required this.onChanged,
    required this.branches,
    this.errors = const [],
    this.enabled = true,
    super.key,
  });

  final List<WindowDraft> value;
  final ValueChanged<List<WindowDraft>> onChanged;
  final List<OffersBranch> branches;

  /// One entry per window (null or missing = no error).
  final List<WindowErrors?> errors;

  /// False = read-only: every control disabled, no Add a window.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final now = ref.watch(clockProvider)();
    final zoned = inZone(now, ref.watch(activeTimezoneProvider));
    final today = DateTime(zoned.year, zoned.month, zoned.day);

    void patch(int i, WindowDraft next) => onChanged([
      for (var j = 0; j < value.length; j++) j == i ? next : value[j],
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        if (value.isEmpty) _AlwaysAvailable(t: t),
        for (var i = 0; i < value.length; i++)
          _WindowCard(
            key: ValueKey(value[i].key),
            index: i,
            window: value[i],
            errors: i < errors.length ? errors[i] : null,
            branches: branches,
            enabled: enabled,
            today: today,
            onChanged: (w) => patch(i, w),
            onRemove: () => onChanged([
              for (var j = 0; j < value.length; j++)
                if (j != i) value[j],
            ]),
          ),
        if (enabled)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashButton(
              label: t('combos.windows.add'),
              icon: 'plus',
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: () => onChanged([...value, WindowDraft.empty()]),
            ),
          ),
      ],
    );
  }
}

class _AlwaysAvailable extends StatelessWidget {
  const _AlwaysAvailable({required this.t});

  final Translator t;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return CustomPaint(
      painter: _DashedBorder(color: c.input, radius: Radii.card),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.lg),
        child: Row(
          spacing: Space.md,
          children: [
            DashIcon('calendar-clock', color: c.textSecondary),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t('combos.windows.always'),
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    t('combos.windows.alwaysHint'),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowCard extends ConsumerWidget {
  const _WindowCard({
    required this.index,
    required this.window,
    required this.errors,
    required this.branches,
    required this.enabled,
    required this.today,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final int index;
  final WindowDraft window;
  final WindowErrors? errors;
  final List<OffersBranch> branches;
  final bool enabled;
  final DateTime today;
  final ValueChanged<WindowDraft> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final w = window;
    final e = errors ?? const WindowErrors();

    Widget label(String text) => Text(
      text,
      style: DashType.smallMedium.copyWith(color: c.textSecondary),
    );
    Widget error(String key) => Semantics(
      liveRegion: true,
      child: Text(t(key), style: DashType.small.copyWith(color: c.danger)),
    );
    Widget hint(String key) =>
        Text(t(key), style: DashType.small.copyWith(color: c.textSecondary));

    final days = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        label(t('combos.windows.days')),
        Semantics(
          container: true,
          label: t('combos.windows.days'),
          child: Wrap(
            spacing: Space.xs + DashMetrics.hair,
            runSpacing: Space.xs + DashMetrics.hair,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var d = 0; d < 7; d++)
                _DayToggle(
                  label: t('combos.windows.day.${weekdayKeys[d]}'),
                  on: hasDay(w.weekdays, d),
                  enabled: enabled,
                  onTap: () =>
                      onChanged(w.copyWith(weekdays: toggleDay(w.weekdays, d))),
                ),
              DashButton(
                label: w.weekdays == allWeekdays
                    ? t('combos.windows.clearDays')
                    : t('combos.windows.everyDay'),
                variant: DashButtonVariant.link,
                size: DashButtonSize.compact,
                onPressed: enabled
                    ? () => onChanged(
                        w.copyWith(
                          weekdays: w.weekdays == allWeekdays ? 0 : allWeekdays,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        if (e.weekdays != null) error(e.weekdays!),
      ],
    );

    final hours = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        label(t('combos.windows.hours')),
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: DashTimeField(
                value: w.startsAt.isEmpty ? null : w.startsAt,
                onChanged: (v) =>
                    onChanged(w.copyWith(startsAt: hhmm(v) ?? '')),
                placeholder: t('combos.windows.from'),
                semanticLabel: t('combos.windows.from'),
                clearable: true,
                enabled: enabled,
              ),
            ),
            Expanded(
              child: DashTimeField(
                value: w.endsAt.isEmpty ? null : w.endsAt,
                onChanged: (v) => onChanged(w.copyWith(endsAt: hhmm(v) ?? '')),
                placeholder: t('combos.windows.to'),
                semanticLabel: t('combos.windows.to'),
                clearable: true,
                invalid: e.endsAt != null,
                enabled: enabled,
              ),
            ),
          ],
        ),
        if (e.endsAt != null)
          error(e.endsAt!)
        else if (w.startsAt.isNotEmpty &&
            w.endsAt.isNotEmpty &&
            w.endsAt.compareTo(w.startsAt) < 0)
          hint('combos.windows.crossesMidnight'),
      ],
    );

    final dates = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        label(t('combos.windows.dates')),
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: DashDateField(
                value: _dayOf(w.validFrom),
                onChanged: (d) => onChanged(w.copyWith(validFrom: _isoDay(d))),
                placeholder: t('combos.windows.fromDate'),
                semanticLabel: t('combos.windows.fromDate'),
                today: today,
                enabled: enabled,
              ),
            ),
            Expanded(
              child: DashDateField(
                value: _dayOf(w.validTo),
                onChanged: (d) => onChanged(w.copyWith(validTo: _isoDay(d))),
                placeholder: t('combos.windows.toDate'),
                semanticLabel: t('combos.windows.toDate'),
                today: today,
                invalid: e.validTo != null,
                enabled: enabled,
              ),
            ),
          ],
        ),
        if (e.validTo != null) error(e.validTo!),
        if ((w.validFrom.isNotEmpty || w.validTo.isNotEmpty) && enabled)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashButton(
              label: t('combos.windows.clearDates'),
              variant: DashButtonVariant.link,
              size: DashButtonSize.compact,
              onPressed: () =>
                  onChanged(w.copyWith(validFrom: '', validTo: '')),
            ),
          ),
      ],
    );

    final branch = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs + DashMetrics.hair,
        children: [
          label(t('combos.windows.branch')),
          DashSelect<String>(
            options: [
              DashOption(value: '', label: t('combos.windows.allBranches')),
              for (final b in branches) DashOption(value: b.id, label: b.name),
            ],
            value: w.branchId,
            onChanged: (v) => onChanged(w.copyWith(branchId: v)),
            semanticLabel: t('combos.windows.branch'),
            enabled: enabled,
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: t('combos.windows.windowN', args: {'n': index + 1}),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.hairline),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.md,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('combos.windows.windowN', args: {'n': index + 1}),
                      style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                    ),
                  ),
                  DashIconButton(
                    icon: 'trash-2',
                    semanticLabel: t('combos.windows.remove'),
                    color: c.danger,
                    onPressed: enabled ? onRemove : null,
                  ),
                ],
              ),
              days,
              LayoutBuilder(
                builder: (context, box) => box.maxWidth >= DashBreakpoints.sm
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.md,
                        children: [
                          Expanded(child: hours),
                          Expanded(child: dates),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: Space.md,
                        children: [hours, dates],
                      ),
              ),
              Align(alignment: AlignmentDirectional.centerStart, child: branch),
            ],
          ),
        ),
      ),
    );
  }
}

/// A weekday toggle: filled when on (`aria-pressed`), 44 tall.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.label,
    required this.on,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      selected: on,
      semanticLabel: label,
      excludeChildSemantics: true,
      builder: (context, s) {
        final radius = BorderRadius.circular(Radii.sm);
        return Opacity(
          opacity: enabled ? 1 : 0.6,
          child: Container(
            height: DashMetrics.target,
            constraints: const BoxConstraints(minWidth: DashMetrics.target),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.sm,
            ),
            foregroundDecoration: dashFocusRing(context, s, radius),
            decoration: BoxDecoration(
              color: on ? c.accent : (s.highlighted ? c.muted : c.card),
              borderRadius: radius,
              border: Border.all(color: on ? c.accent : c.input),
            ),
            // Sized to the label (a Container with an alignment would fill
            // the whole row).
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: DashType.smallMedium.copyWith(
                  color: on ? c.textOnAccent : c.textSecondary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

DateTime? _dayOf(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(iso);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A dashed rounded outline (the web's `border-dashed`).
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.5);
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}
