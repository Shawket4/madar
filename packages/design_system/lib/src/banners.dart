import 'package:design_system/src/icons.dart';
import 'package:design_system/src/toast.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:design_system/src/touch.dart';
import 'package:flutter/widgets.dart';

// Native banner/chip metrics (Components.kt NoticeBanner / StatusChip) that
// fall between the 4-pt Space steps — kept verbatim so the Flutter chrome
// measures identically to the Kotlin/Swift natives.

/// Banner horizontal inset (natives: 14.dp).
const double _bannerHPad = 14;

/// Gap between the banner's icon, message, and trailing slot (natives: 10.dp).
const double _bannerGap = 10;

/// Chip / action-pill horizontal inset (natives: 10.dp).
const double _pillHPad = 10;

/// Chip / action-pill vertical inset (natives: 5.dp).
const double _pillVPad = 5;

/// Gap between a chip's icon/dot and its label (natives: 5.dp).
const double _chipGap = 5;

/// Diameter of the chip's signature tone dot (natives: 6.dp).
const double _chipDot = 6;

/// Tone → background tint (the `*Bg` roles) — the natives' `ChipTone.bg`.
Color _toneBg(ChipTone tone, MadarColors colors) => switch (tone) {
  ChipTone.info => colors.navyBg,
  ChipTone.accent => colors.accentBg,
  ChipTone.success => colors.successBg,
  ChipTone.warning => colors.warningBg,
  ChipTone.danger => colors.dangerBg,
  ChipTone.neutral => colors.surfaceAlt,
};

/// A full-width inline notice — offline / auth-paused / clock-skew / error
/// chrome and the KDS reconnecting strip. Mirrors the natives' `NoticeBanner`
/// (Components.kt): tone-tinted rounded row with a hairline tone border, an
/// optional leading icon, and an optional [trailing] slot (typically a
/// [BannerActionPill]).
///
/// When [onTap] is set the whole banner is pressable (spring press-scale +
/// haptic) — the natives' tappable `AuthPausedBanner`:
///
/// ```dart
/// NoticeBanner(
///   text: t('chrome.auth_paused'),
///   tone: ChipTone.danger,
///   icon: 'lock',
///   onTap: showReauth,
///   trailing: BannerActionPill(label: t('chrome.auth_paused_action')),
/// )
/// ```
class NoticeBanner extends StatelessWidget {
  /// Creates a tone-tinted notice banner.
  const NoticeBanner({
    required this.text,
    this.tone = ChipTone.warning,
    this.icon,
    this.onTap,
    this.trailing,
    super.key,
  });

  /// The message. Takes all remaining width so short messages never wrap
  /// prematurely (the natives' banner-wrap fix).
  final String text;

  /// Semantic tone — drives the background tint, border, icon, and text.
  final ChipTone tone;

  /// Optional leading [MadarIcon] name (e.g. `'wifi.slash'`, `'lock'`).
  final String? icon;

  /// Makes the whole banner pressable (e.g. auth-paused → re-auth sheet).
  final VoidCallback? onTap;

  /// Optional trailing slot, end-aligned — typically a [BannerActionPill]
  /// signalling that the banner is tappable.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = tone.resolve(colors);

    final banner = DecoratedBox(
      decoration: BoxDecoration(
        color: _toneBg(tone, colors),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: fg.withValues(alpha: Opacities.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _bannerHPad,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              MadarIcon(icon, tint: fg),
              const SizedBox(width: _bannerGap),
            ],
            Expanded(
              child: Text(
                text,
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: _bannerGap),
              trailing!,
            ],
          ],
        ),
      ),
    );

    final onTap = this.onTap;
    if (onTap == null) return banner;
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: banner,
      ),
    );
  }
}

/// The trailing call-to-action pill inside a tappable [NoticeBanner] —
/// accent-filled with a [MadarColors.textOnAccent] label and a forward
/// chevron (auto-mirrored in RTL by [MadarIcon]).
///
/// Purely decorative: the tap target is the whole banner ([NoticeBanner.onTap]),
/// matching the natives' `AuthPausedBanner`.
class BannerActionPill extends StatelessWidget {
  /// Creates the banner's call-to-action pill.
  const BannerActionPill({required this.label, super.key});

  /// Short imperative label (e.g. "Sign in").
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _pillHPad,
          vertical: _pillVPad,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: MadarType.label.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textOnAccent,
              ),
            ),
            const SizedBox(width: Space.xs),
            MadarIcon(
              'chevron.forward',
              tint: colors.textOnAccent,
              size: IconSize.xs,
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact tone-tinted pill — sync status, offline chip, count badges.
/// Mirrors the natives' `StatusChip` (Components.kt): pill with a hairline
/// tone border, a leading [MadarIcon] (or the signature tone dot when no
/// icon is given), and an 11-pt semibold label; optionally a trailing
/// solid-tone [badgeCount].
class StatusChip extends StatelessWidget {
  /// Creates a compact status pill.
  const StatusChip({
    required this.label,
    this.tone = ChipTone.neutral,
    this.icon,
    this.leading,
    this.badgeCount,
    super.key,
  });

  /// Single-line label; ellipsizes when cramped.
  final String label;

  /// Semantic tone — drives the tint, border, dot/icon, and label color.
  final ChipTone tone;

  /// Optional leading [MadarIcon] name; when null a tone dot is shown.
  final String? icon;

  /// Optional custom leading widget (e.g. an animated glyph) — wins over
  /// [icon] and the tone dot when given.
  final Widget? leading;

  /// Optional trailing count rendered as a solid tone badge (e.g. pending
  /// sync items). Hidden when null.
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = tone.resolve(colors);
    final bg = _toneBg(tone, colors);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(
          color: fg.withValues(alpha: Opacities.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _pillHPad,
          vertical: _pillVPad,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading case final leading?)
              leading
            else if (icon != null)
              MadarIcon(icon, tint: fg, size: IconSize.xs)
            else
              DecoratedBox(
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: _chipDot),
              ),
            const SizedBox(width: _chipGap),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.labelSm.copyWith(color: fg),
              ),
            ),
            if (badgeCount != null) ...[
              const SizedBox(width: _chipGap),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: fg,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                  child: Text(
                    '$badgeCount',
                    style: MadarType.labelSm.copyWith(color: bg),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
