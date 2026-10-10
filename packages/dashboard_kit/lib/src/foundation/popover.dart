import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'press.dart';
import 'tokens.dart';

/// Opens and closes a [DashPopover] from outside (a trigger, a test).
class DashPopoverController extends ChangeNotifier {
  bool _open = false;
  bool get isOpen => _open;

  void open() {
    if (_open) return;
    _open = true;
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }

  void toggle() => _open ? close() : open();
}

/// The theme a popover's card is drawn in when its trigger sits on a surface
/// of another theme: the shell's dark header opens cards in the page's
/// colours, as the web's header dropdowns are.
class DashPopoverTheme extends InheritedWidget {
  const DashPopoverTheme({required this.data, required super.child, super.key});

  final ThemeData data;

  static ThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashPopoverTheme>()?.data;

  @override
  bool updateShouldNotify(DashPopoverTheme old) => old.data != data;
}

/// Which edge of the trigger a popover lines up with ([center]: its middle,
/// the web's `align="center"`).
enum DashPopoverAlign { start, end, center }

/// A floating card anchored under (or, when it does not fit there, over) its
/// trigger — the web's Radix popover: a dropdown, a select list, a calendar.
/// A tap outside or Escape closes it; it never leaves the window. When it
/// fits on neither side it is capped to the roomier one, so content that can
/// be that tall scrolls itself (a list, or a `SingleChildScrollView`).
class DashPopover extends StatefulWidget {
  const DashPopover({
    required this.anchor,
    required this.content,
    this.controller,
    this.width,
    this.matchAnchorWidth = false,
    this.align = DashPopoverAlign.start,
    this.maxHeight = 360,
    this.onClose,
    this.autofocusContent = true,
    super.key,
  });

  /// The trigger. Receives the controller to open it.
  final Widget Function(BuildContext context, DashPopoverController c) anchor;

  /// The card's content.
  final Widget Function(BuildContext context, DashPopoverController c) content;

  final DashPopoverController? controller;

  /// The card's width; defaults to [DashMetrics.popover].
  final double? width;

  /// At least as wide as the trigger (a select's list).
  final bool matchAnchorWidth;
  final DashPopoverAlign align;
  final double maxHeight;
  final VoidCallback? onClose;

  /// Move focus into the card when it opens (off for a list that follows
  /// typing in its trigger).
  final bool autofocusContent;

  @override
  State<DashPopover> createState() => _DashPopoverState();
}

class _DashPopoverState extends State<DashPopover> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _scope = FocusScopeNode(debugLabel: 'DashPopover');
  DashPopoverController? _own;
  DashPopoverController get _c =>
      widget.controller ?? (_own ??= DashPopoverController());

  @override
  void initState() {
    super.initState();
    _c.addListener(_sync);
  }

  @override
  void didUpdateWidget(DashPopover old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_sync);
      _c.addListener(_sync);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_sync);
    _own?.dispose();
    _scope.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (_c.isOpen && !_portal.isShowing) {
      _portal.show();
    } else if (!_c.isOpen && _portal.isShowing) {
      // Hand focus back now: a card that still holds it when it is torn
      // down next frame pulls focus to the page, away from a dialog its
      // choice just opened (whose Escape then goes nowhere).
      if (_scope.hasFocus) {
        _scope.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
      }
      _portal.hide();
      widget.onClose?.call();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _overlay,
        child: widget.anchor(context, _c),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final box = this.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final origin = box.localToGlobal(Offset.zero);
    final anchor = origin & box.size;
    const margin = Space.sm;
    final rtl = Directionality.of(this.context) == TextDirection.rtl;

    var width = widget.width ?? DashMetrics.popover;
    if (widget.matchAnchorWidth) width = math.max(width, anchor.width);
    width = math.min(width, screen.width - Space.lg * 2);

    // The overlay the card is drawn (and clipped) in: the window, or a
    // shell page's area under its header.
    final host = Overlay.maybeOf(context)?.context.findRenderObject();
    final area = host is RenderBox && host.hasSize
        ? host.localToGlobal(Offset.zero) & host.size
        : Offset.zero & screen;
    final top = math.max(area.top, pad.top);
    // Above the keyboard: a phone's searchable list opens over it, not under.
    final bottom = math.min(
      area.bottom,
      screen.height -
          math.max(pad.bottom, MediaQuery.viewInsetsOf(context).bottom),
    );

    // The room under and over the trigger. The card opens below when it
    // fits there, above when it fits there instead, and otherwise on the
    // roomier side, capped to it (its content scrolls).
    final below = bottom - anchor.bottom - margin * 2;
    final above = anchor.top - top - margin * 2;
    final maxH = math.max(
      120.0,
      math.min(widget.maxHeight, math.max(above, below)),
    );

    // Line up with the trigger's start (or end) edge, then keep it inside.
    final startAligned = (widget.align == DashPopoverAlign.start) != rtl;
    var left = widget.align == DashPopoverAlign.center
        ? anchor.center.dx - width / 2
        : startAligned
        ? anchor.left
        : anchor.right - width;
    left = left.clamp(
      Space.lg,
      math.max(Space.lg, screen.width - Space.lg - width),
    );
    final dx = left - anchor.left;

    // A trigger on another surface (the shell's dark header) still opens a
    // card in the page's colours, as the web's dropdowns are.
    final paper = DashPopoverTheme.maybeOf(this.context);
    Widget card = Builder(
      builder: (context) {
        final colors = context.madarColors;
        return Material(
          type: MaterialType.transparency,
          child: Container(
            width: width,
            constraints: BoxConstraints(maxHeight: maxH),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(Radii.control),
              border: Border.all(color: colors.hairline),
              boxShadow: DashShadows.popover(context),
            ),
            clipBehavior: Clip.antiAlias,
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              },
              child: Actions(
                actions: {
                  DismissIntent: CallbackAction<DismissIntent>(
                    onInvoke: (_) {
                      _c.close();
                      return null;
                    },
                  ),
                },
                child: FocusScope(
                  node: _scope,
                  autofocus: widget.autofocusContent,
                  child: widget.content(context, _c),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (paper != null) card = Theme(data: paper, child: card);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _c.close,
            excludeFromSemantics: true,
          ),
        ),
        // A column as tall as the overlay, over the trigger, so the side is
        // chosen once the card's own height is known.
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: Offset(dx, area.top - anchor.top),
          child: _Placement(
            size: Size(width, area.height),
            top: anchor.top - area.top,
            bottom: anchor.bottom - area.top,
            above: above,
            below: below,
            margin: margin,
            child: card,
          ),
        ),
      ],
    );
  }
}

/// Puts the card under the trigger when it fits, else over it when it fits
/// there, else on the roomier side (where its capped height fits).
class _Placement extends SingleChildRenderObjectWidget {
  const _Placement({
    required this.size,
    required this.top,
    required this.bottom,
    required this.above,
    required this.below,
    required this.margin,
    super.child,
  });

  /// The column: the card's width, the overlay's height.
  final Size size;

  /// The trigger's edges in the column's frame (the overlay's).
  final double top;
  final double bottom;
  final double above;
  final double below;
  final double margin;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlacement(this);

  @override
  void updateRenderObject(BuildContext context, _RenderPlacement r) =>
      r.spec = this;
}

class _RenderPlacement extends RenderShiftedBox {
  _RenderPlacement(this._spec) : super(null);

  _Placement _spec;
  set spec(_Placement v) {
    _spec = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    size = constraints.constrain(_spec.size);
    final card = child;
    if (card == null) return;
    card.layout(BoxConstraints.loose(_spec.size), parentUsesSize: true);
    final h = card.size.height;
    final up =
        h > _spec.below && (h <= _spec.above || _spec.above > _spec.below);
    (card.parentData! as BoxParentData).offset = Offset(
      0,
      up ? _spec.top - _spec.margin - h : _spec.bottom + _spec.margin,
    );
  }

  // The card follows its trigger (a page scrolled under an open menu moves
  // both), so it can sit outside this column: it takes taps wherever it is.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);
}

/// One row of a [DashMenu].
@immutable
class DashMenuItem {
  const DashMenuItem({
    required this.label,
    this.onSelected,
    this.onIntent,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.checked,
    this.keepOpen = false,
    this.hint,
  }) : divider = false;

  /// A hairline between groups.
  const DashMenuItem.divider()
    : label = '',
      onSelected = null,
      onIntent = null,
      icon = null,
      destructive = false,
      enabled = false,
      checked = null,
      keepOpen = false,
      hint = null,
      divider = true;

  final String label;
  final VoidCallback? onSelected;

  /// About to be chosen ([DashIntent]): warm the read [onSelected] opens (a
  /// dialog's data). Never a write.
  final VoidCallback? onIntent;

  /// A `MadarIcon` name drawn before the label.
  final String? icon;
  final bool destructive;
  final bool enabled;

  /// A checkbox item (column visibility) when not null.
  final bool? checked;

  /// Leaves the menu open after selecting (checkbox items).
  final bool keepOpen;

  /// A quiet word on the end side.
  final String? hint;
  final bool divider;
}

/// A dropdown menu on a trigger — the web's `DropdownMenu`.
class DashMenu extends StatelessWidget {
  const DashMenu({
    required this.items,
    required this.builder,
    this.align = DashPopoverAlign.end,
    this.width = DashMetrics.menu,
    this.controller,
    super.key,
  });

  final List<DashMenuItem> items;

  /// The trigger; call `c.toggle` from its tap.
  final Widget Function(BuildContext context, DashPopoverController c) builder;
  final DashPopoverAlign align;
  final double width;
  final DashPopoverController? controller;

  @override
  Widget build(BuildContext context) {
    return DashPopover(
      controller: controller,
      width: width,
      align: align,
      anchor: builder,
      content: (context, c) => _MenuList(items: items, controller: c),
    );
  }
}

class _MenuList extends StatefulWidget {
  const _MenuList({required this.items, required this.controller});
  final List<DashMenuItem> items;
  final DashPopoverController controller;

  @override
  State<_MenuList> createState() => _MenuListState();
}

class _MenuListState extends State<_MenuList> {
  late final Map<int, bool> _checked = {
    for (var i = 0; i < widget.items.length; i++)
      if (widget.items[i].checked != null) i: widget.items[i].checked!,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widget.items.length; i++)
            if (widget.items[i].divider)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Divider(height: 1, thickness: 1, color: colors.hairline),
              )
            else
              _row(context, i, widget.items[i]),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i, DashMenuItem item) {
    final colors = context.madarColors;
    final checked = _checked[i];
    final fg = !item.enabled
        ? colors.disabledText
        : item.destructive
        ? colors.errorText
        : colors.textPrimary;
    return DashPressable(
      enabled: item.enabled,
      onIntent: item.onIntent,
      pressScale: false,
      checked: checked,
      semanticLabel: item.label,
      excludeChildSemantics: true,
      onTap: () {
        if (checked != null) setState(() => _checked[i] = !checked);
        // Close first, so a dialog the item opens keeps the focus (and its
        // Escape).
        if (!item.keepOpen) widget.controller.close();
        item.onSelected?.call();
      },
      builder: (context, s) => Container(
        constraints: const BoxConstraints(
          minHeight: DashMetrics.target - Space.xs,
        ),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.sm),
        decoration: BoxDecoration(
          color: s.highlighted || s.focused ? colors.hover : null,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Row(
          spacing: Space.sm,
          children: [
            if (checked != null)
              SizedBox.square(
                dimension: IconSize.sm,
                child: checked
                    ? DashIcon('check', size: IconSize.sm, color: fg)
                    : null,
              )
            else if (item.icon != null)
              DashIcon(
                item.icon!,
                size: IconSize.sm,
                color: item.destructive ? fg : colors.textSecondary,
              ),
            Expanded(
              child: MadarClippedText(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(color: fg),
              ),
            ),
            if (item.hint != null)
              Text(
                item.hint!,
                style: DashType.small.copyWith(color: colors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}
