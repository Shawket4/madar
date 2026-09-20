import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The three states of the orientation preference. An explicit lock always
/// wins over the device-class default; [device] is that default (tablet →
/// landscape, phone → portrait — see [OrientationController.setDeviceClass]).
enum OrientationMode {
  device,
  portrait,
  landscape;

  /// Parses a persisted string, defaulting to [device] for anything else
  /// (including a value written by an older build that never had this key).
  static OrientationMode parse(String value) => switch (value) {
    'portrait' => OrientationMode.portrait,
    'landscape' => OrientationMode.landscape,
    _ => OrientationMode.device,
  };
}

/// Device-class-aware screen-orientation lock.
///
/// Tablets/desktop lock to ONE landscape at a time — never auto-rotating —
/// and the user flips between the two with a button. Phones lock to normal
/// portrait with no flip. That's the [OrientationMode.device] default; a
/// person can override it to always-portrait or always-landscape from
/// Settings, and the override persists and wins over the device-class guess.
///
/// App-global platform state, so it's a singleton (it must be the same
/// instance across the app's separate provider containers — see the
/// ready-scope split in main.dart). The ANDROID side re-derives this same
/// decision natively (`MainActivity.onCreate`, before `super.onCreate`) from
/// the same persisted prefs, so the activity launches directly in the right
/// orientation — this controller's job from then on is only to keep it in
/// sync with a live in-app change (a mode switch, a threshold edit, a flip).
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
  OrientationMode _mode = OrientationMode.device;

  /// Tablet/desktop → landscape with a flip; phone → portrait, no flip.
  /// This is the DEVICE-CLASS guess — [effectiveLandscape] is what's
  /// actually applied once [mode] is factored in.
  bool get isTablet => _isTablet;

  /// Which of the two landscape locks is active when landscape applies.
  bool get landscapeRight => _landscapeRight;

  /// The explicit override, if any — wins over the device-class guess.
  OrientationMode get mode => _mode;

  /// What's actually locked right now: the explicit mode if set, else the
  /// device-class guess.
  bool get effectiveLandscape => switch (_mode) {
    OrientationMode.landscape => true,
    OrientationMode.portrait => false,
    OrientationMode.device => _isTablet,
  };

  /// The flip (choosing which of the two landscape sides) is only
  /// meaningful while landscape actually applies.
  bool get canFlip => effectiveLandscape;

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

  /// Host hook that persists the mode override — wired at boot like
  /// [persister]. Called after each [setMode]; never on [restoreMode] (no
  /// persist echo). The Android native side reads the SAME persisted value
  /// directly (no Dart round trip) so the very first frame already matches.
  void Function({required OrientationMode mode})? modePersister;

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
    if (effectiveLandscape) _apply();
    scheduleMicrotask(notifyListeners);
  }

  /// Toggle between the two landscape locks. No-op unless landscape is
  /// actually in effect (device-class tablet, or an explicit landscape
  /// lock).
  void flip() {
    if (!canFlip) return;
    _landscapeRight = !_landscapeRight;
    _apply();
    persister?.call(landscapeRight: _landscapeRight);
    notifyListeners();
  }

  /// Explicit override: follow the device class, or force one orientation.
  /// Wins over [setDeviceClass] from the moment it's set, and persists.
  void setMode(OrientationMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _apply();
    modePersister?.call(mode: mode);
    notifyListeners();
  }

  /// Seed the persisted mode at boot — same shape as [restoreFlip]. No
  /// persist echo.
  void restoreMode(OrientationMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _apply();
    scheduleMicrotask(notifyListeners);
  }

  void _apply() {
    _applied = true;
    // Landscape (device-class or explicit) accepts either side, so the
    // device can be rotated end-for-end without fighting the lock. The
    // persisted flip only decides which side is listed first (the preferred
    // one at apply time).
    final orientations = <DeviceOrientation>[
      if (!effectiveLandscape)
        DeviceOrientation.portraitUp
      else ...[
        if (_landscapeRight)
          DeviceOrientation.landscapeRight
        else
          DeviceOrientation.landscapeLeft,
        if (_landscapeRight)
          DeviceOrientation.landscapeLeft
        else
          DeviceOrientation.landscapeRight,
      ],
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
