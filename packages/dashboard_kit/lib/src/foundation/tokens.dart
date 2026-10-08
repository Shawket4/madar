import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The dashboard's density on top of design_system — the web dashboard's
/// type ramp and geometry (14 body, 11 tracked table labels, 56 rows), every
/// value derived from a design_system token. Pages use these, never numbers.
abstract final class DashType {
  /// A page title: 28/700, tracked tight (24 on a phone).
  static final TextStyle pageTitle = MadarType.h1.copyWith(height: 1.15);
  static final TextStyle pageTitlePhone = MadarType.h1.copyWith(
    fontSize: MadarType.h2.fontSize! + 2,
    height: 1.15,
  );

  /// A pane title (a page embedded in a settings shell), a dialog title: 18/600.
  static final TextStyle paneTitle = MadarType.h3.copyWith(height: 1.25);

  /// A section's label, a card title: 16/600.
  static final TextStyle sectionTitle = MadarType.title.copyWith(height: 1.3);

  /// Body copy — the web's `text-sm`: 14/400.
  static final TextStyle body = MadarType.bodySm.copyWith(
    fontSize: MadarType.bodySm.fontSize! + 1,
    fontWeight: FontWeight.w400,
    height: 1.43,
  );

  /// Buttons, tabs, a label above a field: 14/500.
  static final TextStyle bodyMedium = body.copyWith(
    fontWeight: FontWeight.w500,
  );

  /// A row title: 14/600.
  static final TextStyle bodyStrong = body.copyWith(
    fontWeight: FontWeight.w600,
  );

  /// Meta and hints — the web's `text-[13px]`.
  static final TextStyle meta = MadarType.bodySm.copyWith(
    fontWeight: FontWeight.w400,
    height: 1.38,
  );

  /// The web's `text-xs`: 12/400.
  static final TextStyle small = MadarType.label.copyWith(
    fontWeight: FontWeight.w400,
    height: 1.33,
  );
  static final TextStyle smallMedium = small.copyWith(
    fontWeight: FontWeight.w500,
  );
  static final TextStyle smallStrong = small.copyWith(
    fontWeight: FontWeight.w600,
  );

  /// A table header: 11/600 uppercase, tracked .06em.
  static final TextStyle tableHeader = MadarType.labelSm.copyWith(
    letterSpacing: MadarType.labelSm.fontSize! * 0.06,
    height: 1.2,
  );

  /// Figures in a cell: Plex Mono 13, tabular.
  static final TextStyle mono = MadarType.num.copyWith(
    fontWeight: FontWeight.w400,
  );
  static final TextStyle monoMedium = MadarType.num.copyWith(
    fontWeight: FontWeight.w500,
  );
  static final TextStyle monoStrong = MadarType.num;

  /// A figure at [size] in the stat ladder (24 → 16), semibold mono.
  static TextStyle statFigure(double size) => MadarType.numXl.copyWith(
    fontSize: size,
    fontWeight: FontWeight.w600,
    letterSpacing: -size * 0.025,
    height: 1,
  );
}

/// Heights and widths the kit shares. Every control a finger or pointer hits
/// is at least [target] (44) tall: the dashboard is touch-first on tablets.
abstract final class DashMetrics {
  /// The finest step: the gap between a label and its figure, a pill's
  /// vertical inset.
  static const double hair = Space.xs / 2;

  /// The focus ring's width; a segment track's inset.
  static const double ring = 3;

  /// A prose line's cap (the web's `max-w-sm` / `max-w-prose`).
  static const double prose = 384;
  static const double proseWide = 640;

  /// The minimum hit target.
  static const double target = Metrics.buttonSmallHeight;

  /// A field, a button, a select trigger.
  static const double control = Metrics.buttonSmallHeight;

  /// A table's header row (the web's `h-11`).
  static const double tableHeader = Metrics.buttonSmallHeight;

  /// A table row (the web's `h-14`).
  static const double tableRow = Metrics.tableRowHeight;

  /// A list row's minimum height.
  static const double listRow = Metrics.tableRowHeight;

  /// The page header's title row (`h-12`).
  static const double headerRow = Metrics.headerHeight;

  /// A tab in a tab strip.
  static const double tab = Metrics.buttonSmallHeight;

  /// A status pill (`h-6` / `h-5`).
  static const double pill = Space.xl;
  static const double pillSmall = Space.lg + Space.xs;

  /// A progress bar's track (`h-1.5`).
  static const double progress = Space.xs + 2;

  /// A side panel's width on a wide screen.
  static const double sidePanel = 480;
  static const double sidePanelWide = 640;

  /// A dialog's widths (`sm:max-w-lg`, `sm:max-w-2xl`).
  static const double dialog = 512;
  static const double dialogWide = 672;

  /// A popover / dropdown's widths.
  static const double popover = 288;
  static const double menu = 224;

  /// The search box in a table toolbar (`sm:w-72`).
  static const double searchWidth = 288;

  /// The stat card glyph and the empty-state disc.
  static const double badgeDisc = 48;

  /// A single checkbox / radio box.
  static const double checkbox = Space.lg;

  /// The switch track.
  static const double switchWidth = 36;
  static const double switchHeight = 20;

  /// Width cap per page mode (the web's `max-w-[1600px]` / 880 / 560).
  static const double pageFull = 1600;
  static const double pageReading = 880;
  static const double pageForm = 560;
}

/// Where the dashboard changes shape.
abstract final class DashBreakpoints {
  /// Below this width: the phone layout (cards, full-screen panels, sheets).
  static const double phone = 760;

  /// The web's `sm` (640): two-column grids, header actions beside the title.
  static const double sm = 640;

  /// The web's `lg` (1024): four-up stat strips, wider gutters.
  static const double lg = 1024;

  /// The web's `xl` (1280).
  static const double xl = 1280;

  static bool isPhoneWidth(double width) => width < phone;

  /// True when the window is narrower than [phone].
  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < phone;

  /// The page gutter for a window [width]: 16 / 24 / 32.
  static double gutter(double width) => width >= lg
      ? Space.xxl
      : width >= sm
      ? Space.xl
      : Space.lg;
}

/// A meaning a colour carries: the web's six tones.
enum DashTone { neutral, accent, success, warning, danger, info }

extension DashToneColors on DashTone {
  /// Text and glyph colour on the tone's wash — the tone pulled toward the
  /// foreground so it clears AA in both themes (the web's 60% colour-mix).
  Color foreground(MadarColors c) => switch (this) {
    DashTone.neutral => c.textSecondary,
    DashTone.accent => c.textPrimary,
    DashTone.success => Color.lerp(c.success, c.textPrimary, 0.4)!,
    DashTone.warning => Color.lerp(c.warning, c.textPrimary, 0.45)!,
    DashTone.danger => Color.lerp(c.danger, c.textPrimary, 0.4)!,
    DashTone.info => Color.lerp(c.info, c.textPrimary, 0.4)!,
  };

  /// The wash behind it.
  Color wash(MadarColors c) => switch (this) {
    DashTone.neutral => c.surfaceAlt,
    DashTone.accent => c.accentBg,
    DashTone.success => c.successBg,
    DashTone.warning => c.warningBg,
    DashTone.danger => c.dangerBg,
    DashTone.info => c.infoBg,
  };

  /// The raw tone (a progress fill, a chart).
  Color solid(MadarColors c) => switch (this) {
    DashTone.neutral => c.textMuted,
    DashTone.accent => c.accent,
    DashTone.success => c.success,
    DashTone.warning => c.warning,
    DashTone.danger => c.danger,
    DashTone.info => c.info,
  };
}

/// Colours the web names that design_system spells differently.
extension DashColorsX on MadarColors {
  /// A card / popover face.
  Color get card => surface;

  /// The sunk grey of a track, a chip at rest.
  Color get muted => surfaceAlt;

  /// Hover wash (`bg-accent`).
  Color get hover => accentBg;

  /// A field's edge (`--input`).
  Color get input => border;

  /// A card's edge and a hairline (`--border`).
  Color get hairline => borderLight;

  /// The focus ring (`ring-ring/50`).
  Color get ring => accent.withValues(alpha: 0.35);

  /// Error text: readable red, not the raw token.
  Color get errorText => Color.lerp(danger, textPrimary, 0.25)!;

  /// Disabled text.
  Color get disabledText => textMuted;

  /// The scrim behind a dialog or panel (`bg-black/50`).
  Color get scrim => const Color(0xFF000000).withValues(alpha: Opacities.scrim);
}

/// The two shadows the flat system allows: a popover/menu lift and a modal.
abstract final class DashShadows {
  static List<BoxShadow> popover(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: const Color(0xFF000000).withValues(alpha: dark ? 0.45 : 0.12),
        blurRadius: Space.xl,
        offset: const Offset(0, Space.sm),
      ),
    ];
  }

  /// The web's `shadow-lg`: a soft lift, darker on a dark ground.
  static List<BoxShadow> modal(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = const Color(0xFF000000);
    return [
      BoxShadow(
        color: ink.withValues(alpha: dark ? 0.5 : 0.1),
        blurRadius: Space.lg - 1,
        spreadRadius: -3,
        offset: const Offset(0, Space.sm + 2),
      ),
      BoxShadow(
        color: ink.withValues(alpha: dark ? 0.4 : 0.1),
        blurRadius: Space.sm - 2,
        spreadRadius: -4,
        offset: const Offset(0, Space.xs),
      ),
    ];
  }
}

/// Durations of the dashboard's motion (the web's 160 / 220 / 320 ms).
abstract final class DashMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = MotionSpec.standardDuration;
  static const Duration slow = Duration(milliseconds: 320);

  /// KPI count-ups and chart draws finish together.
  static const Duration count = Duration(milliseconds: 1100);

  /// ease-out-quart.
  static const Curve ease = Cubic(0.25, 1, 0.5, 1);

  /// Reduced motion asked for by the platform.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero under reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
