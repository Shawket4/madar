/// How many dimming layers are on screen, so a second one does not dim again.
///
/// Every modal surface in this kit — the sheet, the centred modal, the
/// confirm — dims the page behind it by `Opacities.scrim`, which is half
/// black. That is right for one. It is wrong for two: a sheet that opens a
/// sheet lands at 0.75, a third at 0.875, and by then the room behind is gone
/// and the teller has lost every bit of context about what they were doing
/// when they opened the first one. Stacking is not rare here — a bill opens a
/// void sheet, a table opens a bill, a payment method opens a keypad.
///
/// So the dim belongs to the STACK, not to each surface: the first one down
/// paints it, everything above it paints nothing, and the one dim stays until
/// the whole stack is gone. Depth is decided when a surface is pushed and
/// held for its lifetime — a surface can only be popped from the top, so the
/// one that claimed the dim is always the last to leave.
library;

/// The number of surfaces currently claiming the dim. Only ever 0 or 1 in
/// practice; kept as a count because the claim is released on dispose and
/// two routes can overlap for the length of one dismissal animation.
int _claimed = 0;

/// Claims the dim for a surface being pushed now.
///
/// Returns true if this surface should paint it — i.e. nothing below it
/// already is. The caller MUST call [releaseScrim] with the same answer when
/// the surface is disposed.
bool claimScrim() {
  if (_claimed > 0) return false;
  _claimed += 1;
  return true;
}

/// Releases a claim taken by [claimScrim]. A no-op when [painting] is false,
/// so callers can pass their own answer straight through.
void releaseScrim({required bool painting}) {
  if (painting && _claimed > 0) _claimed -= 1;
}

/// Whether anything is dimming the page right now — read by surfaces that
/// hand their barrier to Flutter instead of painting it themselves.
bool get scrimIsDown => _claimed > 0;

/// Test-only: forget every claim, so one test's undisposed route cannot
/// silently turn off the dim for the next.
void debugResetScrim() => _claimed = 0;
