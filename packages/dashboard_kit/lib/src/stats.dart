import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'display.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// How a stat's number is written.
enum DashStatFormat {
  /// Minor units of the org currency.
  money,

  /// A plain count.
  number,

  /// A ratio (0.123 → 12.3%).
  percent,
}

typedef _Fmt = String Function(double n);

List<_Fmt> _formattersFor(DashKitFormats f, DashStatFormat? type) =>
    switch (type) {
      DashStatFormat.money => [
        (n) => f.money(n.round()),
        (n) => f.money(n.round(), maxFractionDigits: 0),
        (n) => f.moneyCompact(n.round()),
      ],
      DashStatFormat.percent => [(n) => f.percent(n)],
      _ => [(n) => f.number(n.round()), (n) => f.numberCompact(n.round())],
    };

/// A number that counts up from zero the first time it is drawn (1.1 s,
/// ease-out-quart, in step with the charts) and then tells the truth at
/// once on later changes — or tweens every change with [tweenOnChange].
/// Reduced motion shows the final value immediately (the web's
/// `AnimatedNumber`).
class DashAnimatedNumber extends StatefulWidget {
  const DashAnimatedNumber({
    required this.value,
    required this.format,
    this.style,
    this.tweenOnChange = false,
    super.key,
  });

  final double value;
  final String Function(double n) format;
  final TextStyle? style;
  final bool tweenOnChange;

  @override
  State<DashAnimatedNumber> createState() => _DashAnimatedNumberState();
}

class _DashAnimatedNumberState extends State<DashAnimatedNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DashMotion.count,
  );
  double _from = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (DashMotion.reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void didUpdateWidget(DashAnimatedNumber old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    if (widget.tweenOnChange && !DashMotion.reduced(context)) {
      _from = _shown(old.value);
      _c.forward(from: 0);
    } else {
      _c.value = 1;
    }
  }

  double _shown(double target) =>
      _from + (target - _from) * DashMotion.ease.transform(_c.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Text(
      widget.format(_shown(widget.value)),
      style: widget.style,
      maxLines: 1,
      softWrap: false,
    ),
  );
}

/// A KPI figure aware of its slot (the web's `StatValue`): it shows the
/// richest form that fits — shrinking the type down [sizes] before it
/// compacts ("EGP 1,234.56" → "EGP 1,235" → "EGP 1.2K") — and a shortened
/// figure opens the exact one on tap. Counts up on first draw.
class DashStatValue extends StatelessWidget {
  const DashStatValue({
    required this.value,
    required this.label,
    this.format,
    this.sizes = const [24, 22, 20, 18, 16],
    this.color,
    super.key,
  });

  /// Minor units for money, a ratio for percent, a count otherwise.
  final num value;
  final DashStatFormat? format;

  /// Shown over the exact figure when the slot had to shorten it.
  final String label;

  /// Candidate font sizes, largest first.
  final List<double> sizes;
  final Color? color;

  static const List<double> regularSizes = [24, 22, 20, 18, 16];
  static const List<double> denseSizes = [20, 18, 16, 15, 14];

  @override
  Widget build(BuildContext context) {
    final f = context.dashFormats;
    final c = context.madarColors;
    final fmts = _formattersFor(f, format);
    final v = value.toDouble();
    final seen = <String>{};
    final reps = [
      for (final fm in fmts)
        if (seen.add(fm(v))) fm,
    ];
    final exact = fmts.first(v);
    final dir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final avail = constraints.maxWidth;
        var rep = reps.last;
        var size = sizes.last;
        var found = false;
        for (final r in reps) {
          for (final s in sizes) {
            final tp = TextPainter(
              text: TextSpan(text: r(v), style: DashType.statFigure(s)),
              textDirection: dir,
              maxLines: 1,
            )..layout();
            final w = tp.width;
            tp.dispose();
            if (w <= avail) {
              rep = r;
              size = s;
              found = true;
              break;
            }
          }
          if (found) break;
        }
        final shortened = rep(v) != exact;
        final isDecimal =
            format == DashStatFormat.money || format == DashStatFormat.percent;
        final style = DashType.statFigure(size).copyWith(
          color: color ?? c.textPrimary,
          decoration: shortened ? TextDecoration.underline : null,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: c.textSecondary.withValues(alpha: 0.5),
        );
        final figure = DashAnimatedNumber(
          value: v,
          style: style,
          format: (n) => rep(isDecimal ? n : n.roundToDouble()),
        );
        if (!shortened) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: figure,
          );
        }
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: DashPopover(
            width: math.max(DashMetrics.menu - Space.xxl, avail * 0.6),
            anchor: (context, ctl) => DashPressable(
              onTap: ctl.toggle,
              pressScale: false,
              semanticLabel: '$label: $exact',
              excludeChildSemantics: true,
              builder: (context, s) => figure,
            ),
            content: (context, ctl) => Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: DashType.smallMedium.copyWith(
                      color: c.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: DashMetrics.hair),
                  Text(
                    exact,
                    style: DashType.monoStrong.copyWith(
                      fontSize: 16,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A KPI card (the web's `StatCard`): a small muted glyph and label, the
/// figure, a trend pill and a hint. Quiet — only a state that means
/// something (a void, a shortfall) tints the glyph.
class DashStatCard extends StatelessWidget {
  const DashStatCard({
    required this.label,
    this.value,
    this.valueText,
    this.valueWidget,
    this.format,
    this.icon,
    this.tone = DashTone.neutral,
    this.trend,
    this.hint,
    this.loading = false,
    this.dense = false,
    this.action,
    this.onTap,
    this.reserveFooter = false,
    super.key,
  });

  final String label;

  /// A number, fitted and counted ([format] decides how it reads).
  final num? value;

  /// A ready string.
  final String? valueText;

  /// A ready widget (a pill, a skeleton).
  final Widget? valueWidget;
  final DashStatFormat? format;
  final String? icon;

  /// success / warning / danger tint the glyph; the rest stay muted.
  final DashTone tone;

  /// A signed ratio: 0.123 → +12.3%.
  final double? trend;
  final String? hint;
  final bool loading;
  final bool dense;

  /// A small control in the header row.
  final Widget? action;
  final VoidCallback? onTap;

  /// Keep the trend/hint line's room even without one, so cards in a strip
  /// share a height.
  final bool reserveFooter;

  /// The height of the trend/hint line.
  static const double footerHeight = Space.card;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    final pad = EdgeInsets.all(dense ? Space.lg : Space.card);
    final gap = dense ? Space.sm : Space.md;
    final valueSlot = dense
        ? DashStatValue.denseSizes.first
        : DashStatValue.regularSizes.first;
    if (loading) {
      return DashCard(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: gap,
          children: [
            SizedBox(
              height: Space.card,
              child: Row(
                children: [
                  const DashSkeleton(width: 80),
                  const Spacer(),
                  if (icon != null)
                    const DashSkeleton(width: Space.lg, height: Space.lg),
                ],
              ),
            ),
            DashSkeleton(width: 96, height: valueSlot),
            if (reserveFooter) const SizedBox(height: footerHeight),
          ],
        ),
      );
    }
    final glyphColor = switch (tone) {
      DashTone.success ||
      DashTone.warning ||
      DashTone.danger => tone.foreground(c),
      _ => c.textSecondary,
    };
    final Widget valueNode;
    if (valueWidget != null) {
      valueNode = DefaultTextStyle.merge(
        style: DashType.statFigure(
          dense ? 18 : 24,
        ).copyWith(color: c.textPrimary),
        child: valueWidget!,
      );
    } else if (value != null) {
      valueNode = DashStatValue(
        value: value!,
        format: format,
        label: label,
        sizes: dense ? DashStatValue.denseSizes : DashStatValue.regularSizes,
      );
    } else {
      valueNode = MadarClippedText(
        valueText ?? '—',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: DashType.statFigure(
          dense ? 18 : 24,
        ).copyWith(color: c.textPrimary),
      );
    }
    final up = (trend ?? 0) >= 0;
    final trendTone = up ? DashTone.success : DashTone.danger;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: gap,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Space.card),
          child: Row(
            spacing: Space.sm,
            children: [
              if (icon != null)
                DashIcon(icon!, size: IconSize.sm, color: glyphColor),
              Expanded(
                child: MadarClippedText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.meta.copyWith(
                    color: c.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ?action,
            ],
          ),
        ),
        SizedBox(
          height: valueSlot,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: valueNode,
          ),
        ),
        if (trend == null && hint == null && reserveFooter)
          const SizedBox(height: footerHeight),
        if (trend != null || hint != null)
          SizedBox(
            height: footerHeight,
            child: Row(
              spacing: Space.sm,
              children: [
                if (trend != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.xs + DashMetrics.hair,
                      vertical: DashMetrics.hair,
                    ),
                    decoration: BoxDecoration(
                      color: trendTone.wash(c),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: DashMetrics.hair,
                      children: [
                        DashIcon(
                          up ? 'arrow-up-right' : 'arrow-down-right',
                          size: 12,
                          color: trendTone.foreground(c),
                        ),
                        Text(
                          dashFigure(f.percent(trend!.abs())),
                          style: DashType.smallMedium.copyWith(
                            color: trendTone.foreground(c),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (hint != null)
                  Expanded(
                    child: MadarClippedText(
                      hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    return DashCard(
      padding: pad,
      onTap: onTap,
      semanticLabel: label,
      child: body,
    );
  }
}

/// One KPI of a [DashLedgerStrip].
@immutable
class DashLedgerItem {
  const DashLedgerItem({
    required this.key,
    required this.label,
    this.value,
    this.valueText,
    this.valueWidget,
    this.format,
    this.icon,
    this.tone = DashTone.neutral,
    this.trend,
    this.hint,
    this.loading = false,
    this.action,
  });

  final String key;
  final String label;
  final num? value;
  final String? valueText;
  final Widget? valueWidget;
  final DashStatFormat? format;
  final String? icon;
  final DashTone tone;
  final double? trend;
  final String? hint;
  final bool loading;
  final Widget? action;
}

/// A row of KPIs (the web's `LedgerStrip`): a responsive grid of
/// [DashStatCard]s — two up on a phone, then by count (4 → 2·4, 5 → 3·5,
/// 6 → 3·6) — every card in a row the same height. Dense from five items.
class DashLedgerStrip extends StatelessWidget {
  const DashLedgerStrip({required this.items, this.dense, super.key});
  final List<DashLedgerItem> items;
  final bool? dense;

  int _columns(double width) {
    final n = items.length;
    if (width < DashBreakpoints.sm) return math.min(2, n);
    final lg = width >= DashBreakpoints.lg - Space.xxl * 4;
    return switch (n) {
      1 => 1,
      2 => 2,
      3 => 3,
      4 => lg ? 4 : 2,
      5 => lg ? 5 : 3,
      6 => lg ? 6 : 3,
      _ => lg ? 4 : 2,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDense = dense ?? items.length >= 5;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = _columns(constraints.maxWidth);
        final gap = constraints.maxWidth >= DashBreakpoints.sm
            ? Space.lg
            : Space.md;
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += cols) {
          final slice = items.sublist(i, math.min(i + cols, items.length));
          final footer = slice.any((it) => it.trend != null || it.hint != null);
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: gap,
              children: [
                for (final it in slice)
                  Expanded(
                    child: DashStatCard(
                      key: ValueKey(it.key),
                      label: it.label,
                      value: it.value,
                      valueText: it.valueText,
                      valueWidget: it.valueWidget,
                      format: it.format,
                      icon: it.icon,
                      tone: it.tone,
                      trend: it.trend,
                      hint: it.hint,
                      loading: it.loading,
                      action: it.action,
                      dense: isDense,
                      reserveFooter: footer,
                    ),
                  ),
                for (var k = slice.length; k < cols; k++)
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: rows,
        );
      },
    );
  }
}

/// A value that shows its concise form on a phone (or when [forceCompact])
/// and reveals the full value on press; wide screens show the full value
/// (the web's `ConciseValue`).
class DashConciseValue extends StatelessWidget {
  const DashConciseValue({
    required this.full,
    this.compact,
    this.forceCompact = false,
    this.style,
    super.key,
  });
  final String full;
  final String? compact;
  final bool forceCompact;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final base = style ?? DefaultTextStyle.of(context).style;
    if ((!phone && !forceCompact) || compact == null) {
      return Text(full, style: base);
    }
    return DashPopover(
      width: DashMetrics.menu,
      anchor: (context, ctl) => DashPressable(
        onTap: ctl.toggle,
        pressScale: false,
        semanticLabel: full,
        excludeChildSemantics: true,
        builder: (context, s) => Text(
          compact!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: base.copyWith(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: c.textSecondary.withValues(alpha: 0.4),
          ),
        ),
      ),
      content: (context, ctl) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Text(
          full,
          style: DashType.bodyStrong.copyWith(color: c.textPrimary),
        ),
      ),
    );
  }
}

/// A figure that cross-fades and lifts a quarter of its height when it
/// changes (220 ms, ease-out) — never counting through values in between.
/// Reduced motion swaps it in place (the web's `AnimatedFigure`).
class DashAnimatedFigure extends StatelessWidget {
  const DashAnimatedFigure(this.text, {this.style, super.key});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final reduced = DashMotion.reduced(context);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: reduced ? Duration.zero : DashMotion.base,
        switchInCurve: const Cubic(0, 0, 0.58, 1),
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, anim) {
          final incoming = child.key == ValueKey(text);
          if (!incoming) return FadeTransition(opacity: anim, child: child);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          );
        },
        child: Text(
          text,
          key: ValueKey(text),
          style: (style ?? DefaultTextStyle.of(context).style).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
