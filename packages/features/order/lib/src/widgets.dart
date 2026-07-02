/// Small shared pieces the order feature reuses across its panels — the
/// action button + text field (the natives' MadarButton / MadarTextField),
/// the accent-dot section title, and the RFC3339/category helpers.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

// Native metrics (OrderScreen.kt / Components.kt) that fall between the 4-pt
// Space steps — kept verbatim so the Flutter chrome measures identically.

/// Primary action button height (natives: 50.dp).
const double kActionButtonHeight = 50;

/// The item card's width/height ratio (natives: aspectRatio(0.94f)).
const double kMenuCardAspect = 0.94;

/// The wide layout's cart column width (natives: 340.dp).
const double kCartPanelWidth = 340;

/// Held-order chip height (natives: 46.dp).
const double kHeldChipHeight = 46;

/// Category tab strip height (natives: 46.dp).
const double kCategoryTabsHeight = 46;

/// Search field height (natives: 40.dp).
const double kSearchFieldHeight = 40;

/// Small square control (close / recipe / price badge, natives: 32–36.dp).
const double kSquareControl = 36;

/// Visual style of an [ActionButton].
enum ActionVariant {
  /// Accent-filled — the terminal action.
  filled,

  /// Hairline outline on surface — secondary.
  outline,

  /// Danger-filled — destructive confirm.
  danger,
}

/// The natives' MadarButton: a full-width tactile CTA with an optional
/// leading icon, a loading spinner, and a disabled (45%-alpha) state.
class ActionButton extends StatelessWidget {
  const ActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.loading = false,
    this.variant = ActionVariant.filled,
    this.tooltip,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final String? icon;
  final bool enabled;
  final bool loading;
  final ActionVariant variant;

  /// When set, wraps the button in a [Tooltip] (the disabled-checkout hint).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = enabled && !loading;
    final (Color bg, Color fg, Border? border) = switch (variant) {
      ActionVariant.filled => (colors.accent, colors.textOnAccent, null),
      ActionVariant.danger => (colors.danger, colors.textOnAccent, null),
      ActionVariant.outline => (
        colors.surface,
        colors.textPrimary,
        Border.all(color: colors.border),
      ),
    };

    Widget button = Container(
      height: kActionButtonHeight,
      decoration: BoxDecoration(
        color: active ? bg : bg.withValues(alpha: Opacities.disabled),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: border,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox.square(
              dimension: IconSize.md,
              child: CircularProgressIndicator(color: fg, strokeWidth: 2),
            )
          else if (icon != null)
            MadarIcon(icon, tint: fg, size: IconSize.lg),
          if (loading || icon != null) const SizedBox(width: Space.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.body.copyWith(
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );

    if (active) {
      button = TactileScale(
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: button,
      );
    }
    final tooltip = this.tooltip;
    if (tooltip != null) {
      button = Tooltip(message: tooltip, child: button);
    }
    return Semantics(button: true, enabled: active, child: button);
  }
}

/// The natives' MadarTextField: leading icon, muted placeholder, surface-alt
/// fill with a hairline border.
class OrderTextField extends StatelessWidget {
  const OrderTextField({
    required this.controller,
    required this.placeholder,
    this.icon,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? icon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      height: Metrics.inputHeight,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: colors.borderLight),
      ),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.md),
      child: Row(
        children: [
          if (icon != null) ...[
            MadarIcon(icon, tint: colors.textMuted),
            const SizedBox(width: Space.sm),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              cursorColor: colors.accent,
              style: MadarType.body.copyWith(color: colors.textPrimary),
              decoration: InputDecoration.collapsed(
                hintText: placeholder,
                hintStyle: MadarType.body.copyWith(color: colors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Accent-dot + bold uppercase section label (the natives' SectionTitle) —
/// SIZE / NOTES / OPTIONALS read with the same authority as the group cards.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
          child: const SizedBox.square(dimension: Space.sm),
        ),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.labelSm.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
              letterSpacing: MadarType.tracking,
            ),
          ),
        ),
      ],
    );
  }
}

/// `#RRGGBB` → opaque [Color]. Pairs with the core's CatStyleView hex fields.
Color hexColor(String hex) {
  final s = hex.replaceFirst('#', '');
  final value = int.tryParse(s, radix: 16) ?? 0;
  return Color(0xFF000000 | value);
}

/// Pull "HH:MM" out of an RFC3339 timestamp ("2026-07-01T14:32:07Z" → "14:32").
/// Falls back to the raw string if the shape is unexpected.
String formatHHMM(String rfc3339) {
  final index = rfc3339.indexOf('T');
  if (index < 0 || rfc3339.length < index + 6) return rfc3339;
  return rfc3339.substring(index + 1, index + 6);
}

/// Current instant as an RFC3339 UTC timestamp — the live-cart / New chip's
/// sort-key fallback when no recorded start time exists yet.
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// Local wall-clock "HH:MM" — the parked draft's display name on hold.
String nowHHMM() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(now.hour)}:${two(now.minute)}';
}

/// Local time as RFC3339 WITH a colon offset, so the core gates bundle
/// windows in the till's timezone (mirrors the natives' nowRfc3339()).
String nowRfc3339Local() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final oh = two(abs.inHours);
  final om = two(abs.inMinutes % 60);
  return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-'
      '${two(now.day)}T${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
      '$sign$oh:$om';
}

/// Core CatStyleView.icon key → shared icon-catalog name; null for the 'cafe'
/// default (custom category) → the caller shows text only (the monogram
/// carries the identity on the card itself).
String? categoryIconName(String key) => switch (key) {
  'coffee' ||
  'mocha' ||
  'tea' ||
  'bakery' ||
  'lunch' ||
  'icecream' ||
  'drink' ||
  'water' ||
  'ice' ||
  'matcha' => 'cat.$key',
  _ => null,
};

/// Up to two initials from the item name (the natives' monogram rule).
String monogram(String name) {
  final words = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList(growable: false);
  if (words.length >= 2) {
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }
  if (words.isNotEmpty) {
    final w = words[0];
    return w.substring(0, w.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '•';
}
