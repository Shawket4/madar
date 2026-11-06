/// The switches that decide how a code comes out (`features/qr/
/// output-controls.tsx`): the page's panel above the codes, and the same
/// switches inside a code's preview, so they are never more than a glance
/// from the code they change.
///
/// Unbranded is the headline: one switch for "just the QR code". Under it,
/// and only meaningful with it, "Logo in the middle": off, a completely plain
/// QR. The card switch belongs to branded mode and steps aside when
/// Unbranded is on; the resolution stays (the unbranded code is a raster
/// too).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'qr_output.dart';

class QrOutputControls extends ConsumerWidget {
  const QrOutputControls({required this.orgId, this.noLogo = false, super.key});

  final String orgId;

  /// The last code came back with nothing in the middle although the logo
  /// was asked for: the shop has no logo for codes.
  final bool noLogo;

  /// The DPI select's width (the web's `w-20`).
  static const double dpiWidth = 80;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final o = ref.watch(qrOutputProvider(orgId));
    void set(QrOutput next) =>
        ref.read(qrOutputProvider(orgId).notifier).update(next);
    final hasBranding = planHasFeature(
      ref.watch(planFeaturesProvider),
      'branding',
    );

    final card = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        DashSwitch(
          key: const ValueKey('qr-card'),
          value: o.card,
          onChanged: (v) => set(o.copyWith(card: v)),
          semanticLabel: t('qr.output.card'),
        ),
        ExcludeSemantics(
          child: GestureDetector(
            onTap: () => set(o.copyWith(card: !o.card)),
            child: Text(
              t('qr.output.card'),
              style: DashType.body.copyWith(color: c.textPrimary),
            ),
          ),
        ),
        if (!o.card)
          Flexible(
            child: Text(
              t('qr.output.cardOff'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ),
      ],
    );

    final dpi = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Text(
          t('qr.opts.dpiLabel'),
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
        DashSelect<int>(
          key: const ValueKey('qr-dpi'),
          options: [for (final d in qrDpis) DashOption(value: d, label: '$d')],
          value: o.dpi,
          onChanged: (v) => set(o.copyWith(dpi: v)),
          semanticLabel: t('qr.opts.dpiLabel'),
          width: dpiWidth,
          expand: false,
        ),
      ],
    );

    return Column(
      key: const ValueKey('qr-output-controls'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        _SwitchRow(
          switchKey: const ValueKey('qr-unbranded'),
          value: o.unbranded,
          onChanged: (v) => set(o.copyWith(unbranded: v)),
          label: t('qr.output.unbranded'),
          hint: t('qr.output.unbrandedHint'),
        ),
        // The sub-switch sits under its parent and reads as part of it.
        Container(
          margin: const EdgeInsetsDirectional.only(start: Space.xs),
          padding: const EdgeInsetsDirectional.only(start: Space.lg),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: c.border, width: 2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              _SwitchRow(
                switchKey: const ValueKey('qr-centre-logo'),
                value: o.centreLogo,
                enabled: o.unbranded,
                onChanged: (v) => set(o.copyWith(centreLogo: v)),
                label: t('qr.output.centreLogo'),
                hint: o.unbranded
                    ? t('qr.output.centreLogoHint')
                    : t('qr.output.centreLogoOff'),
              ),
              if (o.unbranded && o.centreLogo && noLogo)
                Wrap(
                  key: const ValueKey('qr-no-logo'),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.xs,
                  children: [
                    Text(
                      t('qr.output.noLogo'),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                    if (hasBranding)
                      DashButton(
                        key: const ValueKey('qr-add-logo'),
                        label: t('qr.output.addLogo'),
                        variant: DashButtonVariant.link,
                        size: DashButtonSize.compact,
                        to: '/settings/brand',
                        onPressed: () => _toBrand(context),
                      ),
                  ],
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.only(top: Space.md),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.hairline)),
          ),
          child: Wrap(
            spacing: Space.xl,
            runSpacing: Space.md,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [if (!o.unbranded) card, if (o.unbranded || o.card) dpi],
          ),
        ),
      ],
    );
  }

  /// Brand, closing the code's preview first when the switches are in one.
  static void _toBrand(BuildContext context) {
    final router = GoRouter.of(context);
    if (ModalRoute.of(context) is PopupRoute) Navigator.of(context).pop();
    router.go('/settings/brand');
  }
}

/// A switch with its label and a hint under it; the words toggle it too.
/// Disabled, the whole row is dimmed (the web's `opacity-60`).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.hint,
    this.enabled = true,
  });

  final Key switchKey;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? () => onChanged(!value) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: DashMetrics.hair,
                  children: [
                    Text(
                      label,
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                    Text(
                      hint,
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DashSwitch(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            enabled: enabled,
            semanticLabel: label,
          ),
        ],
      ),
    );
  }
}
