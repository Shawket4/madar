/// The chrome — the dark frame around the light work surface.
///
/// On a tablet: an 88px ink rail on the START edge (the brand mark at its
/// head, the tabs, the signed-in person at its foot) and a 56px ink top bar
/// (branch · till, and the one outbox pill at the end). On a phone: the same
/// top bar as a status strip and the same tabs as a bottom bar. The tabs are
/// declared once as [MadarTab]s and both chromes draw them, so a badge means
/// the same thing at the same place on both devices.
///
/// The outbox pill is not decoration. It is the one place the till admits
/// what it has not yet told the server, and it is on every screen of every
/// shell: [OutboxState] says how (queued, offline, stuck), the caller says
/// how many and in what words.
library;

import 'package:design_system/src/glyphs.dart';
import 'package:design_system/src/responsive.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/material.dart';

/// A rail tab's corner and the badge's inset from its corner.
const double _railTabRadius = 14;
const double _badgeTop = 8;
const double _badgeEnd = 10;
const double _badgeSize = 20;

/// One destination in a shell: Sell, Floor, Queue, Till — or Floor, Bills,
/// Me. The label arrives localised; the glyph is the outline that fills
/// when the tab is active.
@immutable
class MadarTab {
  const MadarTab({
    required this.label,
    required this.glyph,
    this.badge = 0,
    this.key,
  });

  final String label;
  final MadarGlyph glyph;

  /// Things waiting behind this tab. Zero draws nothing.
  final int badge;

  /// For tests and analytics; not shown.
  final String? key;
}

/// Who is signed in, for the foot of the rail and the phone's status strip.
@immutable
class MadarPerson {
  const MadarPerson({
    required this.name,
    required this.initial,
    this.online = true,
  });

  final String name;

  /// One character for the disc.
  final String initial;

  /// Draws a green ring when true; a dashed muted one when false.
  final bool online;
}

/// The rail tab, exposed on its own for a screen that composes its own
/// chrome. 72 × 68, 14px corners; active fills with the raised ink, turns
/// the word white and the glyph duotone.
class MadarRailTab extends StatelessWidget {
  const MadarRailTab({
    required this.tab,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final MadarTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = selected ? Colors.white : colors.onChromeMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: TactileScale(
        onTap: onTap,
        child: Container(
          width: Metrics.railTabWidth,
          height: Metrics.railTabHeight,
          decoration: BoxDecoration(
            color: selected ? colors.chromeRaised : null,
            borderRadius: BorderRadius.circular(_railTabRadius),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 5,
                  children: [
                    MadarGlyphIcon(
                      tab.glyph,
                      size: IconSize.xxl,
                      color: fg,
                      filled: selected,
                    ),
                    Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
              if (tab.badge > 0)
                PositionedDirectional(
                  top: _badgeTop,
                  end: _badgeEnd,
                  child: MadarBadge(count: tab.badge),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The amber count disc on a tab. Mono, LTR.
class MadarBadge extends StatelessWidget {
  const MadarBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // No `alignment:` on the Container — under loose constraints (a Wrap, a
    // Stack) that would expand the disc to the full width. The Row centres.
    return Container(
      constraints: const BoxConstraints(minWidth: _badgeSize),
      height: _badgeSize,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.warning,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$count',
            textDirection: TextDirection.ltr,
            style: MadarType.num.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// The signed-in person's disc: 40, raised ink, a 2px ring that is green
/// when the till can reach the server and dashed muted when it cannot.
class MadarAvatar extends StatelessWidget {
  const MadarAvatar({
    required this.person,
    this.size = Metrics.avatar,
    super.key,
  });

  final MadarPerson person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return CustomPaint(
      foregroundPainter: _RingPainter(
        color: person.online ? colors.success : colors.textMuted,
        dashed: !person.online,
      ),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.chromeRaised,
          shape: BoxShape.circle,
        ),
        child: Text(
          person.initial,
          style: MadarType.title.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
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
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    final rect = Offset.zero & size;
    final ring = Path()..addOval(rect.deflate(1));
    if (!dashed) {
      canvas.drawPath(ring, paint);
      return;
    }
    for (final metric in ring.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + 5).clamp(0, metric.length)),
          paint,
        );
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.dashed != dashed;
}

/// THE rail: 88 wide on the start edge of a tablet.
class MadarRail extends StatelessWidget {
  const MadarRail({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    this.person,
    this.onPersonTap,
    this.onMarkTap,
    super.key,
  });

  final List<MadarTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Shown at the foot. Tapping it is the whole of "More" (language,
  /// settings, sign out).
  final MadarPerson? person;
  final VoidCallback? onPersonTap;

  /// The brand mark at the head; tapping it is optional (a gallery, a spike).
  final VoidCallback? onMarkTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      width: Metrics.railWidth,
      color: colors.chrome,
      padding: EdgeInsetsDirectional.only(
        top: topInset + Space.lg,
        bottom: bottomInset + 18,
      ),
      child: Column(
        children: [
          _Mark(onTap: onMarkTap),
          const SizedBox(height: 14),
          for (var i = 0; i < tabs.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            MadarRailTab(
              tab: tabs[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
          ],
          const Spacer(),
          if (person != null)
            _Who(person: person!, onTap: onPersonTap, vertical: true),
        ],
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final mark = Container(
      width: Metrics.railMark,
      height: Metrics.railMark,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: const MadarGlyphIcon(
        MadarGlyph.mark,
        size: IconSize.xxl,
        color: Colors.white,
      ),
    );
    if (onTap == null) return ExcludeSemantics(child: mark);
    return TactileScale(onTap: onTap, child: mark);
  }
}

class _Who extends StatelessWidget {
  const _Who({required this.person, required this.vertical, this.onTap});

  final MadarPerson person;
  final bool vertical;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final name = Text(
      person.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (vertical ? MadarType.labelSm : MadarType.body).copyWith(
        fontWeight: FontWeight.w600,
        color: vertical ? colors.onChromeMuted : colors.onChrome,
      ),
    );
    final who = vertical
        ? SizedBox(
            width: Metrics.railTabWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                MadarAvatar(person: person),
                name,
              ],
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              MadarAvatar(person: person, size: 28),
              Flexible(child: name),
            ],
          );
    return Semantics(
      button: onTap != null,
      label: person.name,
      child: TactileScale(onTap: onTap, child: who),
    );
  }
}

/// The phone's bottom tab bar: the same tabs, ink, above the home indicator.
class MadarTabBar extends StatelessWidget {
  const MadarTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  final List<MadarTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      color: colors.chrome,
      padding: EdgeInsetsDirectional.only(
        top: Space.sm,
        bottom: bottomInset + Space.sm,
        start: Space.sm,
        end: Space.sm,
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _BarTab(
                tab: tabs[i],
                selected: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarTab extends StatelessWidget {
  const _BarTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final MadarTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = selected ? Colors.white : colors.onChromeMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          MadarHaptics.selection();
          onTap();
        },
        child: Container(
          height: Metrics.tabBarHeight - Space.lg,
          decoration: BoxDecoration(
            color: selected ? colors.chromeRaised : null,
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 3,
                children: [
                  MadarGlyphIcon(
                    tab.glyph,
                    size: IconSize.xl,
                    color: fg,
                    filled: selected,
                  ),
                  Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MadarType.labelSm.copyWith(color: fg),
                  ),
                ],
              ),
              if (tab.badge > 0)
                PositionedDirectional(
                  top: 2,
                  end: Space.md,
                  child: MadarBadge(count: tab.badge),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the outbox has to say.
enum OutboxState {
  /// Nothing waiting and the server is reachable. The pill is quiet.
  synced,

  /// Work is queued and will go when it can. Nothing is wrong.
  queued,

  /// The server cannot be reached; [queued] work is waiting. Amber: a
  /// supported mode, not an error.
  offline,

  /// The server said no and the operation is dead until someone acts. Red.
  stuck,
}

/// THE outbox pill: 32 tall at the end of the top bar. Glyph + count + word.
/// The word arrives localised ("queued", "Offline", "stuck"); the count is
/// mono and LTR. Tapping it opens Sync.
class MadarOutboxPill extends StatelessWidget {
  const MadarOutboxPill({
    required this.state,
    required this.label,
    this.count = 0,
    this.onTap,
    super.key,
  });

  final OutboxState state;

  /// The state word, already localised.
  final String label;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final (
      Color fill,
      Color fg,
      Color glyphColor,
      MadarGlyph glyph,
    ) = switch (state) {
      OutboxState.synced => (
        colors.chromeRaised,
        colors.onChromeMuted,
        colors.onChromeMuted,
        MadarGlyph.wifi,
      ),
      OutboxState.queued => (
        colors.chromeRaised,
        Colors.white,
        colors.accent,
        MadarGlyph.half,
      ),
      OutboxState.offline => (
        colors.warning,
        Colors.white,
        Colors.white,
        MadarGlyph.wifiOff,
      ),
      OutboxState.stuck => (
        colors.danger,
        Colors.white,
        Colors.white,
        MadarGlyph.xCircle,
      ),
    };
    final pill = Container(
      height: Metrics.pillHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          MadarGlyphIcon(glyph, size: IconSize.sm, color: glyphColor),
          if (count > 0)
            Text(
              '$count',
              textDirection: TextDirection.ltr,
              style: MadarType.num.copyWith(
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          Text(
            label,
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          if (state == OutboxState.queued)
            MadarGlyphIcon(
              MadarGlyph.arrowUp,
              size: IconSize.xs,
              color: colors.onChromeMuted,
            ),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: '$count $label',
      child: TactileScale(onTap: onTap, child: pill),
    );
  }
}

/// THE top bar: 56 of ink. Branch · till at the start, the outbox pill at
/// the end. On a phone it is the status strip — person · branch · pill, the
/// till dropped for room — and the person ([person], tappable for the More
/// sheet) stands in for the rail foot.
///
/// Paints up under the status bar; do not wrap it in a SafeArea.
class MadarTopBar extends StatelessWidget {
  const MadarTopBar({
    required this.title,
    this.subtitle,
    this.pill,
    this.person,
    this.onPersonTap,
    this.actions = const [],
    super.key,
  });

  /// The branch.
  final String title;

  /// The till, when there is more than one.
  final String? subtitle;

  /// The outbox pill.
  final MadarOutboxPill? pill;

  /// Shown at the start on a phone (the rail shows it on a tablet).
  final MadarPerson? person;
  final VoidCallback? onPersonTap;

  /// Anything else at the end, before the pill — rare.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final layout = MadarLayout.of(context);
    final showPerson = person != null && layout.isPhone;
    return Container(
      color: colors.chrome,
      padding: EdgeInsetsDirectional.only(
        top: topInset,
        start: layout.gutter,
        end: layout.gutter,
      ),
      child: SizedBox(
        height: Metrics.topBarHeight,
        child: Row(
          spacing: Space.md,
          children: [
            if (showPerson) ...[
              // Capped, so a long name cannot push the branch off the strip.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: _Who(
                  person: person!,
                  vertical: false,
                  onTap: onPersonTap,
                ),
              ),
              Text(
                '·',
                style: MadarType.body.copyWith(color: colors.onChromeMuted),
              ),
            ],
            // The branch takes what is left and pushes the pill to the end;
            // a second Flexible beside it would halve its share.
            Expanded(
              child: Row(
                spacing: Space.md,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.onChrome,
                      ),
                    ),
                  ),
                  if (subtitle != null && layout.isTablet) ...[
                    Text(
                      '·',
                      style: MadarType.body.copyWith(
                        color: colors.onChromeMuted,
                      ),
                    ),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.body.copyWith(
                        color: colors.onChromeMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ...actions,
            ?pill,
          ],
        ),
      ),
    );
  }
}

/// THE shell scaffold: rail + top bar + body on a tablet; top bar + body + bottom
/// tabs on a phone. One widget, so every shell (waiter, teller, manager)
/// flips at the same [MadarLayout] line and lays its chrome out the same
/// way. The body is the light work surface; it owns its own page padding.
class MadarShellScaffold extends StatelessWidget {
  const MadarShellScaffold({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelect,
    required this.topBar,
    required this.body,
    this.person,
    this.onPersonTap,
    this.onMarkTap,
    super.key,
  });

  final List<MadarTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Built without [MadarTopBar.person]; the shell supplies it where the
  /// device needs it.
  final MadarTopBar topBar;
  final Widget body;
  final MadarPerson? person;
  final VoidCallback? onPersonTap;
  final VoidCallback? onMarkTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final layout = MadarLayout.of(context);
    final bar = MadarTopBar(
      title: topBar.title,
      subtitle: topBar.subtitle,
      pill: topBar.pill,
      actions: topBar.actions,
      person: layout.isPhone ? person : null,
      onPersonTap: onPersonTap,
    );
    final surface = ColoredBox(color: colors.bg, child: body);
    if (layout.usesRail) {
      return ColoredBox(
        color: colors.chrome,
        child: Row(
          textDirection: Directionality.of(context),
          children: [
            MadarRail(
              tabs: tabs,
              selectedIndex: selectedIndex,
              onSelect: onSelect,
              person: person,
              onPersonTap: onPersonTap,
              onMarkTap: onMarkTap,
            ),
            Expanded(
              child: Column(
                children: [
                  bar,
                  Expanded(child: surface),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: colors.chrome,
      child: Column(
        children: [
          bar,
          Expanded(child: surface),
          MadarTabBar(
            tabs: tabs,
            selectedIndex: selectedIndex,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}
