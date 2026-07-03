import 'dart:async';

import 'package:design_system/src/icons.dart';
import 'package:design_system/src/playful.dart';
import 'package:design_system/src/tokens/colors.dart';
import 'package:design_system/src/tokens/dimens.dart';
import 'package:design_system/src/tokens/elevation.dart';
import 'package:design_system/src/tokens/motion.dart';
import 'package:design_system/src/tokens/typography.dart';
import 'package:flutter/widgets.dart';

/// Semantic tone shared by toasts, chips and banners — mirrors the natives'
/// `ChipTone` (Toast.kt / Chips.kt).
enum ChipTone {
  /// Informational — tinted with [MadarColors.navy].
  info,

  /// Brand emphasis — tinted with [MadarColors.accent].
  accent,

  /// Positive confirmation — tinted with [MadarColors.success].
  success,

  /// Caution — tinted with [MadarColors.warning].
  warning,

  /// Destructive / error — tinted with [MadarColors.danger].
  danger,

  /// Default quiet tone — tinted with [MadarColors.textSecondary].
  neutral,
}

/// Tone → color resolution against the current theme's [MadarColors].
extension ChipToneColor on ChipTone {
  /// The accent color this tone maps to, per the natives' tone table.
  Color resolve(MadarColors colors) => switch (this) {
    ChipTone.info => colors.navy,
    ChipTone.accent => colors.accent,
    ChipTone.success => colors.success,
    ChipTone.warning => colors.warning,
    ChipTone.danger => colors.danger,
    ChipTone.neutral => colors.textSecondary,
  };
}

/// The data half of a toast (the action itself lives on the model) —
/// mirrors the natives' `ToastData` (Toast.kt).
@immutable
class ToastData {
  /// Creates the payload for a single toast presentation.
  const ToastData({
    required this.id,
    required this.text,
    this.tone = ChipTone.neutral,
    this.actionLabel,
    this.seconds = 2.6,
    this.icon,
    this.sticky = false,
  });

  /// Unique identifier — a new id restarts the auto-dismiss timer.
  final int id;

  /// Message text.
  final String text;

  /// Semantic tone driving the icon / action tint.
  final ChipTone tone;

  /// Optional action label rendered after the message.
  final String? actionLabel;

  /// Auto-dismiss delay in seconds. Ignored when [sticky].
  final double seconds;

  /// Optional `MadarIcon` name rendered before the message.
  final String? icon;

  /// Sticky toasts never auto-dismiss — they stay until the host clears
  /// them (e.g. the new-order alert persists until Incoming is viewed).
  final bool sticky;
}

/// Bottom offset of the pill from the host's bottom edge (natives: 40.dp).
const double _bottomOffset = Space.xl + Space.lg;

/// Max pill width (natives: 460.dp).
const double _maxWidth = 460;

/// A transient bottom-center pill mirroring the natives' `ToastHost`
/// (Toast.kt) — one optional action, auto-dismiss after [ToastData.seconds].
///
/// Render once at the root, above the route and any sheets, inside a loose
/// [Stack]. Decoupled from any model: the host wires [onAction] and
/// [onDismiss]. The last payload stays visible through the exit animation,
/// so flipping [toast] back to `null` never hard-cuts the content.
class ToastHost extends StatefulWidget {
  /// Creates a toast presenter for [toast]; pass `null` to dismiss.
  const ToastHost(this.toast, {this.onAction, this.onDismiss, super.key});

  /// The toast to show, or `null` to animate the current one out.
  final ToastData? toast;

  /// Invoked when the action label is tapped.
  final VoidCallback? onAction;

  /// Invoked with the toast's id when its auto-dismiss timer elapses.
  final ValueChanged<int>? onDismiss;

  @override
  State<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<ToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionSpec.standardDuration,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: MotionSpec.standardCurve,
    reverseCurve: MotionSpec.standardCurve.flipped,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.5),
    end: Offset.zero,
  ).animate(_curve);

  /// Last shown payload — kept so the exit animation has content to render
  /// after [ToastHost.toast] flips back to null (no hard cut).
  ToastData? _shown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
    if (widget.toast != null) _present(widget.toast!);
  }

  @override
  void didUpdateWidget(ToastHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final toast = widget.toast;
    if (toast != null) {
      if (toast.id != oldWidget.toast?.id) {
        _present(toast);
      } else {
        _shown = toast;
      }
    } else if (oldWidget.toast != null) {
      _timer?.cancel();
      unawaited(_controller.reverse());
    }
  }

  void _present(ToastData toast) {
    _shown = toast;
    unawaited(_controller.forward());
    _timer?.cancel();
    if (toast.sticky) return;
    _timer = Timer(
      Duration(milliseconds: (toast.seconds * 1000).round()),
      () => widget.onDismiss?.call(toast.id),
    );
  }

  void _onStatus(AnimationStatus status) {
    // Fully exited with nothing pending: drop the payload from the tree.
    if (status == AnimationStatus.dismissed && widget.toast == null) {
      setState(() => _shown = null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _shown;
    if (data == null) return const SizedBox.shrink();
    final colors = context.madarColors;
    final tone = data.tone.resolve(colors);
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        ignoring: widget.toast == null,
        child: FadeTransition(
          opacity: _curve,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.only(bottom: _bottomOffset),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    border: Border.all(color: colors.border),
                    boxShadow: MadarElevation.raised.shadows(
                      colors,
                      dark: dark,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg,
                      vertical: Space.md,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (data.icon != null) ...[
                          // The chosen new-order animation: a bell icon rings
                          // (decaying swing + halo) as its toast presents.
                          if (data.icon == 'bell')
                            BellShake(
                              trigger: data.id,
                              child: MadarIcon(data.icon, tint: tone),
                            )
                          else
                            MadarIcon(data.icon, tint: tone),
                          const SizedBox(width: Space.sm),
                        ],
                        Flexible(
                          child: Text(
                            data.text,
                            style: MadarType.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (data.actionLabel != null) ...[
                          const SizedBox(width: Space.sm),
                          _ToastAction(
                            label: data.actionLabel!,
                            color: tone,
                            onTap: widget.onAction,
                          ),
                        ],
                      ],
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

/// The tappable action label — Cairo Black 13 in the tone accent.
class _ToastAction extends StatelessWidget {
  const _ToastAction({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: Space.xs),
          child: Text(
            label,
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
