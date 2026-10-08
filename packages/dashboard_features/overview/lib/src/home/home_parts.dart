/// Small pieces the home's cards share: the web's fixed state heights, a
/// text link with a real tap target, the entrance motion, the row that
/// gives its cards one height, and the colours of payment methods.
library;

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The web's fixed heights (Tailwind `h-64`, `h-40`, `h-24`, `h-40` donut).
abstract final class HomeMetrics {
  /// A chart's plot and its skeleton / empty / error box (`h-64`).
  static const double chart = Space.xxl * 8;

  /// The branch list's and margin watch's skeleton (`h-40`).
  static const double block = Space.xxl * 5;

  /// The open tills skeleton (`h-24`).
  static const double tills = Space.xxl * 3;

  /// The payment donut's square (outer radius 72).
  static const double donut = Space.xxl * 4.5;

  /// Width of a branch's rank column (`w-5`).
  static const double rank = Space.xl - Space.xs;
}

/// A card body of a fixed [height] showing a loading block, or a state
/// (empty / error) centred in it, the way the web sizes them (`h-64`).
class HomeStateBox extends StatelessWidget {
  const HomeStateBox({required this.child, this.height, super.key});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (height == null) return child;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height!),
      child: Center(child: child),
    );
  }
}

/// A full-width skeleton block.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) => DashSkeleton(
    width: double.infinity,
    height: height,
    radius: Radii.md,
  );
}

/// A text link (the web's `<Link>`): underlined on hover and focus, an
/// optional arrow toward the end of the line, and a 44 pt tap target.
class HomeLink extends StatelessWidget {
  const HomeLink({
    required this.label,
    required this.onTap,
    this.arrow = false,
    this.style,
    this.color,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  /// An arrow after the label (mirrored in Arabic).
  final bool arrow;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final tint = color ?? c.textPrimary;
    return DashPressable(
      onTap: onTap,
      pressScale: false,
      semanticLabel: label,
      excludeChildSemantics: true,
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.xs,
          children: [
            Text(
              label,
              style: (style ?? DashType.bodyMedium).copyWith(
                color: tint,
                decoration: s.hovered || s.focused
                    ? TextDecoration.underline
                    : null,
                decorationColor: tint,
              ),
            ),
            if (arrow)
              DashIcon(
                DashIcon.arrowForward(context),
                size: IconSize.xs,
                color: tint,
              ),
          ],
        ),
      ),
    );
  }
}

/// Fades a section up into place once (the web's `fadeInUp`, staggered by
/// [order] × 60 ms); nothing moves under reduced motion.
class HomeReveal extends StatefulWidget {
  const HomeReveal({required this.child, this.order = 0, super.key});

  final Widget child;
  final int order;

  @override
  State<HomeReveal> createState() => _HomeRevealState();
}

class _HomeRevealState extends State<HomeReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DashMotion.slow + Duration(milliseconds: 60 * widget.order),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DashMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delay = widget.order * 60 / _c.duration!.inMilliseconds;
    final curve = CurvedAnimation(
      parent: _c,
      curve: Interval(delay.clamp(0, 0.9), 1, curve: DashMotion.ease),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

/// Cards side by side sharing one height (the web's grid row with `h-full`
/// children): widths by [flex], the row as tall as its tallest card, every
/// card stretched to it.
class HomeEqualRow extends MultiChildRenderObjectWidget {
  const HomeEqualRow({
    required super.children,
    required this.flex,
    this.gap = Space.lg,
    super.key,
  });

  final List<int> flex;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderHomeEqualRow(
    flex: flex,
    gap: gap,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderHomeEqualRow renderObject) {
    renderObject
      ..flex = flex
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

class HomeEqualRowParentData extends ContainerBoxParentData<RenderBox> {}

class RenderHomeEqualRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, HomeEqualRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, HomeEqualRowParentData> {
  RenderHomeEqualRow({
    required List<int> flex,
    required double gap,
    required TextDirection textDirection,
  }) : _flex = flex,
       _gap = gap,
       _textDirection = textDirection;

  List<int> _flex;
  set flex(List<int> v) {
    _flex = v;
    markNeedsLayout();
  }

  double _gap;
  set gap(double v) {
    _gap = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    _textDirection = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! HomeEqualRowParentData) {
      child.parentData = HomeEqualRowParentData();
    }
  }

  @override
  void performLayout() {
    final kids = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      kids.add(child);
      child = childAfter(child);
    }
    final width = constraints.maxWidth;
    final total = _flex.take(kids.length).fold<int>(0, (a, b) => a + b);
    final free = width - _gap * (kids.length - 1);
    final widths = [
      for (var i = 0; i < kids.length; i++) free * _flex[i] / total,
    ];
    var tallest = 0.0;
    for (var i = 0; i < kids.length; i++) {
      kids[i].layout(BoxConstraints.tightFor(width: widths[i]), parentUsesSize: true);
      if (kids[i].size.height > tallest) tallest = kids[i].size.height;
    }
    var x = 0.0;
    for (var i = 0; i < kids.length; i++) {
      kids[i].layout(
        BoxConstraints.tight(Size(widths[i], tallest)),
        parentUsesSize: true,
      );
      final dx = _textDirection == TextDirection.rtl
          ? width - x - widths[i]
          : x;
      (kids[i].parentData! as HomeEqualRowParentData).offset = Offset(dx, 0);
      x += widths[i] + _gap;
    }
    size = constraints.constrain(Size(width, tallest));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

// ── Colours ───────────────────────────────────────────────────────────────

/// The web's chart palette (`--chart-1…6`: brand, info, success, warning,
/// violet, destructive), from the theme's roles.
List<Color> homeChartPalette(MadarColors c) => [
  c.brand,
  c.info,
  c.success,
  c.warning,
  Color.lerp(c.info, c.danger, 0.5)!,
  c.danger,
];

/// `chartColor(i)`.
Color homeChartColor(MadarColors c, int i) {
  final p = homeChartPalette(c);
  return p[i % p.length];
}

/// `PAYMENT_COLORS[method] ?? chartColor(i)`: cash green, card blue, wallet
/// violet, mixed amber, the two Talabat oranges; any other method by its
/// position.
Color homePaymentColor(MadarColors c, String method, int index) =>
    switch (method) {
      'cash' => c.success,
      'card' => c.info,
      'digital_wallet' => Color.lerp(c.info, c.danger, 0.5)!,
      'mixed' => c.warning,
      'talabat_online' => Color.lerp(c.warning, c.danger, 0.45)!,
      'talabat_cash' => Color.lerp(c.warning, c.danger, 0.2)!,
      _ => homeChartColor(c, index),
    };
