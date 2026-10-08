/// Pieces the organization editor and the provision wizard share: the muted
/// box the web draws around a switch and its hint (`rounded-lg bg-muted
/// p-3`), the Modules box (POS / Dawam), the rate and currency input rules,
/// and a picked image as the uploader takes it.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The org modules, in the order the boxes list them.
const List<String> orgModuleKeys = [OrgModule.pos, OrgModule.dawam];

/// What a rate field lets through: digits (Latin or Arabic), one decimal
/// mark, a sign (so "-1" can be refused in words, as the web's number input
/// lets it be typed).
final List<TextInputFormatter> percentInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp('[-0-9.٠-٩٫]')),
];

/// The currency field reads upper case (the web's `uppercase` class); here
/// the value is upper case too, so what is shown is what is sent.
class UpperCaseFormatter extends TextInputFormatter {
  const UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// A rounded muted box around a settings switch and its hint.
class OrgMutedBox extends StatelessWidget {
  const OrgMutedBox({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.md),
    decoration: BoxDecoration(
      color: context.madarColors.muted,
      borderRadius: BorderRadius.circular(Radii.xs),
    ),
    child: child,
  );
}

/// A switch with its words and an optional hint, in a muted box.
class OrgSwitchBox extends StatelessWidget {
  const OrgSwitchBox({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.enabled = true,
    super.key,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return OrgMutedBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Row(
            spacing: Space.lg,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: DashType.body.copyWith(color: c.textPrimary),
                ),
              ),
              DashSwitch(
                value: value,
                onChanged: onChanged,
                semanticLabel: label,
                enabled: enabled,
              ),
            ],
          ),
          if (hint != null)
            Text(
              hint!,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// A checkbox and its words on one line; the words toggle it too.
class OrgCheckRow extends StatelessWidget {
  const OrgCheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: enabled ? () => onChanged(!value) : null,
      enabled: enabled,
      isButton: false,
      checked: value,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            IgnorePointer(
              child: DashCheckbox(
                value: value,
                onChanged: (_) {},
                semanticLabel: label,
                enabled: enabled,
                alignStart: true,
              ),
            ),
            Flexible(
              child: Text(
                label,
                style: DashType.body.copyWith(
                  color: enabled ? c.textPrimary : c.disabledText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Modules box (PS-2): Madar POS and Dawam by Madar, at least one.
class OrgModulesBox extends ConsumerWidget {
  const OrgModulesBox({
    required this.modules,
    required this.onChanged,
    this.error,
    this.showHint = false,
    super.key,
  });

  /// Ticked modules, in the order they were ticked.
  final List<String> modules;
  final ValueChanged<List<String>> onChanged;
  final String? error;

  /// "Switching a module off hides its pages and keeps every record."
  final bool showHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final invalid = error != null;
    return OrgMutedBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Text(
            t('dawam.modules'),
            style: DashType.bodyMedium.copyWith(
              color: invalid ? c.errorText : c.textPrimary,
            ),
          ),
          Wrap(
            spacing: Space.lg,
            children: [
              for (final m in orgModuleKeys)
                OrgCheckRow(
                  key: ValueKey('org-module-$m'),
                  label: m == OrgModule.pos
                      ? t('dawam.modulePos')
                      : t('dawam.moduleDawam'),
                  value: modules.contains(m),
                  onChanged: (on) => onChanged(
                    on
                        ? [...modules, m]
                        : [
                            for (final x in modules)
                              if (x != m) x,
                          ],
                  ),
                ),
            ],
          ),
          if (showHint)
            Text(
              t('dawam.modulesHint'),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          if (invalid)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: DashType.body.copyWith(color: c.errorText),
              ),
            ),
        ],
      ),
    );
  }
}

/// A label over a control (the web's `<p class="text-sm font-medium">`).
class OrgFieldLabel extends StatelessWidget {
  const OrgFieldLabel(this.text, {this.invalid = false, super.key});

  final String text;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Text(
      text,
      style: DashType.bodyMedium.copyWith(
        color: invalid ? c.errorText : c.textPrimary,
      ),
    );
  }
}

/// The person's picked image as the uploader takes it (null = cancelled).
Future<DashPickedFile?> pickOrgImage(WidgetRef ref) async {
  final f = await ref.read(fileGatewayProvider).pickImage();
  if (f == null) return null;
  return DashPickedFile(
    bytes: Uint8List.fromList(f.bytes),
    name: f.name,
    mimeType: f.mimeType ?? _mimeOf(f.name),
  );
}

String _mimeOf(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'svg' => 'image/svg+xml',
    _ => 'application/octet-stream',
  };
}
