/// [PoNumberInput]: an `<input type="number">` that reports its raw text on
/// every keystroke (the kit's number field settles on blur, but the web
/// re-estimates a line total as the quantity is typed). Purchasing,
/// transfers and waste share it.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Digits (Latin or Arabic-Indic) and one decimal sign.
final TextInputFormatter _numberChars = FilteringTextInputFormatter.allow(
  RegExp('[0-9٠-٩.٫]'),
);

/// A number typed as text (`<input type="number" min="0">`): left to right,
/// tabular, at the line's start; [onChanged] gets every keystroke.
class PoNumberInput extends StatelessWidget {
  const PoNumberInput({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.placeholder,
    this.enabled = true,
    this.decimals = true,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String semanticLabel;
  final String? placeholder;
  final bool enabled;
  final bool decimals;

  @override
  Widget build(BuildContext context) => DashTextInput(
    value: value,
    onChanged: onChanged,
    placeholder: placeholder,
    semanticLabel: semanticLabel,
    enabled: enabled,
    mono: true,
    keyboardType: TextInputType.numberWithOptions(decimal: decimals),
    textDirection: TextDirection.ltr,
    textAlign: Directionality.of(context) == TextDirection.rtl
        ? TextAlign.right
        : TextAlign.left,
    inputFormatters: [_numberChars],
  );
}
