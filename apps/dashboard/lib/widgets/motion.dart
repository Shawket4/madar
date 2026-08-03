import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../format.dart';

/// Staggered entrance: fade + a small fixed upward rise (both GPU-safe) after
/// an optional [delay]. Curve matches the web's product ease-out-quart.
class Reveal extends StatefulWidget {
  const Reveal({required this.child, this.delay = Duration.zero, super.key});

  final Widget child;
  final Duration delay;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _shown = true;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _shown ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutQuart,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - v) * 10),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Desktop hover-lift (the web's `liftCard`): raises the child a few pixels
/// with a soft shadow on pointer hover.
class HoverLift extends StatefulWidget {
  const HoverLift({required this.child, this.radius = Radii.md, super.key});

  final Widget child;
  final double radius;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

/// A money amount (minor units) that counts up — starting after [delay] so it
/// syncs with a staggered reveal. Locale-aware (Arabic-Indic + ج.م in Arabic).
class AnimatedMoney extends ConsumerStatefulWidget {
  const AnimatedMoney(
    this.minor, {
    required this.currency,
    this.style,
    this.color,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 1100),
    super.key,
  });

  final int minor;
  final String currency;
  final TextStyle? style;
  final Color? color;
  final Duration delay;
  final Duration duration;

  @override
  ConsumerState<AnimatedMoney> createState() => _AnimatedMoneyState();
}

class _AnimatedMoneyState extends ConsumerState<AnimatedMoney> {
  bool _go = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _go = true;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _go = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final base = widget.style ?? MadarType.moneyLg;
    final resolved = widget.color ?? base.color ?? context.madarColors.accent;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _go ? widget.minor.toDouble() : 0),
      duration: widget.duration,
      curve: Curves.easeOutQuart,
      builder: (context, value, _) => Text(
        fmtMoney(value.round(), currency: widget.currency, locale: locale),
        style: base.copyWith(color: resolved),
      ),
    );
  }
}

/// An integer that counts up after [delay] (locale-aware digits).
class AnimatedCountText extends ConsumerStatefulWidget {
  const AnimatedCountText(
    this.value, {
    required this.style,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 1100),
    super.key,
  });

  final int value;
  final TextStyle style;
  final Duration delay;
  final Duration duration;

  @override
  ConsumerState<AnimatedCountText> createState() => _AnimatedCountTextState();
}

class _AnimatedCountTextState extends ConsumerState<AnimatedCountText> {
  bool _go = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _go = true;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _go = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: _go ? widget.value.toDouble() : 0),
      duration: widget.duration,
      curve: Curves.easeOutQuart,
      builder: (context, v, _) =>
          Text(fmtInt(v.round(), locale: locale), style: widget.style),
    );
  }
}
