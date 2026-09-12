/// How many dimming layers are on screen, so a second one does not dim again.
///
/// Every modal surface in this kit — the sheet, the drawer, the centred
/// modal, the confirm, the Done card — dims the page behind it by
/// `Opacities.scrim`, which is half black. That is right for one. It is wrong
/// for two: a sheet that opens a sheet lands at 0.75, a third at 0.875, and by
/// then the room behind is gone.
///
/// So the dim belongs to the STACK, not to each surface: the first one down
/// paints it, everything above it paints nothing, and the one dim stays until
/// the whole stack is gone.
///
/// The HANDOFF. A surface gives its claim back the moment it starts to leave
/// (not when it is disposed a frame or an animation later) — otherwise the
/// next surface, pushed the instant the first one's future resolves, would
/// see the dim still taken and paint none, and the old one would then fade
/// its dim away beneath it. While it fades out the leaving surface stays the
/// "fading" claim; a new painter arriving in that window takes over the dim
/// at the exact opacity the leaver had reached, and the leaver drops its own
/// to nothing. One dim, continuous, no flash and no double.
library;

import 'package:flutter/widgets.dart';

/// One surface's stake in the shared dim. Obtain with [ScrimClaim.claim].
class ScrimClaim {
  ScrimClaim._({required this.paints, required this.startOpacity});

  /// Claims the dim for a surface being pushed now.
  factory ScrimClaim.claim() {
    if (_painters > 0) {
      return ScrimClaim._(paints: false, startOpacity: 0);
    }
    _painters += 1;
    final previous = _fading;
    var start = 0.0;
    if (previous != null) {
      start = previous.visibleOpacity?.call() ?? 0;
      previous._supersede();
    }
    return ScrimClaim._(paints: true, startOpacity: start.clamp(0, 1));
  }

  /// Whether this surface paints the dim (nothing below it already does).
  final bool paints;

  /// Where this painter's dim should START (0..1 of the full dim) — non-zero
  /// when it took over from a surface still fading out.
  final double startOpacity;

  /// The owner reports how visible its dim currently is (0..1), so a
  /// successor can pick up from there.
  double Function()? visibleOpacity;

  /// True once a newer painter took over the dim — the owner must stop
  /// painting its own (it is on its way out anyway).
  final ValueNotifier<bool> superseded = ValueNotifier<bool>(false);

  bool _released = false;
  bool _gone = false;

  /// Gives the dim back — call when the surface STARTS to leave. Idempotent.
  void release() {
    if (_released) return;
    _released = true;
    if (!paints) return;
    if (_painters > 0) _painters -= 1;
    if (!_gone && !superseded.value) _fading = this;
  }

  /// The surface is fully gone (disposed). Releases if it never did.
  void dispose() {
    release();
    _gone = true;
    if (identical(_fading, this)) _fading = null;
  }

  void _supersede() {
    if (identical(_fading, this)) _fading = null;
    if (!_gone) superseded.value = true;
  }
}

int _painters = 0;
ScrimClaim? _fading;

/// Claims the dim for a surface being pushed now (boolean form, for callers
/// that have no fade to hand over).
///
/// Returns true if this surface should paint it. The caller MUST call
/// [releaseScrim] with the same answer when the surface starts to leave.
bool claimScrim() {
  if (_painters > 0) return false;
  _painters += 1;
  _fading?._supersede();
  return true;
}

/// Releases a claim taken by [claimScrim]. A no-op when [painting] is false.
void releaseScrim({required bool painting}) {
  if (painting && _painters > 0) _painters -= 1;
}

/// Whether anything is dimming the page right now.
bool get scrimIsDown => _painters > 0;

/// Test-only: forget every claim.
void debugResetScrim() {
  _painters = 0;
  _fading = null;
}

/// The dim itself, for a surface that holds [claim]: [opacity] (0..1) of the
/// shared black scrim, nothing at all when the claim does not paint or was
/// superseded by a newer painter.
class StackScrim extends StatelessWidget {
  /// Creates the dim layer.
  const StackScrim({required this.claim, required this.opacity, super.key});

  /// The surface's claim.
  final ScrimClaim claim;

  /// How much of the full dim to show.
  final Animation<double> opacity;

  /// Pure black in both themes at half — `Opacities.scrim`.
  static const Color color = Color.from(alpha: 0.5, red: 0, green: 0, blue: 0);

  @override
  Widget build(BuildContext context) {
    if (!claim.paints) return const SizedBox.expand();
    return ValueListenableBuilder<bool>(
      valueListenable: claim.superseded,
      builder: (context, gone, _) => gone
          ? const SizedBox.expand()
          : FadeTransition(
              opacity: opacity,
              child: const ColoredBox(color: color),
            ),
    );
  }
}
