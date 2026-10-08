import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// What a [DashPressable] is going through right now.
@immutable
class DashPressState {
  const DashPressState({
    this.hovered = false,
    this.focused = false,
    this.pressed = false,
    this.enabled = true,
  });

  final bool hovered;

  /// Keyboard focus is showing (a ring is due).
  final bool focused;
  final bool pressed;
  final bool enabled;

  /// Hovered or pressed: the hover wash is due.
  bool get highlighted => enabled && (hovered || pressed);
}

/// The kit's one interactive surface: pointer (hover, press), keyboard
/// (focus, Enter/Space), screen reader (a button with a label) and the web's
/// `active:scale-[0.98]` press, which reduced motion turns off.
class DashPressable extends StatefulWidget {
  const DashPressable({
    required this.builder,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.semanticLabel,
    this.tooltip,
    this.selected,
    this.checked,
    this.isButton = true,
    this.focusNode,
    this.autofocus = false,
    this.pressScale = true,
    this.excludeChildSemantics = false,
    super.key,
  });

  final Widget Function(BuildContext context, DashPressState state) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;

  /// What a screen reader calls it — REQUIRED for a glyph-only control.
  final String? semanticLabel;

  /// Shown on a resting pointer or a long press.
  final String? tooltip;
  final bool? selected;
  final bool? checked;
  final bool isButton;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool pressScale;

  /// The label above says it all; the child's own text is not read twice.
  final bool excludeChildSemantics;

  @override
  State<DashPressable> createState() => _DashPressableState();
}

class _DashPressableState extends State<DashPressable> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _active => widget.enabled && widget.onTap != null;

  void _activate() {
    if (!_active) return;
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final state = DashPressState(
      hovered: _hovered,
      focused: _focused,
      pressed: _pressed,
      enabled: widget.enabled,
    );
    Widget child = widget.builder(context, state);
    if (widget.pressScale && _active && !DashMotion.reduced(context)) {
      child = AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: DashMotion.fast,
        curve: DashMotion.ease,
        child: child,
      );
    }
    child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: _active ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: _active ? () => setState(() => _pressed = false) : null,
      onTap: _active ? _activate : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      excludeFromSemantics: true,
      child: child,
    );
    child = FocusableActionDetector(
      enabled: _active,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: _active ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hovered = v),
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: child,
    );
    child = Semantics(
      container: true,
      button: widget.isButton,
      enabled: widget.enabled,
      selected: widget.selected,
      checked: widget.checked,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeChildSemantics,
      onTap: _active ? _activate : null,
      child: child,
    );
    final tip = widget.tooltip;
    if (tip != null && tip.isNotEmpty) {
      child = MadarHoldHint(
        message: tip,
        hold: widget.onLongPress == null,
        child: child,
      );
    }
    return child;
  }
}

/// The focus ring the web draws on a keyboard-focused control
/// (`ring-[3px] ring-ring/50`), as a foreground decoration.
BoxDecoration? dashFocusRing(
  BuildContext context,
  DashPressState state,
  BorderRadius radius,
) {
  if (!state.focused) return null;
  return BoxDecoration(
    borderRadius: radius,
    border: Border.all(
      color: context.madarColors.ring,
      width: DashMetrics.ring,
      strokeAlign: BorderSide.strokeAlignOutside,
    ),
  );
}

/// A Lucide/Madar glyph by name, sized and tinted — `DashIcon('search')`.
/// Names are the web's lucide names in kebab case (`chevron-down`,
/// `trash-2`); see `madarIconCatalog`.
class DashIcon extends StatelessWidget {
  const DashIcon(this.name, {this.size = IconSize.sm, this.color, super.key});

  final String name;
  final double size;

  /// Defaults to the ambient [IconTheme] colour, then the muted text.
  final Color? color;

  /// The glyph that points toward the END of the line (next, forward):
  /// `chevron-right` in English, `chevron-left` in Arabic.
  static String forward(BuildContext context) =>
      context.isRtlLayout ? 'chevron-left' : 'chevron-right';

  /// The glyph that points toward the START of the line (back, previous).
  static String backward(BuildContext context) =>
      context.isRtlLayout ? 'chevron-right' : 'chevron-left';

  /// An arrow toward the end of the line.
  static String arrowForward(BuildContext context) =>
      context.isRtlLayout ? 'arrow-left' : 'arrow-right';

  @override
  Widget build(BuildContext context) {
    final tint =
        color ??
        IconTheme.of(context).color ??
        context.madarColors.textSecondary;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: MadarIcon(name, tint: tint, size: size),
      ),
    );
  }
}

extension on BuildContext {
  bool get isRtlLayout => Directionality.of(this) == TextDirection.rtl;
}
