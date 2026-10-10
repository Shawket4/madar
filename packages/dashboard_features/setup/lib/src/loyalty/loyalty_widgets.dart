/// The shapes every setting on the loyalty screens takes (the web's
/// `program/fields.tsx`): a titled group, a labelled switch with its reason,
/// a labelled input whose error REPLACES its hint (SET-LOY-083), plus the
/// card and the quiet notes the panes share.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A loyalty card (`Card > CardContent p-5 space-y-5`).
class LoyaltyCard extends StatelessWidget {
  const LoyaltyCard({
    required this.children,
    this.spacing = Space.card,
    this.padding = const EdgeInsets.all(Space.card),
    super.key,
  });

  final List<Widget> children;
  final double spacing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => DashCard(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: spacing,
      children: children,
    ),
  );
}

/// `Group`: a 16/600 title and its muted hint over related settings.
class LoyaltyGroup extends StatelessWidget {
  const LoyaltyGroup({
    required this.title,
    required this.child,
    this.hint,
    super.key,
  });

  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: DashType.sectionTitle.copyWith(color: c.textPrimary),
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
          ],
        ),
        child,
      ],
    );
  }
}

/// `ToggleRow`: the name (bold, or small and muted when [subdued]), why you
/// would want it, the switch. [onChanged] null = read-only. The whole row
/// toggles (a 44-pt target).
class LoyaltyToggle extends StatelessWidget {
  const LoyaltyToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.subdued = false,
    super.key,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final enabled = onChanged != null;
    return DashPressable(
      onTap: enabled ? () => onChanged!(!value) : null,
      enabled: enabled,
      isButton: false,
      checked: value,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Row(
        spacing: Space.lg,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: subdued
                      ? DashType.small.copyWith(color: c.textSecondary)
                      : DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
                if (hint != null)
                  Text(
                    hint!,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
          IgnorePointer(
            child: DashSwitch(
              value: value,
              onChanged: onChanged,
              semanticLabel: label,
              enabled: enabled,
            ),
          ),
        ],
      ),
    );
  }
}

/// `TextRow`: a label, the input, then the error (red, live region) or else
/// the hint.
class LoyaltyField extends StatelessWidget {
  const LoyaltyField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.placeholder,
    this.error,
    this.rtl = false,
    this.mono = false,
    this.number = false,
    this.enabled = true,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? placeholder;

  /// Already in words.
  final String? error;

  /// `dir="rtl"`: an Arabic field in any language.
  final bool rtl;
  final bool mono;

  /// A number field: digits and a point, left to right.
  final bool number;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(label, style: DashType.bodyMedium.copyWith(color: c.textPrimary)),
        DashTextInput(
          value: value,
          onChanged: onChanged,
          placeholder: placeholder,
          semanticLabel: label,
          invalid: error != null,
          enabled: enabled,
          mono: mono,
          onSubmitted: onSubmitted,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          inputFormatters: number
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-eE]'))]
              : null,
          textDirection: rtl
              ? TextDirection.rtl
              : (number ? TextDirection.ltr : null),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: DashType.small.copyWith(color: c.errorText),
            ),
          )
        else if (hint != null)
          Text(hint!, style: DashType.small.copyWith(color: c.textSecondary)),
      ],
    );
  }
}

/// The muted, bordered note (`rounded-lg border border-border/60 bg-muted/40
/// p-3 text-xs`), or the amber warning when [warning].
class LoyaltyNote extends StatelessWidget {
  const LoyaltyNote(this.text, {this.warning = false, super.key});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = warning ? DashTone.warning.foreground(c) : c.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: warning
            ? DashTone.warning.wash(c)
            : c.muted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(
          color: warning
              ? fg.withValues(alpha: 0.4)
              : c.hairline.withValues(alpha: 0.6),
        ),
      ),
      child: Text(text, style: DashType.small.copyWith(color: fg)),
    );
  }
}

/// Two fields side by side from the web's `sm` (640), stacked below.
class LoyaltyPair extends StatelessWidget {
  const LoyaltyPair({required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= DashBreakpoints.sm
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            Expanded(child: first),
            Expanded(child: second),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [first, second],
        );
}
