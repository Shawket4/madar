/// One readiness check as a row (web `check-row.tsx`): its state mark, what
/// it is, what's wrong in one line, one button to the page that fixes it,
/// and the named things it found, each opening its own editor. State is
/// never colour alone: a tick, an open ring or a dashed ring, each named for
/// a screen reader.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart'
    show CheckLevel, ReadinessCheck, ReadinessProblem;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'checks.dart';

class CheckRow extends ConsumerStatefulWidget {
  const CheckRow({required this.check, this.actions, super.key});

  final ReadinessCheck check;

  /// The fix when it starts here rather than on another page (the tablet's
  /// sheet, an empty menu's two starts); else the check's own page.
  final List<Widget>? actions;

  @override
  ConsumerState<CheckRow> createState() => _CheckRowState();
}

class _CheckRowState extends ConsumerState<CheckRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final check = widget.check;
    final def = checkDefs[check.key]!;
    final blocking = check.level == CheckLevel.blocking;
    // A branch's name is in the sentence already.
    final named =
        check.problems.isNotEmpty && !perBranchChecks.contains(check.key);

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DashMetrics.hair,
      children: [
        Text(
          t.checkTitle(check.key),
          style: DashType.bodyStrong.copyWith(
            color: check.ok ? c.textSecondary : c.textPrimary,
          ),
        ),
        Text(
          t.checkLine(check),
          style: DashType.meta.copyWith(color: c.textSecondary),
        ),
      ],
    );
    final actions = check.ok
        ? const <Widget>[]
        : [
            if (named)
              DashButton(
                label: _open ? t('setup.hideList') : t('setup.showList'),
                variant: DashButtonVariant.ghost,
                size: DashButtonSize.compact,
                trailingIcon: _open ? 'chevron-up' : 'chevron-down',
                onPressed: () => setState(() => _open = !_open),
              ),
            ...widget.actions ??
                [
                  DashButton(
                    label: t.checkAction(check.key),
                    variant: blocking
                        ? DashButtonVariant.primary
                        : DashButtonVariant.outline,
                    size: DashButtonSize.compact,
                    to: def.to,
                    onPressed: () => context.go(def.to),
                  ),
                ],
          ];
    // A zero-length AnimatedSize asserts: reduced motion shows it at once.
    final list = named && _open
        ? _ProblemList(check: check)
        : const SizedBox(width: double.infinity);
    final glyph = DashIcon(
      def.icon,
      size: IconSize.sm,
      color: check.ok ? c.textMuted : c.textPrimary,
    );

    return Container(
      key: ValueKey('check-${check.key}'),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(
          color: check.ok
              ? c.hairline
              : Color.lerp(c.hairline, c.textPrimary, blocking ? 0.12 : 0.05)!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: LayoutBuilder(
              builder: (context, box) {
                final lead = [
                  StateMark(check: check),
                  Padding(
                    padding: const EdgeInsets.only(top: DashMetrics.hair * 3),
                    child: glyph,
                  ),
                ];
                if (box.maxWidth >= 560) {
                  return Row(
                    spacing: Space.md,
                    children: [
                      ...lead,
                      Expanded(child: text),
                      if (actions.isNotEmpty)
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: actions,
                        ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.md,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.md,
                      children: [
                        ...lead,
                        Expanded(child: text),
                      ],
                    ),
                    if (actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: _markSize + Space.md,
                        ),
                        child: Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: actions,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (DashMotion.reduced(context))
            list
          else
            AnimatedSize(
              duration: DashMotion.base,
              curve: DashMotion.ease,
              alignment: AlignmentDirectional.topStart,
              child: list,
            ),
        ],
      ),
    );
  }
}

const double _markSize = 28;

/// The state mark: a tick (done), an open ring (to do before selling) or a
/// dashed ring (worth doing).
class StateMark extends ConsumerWidget {
  const StateMark({required this.check, super.key});
  final ReadinessCheck check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final blocking = check.level == CheckLevel.blocking;
    final label = check.ok
        ? t('setup.state.done')
        : blocking
        ? t('setup.state.todo')
        : t('setup.state.advice');
    final Widget mark;
    if (check.ok) {
      mark = Container(
        decoration: BoxDecoration(
          color: DashTone.success.wash(c),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: DashIcon(
          'check',
          size: IconSize.sm,
          color: DashTone.success.foreground(c),
        ),
      );
    } else {
      mark = CustomPaint(
        painter: _RingPainter(
          color: blocking ? c.warning : c.textMuted,
          dashed: !blocking,
        ),
      );
    }
    return Semantics(
      label: label,
      child: SizedBox.square(dimension: _markSize, child: mark),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.dashed});
  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = (Offset.zero & size).deflate(1);
    if (!dashed) {
      canvas.drawOval(rect, paint);
      return;
    }
    const dashes = 12;
    const sweep = math.pi * 2 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.dashed != dashed;
}

/// The named problems (at most 20, then "and N more"), each a link to its
/// own editor.
class _ProblemList extends ConsumerWidget {
  const _ProblemList({required this.check});
  final ReadinessCheck check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: const EdgeInsetsDirectional.only(
        start: Space.lg + _markSize + Space.md,
        end: Space.lg,
        top: Space.sm,
        bottom: Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in check.problems)
            _ProblemLink(key: ValueKey('problem-${p.entityId}'), problem: p),
          if (check.more > 0)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                t('setup.andMore', count: check.more),
                style: DashType.meta.copyWith(color: c.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProblemLink extends StatelessWidget {
  const _ProblemLink({required this.problem, super.key});
  final ReadinessProblem problem;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final to = problemRoute(problem);
    return DashPressable(
      semanticLabel: problem.name,
      isButton: false,
      pressScale: false,
      excludeChildSemantics: true,
      to: to,
      onTap: () => context.go(to),
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: Container(
            foregroundDecoration: dashFocusRing(
              context,
              s,
              BorderRadius.circular(Radii.xs / 2),
            ),
            child: MadarClippedText(
              problem.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.body.copyWith(
                color: c.textPrimary,
                decoration: TextDecoration.underline,
                decorationColor: s.highlighted ? c.textPrimary : c.border,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
