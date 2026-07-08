import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Device-class-aware screen-orientation lock.
///
/// Tablets/desktop lock to ONE landscape at a time — never auto-rotating —
/// and the user flips between the two with a button. Phones lock to normal
/// portrait with no flip. App-global platform state, so it's a singleton
/// (it must be the same instance across the app's separate provider
/// containers — see the ready-scope split in main.dart).
class OrientationController extends ChangeNotifier {
  OrientationController._();

  /// The one instance every screen reads.
  static final OrientationController instance = OrientationController._();

  /// Android's mdpi baseline: 160 logical (dp) pixels per inch. Because dp is
  /// already density-normalized, this ratio holds regardless of the device's
  /// actual devicePixelRatio.
  static const double _dpPerInch = 160;

  /// Default tablet cutoff, in diagonal inches. A shortest-side dp check
  /// (Material's old sw600 convention) misreads small, low-aspect-ratio ~7"
  /// tablets as phones when their reported density inflates devicePixelRatio;
  /// the full diagonal holds up across odd aspect ratios. User-configurable
  /// via [setTabletThresholdInches] for exactly that kind of device quirk.
  static const double defaultTabletThresholdInches = 7;

  double _tabletThresholdInches = defaultTabletThresholdInches;
  Size _lastSize = Size.zero;
  bool _isTablet = true;
  bool _landscapeRight = true;
  bool _applied = false;

  /// Tablet/desktop → landscape with a flip; phone → portrait, no flip.
  bool get isTablet => _isTablet;

  /// Which of the two landscape locks is active (tablet only).
  bool get landscapeRight => _landscapeRight;

  /// The flip is only meaningful on a tablet (phones are portrait-locked).
  bool get canFlip => _isTablet;

  /// Current tablet cutoff, in diagonal inches.
  double get tabletThresholdInches => _tabletThresholdInches;

  /// Host hook that persists the flip choice — the app wires this to its
  /// vault at boot (this package is storage-agnostic). Called after each
  /// user [flip]; never on [restoreFlip] (no persist echo).
  void Function({required bool landscapeRight})? persister;

  /// Host hook that persists the tablet threshold — wired at boot like
  /// [persister]. Called after each [setTabletThresholdInches]; never on
  /// [restoreTabletThresholdInches] (no persist echo).
  void Function({required double tabletThresholdInches})? thresholdPersister;

  /// Diagonal screen size in inches, assuming the 160dp/inch baseline.
  static double diagonalInches(Size size) {
    if (size.isEmpty) return 0;
    return math.sqrt(size.width * size.width + size.height * size.height) /
        _dpPerInch;
  }

  /// Set the device class from a logical [size] (from the platform view at
  /// launch, then confirmed from MediaQuery on the first frame) and apply
  /// the lock. Applies once per distinct class; safe to call every build.
  void setDeviceClass({required Size size}) {
    if (!size.isEmpty) _lastSize = size;
    // No signal yet (physicalSize can be 0 pre-frame) → default to tablet;
    // the MediaQuery-confirmed call corrects it on first frame.
    final isTablet =
        _lastSize.isEmpty ||
        diagonalInches(_lastSize) >= _tabletThresholdInches;
    if (_applied && isTablet == _isTablet) return;
    _isTablet = isTablet;
    _apply();
    // Deferred so a MediaQuery-time caller (MaterialApp.builder) never
    // notifies listeners mid-build.
    scheduleMicrotask(notifyListeners);
  }

  /// Change the tablet cutoff (diagonal inches) and re-evaluate the current
  /// device against it.
  void setTabletThresholdInches(double inches) {
    if (_tabletThresholdInches == inches) return;
    _setThresholdInches(inches);
    thresholdPersister?.call(tabletThresholdInches: inches);
    scheduleMicrotask(notifyListeners);
  }

  /// Seed the persisted threshold at boot — re-evaluates against whatever
  /// [Size] has already landed via [setDeviceClass].
  void restoreTabletThresholdInches(double inches) {
    if (_tabletThresholdInches == inches) return;
    _setThresholdInches(inches);
    scheduleMicrotask(notifyListeners);
  }

  void _setThresholdInches(double inches) {
    _tabletThresholdInches = inches;
    if (_lastSize.isEmpty) return;
    final isTablet = diagonalInches(_lastSize) >= _tabletThresholdInches;
    if (isTablet != _isTablet) {
      _isTablet = isTablet;
      _apply();
    }
  }

  /// Seed the persisted flip at boot (the vault loads async, so this lands
  /// once boot completes — the splash is orientation-neutral). Applies only
  /// when it changes the current lock; notify deferred like
  /// [setDeviceClass] (boot completion can land mid-build).
  void restoreFlip({required bool landscapeRight}) {
    if (_landscapeRight == landscapeRight) return;
    _landscapeRight = landscapeRight;
    if (_isTablet) _apply();
    scheduleMicrotask(notifyListeners);
  }

  /// Toggle between the two landscape locks (tablet only). No-op on phones.
  void flip() {
    if (!_isTablet) return;
    _landscapeRight = !_landscapeRight;
    _apply();
    persister?.call(landscapeRight: _landscapeRight);
    notifyListeners();
  }

  void _apply() {
    _applied = true;
    final orientations = <DeviceOrientation>[
      if (!_isTablet)
        DeviceOrientation.portraitUp
      else if (_landscapeRight)
        DeviceOrientation.landscapeRight
      else
        DeviceOrientation.landscapeLeft,
    ];
    unawaited(SystemChrome.setPreferredOrientations(orientations));
  }
}

/// A `MaterialApp.builder` that confirms the device class from MediaQuery
/// (reliable once a frame exists) and re-applies the orientation lock. Use
/// on every MaterialApp so the lock is correct regardless of which one is
/// mounted (splash vs the ready shell).
Widget orientationProbe(BuildContext context, Widget? child) {
  OrientationController.instance.setDeviceClass(
    size: MediaQuery.sizeOf(context),
  );
  // App-wide tap-to-dismiss: a tap that lands outside any field drops focus
  // (and hides the keyboard). Paired with EntranceFocus (never raw autofocus),
  // this keeps the iPad text-input connection from wedging on route changes.
  return GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: child ?? const SizedBox.shrink(),
  );
}
