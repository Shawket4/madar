import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';
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

/// Which edge of the trigger a popover lines up with.
enum DashPopoverAlign { start, end }

/// A floating card anchored under (or, when there is no room, over) its
/// trigger — the web's Radix popover: a dropdown, a select list, a calendar.
/// A tap outside or Escape closes it; it never leaves the window.
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
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (_c.isOpen && !_portal.isShowing) {
      _portal.show();
    } else if (!_c.isOpen && _portal.isShowing) {
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

    final below = screen.height - pad.bottom - anchor.bottom - margin * 2;
    final above = anchor.top - pad.top - margin * 2;
    final flip = below < math.min(widget.maxHeight, 220) && above > below;
    final maxH = math.max(
      120.0,
      math.min(widget.maxHeight, flip ? above : below),
    );

    // Line up with the trigger's start (or end) edge, then keep it inside.
    final startAligned = (widget.align == DashPopoverAlign.start) != rtl;
    var left = startAligned ? anchor.left : anchor.right - width;
    left = left.clamp(
      Space.lg,
      math.max(Space.lg, screen.width - Space.lg - width),
    );
    final dx = left - anchor.left;

    final colors = context.madarColors;
    final card = Material(
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
              autofocus: widget.autofocusContent,
              child: widget.content(context, _c),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _c.close,
            excludeFromSemantics: true,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: flip ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: flip ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(dx, flip ? -margin : margin),
          child: Align(
            alignment: AlignmentDirectional.topStart,
            widthFactor: 1,
            heightFactor: 1,
            child: card,
          ),
        ),
      ],
    );
  }
}

/// One row of a [DashMenu].
@immutable
class DashMenuItem {
  const DashMenuItem({
    required this.label,
    this.onSelected,
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
      icon = null,
      destructive = false,
      enabled = false,
      checked = null,
      keepOpen = false,
      hint = null,
      divider = true;

  final String label;
  final VoidCallback? onSelected;

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
      pressScale: false,
      checked: checked,
      semanticLabel: item.label,
      excludeChildSemantics: true,
      onTap: () {
        if (checked != null) setState(() => _checked[i] = !checked);
        item.onSelected?.call();
        if (!item.keepOpen) widget.controller.close();
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

/// Opens a picker as a bottom sheet — the phone's answer to a dropdown.
Future<T?> showDashPickerSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context) builder,
  bool fullHeight = false,
}) {
  final colors = context.madarColors;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: colors.card,
    barrierColor: colors.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
    ),
    builder: (context) {
      final h = MediaQuery.sizeOf(context).height;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: fullHeight ? h : h * 0.75),
        child: SizedBox(
          height: fullHeight ? h : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Space.card,
                  Space.lg,
                  Space.sm,
                  Space.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: DashType.sectionTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    DashPressable(
                      semanticLabel: context.dashStrings.close,
                      excludeChildSemantics: true,
                      onTap: () => Navigator.of(context).maybePop(),
                      builder: (context, s) => SizedBox.square(
                        dimension: DashMetrics.target,
                        child: Center(
                          child: DashIcon(
                            'x',
                            size: IconSize.md,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                fit: fullHeight ? FlexFit.tight : FlexFit.loose,
                child: builder(context),
              ),
            ],
          ),
        ),
      );
    },
  );
}
