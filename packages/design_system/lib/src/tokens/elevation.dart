import 'package:design_system/src/tokens/colors.dart';
import 'package:flutter/widgets.dart';

/// Depth in a flat system.
///
/// The canvas draws no gradients and no glows; a card is a border, not a
/// shadow. Only two things cast one: a segment's thumb (a 1px lift, so it
/// reads as sitting ON the track) and a modal (a deep soft shadow, so it
/// reads as floating OVER the page). The other levels exist so that call
/// sites written against the old kit keep compiling; they draw nothing.
enum MadarElevation {
  none,

  /// A card. Flat — the border does the work. Draws nothing.
  card,

  /// A modal, a floating done-card, a toast.
  raised,

  /// Legacy: the old primary-button halo. Draws nothing; glows are gone.
  glow,

  /// A segmented control's selected thumb.
  thumb,
}

extension MadarElevationX on MadarElevation {
  /// Shadow list for this level. [dark] deepens the alpha so the lift still
  /// reads on a dark ground.
  List<BoxShadow> shadows(MadarColors colors, {required bool dark}) {
    switch (this) {
      case MadarElevation.none:
      case MadarElevation.card:
      case MadarElevation.glow:
        return const [];
      case MadarElevation.raised:
        return [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: dark ? 0.6 : 0.35),
            blurRadius: 60,
            offset: const Offset(0, 24),
          ),
        ];
      case MadarElevation.thumb:
        return [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: dark ? 0.3 : 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ];
    }
  }
}
