import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controls.dart';
import 'dates.dart';
import 'foundation/l10n.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';
import 'select.dart';
import 'time.dart';

/// Validates a field's current value: an error sentence, or null.
typedef DashValidator<V> = String? Function(V value);

/// The frame of a form field (the web's `FormItem`): a 14/500 label (red
/// when the field is wrong), the control, then either the error under it
/// (14, readable red) or a quiet description.
///
/// Give [validator] to take part in a surrounding [Form]: `Form.validate()`
/// shows its sentence under the field, and after that every change
/// re-checks (the web's react-hook-form `reValidateMode: onChange`).
/// [errorText] — a server's 422 for this field — wins over the validator.
class DashFormField<V> extends StatefulWidget {
  const DashFormField({
    required this.builder,
    this.label,
    this.description,
    this.errorText,
    this.validator,
    this.value,
    this.requiredMark = false,
    this.optionalText,
    this.labelTrailing,
    this.inlineLabel = false,
    super.key,
  });

  /// The control; `invalid` is true while an error is showing.
  final Widget Function(BuildContext context, bool invalid) builder;
  final String? label;
  final String? description;
  final String? errorText;
  final DashValidator<V>? validator;

  /// The value the validator checks.
  final V? value;

  /// A red asterisk after the label.
  final bool requiredMark;

  /// A muted word after the label ("Optional").
  final String? optionalText;
  final Widget? labelTrailing;

  /// Label beside the control (a switch, a checkbox row) instead of above.
  final bool inlineLabel;

  @override
  State<DashFormField<V>> createState() => _DashFormFieldState<V>();
}

class _DashFormFieldState<V> extends State<DashFormField<V>> {
  final _key = GlobalKey<FormFieldState<V>>();

  @override
  Widget build(BuildContext context) {
    if (widget.validator == null) return _frame(context, widget.errorText);
    return FormField<V>(
      key: _key,
      initialValue: widget.value,
      validator: (_) => widget.validator!(widget.value as V),
      builder: (state) {
        if (state.value != widget.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final s = _key.currentState;
            if (s == null) return;
            final had = s.hasError;
            s.didChange(widget.value);
            if (had) s.validate();
          });
        }
        return _frame(context, widget.errorText ?? state.errorText);
      },
    );
  }

  Widget _frame(BuildContext context, String? error) {
    final c = context.madarColors;
    final invalid = error != null && error.isNotEmpty;
    final control = widget.builder(context, invalid);
    final label = widget.label == null
        ? null
        : Row(
            mainAxisSize: widget.inlineLabel
                ? MainAxisSize.max
                : MainAxisSize.min,
            spacing: Space.xs,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: widget.label,
                    children: [
                      if (widget.requiredMark)
                        TextSpan(
                          text: ' *',
                          style: TextStyle(color: c.errorText),
                        ),
                    ],
                  ),
                  style: DashType.bodyMedium.copyWith(
                    color: invalid ? c.errorText : c.textPrimary,
                  ),
                ),
              ),
              if (widget.optionalText != null)
                Text(
                  widget.optionalText!,
                  style: DashType.small.copyWith(color: c.textMuted),
                ),
              ?widget.labelTrailing,
            ],
          );
    final below = invalid
        ? Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: DashType.body.copyWith(color: c.errorText),
            ),
          )
        : widget.description == null
        ? null
        : Text(
            widget.description!,
            style: DashType.body.copyWith(color: c.textSecondary),
          );
    if (widget.inlineLabel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Row(
            children: [
              if (label != null) Expanded(child: label),
              control,
            ],
          ),
          ?below,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [?label, control, ?below],
    );
  }
}

/// A text field with its label and error (the web's `Input` in a
/// `FormItem`).
class DashTextField extends StatelessWidget {
  const DashTextField({
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.description,
    this.errorText,
    this.validator,
    this.requiredMark = false,
    this.enabled = true,
    this.obscure = false,
    this.keyboardType,
    this.maxLength,
    this.textDirection,
    this.mono = false,
    this.autofocus = false,
    this.leadingIcon,
    this.inputFormatters,
    this.onSubmitted,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? placeholder;
  final String? description;
  final String? errorText;
  final DashValidator<String>? validator;
  final bool requiredMark;
  final bool enabled;
  final bool obscure;
  final TextInputType? keyboardType;
  final int? maxLength;
  final TextDirection? textDirection;
  final bool mono;
  final bool autofocus;
  final String? leadingIcon;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => DashFormField<String>(
    label: label,
    description: description,
    errorText: errorText,
    validator: validator,
    value: value,
    requiredMark: requiredMark,
    builder: (context, invalid) => DashTextInput(
      value: value,
      onChanged: onChanged,
      placeholder: placeholder,
      semanticLabel: label ?? placeholder,
      invalid: invalid,
      enabled: enabled,
      obscure: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      textDirection: textDirection,
      mono: mono,
      autofocus: autofocus,
      leadingIcon: leadingIcon,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
    ),
  );
}

/// A multi-line text field (the web's `Textarea`).
class DashTextAreaField extends StatelessWidget {
  const DashTextAreaField({
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.description,
    this.errorText,
    this.validator,
    this.minLines = 3,
    this.maxLines = 8,
    this.maxLength,
    this.enabled = true,
    this.textDirection,
    this.mono = false,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? placeholder;
  final String? description;
  final String? errorText;
  final DashValidator<String>? validator;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool enabled;
  final TextDirection? textDirection;
  final bool mono;

  @override
  Widget build(BuildContext context) => DashFormField<String>(
    label: label,
    description: description,
    errorText: errorText,
    validator: validator,
    value: value,
    builder: (context, invalid) => DashTextInput(
      value: value,
      onChanged: onChanged,
      placeholder: placeholder,
      semanticLabel: label ?? placeholder,
      invalid: invalid,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      textDirection: textDirection,
      mono: mono,
    ),
  );
}

/// Read a number the way it gets typed in Egypt (the web's `parseNumber`):
/// Latin or Arabic digits, `,`/`٬` thousands, `.`/`٫` decimal. Null when it
/// is not a number.
double? dashParseNumber(String raw) {
  final s = DashTime.latinDigits(raw)
      .trim()
      .replaceAll(RegExp('[\\s,٬]'), '')
      .replaceAll('٫', '.')
      .replaceFirst(RegExp('^−'), '-');
  if (s.isEmpty || !RegExp(r'^-?(\d+\.?\d*|\.\d+)$').hasMatch(s)) return null;
  return double.tryParse(s);
}

double _roundTo(double n, int decimals) {
  final f = math.pow(10, decimals);
  return (n * f).round() / f;
}

int _decimalsOf(num step) {
  final s = step.toString();
  final i = s.indexOf('.');
  return i < 0 ? 0 : (s.substring(i + 1) == '0' ? 0 : s.length - i - 1);
}

/// The kit's number (the web's `NumberField`): typed in Latin or Arabic
/// digits, stepped with −/+ or ↑/↓, or set by a preset chip. A number out of
/// range, or one it cannot read, is refused out loud and handed on as typed
/// (NaN when unreadable) — the field never quietly clamps or keeps the last
/// good number.
class DashNumberInput extends StatefulWidget {
  const DashNumberInput({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.step = 1,
    this.decimals,
    this.minDecimals = 0,
    this.suffix,
    this.prefix,
    this.stepper = false,
    this.presets = const [],
    this.presetLabel,
    this.allowEmpty = false,
    this.emptyLabel,
    this.hint,
    this.unitWord,
    this.invalid = false,
    this.enabled = true,
    this.center = false,
    this.semanticLabel,
    super.key,
  });

  final double? value;
  final ValueChanged<double?> onChanged;
  final double min;
  final double? max;
  final double step;
  final int? decimals;
  final int minDecimals;
  final String? suffix;
  final String? prefix;
  final bool stepper;
  final List<double> presets;
  final String Function(double)? presetLabel;
  final bool allowEmpty;
  final String? emptyLabel;
  final String? hint;
  final String? unitWord;

  /// Marked wrong by the form: its message speaks, not the field's own.
  final bool invalid;
  final bool enabled;
  final bool center;
  final String? semanticLabel;

  @override
  State<DashNumberInput> createState() => _DashNumberInputState();
}

class _DashNumberInputState extends State<DashNumberInput> {
  String? _draft;
  String? _problem;
  late double? _emitted = widget.value;
  final _focus = FocusNode();

  int get _places => widget.decimals ?? _decimalsOf(widget.step);
  bool get _has => widget.value != null && widget.value!.isFinite;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _settle();
    });
  }

  @override
  void didUpdateWidget(DashNumberInput old) {
    super.didUpdateWidget(old);
    final v = widget.value;
    final same =
        v == _emitted ||
        (v != null && _emitted != null && v.isNaN && _emitted!.isNaN);
    if (!same) {
      _emitted = v;
      _draft = null;
      _problem = null;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _emit(double? n) {
    _emitted = n;
    final same =
        n == widget.value ||
        (n != null && widget.value != null && n.isNaN && widget.value!.isNaN);
    if (!same) widget.onChanged(n);
  }

  void _accept(double? n) {
    setState(() {
      _draft = null;
      _problem = null;
    });
    _emit(n);
  }

  void _refuse(String message, double n) {
    setState(() => _problem = message);
    _emit(n);
  }

  String _range(DashKitStrings t, DashKitFormats f) {
    final u = widget.unitWord == null ? '' : ' ${widget.unitWord}';
    return widget.max != null
        ? t.between(f.figure(widget.min), f.figure(widget.max!), u)
        : t.atLeast(f.figure(widget.min), u);
  }

  void _settle() {
    final d = _draft;
    if (d == null) return;
    final t = context.dashStrings;
    final f = context.dashFormats;
    final text = d.trim();
    if (text.isEmpty) {
      if (widget.allowEmpty) {
        _accept(null);
      } else {
        _refuse(t.needsValue, double.nan);
      }
      return;
    }
    final n = dashParseNumber(text);
    if (n == null) {
      _refuse(t.notANumber(text), double.nan);
      return;
    }
    if (n < widget.min || (widget.max != null && n > widget.max!)) {
      _refuse(_range(t, f), _roundTo(n, _places));
      return;
    }
    _accept(_roundTo(n, _places));
  }

  void _bump(int dir) {
    final base = _has ? widget.value! : widget.min;
    var next = _roundTo(base + dir * widget.step, _places);
    if (next < widget.min) next = widget.min;
    if (widget.max != null && next > widget.max!) next = widget.max!;
    _accept(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    final f = context.dashFormats;
    final shown =
        _draft ??
        (_has
            ? f.figure(
                widget.value!,
                minDecimals: math.min(widget.minDecimals, _places),
                maxDecimals: _places,
              )
            : '');
    Widget stepBtn(String icon, String label, bool can, int dir) =>
        DashPressable(
          onTap: widget.enabled && can ? () => _bump(dir) : null,
          enabled: widget.enabled && can,
          semanticLabel: label,
          excludeChildSemantics: true,
          builder: (context, s) => Container(
            width: Space.xxl - Space.xs,
            height: Space.xxl - Space.xs,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.highlighted ? c.hover : null,
              borderRadius: BorderRadius.circular(Space.xs),
            ),
            child: Opacity(
              opacity: widget.enabled && can ? 1 : 0.4,
              child: DashIcon(icon, size: IconSize.xs, color: c.textSecondary),
            ),
          ),
        );
    final input = DashTextInput(
      value: shown,
      focusNode: _focus,
      enabled: widget.enabled,
      invalid: widget.invalid || _problem != null,
      placeholder: widget.emptyLabel,
      semanticLabel: widget.semanticLabel,
      textDirection: TextDirection.ltr,
      // The figure types left to right, but sits at the line's start: the
      // right edge in Arabic (the web's `text-start rtl:text-end`).
      textAlign: widget.center
          ? TextAlign.center
          : (Directionality.of(context) == TextDirection.rtl
                ? TextAlign.right
                : TextAlign.left),
      keyboardType: TextInputType.numberWithOptions(
        decimal: _places > 0,
        signed: widget.min < 0,
      ),
      selectAllOnFocus: true,
      onChanged: (v) => setState(() {
        _draft = v;
        _problem = null;
      }),
      onSubmitted: (_) => _settle(),
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
          _bump(1);
          return KeyEventResult.handled;
        }
        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
          _bump(-1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      leading: widget.stepper || widget.prefix != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.stepper)
                  stepBtn(
                    'minus',
                    t.less,
                    !_has || widget.value! > widget.min,
                    -1,
                  ),
                if (widget.prefix != null)
                  Text(
                    widget.prefix!,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
              ],
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          if (widget.suffix != null)
            Text(
              widget.suffix!,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          if (widget.stepper)
            stepBtn(
              'plus',
              t.more,
              !_has || widget.max == null || widget.value! < widget.max!,
              1,
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        input,
        if (widget.presets.isNotEmpty)
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final p in widget.presets)
                DashChoiceChip(
                  label: widget.presetLabel?.call(p) ?? f.figure(p),
                  selected: widget.value == p,
                  enabled: widget.enabled,
                  onTap: () => _accept(p),
                ),
            ],
          ),
        if (_problem != null && !widget.invalid)
          Semantics(
            liveRegion: true,
            child: Text(
              _problem!,
              style: DashType.small.copyWith(color: c.errorText),
            ),
          )
        else if (widget.hint != null)
          Text(
            widget.hint!,
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

/// A number field with label and error.
class DashNumberField extends StatelessWidget {
  const DashNumberField({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.validator,
    this.min = 0,
    this.max,
    this.step = 1,
    this.decimals,
    this.suffix,
    this.stepper = false,
    this.presets = const [],
    this.allowEmpty = false,
    this.emptyLabel,
    this.unitWord,
    this.enabled = true,
    super.key,
  });

  final double? value;
  final ValueChanged<double?> onChanged;
  final String? label;
  final String? description;
  final String? errorText;
  final DashValidator<double?>? validator;
  final double min;
  final double? max;
  final double step;
  final int? decimals;
  final String? suffix;
  final bool stepper;
  final List<double> presets;
  final bool allowEmpty;
  final String? emptyLabel;
  final String? unitWord;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DashFormField<double?>(
    label: label,
    errorText: errorText,
    validator: validator,
    value: value,
    builder: (context, invalid) => DashNumberInput(
      value: value,
      onChanged: onChanged,
      min: min,
      max: max,
      step: step,
      decimals: decimals,
      suffix: suffix,
      stepper: stepper,
      presets: presets,
      allowEmpty: allowEmpty,
      emptyLabel: emptyLabel,
      unitWord: unitWord,
      hint: description,
      invalid: invalid,
      enabled: enabled,
      semanticLabel: label,
    ),
  );
}

/// Money in minor units (the web's `MoneyField`): what a person types and
/// reads is pounds, grouped, with the currency after it; the value is
/// piastres.
class DashMoneyField extends StatelessWidget {
  const DashMoneyField({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.validator,
    this.min = 0,
    this.max,
    this.stepMajor = 50,
    this.stepper = false,
    this.allowEmpty = false,
    this.enabled = true,
    super.key,
  });

  /// Minor units (piastres), or null.
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? label;
  final String? description;
  final String? errorText;
  final DashValidator<int?>? validator;
  final int min;
  final int? max;

  /// −/+ step in major units.
  final double stepMajor;
  final bool stepper;
  final bool allowEmpty;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cur = context.dashFormats.currencyLabel;
    return DashFormField<int?>(
      label: label,
      errorText: errorText,
      validator: validator,
      value: value,
      builder: (context, invalid) => DashNumberInput(
        value: value == null ? null : value! / 100,
        onChanged: (major) => onChanged(
          major == null ? null : (major.isNaN ? null : (major * 100).round()),
        ),
        min: min / 100,
        max: max == null ? null : max! / 100,
        step: stepMajor,
        decimals: 2,
        minDecimals: 2,
        suffix: cur,
        unitWord: cur,
        stepper: stepper,
        allowEmpty: allowEmpty,
        hint: description,
        invalid: invalid,
        enabled: enabled,
        semanticLabel: label,
      ),
    );
  }
}

/// A percent typed as `12.5` and held as a ratio (`0.125`).
class DashPercentField extends StatelessWidget {
  const DashPercentField({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.validator,
    this.max = 100,
    this.decimals = 2,
    this.allowEmpty = false,
    this.enabled = true,
    super.key,
  });

  /// A ratio (0.125 = 12.5%), or null.
  final double? value;
  final ValueChanged<double?> onChanged;
  final String? label;
  final String? description;
  final String? errorText;
  final DashValidator<double?>? validator;

  /// The largest percent (100).
  final double max;
  final int decimals;
  final bool allowEmpty;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DashFormField<double?>(
    label: label,
    errorText: errorText,
    validator: validator,
    value: value,
    builder: (context, invalid) => DashNumberInput(
      value: value == null ? null : _roundTo(value! * 100, decimals),
      onChanged: (p) =>
          onChanged(p == null ? null : (p.isNaN ? double.nan : p / 100)),
      max: max,
      step: 1,
      decimals: decimals,
      suffix: '%',
      unitWord: '%',
      allowEmpty: allowEmpty,
      hint: description,
      invalid: invalid,
      enabled: enabled,
      semanticLabel: label,
    ),
  );
}

/// A select with its label and error.
class DashSelectField<T> extends StatelessWidget {
  const DashSelectField({
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.description,
    this.errorText,
    this.validator,
    this.searchable = false,
    this.searchPlaceholder,
    this.emptyText,
    this.enabled = true,
    this.requiredMark = false,
    super.key,
  });

  final List<DashOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? label;
  final String? placeholder;
  final String? description;
  final String? errorText;
  final DashValidator<T?>? validator;

  /// The web's `Combobox`: a search box over the list.
  final bool searchable;
  final String? searchPlaceholder;
  final String? emptyText;
  final bool enabled;
  final bool requiredMark;

  @override
  Widget build(BuildContext context) => DashFormField<T?>(
    label: label,
    description: description,
    errorText: errorText,
    validator: validator,
    value: value,
    requiredMark: requiredMark,
    builder: (context, invalid) => DashSelect<T>(
      options: options,
      value: value,
      onChanged: onChanged,
      placeholder: placeholder,
      semanticLabel: label,
      searchable: searchable,
      searchPlaceholder: searchPlaceholder,
      emptyText: emptyText,
      invalid: invalid,
      enabled: enabled,
    ),
  );
}

/// A multi-select with its label and error.
class DashMultiSelectField<T> extends StatelessWidget {
  const DashMultiSelectField({
    required this.options,
    required this.values,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.description,
    this.errorText,
    this.validator,
    this.searchable = true,
    this.enabled = true,
    super.key,
  });

  final List<DashOption<T>> options;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;
  final String? label;
  final String? placeholder;
  final String? description;
  final String? errorText;
  final DashValidator<Set<T>>? validator;
  final bool searchable;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DashFormField<Set<T>>(
    label: label,
    description: description,
    errorText: errorText,
    validator: validator,
    value: values,
    builder: (context, invalid) => DashMultiSelect<T>(
      options: options,
      values: values,
      onChanged: onChanged,
      placeholder: placeholder,
      semanticLabel: label,
      searchable: searchable,
      invalid: invalid,
      enabled: enabled,
    ),
  );
}

/// A switch on a labelled row (label and description at the start, the
/// switch at the end) — the web's settings toggles.
class DashSwitchField extends StatelessWidget {
  const DashSwitchField({
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
    this.errorText,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? description;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashFormField<bool>(
      errorText: errorText,
      value: value,
      builder: (context, invalid) => Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DashMetrics.hair,
              children: [
                Text(
                  label,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                if (description != null)
                  Text(
                    description!,
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
              ],
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
    );
  }
}

/// A checkbox with its words beside it; the words toggle it too.
class DashCheckboxField extends StatelessWidget {
  const DashCheckboxField({
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
    this.errorText,
    this.validator,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? description;
  final String? errorText;
  final DashValidator<bool>? validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashFormField<bool>(
      errorText: errorText,
      validator: validator,
      value: value,
      builder: (context, invalid) => DashPressable(
        onTap: enabled ? () => onChanged(!value) : null,
        enabled: enabled,
        isButton: false,
        checked: value,
        semanticLabel: label,
        excludeChildSemantics: true,
        pressScale: false,
        builder: (context, s) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IgnorePointer(
              child: SizedBox(
                width: DashMetrics.checkbox + Space.md,
                child: DashCheckbox(
                  value: value,
                  onChanged: (_) {},
                  semanticLabel: label,
                  invalid: invalid,
                  enabled: enabled,
                  alignStart: true,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: Space.md - DashMetrics.hair,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: DashMetrics.hair,
                  children: [
                    Text(
                      label,
                      style: DashType.bodyMedium.copyWith(
                        color: enabled ? c.textPrimary : c.disabledText,
                      ),
                    ),
                    if (description != null)
                      Text(
                        description!,
                        style: DashType.body.copyWith(color: c.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A radio group: one choice of a few, each a row with its words.
class DashRadioGroup<T> extends StatelessWidget {
  const DashRadioGroup({
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.validator,
    this.enabled = true,
    this.horizontal = false,
    super.key,
  });

  final List<DashOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? label;
  final String? description;
  final String? errorText;
  final DashValidator<T?>? validator;
  final bool enabled;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashFormField<T?>(
      label: label,
      description: description,
      errorText: errorText,
      validator: validator,
      value: value,
      builder: (context, invalid) {
        final rows = [
          for (final o in options)
            DashPressable(
              onTap: enabled && o.enabled ? () => onChanged(o.value) : null,
              enabled: enabled && o.enabled,
              isButton: false,
              selected: o.value == value,
              checked: o.value == value,
              semanticLabel: o.label,
              excludeChildSemantics: true,
              pressScale: false,
              builder: (context, s) => ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DashMetrics.target,
                ),
                child: Row(
                  mainAxisSize: horizontal
                      ? MainAxisSize.min
                      : MainAxisSize.max,
                  spacing: Space.sm,
                  children: [
                    DashRadioDot(
                      selected: o.value == value,
                      enabled: enabled && o.enabled,
                      focused: s.focused,
                    ),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            o.label,
                            style: DashType.body.copyWith(color: c.textPrimary),
                          ),
                          if (o.hint != null)
                            Text(
                              o.hint!,
                              style: DashType.small.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ];
        return Semantics(
          container: true,
          label: label,
          child: horizontal
              ? Wrap(spacing: Space.lg, children: rows)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: rows,
                ),
        );
      },
    );
  }
}

/// A pill-style view switcher (the web's `SegmentedControl`): a sunk track,
/// the chosen segment inked.
class DashSegmentedControl<T> extends StatelessWidget {
  const DashSegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.enabled = true,
    this.expand = false,
    super.key,
  });

  final List<DashOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Names the group for a screen reader ("Status", "View").
  final String? semanticLabel;
  final bool enabled;

  /// Segments share the full width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final segs = [
      for (final o in options)
        DashPressable(
          onTap: enabled ? () => onChanged(o.value) : null,
          enabled: enabled,
          selected: o.value == value,
          checked: o.value == value,
          isButton: false,
          semanticLabel: o.label,
          excludeChildSemantics: true,
          pressScale: false,
          builder: (context, s) {
            final on = o.value == value;
            return AnimatedContainer(
              duration: DashMotion.of(context, DashMotion.base),
              height: DashMetrics.control - Space.xs - 2,
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              alignment: Alignment.center,
              foregroundDecoration: dashFocusRing(
                context,
                s,
                BorderRadius.circular(Radii.xs),
              ),
              decoration: BoxDecoration(
                color: on
                    ? c.accent
                    : s.hovered
                    ? c.hover
                    : null,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs + DashMetrics.hair,
                children: [
                  if (o.icon != null)
                    DashIcon(
                      o.icon!,
                      size: IconSize.sm,
                      color: on ? c.textOnAccent : c.textSecondary,
                    ),
                  Text(
                    o.label,
                    maxLines: 1,
                    style: DashType.bodyMedium.copyWith(
                      color: on
                          ? c.textOnAccent
                          : s.hovered
                          ? c.textPrimary
                          : c.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
    ];
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          height: DashMetrics.control,
          padding: const EdgeInsets.all(DashMetrics.ring),
          decoration: BoxDecoration(
            color: c.muted,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: expand
              ? Row(children: [for (final s in segs) Expanded(child: s)])
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: segs),
                ),
        ),
      ),
    );
  }
}

/// A date with its label and error.
class DashDateFormField extends StatelessWidget {
  const DashDateFormField({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.validator,
    this.placeholder,
    this.today,
    this.disableFuture = false,
    this.disablePast = false,
    this.warnPast = false,
    this.enabled = true,
    super.key,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? label;
  final String? description;
  final String? errorText;
  final DashValidator<DateTime?>? validator;
  final String? placeholder;
  final DateTime? today;
  final bool disableFuture;
  final bool disablePast;
  final bool warnPast;
  final bool enabled;

  @override
  Widget build(BuildContext context) => DashFormField<DateTime?>(
    label: label,
    description: description,
    errorText: errorText,
    validator: validator,
    value: value,
    builder: (context, invalid) => DashDateField(
      value: value,
      onChanged: onChanged,
      placeholder: placeholder,
      semanticLabel: label,
      today: today,
      disableFuture: disableFuture,
      disablePast: disablePast,
      warnPast: warnPast,
      invalid: invalid,
      enabled: enabled,
    ),
  );
}

/// A time with its label and error.
class DashTimeFormField extends StatelessWidget {
  const DashTimeFormField({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.validator,
    this.placeholder,
    this.clearable = false,
    this.step = 15,
    this.enabled = true,
    this.describeOption,
    super.key,
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? description;
  final String? errorText;
  final DashValidator<String?>? validator;
  final String? placeholder;
  final bool clearable;
  final int step;
  final bool enabled;
  final String? Function(String hhmm)? describeOption;

  @override
  Widget build(BuildContext context) => DashFormField<String?>(
    label: label,
    description: description,
    errorText: errorText,
    validator: validator,
    value: value,
    builder: (context, invalid) => DashTimeField(
      value: value,
      onChanged: onChanged,
      placeholder: placeholder,
      semanticLabel: label,
      clearable: clearable,
      step: step,
      invalid: invalid,
      enabled: enabled,
      describeOption: describeOption,
    ),
  );
}

/// The searchable, select-only timezone picker (the web's
/// `TimezoneSelect`): options are the backend's zone names, "new york"
/// finds America/New_York, and a set value missing from the list stays
/// visible.
class DashTimezoneSelect extends StatelessWidget {
  const DashTimezoneSelect({
    required this.zones,
    required this.value,
    required this.onChanged,
    this.label,
    this.errorText,
    this.enabled = true,
    super.key,
  });

  /// From `GET /timezones`.
  final List<String> zones;
  final String? value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    final opts = [
      if (value != null && value!.isNotEmpty && !zones.contains(value))
        DashOption(
          value: value!,
          label: value!,
          keywords: value!.replaceAll(RegExp('[/_]'), ' '),
        ),
      for (final z in zones)
        DashOption(
          value: z,
          label: z,
          keywords: z.replaceAll(RegExp('[/_]'), ' '),
        ),
    ];
    return DashSelectField<String>(
      options: opts,
      value: value,
      onChanged: onChanged,
      label: label,
      errorText: errorText,
      enabled: enabled,
      searchable: true,
      placeholder: t.selectTimezone,
      searchPlaceholder: t.searchTimezone,
    );
  }
}

/// Paired English + Arabic inputs for a translatable field (the web's
/// `BilingualField`): side by side from 640 wide, stacked below; the Arabic
/// one types right-to-left whatever the page's language.
class DashBilingualField extends StatelessWidget {
  const DashBilingualField({
    required this.label,
    required this.en,
    required this.ar,
    required this.onEnChanged,
    required this.onArChanged,
    this.textarea = false,
    this.enError,
    this.arError,
    this.enValidator,
    this.arValidator,
    this.enabled = true,
    super.key,
  });

  final String label;
  final String en;
  final String ar;
  final ValueChanged<String> onEnChanged;
  final ValueChanged<String> onArChanged;
  final bool textarea;
  final String? enError;
  final String? arError;
  final DashValidator<String>? enValidator;
  final DashValidator<String>? arValidator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    Widget field(
      String lab,
      String v,
      ValueChanged<String> on,
      String? err,
      DashValidator<String>? val,
      TextDirection dir,
    ) => textarea
        ? DashTextAreaField(
            label: lab,
            value: v,
            onChanged: on,
            errorText: err,
            validator: val,
            textDirection: dir,
            enabled: enabled,
          )
        : DashTextField(
            label: lab,
            value: v,
            onChanged: on,
            errorText: err,
            validator: val,
            textDirection: dir,
            enabled: enabled,
          );
    final enF = field(
      label,
      en,
      onEnChanged,
      enError,
      enValidator,
      TextDirection.ltr,
    );
    final arF = field(
      t.arabicLabel(label),
      ar,
      onArChanged,
      arError,
      arValidator,
      TextDirection.rtl,
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

/// A colour (`#RRGGBB`): a swatch, the hex typed, and a row of preset
/// swatches to tap — for a brand colour, a category's tint.
class DashColorField extends StatelessWidget {
  const DashColorField({
    required this.value,
    required this.onChanged,
    this.label,
    this.description,
    this.errorText,
    this.presets = const [],
    this.enabled = true,
    super.key,
  });

  /// `#RRGGBB`, or empty.
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? description;
  final String? errorText;

  /// Swatches offered under the field (`#RRGGBB`).
  final List<String> presets;
  final bool enabled;

  static final _hex = RegExp(r'^#?[0-9a-fA-F]{6}$');

  /// Whether [s] is a `#RRGGBB` colour.
  static bool isHex(String s) => _hex.hasMatch(s.trim());

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final ok = isHex(value);
    return DashFormField<String>(
      label: label,
      description: description,
      errorText: errorText,
      value: value,
      builder: (context, invalid) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          DashTextInput(
            value: value,
            enabled: enabled,
            invalid: invalid,
            mono: true,
            semanticLabel: label,
            textDirection: TextDirection.ltr,
            placeholder: '#0F7A8A',
            maxLength: 7,
            onChanged: (v) {
              final s = v.trim();
              onChanged(
                s.isEmpty || s.startsWith('#')
                    ? s.toUpperCase()
                    : '#${s.toUpperCase()}',
              );
            },
            trailing: Container(
              width: Space.xl,
              height: Space.xl,
              decoration: BoxDecoration(
                color: ok ? hexColor(value) : c.muted,
                borderRadius: BorderRadius.circular(
                  Space.xs + DashMetrics.hair,
                ),
                border: Border.all(color: c.input),
              ),
            ),
          ),
          if (presets.isNotEmpty)
            Wrap(
              spacing: Space.xs,
              runSpacing: Space.xs,
              children: [
                for (final p in presets)
                  DashPressable(
                    onTap: enabled ? () => onChanged(p.toUpperCase()) : null,
                    enabled: enabled,
                    selected: p.toUpperCase() == value.toUpperCase(),
                    semanticLabel: p,
                    excludeChildSemantics: true,
                    builder: (context, s) => SizedBox.square(
                      dimension: DashMetrics.target,
                      child: Center(
                        child: Container(
                          width: Space.xxl - Space.xs,
                          height: Space.xxl - Space.xs,
                          decoration: BoxDecoration(
                            color: hexColor(p),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: p.toUpperCase() == value.toUpperCase()
                                  ? c.textPrimary
                                  : c.hairline,
                              width: p.toUpperCase() == value.toUpperCase()
                                  ? 2
                                  : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
