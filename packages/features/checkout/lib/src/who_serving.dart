/// "Who's serving?" — the section at the top of the Charge sheet on a branch
/// that asks (`pick_teller_at_checkout`). Pure presentation: the core decides
/// who is listed and how ([TellerPick]: Focused or All); the sheet holds the
/// pick and keeps the tender locked until there is one.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// A person tile's height floor: a thumb under queue pressure.
const double _tileMinHeight = 56;

/// The tile hugs the name, within a band: wide enough not to read as a chip,
/// capped so one long name wraps to its own line rather than stretching the
/// row.
const double _tileMinWidth = 132;
const double _tileMaxWidth = 240;

/// The section: its title, the people, More / Fewer in Focused, and — until
/// someone is picked — why the tender is locked.
class WhoServing extends StatelessWidget {
  const WhoServing({
    required this.pick,
    required this.picked,
    required this.expanded,
    required this.onPick,
    required this.onToggleMore,
    required this.tr,
    super.key,
  });

  final TellerPick pick;

  /// The person picked in this sheet (a user id), or null.
  final String? picked;

  /// Focused: the rest are shown.
  final bool expanded;
  final ValueChanged<String> onPick;
  final VoidCallback onToggleMore;
  final String Function(String) tr;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final reduced = motionReduced(context);
    final focused = pick.mode == PickMode.focused;
    final duration = reduced ? Duration.zero : MotionSpec.standardDuration;

    Widget tile(PickPerson p, {required bool quiet}) => _PersonTile(
      person: p,
      selected: p.userId == picked,
      // A green ring says "on shift now" only where the core vouched for it.
      onShift: focused && !quiet,
      quiet: quiet,
      onTap: () {
        MadarHaptics.selection();
        onPick(p.userId);
      },
    );

    final more = pick.more;
    final people = Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in pick.primary) tile(p, quiet: false),
        if (focused && expanded)
          for (final p in more)
            // The rest arrive with a fade, under the row's own growth.
            TweenAnimationBuilder<double>(
              key: ValueKey('more-${p.userId}'),
              tween: Tween(begin: reduced ? 1 : 0, end: 1),
              duration: duration,
              curve: MotionSpec.standardCurve,
              builder: (_, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: tile(p, quiet: true),
            ),
        if (focused && more.isNotEmpty)
          _MoreChip(
            label: expanded
                ? tr('charge.pick_fewer')
                : tr(
                    'charge.pick_more',
                  ).replaceAll('{count}', '${more.length}'),
            expanded: expanded,
            onTap: onToggleMore,
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Text(
          tr('charge.who_serving'),
          style: MadarType.title.copyWith(color: colors.textPrimary),
        ),
        if (focused)
          Text(
            tr('charge.on_shift_now'),
            style: MadarType.labelSm.copyWith(color: colors.textSecondary),
          ),
        AnimatedSize(
          duration: duration,
          curve: MotionSpec.standardCurve,
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(width: double.infinity, child: people),
        ),
        if (picked == null)
          Row(
            spacing: Space.xs,
            children: [
              MadarGlyphIcon(
                MadarGlyph.lock,
                size: IconSize.sm,
                color: colors.textSecondary,
              ),
              Flexible(
                child: Text(
                  tr('charge.pick_hint'),
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// One person: their initials disc and name. Selected reads as the accent
/// tone AND a check — never colour alone.
class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.selected,
    required this.onShift,
    required this.quiet,
    required this.onTap,
  });

  final PickPerson person;
  final bool selected;

  /// Draws the disc's solid ring (on shift now); dashed otherwise.
  final bool onShift;

  /// One of the rest behind More: a quieter tone.
  final bool quiet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final reduced = motionReduced(context);
    final name = person.name.trim();
    final initial = name.isEmpty ? '·' : name.characters.first.toUpperCase();
    final fg = selected
        ? colors.textPrimary
        : quiet
        ? colors.textSecondary
        : colors.textPrimary;
    return Semantics(
      key: ValueKey('teller-pick-${person.userId}'),
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: TactileScale(
        haptic: false,
        onTap: onTap,
        child: AnimatedContainer(
          duration: reduced ? Duration.zero : MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          constraints: const BoxConstraints(
            minHeight: _tileMinHeight,
            minWidth: _tileMinWidth,
            maxWidth: _tileMaxWidth,
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.sm,
            Space.sm,
            Space.md,
            Space.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.accentBg
                : quiet
                ? colors.surface
                : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
              color: selected
                  ? colors.accent
                  : quiet
                  ? colors.borderLight
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              Opacity(
                opacity: quiet && !selected ? 0.7 : 1,
                child: MadarAvatar(
                  person: MadarPerson(
                    name: name,
                    initial: initial,
                    online: onShift,
                  ),
                ),
              ),
              Flexible(
                child: MadarClippedText(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.button.copyWith(color: fg),
                ),
              ),
              if (selected)
                MadarGlyphIcon(
                  MadarGlyph.checkCircle,
                  size: IconSize.md,
                  color: colors.accent,
                  filled: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "+3 more" / "Fewer": the rest of the people who can ring sales, in
/// Focused. Says which way it goes with its chevron.
class _MoreChip extends StatelessWidget {
  const _MoreChip({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      button: true,
      expanded: expanded,
      child: TactileScale(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: _tileMinHeight),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(color: colors.borderLight),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              Text(
                label,
                style: MadarType.buttonSm.copyWith(color: colors.textPrimary),
              ),
              MadarGlyphIcon(
                expanded ? MadarGlyph.chevronUp : MadarGlyph.chevronDown,
                size: IconSize.sm,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
