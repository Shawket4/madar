/// A side column beside the main one that follows the page's scroll
/// [Space.lg] under the top, never past the row's end (the web's
/// `sticky top-4` in a two-column grid): the settings rail, the Links
/// preview.
library;

import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

class StickyBeside extends StatefulWidget {
  const StickyBeside({
    required this.main,
    required this.side,
    required this.sideWidth,
    required this.gap,
    this.sideFirst = false,
    super.key,
  });

  final Widget main;
  final Widget side;
  final double sideWidth;
  final double gap;

  /// The side column at the start (the rail) instead of the end.
  final bool sideFirst;

  @override
  State<StickyBeside> createState() => _StickyBesideState();
}

class _StickyBesideState extends State<StickyBeside> {
  final _side = GlobalKey();
  ScrollableState? _scrollable;
  double _shift = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Scrollable.maybeOf(context);
    if (s != _scrollable) {
      _scrollable?.position.removeListener(_follow);
      _scrollable = s?..position.addListener(_follow);
    }
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_follow);
    super.dispose();
  }

  void _follow() {
    final row = context.findRenderObject() as RenderBox?;
    final side = _side.currentContext?.findRenderObject() as RenderBox?;
    final view = _scrollable?.context.findRenderObject() as RenderBox?;
    if (row == null || side == null || view == null) return;
    if (!row.hasSize || !side.hasSize || !row.attached || !view.attached) {
      return;
    }
    final top = row.localToGlobal(Offset.zero, ancestor: view).dy;
    final room = math.max(0.0, row.size.height - side.size.height);
    final next = (Space.lg - top).clamp(0.0, room);
    if (next != _shift) setState(() => _shift = next);
  }

  @override
  Widget build(BuildContext context) {
    // The main column's height changes as it loads: follow after each layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _follow();
    });
    final side = Transform.translate(
      offset: Offset(0, _shift),
      child: SizedBox(key: _side, width: widget.sideWidth, child: widget.side),
    );
    final main = Expanded(child: widget.main);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: widget.gap,
      children: widget.sideFirst ? [side, main] : [main, side],
    );
  }
}
