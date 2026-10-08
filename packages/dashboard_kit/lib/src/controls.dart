import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'foundation/l10n.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';

/// The frame every kit field sits in (the web's `shellClass`): 44 tall, a
/// 1px input edge on the card face, 10 corners, a focus ring, a red edge
/// when [invalid], dimmed when disabled. Icons, units and a clear × share
/// the box with the text.
class DashFieldShell extends StatelessWidget {
  const DashFieldShell({
    required this.child,
    this.focused = false,
    this.invalid = false,
    this.enabled = true,
    this.hovered = false,
    this.leading,
    this.trailing,
    this.multiline = false,
    this.padding,
    this.shrinkWrap = false,
    super.key,
  });

  final Widget child;

  /// Fit the content instead of filling the line.
  final bool shrinkWrap;
  final bool focused;
  final bool invalid;
  final bool enabled;
  final bool hovered;
  final Widget? leading;
  final Widget? trailing;

  /// A textarea: grows from 3 lines, no fixed height.
  final bool multiline;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final edge = invalid
        ? c.danger
        : focused
        ? Color.lerp(c.input, c.textPrimary, 0.5)!
        : c.input;
    final radius = BorderRadius.circular(Radii.sm);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AnimatedContainer(
        duration: DashMotion.of(context, DashMotion.fast),
        constraints: BoxConstraints(minHeight: DashMetrics.control),
        height: multiline ? null : DashMetrics.control,
        padding:
            padding ??
            EdgeInsetsDirectional.symmetric(
              horizontal: Space.md - DashMetrics.hair,
              vertical: multiline ? Space.sm : 0,
            ),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: radius,
          border: Border.all(color: edge),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: invalid ? c.danger.withValues(alpha: 0.2) : c.ring,
                    spreadRadius: DashMetrics.ring,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: multiline
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          spacing: Space.xs + DashMetrics.hair,
          children: [
            ?leading,
            if (shrinkWrap) Flexible(child: child) else Expanded(child: child),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// The bare text input inside a [DashFieldShell] — controlled by [value],
/// synced into its own controller unless the person is typing.
class DashTextInput extends StatefulWidget {
  const DashTextInput({
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.semanticLabel,
    this.leadingIcon,
    this.leading,
    this.trailing,
    this.invalid = false,
    this.enabled = true,
    this.obscure = false,
    this.keyboardType,
    this.textDirection,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.mono = false,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
    this.onFocusChange,
    this.onKeyEvent,
    this.inputFormatters,
    this.textInputAction,
    this.clearable = false,
    this.selectAllOnFocus = false,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;

  /// The accessible name when there is no visible label.
  final String? semanticLabel;
  final String? leadingIcon;

  /// A leading control (a − stepper) when not a glyph.
  final Widget? leading;
  final Widget? trailing;
  final bool invalid;
  final bool enabled;
  final bool obscure;
  final TextInputType? keyboardType;

  /// Force a direction (an Arabic field in an English form, a number).
  final TextDirection? textDirection;
  final TextAlign textAlign;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool mono;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<bool>? onFocusChange;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;

  /// An × that empties the field while it has text.
  final bool clearable;
  final bool selectAllOnFocus;

  @override
  State<DashTextInput> createState() => _DashTextInputState();
}

class _DashTextInputState extends State<DashTextInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _focus.onKeyEvent = widget.onKeyEvent;
  }

  @override
  void didUpdateWidget(DashTextInput old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    _focus.onKeyEvent = widget.onKeyEvent;
    if (widget.value != _controller.text) {
      final sel = _controller.selection;
      _controller.text = widget.value;
      if (_focused && sel.isValid && sel.end <= widget.value.length) {
        _controller.selection = sel;
      }
    }
  }

  void _onFocus() {
    final f = _focus.hasFocus;
    if (f == _focused) return;
    setState(() => _focused = f);
    if (f && widget.selectAllOnFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
    widget.onFocusChange?.call(f);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownFocus?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final style =
        (widget.mono ? DashType.mono.copyWith(fontSize: 14) : DashType.body)
            .copyWith(color: c.textPrimary);
    final multiline = (widget.maxLines ?? 2) > 1;
    final clear = widget.clearable && widget.enabled && widget.value.isNotEmpty
        ? DashPressable(
            onTap: () => widget.onChanged(''),
            semanticLabel: context.dashStrings.clear,
            excludeChildSemantics: true,
            pressScale: false,
            builder: (context, s) => SizedBox.square(
              dimension: Space.xl,
              child: Center(
                child: DashIcon('x', size: IconSize.xs, color: c.textSecondary),
              ),
            ),
          )
        : null;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.text
          : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DashFieldShell(
        focused: _focused,
        hovered: _hovered,
        invalid: widget.invalid,
        enabled: widget.enabled,
        multiline: multiline,
        leading: widget.leadingIcon == null
            ? widget.leading
            : DashIcon(
                widget.leadingIcon!,
                size: IconSize.sm,
                color: c.textSecondary,
              ),
        trailing: (clear != null || widget.trailing != null)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [?clear, ?widget.trailing],
              )
            : null,
        child: Semantics(
          label: widget.semanticLabel,
          textField: true,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            obscureText: widget.obscure,
            keyboardType:
                widget.keyboardType ??
                (multiline ? TextInputType.multiline : null),
            textInputAction: widget.textInputAction,
            textDirection: widget.textDirection,
            textAlign: widget.textAlign,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            inputFormatters: widget.inputFormatters,
            style: style,
            cursorColor: c.textPrimary,
            cursorWidth: 1.5,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            decoration: InputDecoration(
              isDense: true,
              isCollapsed: true,
              border: InputBorder.none,
              counterText: '',
              hintText: widget.placeholder,
              hintStyle: style.copyWith(color: c.textMuted),
              contentPadding: EdgeInsets.symmetric(
                vertical: multiline ? Space.xs : Space.sm,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The search box over a list (the web's `SearchInput`): a magnifier, the
/// text, an × to clear. With [debounce] it holds [onChanged] until typing
/// pauses (the web's `useListSearch`: 300 ms, trimmed) and reports the
/// trimmed query; without, it reports every keystroke.
class DashSearchInput extends StatefulWidget {
  const DashSearchInput({
    required this.value,
    required this.onChanged,
    required this.placeholder,
    this.debounce,
    this.width,
    this.autofocus = false,
    super.key,
  });

  /// The query as last reported.
  final String value;
  final ValueChanged<String> onChanged;

  /// Also the accessible name — a search box has no visible label.
  final String placeholder;

  /// Wait this long after the last keystroke (`Duration(milliseconds: 300)`).
  final Duration? debounce;

  /// A fixed width; full width when null.
  final double? width;
  final bool autofocus;

  /// The web's list-search delay.
  static const Duration listDelay = Duration(milliseconds: 300);

  @override
  State<DashSearchInput> createState() => _DashSearchInputState();
}

class _DashSearchInputState extends State<DashSearchInput> {
  late String _text = widget.value;
  Timer? _timer;

  @override
  void didUpdateWidget(DashSearchInput old) {
    super.didUpdateWidget(old);
    // A reset from outside (Clear filters) replaces what is typed.
    if (widget.value != old.value && widget.value != _text.trim()) {
      _timer?.cancel();
      _text = widget.value;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _changed(String v) {
    setState(() => _text = v);
    final d = widget.debounce;
    if (d == null) {
      widget.onChanged(v);
      return;
    }
    _timer?.cancel();
    if (v.isEmpty) {
      widget.onChanged('');
      return;
    }
    _timer = Timer(d, () {
      final q = v.trim();
      if (q != widget.value) widget.onChanged(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final field = DashTextInput(
      value: _text,
      onChanged: _changed,
      placeholder: widget.placeholder,
      semanticLabel: widget.placeholder,
      leadingIcon: 'search',
      clearable: true,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
    );
    return widget.width == null
        ? field
        : SizedBox(width: widget.width, child: field);
  }
}

/// The checkbox square (the web's `Checkbox`): 16 box, ink when checked, a
/// dash when [value] is null (some of a group). The tap target is 44.
class DashCheckbox extends StatelessWidget {
  const DashCheckbox({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.enabled = true,
    this.invalid = false,
    this.alignStart = false,
    super.key,
  });

  /// The box sits at the start of its 44 target (a labelled row) rather
  /// than in its middle.
  final bool alignStart;

  /// `null` = indeterminate.
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;
  final bool enabled;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final on = value != false;
    final active = enabled && onChanged != null;
    return DashPressable(
      onTap: active ? () => onChanged!(value != true) : null,
      enabled: active,
      checked: value ?? false,
      isButton: false,
      semanticLabel: semanticLabel,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => SizedBox.square(
        dimension: DashMetrics.target,
        child: Align(
          alignment: alignStart
              ? AlignmentDirectional.centerStart
              : Alignment.center,
          child: AnimatedContainer(
            duration: DashMotion.of(context, DashMotion.fast),
            width: DashMetrics.checkbox,
            height: DashMetrics.checkbox,
            alignment: Alignment.center,
            foregroundDecoration: dashFocusRing(
              context,
              s,
              BorderRadius.circular(Space.xs),
            ),
            decoration: BoxDecoration(
              color: !active
                  ? (on ? c.muted : c.card)
                  : on
                  ? c.accent
                  : c.card,
              borderRadius: BorderRadius.circular(Space.xs),
              border: Border.all(
                color: invalid
                    ? c.danger
                    : on && active
                    ? c.accent
                    : s.hovered
                    ? Color.lerp(c.input, c.textPrimary, 0.4)!
                    : c.input,
              ),
            ),
            child: on
                ? DashIcon(
                    value == null ? 'minus' : 'check',
                    size: IconSize.xs - DashMetrics.hair,
                    color: active ? c.textOnAccent : c.textMuted,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// The switch (the web's `Switch`): a 36×20 pill, ink when on.
class DashSwitch extends StatelessWidget {
  const DashSwitch({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final active = enabled && onChanged != null;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return DashPressable(
      onTap: active ? () => onChanged!(!value) : null,
      enabled: active,
      isButton: false,
      checked: value,
      semanticLabel: semanticLabel,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => SizedBox(
        height: DashMetrics.target,
        width: DashMetrics.target,
        child: Center(
          child: Opacity(
            opacity: active ? 1 : 0.5,
            child: AnimatedContainer(
              duration: DashMotion.of(context, DashMotion.base),
              width: DashMetrics.switchWidth,
              height: DashMetrics.switchHeight,
              padding: const EdgeInsets.all(DashMetrics.hair),
              foregroundDecoration: dashFocusRing(
                context,
                s,
                BorderRadius.circular(Radii.pill),
              ),
              decoration: BoxDecoration(
                color: value ? c.accent : c.input,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: AnimatedAlign(
                duration: DashMotion.of(context, DashMotion.base),
                curve: DashMotion.ease,
                alignment: (value != rtl)
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: DashMetrics.switchHeight - 4,
                  height: DashMetrics.switchHeight - 4,
                  decoration: BoxDecoration(
                    color: value ? c.textOnAccent : c.card,
                    shape: BoxShape.circle,
                    boxShadow: MadarElevation.thumb.shadows(
                      c,
                      dark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The radio dot: a 16 ring with an ink centre when selected.
class DashRadioDot extends StatelessWidget {
  const DashRadioDot({
    required this.selected,
    this.enabled = true,
    this.focused = false,
    super.key,
  });
  final bool selected;
  final bool enabled;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      width: DashMetrics.checkbox,
      height: DashMetrics.checkbox,
      decoration: BoxDecoration(
        color: c.card,
        shape: BoxShape.circle,
        border: Border.all(color: selected && enabled ? c.accent : c.input),
        boxShadow: focused
            ? [BoxShadow(color: c.ring, spreadRadius: DashMetrics.ring)]
            : null,
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: Space.sm,
              height: Space.sm,
              decoration: BoxDecoration(
                color: enabled ? c.accent : c.textMuted,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

/// A row with a checkbox and its words, the whole row tappable (a filter
/// toggle: "Today", "Flagged only"), framed like a select trigger.
class DashCheckChip extends StatelessWidget {
  const DashCheckChip({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: () => onChanged(!value),
      checked: value,
      isButton: false,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        height: DashMetrics.control,
        padding: const EdgeInsetsDirectional.only(
          start: Space.md,
          end: Space.md,
        ),
        foregroundDecoration: dashFocusRing(
          context,
          s,
          BorderRadius.circular(Radii.sm),
        ),
        decoration: BoxDecoration(
          color: s.hovered ? c.hover : c.card,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: c.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            IgnorePointer(
              child: SizedBox(
                width: DashMetrics.checkbox,
                height: DashMetrics.checkbox,
                child: OverflowBox(
                  maxWidth: DashMetrics.target,
                  maxHeight: DashMetrics.target,
                  child: DashCheckbox(
                    value: value,
                    onChanged: (_) {},
                    semanticLabel: label,
                  ),
                ),
              ),
            ),
            Text(label, style: DashType.body.copyWith(color: c.textPrimary)),
          ],
        ),
      ),
    );
  }
}
