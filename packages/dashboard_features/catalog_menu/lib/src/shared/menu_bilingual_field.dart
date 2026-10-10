/// The web's `BilingualField` for the menu dialogs, with Enter submitting
/// the form (a dialog form's implicit submission, MENU-AREA-013): the English
/// box and the Arabic one ("Name (ع)", right to left), side by side from
/// `sm`. The kit's `DashBilingualField` has no submit hook; a textarea
/// (description) uses it as is, since Enter there is a new line.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

class MenuBilingualField extends StatelessWidget {
  const MenuBilingualField({
    required this.label,
    required this.en,
    required this.ar,
    required this.onEnChanged,
    required this.onArChanged,
    this.enError,
    this.textarea = false,
    this.onSubmit,
    super.key,
  });

  final String label;
  final String en;
  final String ar;
  final ValueChanged<String> onEnChanged;
  final ValueChanged<String> onArChanged;
  final String? enError;
  final bool textarea;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    if (textarea) {
      return DashBilingualField(
        label: label,
        en: en,
        ar: ar,
        textarea: true,
        enError: enError,
        onEnChanged: onEnChanged,
        onArChanged: onArChanged,
      );
    }
    final arLabel = context.dashStrings.arabicLabel(label);
    final enF = DashTextField(
      label: label,
      value: en,
      errorText: enError,
      textDirection: TextDirection.ltr,
      onChanged: onEnChanged,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
    );
    final arF = DashTextField(
      label: arLabel,
      value: ar,
      textDirection: TextDirection.rtl,
      onChanged: onArChanged,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >= DashBreakpoints.sm - Space.xxl * 4
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(child: enF),
                Expanded(child: arF),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: [enF, arF],
            ),
    );
  }
}
