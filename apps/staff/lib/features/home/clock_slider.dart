import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../../ui/kit.dart';

/// The signature control: a 56px track whose knob is dragged to clock in or out.
///
/// A slide rather than a button because clocking in is a CLAIM about where you
/// are and when — the friction is the point, and it makes an accidental pocket
/// tap impossible. Drag past 60% to clock in, back below 40% to clock out;
/// anything less springs back. A plain tap still works, because insisting on a
/// gesture would punish someone holding a tray.
class ClockSlider extends StatefulWidget {
  const ClockSlider({
    required this.clockedIn,
    required this.labelIn,
    required this.labelOut,
    required this.onToggle,
    this.enabled = true,
    super.key,
  });

  final bool clockedIn;
  final String labelIn;
  final String labelOut;

  /// Called once the gesture commits. The caller does the network work and
  /// flips [clockedIn] when the SERVER confirms it.
  final VoidCallback onToggle;

  /// False outside the geofence — the track dims and stops responding.
  final bool enabled;

  @override
  State<ClockSlider> createState() => _ClockSliderState();
}

class _ClockSliderState extends State<ClockSlider> {
  static const double _height = 56;
  static const double _knob = 48;
  static const double _inset = 3;

  /// 0 = knob at the start, 1 = knob at the end.
  late double _fraction = widget.clockedIn ? 1 : 0;
  bool _dragging = false;

  @override
  void didUpdateWidget(ClockSlider old) {
    super.didUpdateWidget(old);
    // The server is the authority on whether the punch landed, so the resting
    // position follows the confirmed state rather than the gesture.
    if (old.clockedIn != widget.clockedIn && !_dragging) {
      setState(() => _fraction = widget.clockedIn ? 1 : 0);
    }
  }

  void _settle() {
    final committed = widget.clockedIn ? _fraction <= 0.4 : _fraction >= 0.6;
    setState(() {
      _dragging = false;
      _fraction = committed
          ? (widget.clockedIn ? 0 : 1)
          : (widget.clockedIn ? 1 : 0);
    });
    if (committed) widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return Opacity(
      opacity: widget.enabled ? 1 : Opacities.disabled,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final travel = constraints.maxWidth - _knob - _inset * 2;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? widget.onToggle : null,
            onHorizontalDragStart: widget.enabled
                ? (_) => setState(() => _dragging = true)
                : null,
            onHorizontalDragUpdate: widget.enabled
                ? (details) {
                    // In RTL the track runs the other way, so a drag toward the
                    // screen's start is still a drag toward "done".
                    final delta = rtl ? -details.delta.dx : details.delta.dx;
                    setState(
                      () => _fraction = (_fraction + delta / travel).clamp(
                        0.0,
                        1.0,
                      ),
                    );
                  }
                : null,
            onHorizontalDragEnd: widget.enabled ? (_) => _settle() : null,
            onHorizontalDragCancel: widget.enabled ? _settle : null,
            child: SizedBox(
              height: _height,
              child: Stack(
                children: [
                  // Track.
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(Radii.pill),
                      border: Border.all(color: colors.border),
                    ),
                  ),
                  // Accent wash that fades in with the drag.
                  Opacity(
                    opacity: _fraction,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  ),
                  // The two labels cross-fade so the track always reads as the
                  // action it is about to perform.
                  Center(
                    child: Opacity(
                      opacity: 1 - _fraction,
                      child: Text(
                        widget.labelIn,
                        style: MadarType.body.copyWith(
                          color: colors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Opacity(
                      opacity: _fraction,
                      child: Text(
                        widget.labelOut,
                        style: MadarType.body.copyWith(
                          color: colors.textOnAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositionedDirectional(
                    duration: _dragging
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    curve: const Cubic(0.2, 0.8, 0.2, 1),
                    top: _inset,
                    start: _inset + _fraction * travel,
                    child: _Knob(clockedIn: widget.clockedIn, size: _knob),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({required this.clockedIn, required this.size});

  final bool clockedIn;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: clockedIn ? colors.surface : colors.accent,
        shape: BoxShape.circle,
        // Clocked out the knob GLOWS — it is the one thing on the screen
        // asking to be touched. Clocked in it is a plain white disc.
        boxShadow: shadowsOf(
          context,
          clockedIn ? MadarElevation.card : MadarElevation.glow,
        ),
      ),
      alignment: Alignment.center,
      child: MadarIcon(
        // Points the way the knob must travel.
        clockedIn ? 'chevron.backward' : 'chevron.forward',
        tint: clockedIn ? colors.accent : colors.textOnAccent,
        size: IconSize.xl,
      ),
    );
  }
}
