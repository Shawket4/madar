/// Small shared pieces the checkout feature reuses across its sheets — the
/// action button + text field (the natives' MadarButton / MadarTextField),
/// the tender's uppercase section label, the hero amount field, and the
/// payment-glyph/hex helpers. Mirrors the order/shift packages' widget kits
/// so the checkout chrome measures identically to the Kotlin/Swift natives.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

// Native metrics (TenderScreen.kt / Components.kt) that fall between the
// 4-pt Space steps — kept verbatim so the Flutter chrome measures
// identically.

/// Primary action button height (natives: 50.dp).
const double kActionButtonHeight = 50;

/// Section-label font size (natives: 12.sp bold uppercase).
const double kSectionLabelSize = 12;

/// Visual style of an [ActionButton].
enum ActionVariant {
  /// Accent-filled — the terminal action.
  filled,

  /// Hairline outline on surface — secondary (the reprint button).
  outline,
}

/// The natives' MadarButton: a full-width tactile CTA with an optional
/// leading icon, a loading spinner, and a disabled (45%-alpha) state.
/// Convention copy of the order package's ActionButton (its widget kit is
/// package-internal).
class ActionButton extends StatelessWidget {
  const ActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.loading = false,
    this.variant = ActionVariant.filled,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final String? icon;
  final bool enabled;
  final bool loading;
  final ActionVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = enabled && !loading;
    final (Color bg, Color fg, Border? border) = switch (variant) {
      ActionVariant.filled => (colors.accent, colors.textOnAccent, null),
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
    return Semantics(button: true, enabled: active, child: button);
  }
}

/// The natives' MadarTextField: leading icon, muted placeholder, surface-alt
/// fill with a hairline border (the tender's customer/notes capture).
class CheckoutTextField extends StatelessWidget {
  const CheckoutTextField({
    required this.controller,
    required this.placeholder,
    this.icon,
    super.key,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? icon;

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

/// The tender's section label — small uppercase muted heading (the natives'
/// SectionLabel in TenderScreen.kt; plain, no accent dot).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: MadarType.label.copyWith(
        fontSize: kSectionLabelSize,
        fontWeight: FontWeight.w700,
        color: context.madarColors.textMuted,
      ),
    );
  }
}

/// The natives' `AmountField`: one contained hero row — a muted currency
/// prefix, then the big tabular amount at [Metrics.amountFieldHeight].
/// External prefills (quick-cash chips writing the tendered amount) update
/// the text only when they differ from the last value the teller emitted,
/// so the count is never clobbered mid-typing. Convention copy of the shift
/// package's AmountField (its control kit is package-internal).
class AmountField extends StatefulWidget {
  const AmountField({
    required this.amountMinor,
    required this.onAmountMinor,
    required this.currencyCode,
    super.key,
  });

  final int amountMinor;
  final ValueChanged<int> onAmountMinor;
  final String currencyCode;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.amountMinor == 0 ? '' : _minorToText(widget.amountMinor),
  );
  final FocusNode _focus = FocusNode();
  late int _lastEmitted = widget.amountMinor;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amountMinor != _lastEmitted) {
      _controller.text = widget.amountMinor == 0
          ? ''
          : _minorToText(widget.amountMinor);
      _lastEmitted = widget.amountMinor;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String value) {
    final minor = _toMinor(value);
    _lastEmitted = minor;
    widget.onAmountMinor(minor);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      height: Metrics.amountFieldHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: _focused ? colors.accent : colors.border,
          width: _focused ? 2 : 1,
        ),
      ),
      child: Row(
        spacing: Space.sm,
        children: [
          Text(
            widget.currencyCode.toUpperCase(),
            style: MadarType.title.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              onChanged: _changed,
              cursorColor: colors.accent,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: MadarType.moneyLg.copyWith(color: colors.textPrimary),
              decoration: InputDecoration.collapsed(
                hintText: '0.00',
                hintStyle: MadarType.moneyLg.copyWith(color: colors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parse a major-unit decimal string ("500", "499.50") → minor units.
int _toMinor(String s) {
  final cleaned = String.fromCharCodes(
    s.codeUnits.where((u) => (u >= 0x30 && u <= 0x39) || u == 0x2E),
  );
  final major = double.tryParse(cleaned) ?? 0;
  return (major * 100).round();
}

/// Minor units → the editable major-unit text ("12.50", whole "12").
String _minorToText(int minor) {
  if (minor % 100 == 0) return '${minor ~/ 100}';
  return (minor / 100).toStringAsFixed(2);
}

/// `#RRGGBB` → opaque [Color]. Pairs with PaymentMethodView's brand hex.
Color hexColor(String hex) {
  final s = hex.replaceFirst('#', '');
  final value = int.tryParse(s, radix: 16) ?? 0;
  return Color(0xFF000000 | value);
}

/// Map a backend payment-icon token to a shared icon-catalog glyph —
/// mirrors the natives' payGlyph / the Swift PayChip.symbol() mapping.
String payGlyph(String icon) => switch (icon.toLowerCase()) {
  'money' || 'cash' || 'banknote' => 'banknote',
  'credit_card' ||
  'card' ||
  'creditcard' ||
  'visa' ||
  'mastercard' ||
  'debit' => 'creditcard',
  'wallet' || 'ewallet' || 'e_wallet' => 'wallet',
  'pie_chart' => 'chart.pie',
  'delivery' => 'bicycle',
  'qr_code' || 'qr' => 'qrcode',
  'bank' || 'transfer' || 'bank_transfer' => 'bank',
  'gift_card' => 'gift',
  'smartphone' || 'phone' || 'mobile' || 'vodafone' || 'instapay' => 'iphone',
  'receipt' => 'receipt',
  'store' => 'storefront',
  'star' => 'star',
  'link' => 'link',
  _ => 'banknote',
};

/// A 1-px hairline rule in the theme border color — the sticky header /
/// footer separators.
class Hairline extends StatelessWidget {
  const Hairline({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.madarColors.border);
  }
}
