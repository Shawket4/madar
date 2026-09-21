import 'package:design_system/src/controls.dart';
import 'package:flutter/material.dart';

/// The theme a person chose: light, dark, or the device's own setting.
/// Persisted by NAME by each host (the POS vault, the staff app), so "Auto"
/// survives a relaunch instead of quietly becoming light. Lives here, beside
/// the themes it selects, so every app shares one enum and one control.
enum ThemeChoice {
  light,
  dark,
  system;

  /// The persisted name back to a choice; anything unknown is light, the
  /// default the till has always booted with.
  static ThemeChoice parse(String? name) => switch (name) {
    'dark' => ThemeChoice.dark,
    'system' => ThemeChoice.system,
    _ => ThemeChoice.light,
  };

  ThemeMode get mode => switch (this) {
    ThemeChoice.light => ThemeMode.light,
    ThemeChoice.dark => ThemeMode.dark,
    ThemeChoice.system => ThemeMode.system,
  };
}

/// Light · Dark · System. Labels arrive localised (the core's
/// `settings.theme_light|dark|system`).
class MadarThemePicker extends StatelessWidget {
  const MadarThemePicker({
    required this.value,
    required this.onChanged,
    required this.light,
    required this.dark,
    required this.system,
    super.key,
  });

  final ThemeChoice value;
  final ValueChanged<ThemeChoice> onChanged;
  final String light;
  final String dark;
  final String system;

  @override
  Widget build(BuildContext context) => MadarSegmented<ThemeChoice>(
    items: [
      MadarSegmentItem(ThemeChoice.light, light),
      MadarSegmentItem(ThemeChoice.dark, dark),
      MadarSegmentItem(ThemeChoice.system, system),
    ],
    value: value,
    onChanged: onChanged,
  );
}

/// English · العربية. Each language is labelled in its own name, never
/// translated. [value] is a locale; any Arabic region selects Arabic.
class MadarLanguagePicker extends StatelessWidget {
  const MadarLanguagePicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => MadarSegmented<String>(
    items: const [
      MadarSegmentItem('en', 'English'),
      MadarSegmentItem('ar', 'العربية'),
    ],
    value: value.startsWith('ar') ? 'ar' : 'en',
    onChanged: onChanged,
  );
}
